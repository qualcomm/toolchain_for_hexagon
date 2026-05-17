const std = @import("std");

// External C functions - no need for @cImport, just declare them
extern fn printf(format: [*:0]const u8, ...) c_int;

// Helper function for floating-point comparison with tolerance
fn approxEqual(a: f32, b: f32, tolerance: f32) bool {
    return @abs(a - b) <= tolerance;
}

// QHL Math HVX functions
extern fn qhmath_hvx_sqrt_af(input: [*]f32, output: [*]f32, size: u32) i32;
extern fn qhmath_hvx_sin_af(input: [*]f32, output: [*]f32, size: u32) i32;
extern fn qhmath_hvx_exp_af(input: [*]f32, output: [*]f32, size: u32) i32;

// QHL BLAS HVX functions
extern fn qhblas_hvx_w_vector_dot_ah(input_1: [*]i16, input_2: [*]i16, output: *i32, size: u32) i32;

// QHL DSP HVX functions
extern fn qhdsp_hvx_bkfir_af(input: [*]f32, coef: [*]f32, output: [*]f32, length: u32, taps: u32) i32;
extern fn qhdsp_hvx_r1dfft_af(input: [*]f32, N: u32, output: [*]f32, twiddles: [*]f32) i32;

// QHL Complex functions (C99 complex.h compatible)
// These use complex structures, not separate real/imag
const float_complex = extern struct {
    real: f32,
    imag: f32,
};
extern fn qhcomplex_cabs_f(z: float_complex) f32;
extern fn qhcomplex_carg_f(z: float_complex) f32;
extern fn qhcomplex_conj_f(z: float_complex) float_complex;

const ARRAY_SIZE = 16;
const MATRIX_SIZE = 4;

// Demonstrate QHL Math HVX functions
export fn qhl_math_demo() void {
    var input: [ARRAY_SIZE]f32 align(128) = undefined;
    var output: [ARRAY_SIZE]f32 align(128) = undefined;

    _ = printf("  QHL Math HVX Demo:\n");

    // Initialize test data
    for (0..ARRAY_SIZE) |i| {
        input[i] = @as(f32, @floatFromInt(i + 1)) * 0.5;
    }

    // Test qhmath_hvx_sqrt_af - HVX-accelerated square root
    var ret = qhmath_hvx_sqrt_af(&input, &output, ARRAY_SIZE);
    if (ret == 0) {
        _ = printf("    sqrt_f results:\n");
        _ = printf("      Input:  [%.2f, %.2f, %.2f, %.2f, ...]\n",
            input[0], input[1], input[2], input[3]);
        _ = printf("      Output: [%.4f, %.4f, %.4f, %.4f, ...]\n",
            output[0], output[1], output[2], output[3]);

        // Verify results: sqrt(0.5) ~= 0.707, sqrt(1.0) = 1.0, sqrt(4.0) = 2.0
        std.debug.assert(approxEqual(output[0], 0.7071, 0.001));
        std.debug.assert(approxEqual(output[1], 1.0000, 0.001));
        std.debug.assert(approxEqual(output[7], 2.0000, 0.001));
        _ = printf("      [OK] Assertions passed\n");
    } else {
        _ = printf("    sqrt_f failed with error: %d\n", ret);
    }

    // Test qhmath_hvx_sin_af - HVX-accelerated sine
    for (0..ARRAY_SIZE) |i| {
        input[i] = @as(f32, @floatFromInt(i)) * 0.1;
    }

    ret = qhmath_hvx_sin_af(&input, &output, ARRAY_SIZE);
    if (ret == 0) {
        _ = printf("    sin_f results:\n");
        _ = printf("      Input:  [%.2f, %.2f, %.2f, %.2f, ...]\n",
            input[0], input[1], input[2], input[3]);
        _ = printf("      Output: [%.4f, %.4f, %.4f, %.4f, ...]\n",
            output[0], output[1], output[2], output[3]);

        // Verify results: sin(0) = 0, sin(0.1) ~= 0.0998
        std.debug.assert(approxEqual(output[0], 0.0, 0.001));
        std.debug.assert(approxEqual(output[1], 0.0998, 0.001));
        _ = printf("      [OK] Assertions passed\n");
    } else {
        _ = printf("    sin_f failed with error: %d\n", ret);
    }

    // Test qhmath_hvx_exp_af - HVX-accelerated exponential
    for (0..ARRAY_SIZE) |i| {
        input[i] = @as(f32, @floatFromInt(i)) * 0.2;
    }

    ret = qhmath_hvx_exp_af(&input, &output, ARRAY_SIZE);
    if (ret == 0) {
        _ = printf("    exp_f results:\n");
        _ = printf("      Input:  [%.2f, %.2f, %.2f, %.2f, ...]\n",
            input[0], input[1], input[2], input[3]);
        _ = printf("      Output: [%.4f, %.4f, %.4f, %.4f, ...]\n",
            output[0], output[1], output[2], output[3]);

        // Verify results: exp(0) = 1.0, exp(0.2) ~= 1.2214
        std.debug.assert(approxEqual(output[0], 1.0000, 0.001));
        std.debug.assert(approxEqual(output[1], 1.2214, 0.001));
        _ = printf("      [OK] Assertions passed\n");
    } else {
        _ = printf("    exp_f failed with error: %d\n", ret);
    }
}

