// Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
// SPDX-License-Identifier: BSD-3-Clause-Clear

//! Histogram equalization with runtime CPU detection and multi-version HVX
//! dispatch.
//!
//! Tiers:
//!   0 — Scalar:   scalar histogram, scalar remap
//!   1 — HVX v60:  scalar histogram, vlut32 parallel remap
//!   2 — HVX v65:  vscatteracc parallel histogram, vlut32 parallel remap
//!
//! Demonstrates `getauxval(AT_HWCAP)` for feature detection, `vlut32` for
//! parallel LUT application (128 pixels/iteration), and `vscatteracc` for
//! parallel histogram construction (64 bin increments/instruction).

#![feature(stdarch_hexagon)]
#![feature(hexagon_target_feature)]

use core::arch::hexagon::v128::*;
use std::ptr;

const HVX_BYTES: usize = 128;

// ---------------------------------------------------------------------------
// hwcap definitions (from musl bits/hwcap.h)
// ---------------------------------------------------------------------------

const AT_HWCAP: u32 = 16;

const HWCAP_ISA_MASK: u32 = 0x7F;
#[allow(dead_code)]
const HWCAP_ISA_V60: u32 = 6;
#[allow(dead_code)]
const HWCAP_ISA_V62: u32 = 7;
const HWCAP_ISA_V65: u32 = 8;
#[allow(dead_code)]
const HWCAP_ISA_V66: u32 = 9;

const HWCAP_HVX: u32 = 1 << 7;
const HWCAP_HVX_128B: u32 = 1 << 9;

extern "C" {
    fn getauxval(type_: u32) -> u32;
}

struct CpuInfo {
    isa_version: u32,
    has_hvx: bool,
    has_hvx_128b: bool,
}

fn detect_cpu() -> CpuInfo {
    let hwcap = unsafe { getauxval(AT_HWCAP) };
    CpuInfo {
        isa_version: hwcap & HWCAP_ISA_MASK,
        has_hvx: (hwcap & HWCAP_HVX) != 0,
        has_hvx_128b: (hwcap & HWCAP_HVX_128B) != 0,
    }
}

fn isa_name(v: u32) -> &'static str {
    match v {
        6 => "V60",
        7 => "V62",
        8 => "V65",
        9 => "V66",
        10 => "V67",
        11 => "V68",
        12 => "V69",
        13 => "V71",
        14 => "V73",
        15 => "V79",
        _ => "unknown",
    }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

#[repr(C, align(128))]
struct AlignedBuf<const N: usize>([u8; N]);

/// Build a histogram of byte values (256 bins).
fn scalar_histogram(pixels: &[u8]) -> [u32; 256] {
    let mut hist = [0u32; 256];
    for &p in pixels {
        hist[p as usize] += 1;
    }
    hist
}

/// Compute a histogram-equalization LUT from a 256-bin histogram.
///
/// The classic formula:
///   lut[i] = round((cdf[i] - cdf_min) / (n - cdf_min) * 255)
fn compute_lut(hist: &[u32; 256], total: u32) -> [u8; 256] {
    let mut lut = [0u8; 256];
    let mut cdf = 0u32;
    let mut cdf_min = 0u32;
    let mut found_min = false;
    for i in 0..256 {
        cdf += hist[i];
        if !found_min && hist[i] != 0 {
            cdf_min = cdf;
            found_min = true;
        }
        if total > cdf_min {
            lut[i] = (((cdf - cdf_min) as u64 * 255) / (total - cdf_min) as u64) as u8;
        }
    }
    lut
}

/// Deterministic test image: ramp with multiplicative noise.
fn make_test_image(buf: &mut [u8]) {
    for i in 0..buf.len() {
        let base = (i % 256) as u8;
        let noise = ((i.wrapping_mul(7) ^ (i >> 3)) & 0x1F) as u8;
        buf[i] = base.wrapping_add(noise);
    }
}

// ---------------------------------------------------------------------------
// Tier 0 — Scalar
// ---------------------------------------------------------------------------

fn scalar_equalize(pixels: &[u8], out: &mut [u8]) {
    let hist = scalar_histogram(pixels);
    let lut = compute_lut(&hist, pixels.len() as u32);
    for i in 0..pixels.len() {
        out[i] = lut[pixels[i] as usize];
    }
}

// ---------------------------------------------------------------------------
// Tier 1 — HVX v60: scalar histogram + vlut32 remap
// ---------------------------------------------------------------------------

