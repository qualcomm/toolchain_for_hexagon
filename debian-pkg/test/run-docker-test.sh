#!/bin/bash

#  Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
#  SPDX-License-Identifier: BSD-3-Clause-Clear

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}/.."

if ! ls debs/*.deb >/dev/null 2>&1; then
    echo "ERROR: No .deb packages in debs/. Run build-hexagon-sysroot.sh first."
    exit 1
fi

echo "=== Building Docker test image ==="
docker build -f test/Dockerfile -t hexagon-cross-test .

echo ""
echo "=== All tests passed ==="