// Demonstrate QHL BLAS HVX functions
export fn qhl_blas_demo() void {
    var vector_a: [MATRIX_SIZE]i16 align(128) = undefined;
    var vector_b: [MATRIX_SIZE]i16 align(128) = undefined;

    _ = printf("  QHL BLAS HVX Demo:\n");

    // Initialize 16-bit fixed-point vectors
    for (0..MATRIX_SIZE) |i| {
        vector_a[i] = @as(i16, @intCast(i + 1));
        vector_b[i] = @as(i16, @intCast((i + 1) * 2));
    }

    _ = printf("      Vector A (int16): [%d, %d, %d, %d]\n",
        vector_a[0], vector_a[1], vector_a[2], vector_a[3]);
    _ = printf("      Vector B (int16): [%d, %d, %d, %d]\n",
        vector_b[0], vector_b[1], vector_b[2], vector_b[3]);

    // Test qhblas_hvx_w_vector_dot_ah - 16-bit dot product
    var dot_result: i32 = 0;
    const ret = qhblas_hvx_w_vector_dot_ah(&vector_a, &vector_b, &dot_result, MATRIX_SIZE);
    if (ret == 0) {
        _ = printf("    Dot product result (HVX raw): %ld\n", @as(c_long, dot_result));
        _ = printf("    Dot product result (scaled): %ld\n", @as(c_long, dot_result >> 1));

        // Calculate reference result for comparison
        var ref_result: i32 = 0;
        for (0..MATRIX_SIZE) |i| {
            ref_result += @as(i32, vector_a[i]) * @as(i32, vector_b[i]);
        }
        _ = printf("    Dot product result (reference): %ld\n", @as(c_long, ref_result));
        _ = printf("      Expected: (1*2 + 2*4 + 3*6 + 4*8) = 60\n");
        _ = printf("      Note: HVX int16 dot product returns result << 1\n");

        // Verify: HVX returns result << 1, so 60 * 2 = 120
        std.debug.assert(dot_result == 120);
        std.debug.assert((dot_result >> 1) == ref_result);
        std.debug.assert(ref_result == 60);
        _ = printf("      [OK] Assertions passed\n");
    } else {
        _ = printf("    Dot product failed with error: %d\n", ret);
    }
}

// Demonstrate QHL DSP HVX functions
export fn qhl_dsp_demo() void {
    const M_PI = 3.14159265358979323846;
    const TAPS = 8;
    var signal: [ARRAY_SIZE]f32 align(128) = undefined;
    var coef: [TAPS]f32 align(128) = undefined;
    var filtered: [ARRAY_SIZE]f32 align(128) = undefined;

    _ = printf("  QHL DSP HVX Demo:\n");

    // Generate a simple signal (sine wave)
    for (0..ARRAY_SIZE) |i| {
        const angle = 2.0 * M_PI * @as(f32, @floatFromInt(i)) / 8.0;
        signal[i] = @sin(angle);
    }

    _ = printf("    FIR Filter Demo:\n");
    _ = printf("      Input signal (sine wave): [%.3f, %.3f, %.3f, %.3f, ...]\n",
        signal[0], signal[1], signal[2], signal[3]);

    // Create averaging filter coefficients (low-pass filter)
    const coef_value = 1.0 / @as(f32, @floatFromInt(TAPS));
    for (0..TAPS) |i| {
        coef[i] = coef_value;
    }
    _ = printf("      Filter: %d-tap averaging (low-pass), coefficients = %.4f\n", @as(c_int, TAPS), coef_value);

    // Apply block FIR filter using QHL DSP HVX
    const ret = qhdsp_hvx_bkfir_af(&signal, &coef, &filtered, ARRAY_SIZE, TAPS);
    if (ret == 0) {
        _ = printf("      Filtered output: [%.3f, %.3f, %.3f, %.3f, ...]\n",
            filtered[0], filtered[1], filtered[2], filtered[3]);

        // Calculate signal power before and after filtering
        var input_power: f32 = 0.0;
        var output_power: f32 = 0.0;
        for (0..ARRAY_SIZE) |i| {
            input_power += signal[i] * signal[i];
            output_power += filtered[i] * filtered[i];
        }

        _ = printf("      Input signal power: %.4f\n", input_power);
        _ = printf("      Filtered signal power: %.4f\n", output_power);

        // Verify: Averaging filter should smooth the signal, power should be positive
        std.debug.assert(input_power > 0.0);
        std.debug.assert(output_power > 0.0);
        std.debug.assert(output_power <= input_power * 1.5); // Filtered power should be similar
        _ = printf("      [OK] Assertions passed\n");
    } else {
        _ = printf("      Block FIR filter failed with error: %d\n", ret);
        _ = printf("      Note: Block FIR may have specific length requirements\n");

        // Fallback: Calculate signal power manually to show something working
        var total_power: f32 = 0.0;
        for (0..ARRAY_SIZE) |i| {
            total_power += signal[i] * signal[i];
        }
        _ = printf("      Signal power (fallback): %.4f\n", total_power);
        _ = printf("      Average power: %.4f\n", total_power / @as(f32, @floatFromInt(ARRAY_SIZE)));
        std.debug.assert(approxEqual(total_power / @as(f32, @floatFromInt(ARRAY_SIZE)), 0.5, 0.1));
        _ = printf("      [OK] Fallback assertions passed\n");
    }
}