/// Remap pixels through a 256-byte LUT using vlut32 (128 pixels/iteration).
///
/// In 128-byte mode, `vlut32(Vu.b, Vv.b, Rt)` addresses within Vv as:
///
///   byte_offset = (sel & 1) * 64 + ((sel >> 1) & 1) + 2 * idx
///
/// where sel = Vu[i][7:5] (bank 0-7) and idx = Vu[i][4:0] (0-31).
///
/// This interleaves 4 banks into one 128-byte vector.  For a 256-entry LUT,
/// two vectors cover all 8 banks with 8 OR-accumulated passes.
#[target_feature(enable = "hvx-length128b")]
unsafe fn hvx_vlut32_remap(pixels: &[u8], out: &mut [u8], lut: &[u8; 256]) {
    let n = pixels.len();
    assert!(n == out.len());
    assert!(n % HVX_BYTES == 0);

    // Prepare 2 LUT vectors for all 8 banks (4 banks per vector).
    //
    // In 128-byte mode, vlut32 addresses within Vv as:
    //   byte_offset = (sel & 1) * 64 + ((sel >> 1) & 1) + 2 * idx
    //
    // where sel = input[7:5] (bank 0-7), idx = input[4:0] (0-31).
    // This interleaves 4 banks into one 128-byte vector:
    //   bank 0 (sel=0): even bytes in first half  — offsets 0, 2, 4, ..., 62
    //   bank 1 (sel=1): even bytes in second half — offsets 64, 66, ..., 126
    //   bank 2 (sel=2): odd bytes in first half   — offsets 1, 3, 5, ..., 63
    //   bank 3 (sel=3): odd bytes in second half  — offsets 65, 67, ..., 127
    //
    // vec_lo holds banks 0-3 (LUT[0..128]), vec_hi holds banks 4-7 (LUT[128..256]).
    let mut lut_buf = AlignedBuf([0u8; 256]);
    for bank in 0..8usize {
        let b = bank & 3; // bank within its vector
        let base = (b & 1) * 64 + ((b >> 1) & 1);
        let vec_off = if bank < 4 { 0 } else { 128 };
        for j in 0..32usize {
            lut_buf.0[vec_off + base + 2 * j] = lut[bank * 32 + j];
        }
    }

    let vec_lo: HvxVector = ptr::read(lut_buf.0.as_ptr() as *const HvxVector);
    let vec_hi: HvxVector = ptr::read(lut_buf.0.as_ptr().add(128) as *const HvxVector);

    let mut i = 0;
    while i < n {
        let v_in: HvxVector = ptr::read(pixels.as_ptr().add(i) as *const HvxVector);

        // Banks 0-3 from vec_lo, banks 4-7 from vec_hi.
        let mut result = q6_vb_vlut32_vbvbr(v_in, vec_lo, 0);
        result = q6_vb_vlut32or_vbvbvbr(result, v_in, vec_lo, 1);
        result = q6_vb_vlut32or_vbvbvbr(result, v_in, vec_lo, 2);
        result = q6_vb_vlut32or_vbvbvbr(result, v_in, vec_lo, 3);
        result = q6_vb_vlut32or_vbvbvbr(result, v_in, vec_hi, 4);
        result = q6_vb_vlut32or_vbvbvbr(result, v_in, vec_hi, 5);
        result = q6_vb_vlut32or_vbvbvbr(result, v_in, vec_hi, 6);
        result = q6_vb_vlut32or_vbvbvbr(result, v_in, vec_hi, 7);

        ptr::write(out.as_mut_ptr().add(i) as *mut HvxVector, result);
        i += HVX_BYTES;
    }
}

/// Tier 1: scalar histogram + scalar CDF + vlut32 remap.
#[target_feature(enable = "hvx-length128b")]
unsafe fn hvx_v60_equalize(pixels: &[u8], out: &mut [u8]) {
    let hist = scalar_histogram(pixels);
    let lut = compute_lut(&hist, pixels.len() as u32);
    hvx_vlut32_remap(pixels, out, &lut);
}

// ---------------------------------------------------------------------------
// Tier 2 — HVX v65: vscatteracc histogram + vlut32 remap
// ---------------------------------------------------------------------------

/// Build a histogram using vscatteracc (v65+).
///
/// For each 128-pixel chunk:
///   1. Unpack 128 × u8 → 2 × 64 × u16 (bin indices)
///   2. Double the indices (byte offsets into u16 array)
///   3. Scatter-add a vector of ones into the histogram bins
///
/// This performs 64 histogram increments per vscatteracc instruction,
/// vs 1 per iteration in the scalar loop.
#[target_feature(enable = "hvx-length128b,hvxv65")]
unsafe fn hvx_v65_scatter_histogram(pixels: &[u8], hist: &mut [u16; 256]) {
    let n = pixels.len();
    assert!(n % HVX_BYTES == 0);

    // Zero the histogram.
    for h in hist.iter_mut() {
        *h = 0;
    }

    let hist_ptr = hist.as_mut_ptr() as usize as i32;
    let region = 512i32; // 256 bins × 2 bytes
    let ones = q6_v_vsplat_r(0x0001_0001_i32); // 1 in each u16 lane

    let mut i = 0;
    while i < n {
        let v_pixels: HvxVector = ptr::read(pixels.as_ptr().add(i) as *const HvxVector);

        // Unpack 128 × u8 → 2 × 64 × u16.
        let pair: HvxVectorPair = q6_wuh_vunpack_vub(v_pixels);
        let lo: HvxVector = q6_v_lo_w(pair);
        let hi: HvxVector = q6_v_hi_w(pair);

        // Convert bin indices to byte offsets (× 2 for u16 bins).
        let lo_offs = q6_vh_vadd_vhvh(lo, lo);
        let hi_offs = q6_vh_vadd_vhvh(hi, hi);

        // Scatter-add ones into histogram.
        q6_vscatteracc_rmvhv(hist_ptr, region, lo_offs, ones);
        q6_vscatteracc_rmvhv(hist_ptr, region, hi_offs, ones);

        i += HVX_BYTES;
    }
}

