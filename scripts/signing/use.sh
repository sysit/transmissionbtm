#!/usr/bin/env bash
# Switch the live build-profile.json5 between the debug and release signing
# configs. hvigor has no CLI override for the product signingConfig, and the
# two variants differ by exactly that one line — keep them as matched copies
# so switching is one command instead of a hand edit.
#
#   ./scripts/signing/use.sh debug     # installable on a real phone
#   ./scripts/signing/use.sh release   # AppGallery upload (.app)
#
# The variant files hold signing secrets; they are gitignored.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
variant="${1:-}"

case "$variant" in
  debug|release) ;;
  *) echo "usage: $0 debug|release" >&2; exit 2 ;;
esac

src="$here/$variant.json5"
[ -f "$src" ] || { echo "missing $src" >&2; exit 1; }

cp "$src" "$root/build-profile.json5"
echo "build-profile.json5 -> $variant"
