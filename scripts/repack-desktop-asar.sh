#!/usr/bin/env bash
# repack-desktop-asar.sh — rebuild a patched app.asar from the installed one.
#
# Unlike install.sh this is non-interactive and does not touch the live client:
# it extracts the given asar, applies the patches and writes a new asar to
# --output. Meant to be called after a Bitwarden upgrade, when the previously
# saved patched asar belongs to an older version and must not be reused.
#
# Two classes of patches, and they differ in how well they age:
#
#   * biometrics (main process bundle) — spliced between `class
#     OsBiometricsServiceLinux` and `exports["default"] = ...`. tsc does not
#     mangle those names, so it keeps working across upstream releases. Required:
#     if it fails, the repack fails.
#
#   * URL column and sorting (renderer bundle) — patch-desktop.py matches mangled
#     identifiers such as `a.bMT(2,1,"owner")`, which webpack reshuffles on every
#     build. Best effort: a miss is reported, not fatal, unless --require-all.
#
# The `<output>.unpacked` directory that `asar pack --unpack-dir` leaves behind is
# not needed on the target: /opt/Bitwarden/resources/app.asar.unpacked ships with
# the package and the patches never touch the native module.
set -euo pipefail

SOURCE="/opt/Bitwarden/resources/app.asar"
OUTPUT=""
REQUIRE_ALL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { printf 'repack-desktop-asar: %s\n' "$*" >&2; exit "${2:-1}"; }

while [[ $# -gt 0 ]]; do
    case $1 in
        --source)      SOURCE=${2:?}; shift 2 ;;
        --output)      OUTPUT=${2:?}; shift 2 ;;
        --require-all) REQUIRE_ALL=1; shift ;;
        -h|--help)     sed -n '2,25p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *)             die "unknown argument: $1" 2 ;;
    esac
done

[[ -f $SOURCE ]] || die "source asar not found: $SOURCE" 2
[[ -n $OUTPUT  ]] || die "--output is required" 2

command -v python3 >/dev/null || die "python3 not found" 2
if command -v asar >/dev/null; then
    ASAR=(asar)
elif command -v npx >/dev/null; then
    ASAR=(npx --yes asar@3.2.0)          # same version install.sh pins
else
    die "neither 'asar' nor 'npx' found — install nodejs/npm" 2
fi

work=$(mktemp -d /tmp/bw-repack-XXXXXX)
trap 'rm -rf "$work"' EXIT
extract="$work/extract"

echo "→ extracting $SOURCE"
"${ASAR[@]}" extract "$SOURCE" "$extract" >/dev/null

# ── required: persistent biometrics in the main process bundle ─────────────
if ! python3 "$SCRIPT_DIR/patch-biometrics-compiled.py" "$extract"; then
    die "biometrics patch did not apply — upstream layout changed, rebuild
    patches/os-biometrics-linux.compiled.js from a freshly patched build"
fi

# ── best effort: URL column and sorting in the renderer bundle ─────────────
renderer_log="$work/renderer.log"
if python3 "$SCRIPT_DIR/patch-desktop.py" "$extract" --url --sort >"$renderer_log" 2>&1; then
    sed 's/^/  /' "$renderer_log"
    if grep -q 'No changes applied' "$renderer_log"; then
        msg="URL column / sorting patterns did not match this build (webpack remangled them)"
        [[ $REQUIRE_ALL -eq 1 ]] && die "$msg"
        echo "  ! $msg — continuing, biometrics is what matters here"
    fi
else
    [[ $REQUIRE_ALL -eq 1 ]] && die "patch-desktop.py failed"
    echo "  ! patch-desktop.py failed — continuing without URL column / sorting"
fi

echo "→ repacking"
"${ASAR[@]}" pack "$extract" "$OUTPUT" \
    --unpack-dir 'node_modules/@bitwarden/desktop-napi' >/dev/null

# ── sanity: the result must differ from the input and carry the marker ─────
grep -aq -F 'const SERVICE = "Bitwarden_biometric"' "$OUTPUT" \
    || die "repacked asar lacks the biometrics marker — refusing to hand it over"
if cmp -s "$SOURCE" "$OUTPUT"; then
    # Re-packing an already-patched asar is a no-op, not a failure: the output is
    # still a valid patched asar, so callers can use it either way.
    echo "• source was already patched — output is byte-identical"
fi

echo "✓ patched asar written to $OUTPUT ($(stat -c %s "$OUTPUT") bytes)"