/// Tier 2: vscatteracc histogram + scalar CDF + vlut32 remap.
#[target_feature(enable = "hvx-length128b,hvxv65")]
unsafe fn hvx_v65_equalize(pixels: &[u8], out: &mut [u8]) {
    // Scatter histogram (u16 bins).
    let mut hist16 = AlignedHist([0u16; 256]);
    hvx_v65_scatter_histogram(pixels, &mut hist16.0);

    // Convert to u32 for the shared CDF computation.
    let mut hist32 = [0u32; 256];
    for i in 0..256 {
        hist32[i] = hist16.0[i] as u32;
    }

    let lut = compute_lut(&hist32, pixels.len() as u32);
    hvx_vlut32_remap(pixels, out, &lut);
}

#[repr(C, align(128))]
struct AlignedHist([u16; 256]);

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

fn main() {
    const N: usize = 4096; // 32 HVX vectors (e.g. 64×64 image)

    // Parse --force-tier.
    let args: Vec<String> = std::env::args().collect();
    let forced_tier: Option<u32> = args
        .windows(2)
        .find(|w| w[0] == "--force-tier")
        .and_then(|w| w[1].parse().ok());

    // Detect CPU.
    let cpu = detect_cpu();
    println!("CPU: Hexagon {}", isa_name(cpu.isa_version));
    if cpu.has_hvx_128b {
        println!("HVX: 128-byte vectors");
    } else if cpu.has_hvx {
        eprintln!("error: HVX present but 128-byte mode not available");
        eprintln!("This program is compiled for HVX 128b only.");
        std::process::exit(1);
    } else {
        eprintln!("error: HVX not available");
        eprintln!("This program requires HVX 128-byte vector support.");
        std::process::exit(1);
    }

    // Select tier.
    let tier = match forced_tier {
        Some(t) => {
            println!("Tier: forced to {}", t);
            t
        }
        None => {
            if cpu.isa_version >= HWCAP_ISA_V65 {
                2
            } else if cpu.isa_version >= HWCAP_ISA_V60 {
                1
            } else {
                0
            }
        }
    };

    let tier_desc = match tier {
        0 => "scalar histogram + scalar remap",
        1 => "scalar histogram + vlut32 remap (v60)",
        2 => "vscatteracc histogram + vlut32 remap (v65)",
        _ => unreachable!(),
    };
    println!("Selected: tier {} — {}", tier, tier_desc);
    println!();

    // Generate test image.
    let mut input = AlignedBuf([0u8; N]);
    make_test_image(&mut input.0);

    // Scalar reference.
    let mut ref_out = AlignedBuf([0u8; N]);
    scalar_equalize(&input.0, &mut ref_out.0);

    // HVX (or scalar) tier.
    let mut hvx_out = AlignedBuf([0u8; N]);
    unsafe {
        match tier {
            0 => scalar_equalize(&input.0, &mut hvx_out.0),
            1 => hvx_v60_equalize(&input.0, &mut hvx_out.0),
            2 => hvx_v65_equalize(&input.0, &mut hvx_out.0),
            _ => unreachable!(),
        }
    }

    // Show input distribution statistics.
    let in_hist = scalar_histogram(&input.0);
    let out_hist = scalar_histogram(&ref_out.0);
    let in_min = in_hist.iter().filter(|&&c| c > 0).min().unwrap_or(&0);
    let in_max = in_hist.iter().max().unwrap_or(&0);
    let out_min = out_hist.iter().filter(|&&c| c > 0).min().unwrap_or(&0);
    let out_max = out_hist.iter().max().unwrap_or(&0);
    println!(
        "Input  histogram: min_count={}, max_count={} (ideally uniform: {})",
        in_min, in_max, N / 256,
    );
    println!(
        "Output histogram: min_count={}, max_count={} (more uniform after equalization)",
        out_min, out_max,
    );
    println!();

    // Verify tier output matches scalar reference.
    let mut max_err: i32 = 0;
    let mut mismatches = 0;
    for i in 0..N {
        let err = (ref_out.0[i] as i32 - hvx_out.0[i] as i32).abs();
        if err > max_err {
            max_err = err;
        }
        if err > 0 {
            mismatches += 1;
        }
    }

    println!(
        "Comparison: {} pixels, max_error={}, mismatches={}",
        N, max_err, mismatches,
    );
    if mismatches == 0 {
        println!("PASS");
    } else {
        println!("FAIL: {} pixels differ", mismatches);
        std::process::exit(1);
    }
}
