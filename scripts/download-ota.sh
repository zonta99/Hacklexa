#!/usr/bin/env bash
# Download the stock Fire OS OTA for the Echo Dot 3 w/ clock (doebrite),
# the exact build 13323246980 / Fire OS 6.5.7.5 (NS6575).
# Amazon still serves it in the clear from CloudFront. FTVDB only indexes it.
set -euo pipefail

URL="https://d1s31zyz7dcc2d.cloudfront.net/2026/10/27/2d65b731-921e-4634-a158-8abb83de90c7/update-kindle-doebrite-NS6575_user_8349_0013323246980.bin"
OUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/firmware"
OUT="$OUT_DIR/update-kindle-doebrite-NS6575_user_8349_0013323246980.bin"
MD5_EXPECTED="c79bbc974b96c69c9cd9ea083e8ecdca"

mkdir -p "$OUT_DIR"
echo "Downloading OTA to $OUT ..."
curl -L --fail --retry 3 -o "$OUT" "$URL"

echo "Verifying MD5 (expected $MD5_EXPECTED, from FTVDB)..."
GOT="$(md5 -q "$OUT" 2>/dev/null || md5sum "$OUT" | awk '{print $1}')"
echo "got: $GOT"
[ "$GOT" = "$MD5_EXPECTED" ] && echo "OK: checksum matches" || { echo "MISMATCH — do not trust this file"; exit 1; }