// Demonstrate QHL complex number operations
export fn qhl_complex_demo() void {
    _ = printf("  QHL Complex Demo:\n");

    // Test complex numbers using QHL's complex type
    const z1 = float_complex{ .real = 3.0, .imag = 4.0 };
    const z2 = float_complex{ .real = 1.0, .imag = -2.0 };

    _ = printf("    z1 = %.1f + %.1fi\n", z1.real, z1.imag);
    _ = printf("    z2 = %.1f + %.1fi\n", z2.real, z2.imag);

    // Complex arithmetic using Zig (QHL complex uses C99 complex.h which isn't directly callable)
    const add_real = z1.real + z2.real;
    const add_imag = z1.imag + z2.imag;
    _ = printf("    z1 + z2 = %.1f + %.1fi\n", add_real, add_imag);

    const mul_real = z1.real * z2.real - z1.imag * z2.imag;
    const mul_imag = z1.real * z2.imag + z1.imag * z2.real;
    _ = printf("    z1 * z2 = %.1f + %.1fi\n", mul_real, mul_imag);

    // Magnitude using QHL
    const mag1 = qhcomplex_cabs_f(z1);
    const mag2 = qhcomplex_cabs_f(z2);
    _ = printf("    |z1| (QHL cabs) = %.4f\n", mag1);
    _ = printf("    |z2| (QHL cabs) = %.4f\n", mag2);

    // Phase using QHL
    const phase1 = qhcomplex_carg_f(z1);
    const phase2 = qhcomplex_carg_f(z2);
    _ = printf("    arg(z1) (QHL carg) = %.4f radians\n", phase1);
    _ = printf("    arg(z2) (QHL carg) = %.4f radians\n", phase2);

    // Complex conjugate using QHL
    const z1_conj = qhcomplex_conj_f(z1);
    _ = printf("    conj(z1) (QHL) = %.1f + %.1fi\n", z1_conj.real, z1_conj.imag);

    // Verify complex arithmetic
    // z1 + z2 = (3+4i) + (1-2i) = 4+2i
    std.debug.assert(approxEqual(add_real, 4.0, 0.001));
    std.debug.assert(approxEqual(add_imag, 2.0, 0.001));

    // z1 * z2 = (3+4i) * (1-2i) = 3 - 6i + 4i - 8i² = 11 - 2i
    std.debug.assert(approxEqual(mul_real, 11.0, 0.001));
    std.debug.assert(approxEqual(mul_imag, -2.0, 0.001));

    // |z1| = sqrt(3^2 + 4^2) = 5.0
    std.debug.assert(approxEqual(mag1, 5.0, 0.001));

    // |z2| = sqrt(1^2 + 4) = sqrt(5) ~= 2.236
    std.debug.assert(approxEqual(mag2, 2.2361, 0.001));

    // conj(3+4i) = 3-4i
    std.debug.assert(approxEqual(z1_conj.real, 3.0, 0.001));
    std.debug.assert(approxEqual(z1_conj.imag, -4.0, 0.001));

    _ = printf("    [OK] Assertions passed\n");
}

// Main entry point for QuRT's run_main_on_hexagon
export fn main() c_int {
    _ = printf("\n=== Zig QuRT + QHL Libraries Demo ===\n\n");

    _ = printf("Testing QHL Math HVX Functions...\n");
    qhl_math_demo();

    _ = printf("\nTesting QHL BLAS HVX Functions...\n");
    qhl_blas_demo();

    _ = printf("\nTesting QHL DSP HVX Functions...\n");
    qhl_dsp_demo();

    _ = printf("\nTesting QHL Complex Functions...\n");
    qhl_complex_demo();

    _ = printf("\n=== Demo Complete ===\n");

    return 0;
}
