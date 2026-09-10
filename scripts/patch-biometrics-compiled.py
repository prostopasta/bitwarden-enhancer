#!/usr/bin/env python3
"""Apply the persistent-biometrics patch to a compiled main.js.

patch-desktop.py works on the renderer bundle (app/main.js) and covers the URL
column and sorting. The biometrics fix lives in the *main process* bundle
(main.js at the root of the extracted asar), where tsc emits the class almost
verbatim: `class OsBiometricsServiceLinux` ... `exports["default"] = ...`.
Neither anchor is minified, which is why this survives upstream releases even
though the renderer patches are tied to mangled webpack identifiers.

A webpack bundle is one enormous line, so a diff of the whole file is useless.
Instead the class block is sliced out, patched on its own with patch(1), and
spliced back — which keeps patches/04-desktop-compiled-biometrics.patch small and
readable, and touching nothing but the hunks it declares.

Usage:
    patch-biometrics-compiled.py <extracted_dir_or_main.js> [--patch FILE] [--check]

Exit codes: 0 patched or already applied, 1 slice/patch failed, 2 bad usage.
"""
import argparse
import os
import subprocess
import sys
import tempfile

CLASS_ANCHOR = "class OsBiometricsServiceLinux"
EXPORT_ANCHOR = 'exports["default"] = OsBiometricsServiceLinux;'
PREAMBLE_ANCHOR = 'const SERVICE = "Bitwarden_biometric"'
DEFAULT_PATCH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "patches", "04-desktop-compiled-biometrics.patch",
)


def locate(src):
    """Return (start, end) of the class block, or None if the anchors are gone."""
    cls = src.find(CLASS_ANCHOR)
    if cls == -1:
        return None
    end = src.find(EXPORT_ANCHOR, cls)
    if end == -1:
        return None
    end += len(EXPORT_ANCHOR)

    # An already-patched bundle carries the SERVICE/getLookupKeyForUser preamble
    # right before the class; include it so the patch sees the same block it was
    # generated against.
    pre = src.rfind(PREAMBLE_ANCHOR, 0, cls)
    return (pre if pre != -1 and cls - pre < 400 else cls), end


def run_patch(target, patch_file, *extra):
    return subprocess.run(
        ["patch", "--silent", "-p0", "-o", "-", *extra, target, patch_file],
        capture_output=True, text=True,
    )


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("target", help="extracted asar directory, or path to main.js")
    ap.add_argument("--patch", default=DEFAULT_PATCH,
                    help="patch to apply (default: patches/04-desktop-compiled-biometrics.patch)")
    ap.add_argument("--check", action="store_true", help="report state, write nothing")
    args = ap.parse_args()

    main_js = os.path.join(args.target, "main.js") if os.path.isdir(args.target) else args.target
    for path in (main_js, args.patch):
        if not os.path.exists(path):
            print(f"error: {path} not found", file=sys.stderr)
            return 2

    src = open(main_js, encoding="utf-8").read()
    span = locate(src)
    if span is None:
        print(f"✗ anchors not found in {main_js} — upstream layout changed, "
              f"the biometrics patch needs regenerating", file=sys.stderr)
        return 1

    start, end = span
    with tempfile.TemporaryDirectory() as tmp:
        block_path = os.path.join(tmp, "block.js")
        with open(block_path, "w", encoding="utf-8") as f:
            f.write(src[start:end] + "\n")

        # Reverse dry run succeeds only on an already-patched block
        if run_patch(block_path, args.patch, "--dry-run", "--reverse").returncode == 0:
            print("• biometrics: already applied")
            return 0

        forward = run_patch(block_path, args.patch, "--dry-run", "--forward")
        if forward.returncode != 0:
            print(f"✗ biometrics: patch does not apply to this build — regenerate "
                  f"{os.path.basename(args.patch)} against it\n{forward.stdout}{forward.stderr}".rstrip(),
                  file=sys.stderr)
            return 1
        if args.check:
            print("• biometrics: patch applies cleanly (not written)")
            return 0

        applied = run_patch(block_path, args.patch, "--forward")
        if applied.returncode != 0:
            print(f"✗ biometrics: patch failed\n{applied.stdout}{applied.stderr}".rstrip(),
                  file=sys.stderr)
            return 1
        new_block = applied.stdout

    # patch(1) hands back the block with the trailing newline we added
    if new_block.endswith("\n"):
        new_block = new_block[:-1]
    open(main_js, "w", encoding="utf-8").write(src[:start] + new_block + src[end:])
    print(f"✓ biometrics: persistent unlock patch applied "
          f"({len(new_block) - (end - start):+d} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
