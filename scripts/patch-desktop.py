#!/usr/bin/env python3
import os
import sys
import re
import shutil
import subprocess

def patch_desktop_main(main_js_path, enable_url=True, enable_sort=True):
    with open(main_js_path, "r", encoding="utf-8") as f:
        content = f.read()

    changed = False

    if enable_url:
        # 1. Header: change "owner" to "URL"
        if '"owner"' in content:
            # find header bitSortable="owner" or {{ "owner" | i18n }}
            header_pattern = r'(\.i5U\([0-9]+,[0-9]+,)"owner"(\))'
            # Or in compiled header:
            # a.SpI(" ",a.bMT(2,1,"owner")," ") -> a.SpI(" ","URL"," ")
            if 'a.bMT(2,1,"owner")' in content:
                content = content.replace('a.bMT(2,1,"owner")', '"URL"')
                changed = True
                print("✓ Patched desktop header text to URL")

        # 2. Row: change <app-org-badge> to <span class="tw-text-sm tw-text-muted">{{ launchUri }}</span>
        # In desktop main.js:
        # a.nrm(1,"app-org-badge",...)
        # We replace row rendering with launchUri span
        row_target = 'a.j41(0,"td",11),a.nrm(1,"app-org-badge",15)'
        if row_target in content:
            # Locate function containing row_target
            idx = content.find(row_target)
            fn_start = content.rfind("function", 0, idx)
            fn_end = content.find("}}", idx) + 2
            old_fn = content[fn_start:fn_end]
            
            # Craft replacement row function
            # function ir(e,t){if(1&e&&(a.j41(0,"td",11),a.j41(1,"span",10),a.EFF(2),a.k0s(),a.k0s()),2&e){const e=a.XpG();const u=Cn.n.getLaunchUri(e.cipher())||"";a.Y8G("ngClass",e.RowHeightClass),a.R7$(2),a.SpI("",u,"")}}
            # Keep function name dynamic:
            m = re.match(r'function\s+([A-Za-z0-9_$]+)', old_fn)
            if m:
                fn_name = m.group(1)
                new_fn = f'function {fn_name}(e,t){{if(1&e&&(a.j41(0,"td",11),a.j41(1,"span",10),a.EFF(2),a.k0s(),a.k0s()),2&e){{const e=a.XpG();const u=Cn.n.getLaunchUri(e.cipher())||"";a.Y8G("ngClass",e.RowHeightClass),a.R7$(2),a.SpI("",u,"")}}}}'
                content = content.replace(old_fn, new_fn, 1)
                changed = True
                print("✓ Patched desktop table row to display launchUri")

    if enable_sort:
        # 3. Comparator: replace organizationId sorting with launchUri sorting
        sort_target = 'this.sortByOwner=(e,t,i)=>{const n=e=>e.cipher?e.cipher.organizationId||"":e.collection&&e.collection.organizationId||"",r=n(e),s=n(t);return r.localeCompare(s)}'
        sort_repl = 'this.sortByOwner=(e,t,i)=>{const n=e=>e.cipher?(Cn.n.getLaunchUri(e.cipher)||""):e.collection?(e.collection.name||""):"",r=n(e),s=n(t);return r.localeCompare(s)}'
        if sort_target in content:
            content = content.replace(sort_target, sort_repl, 1)
            changed = True
            print("✓ Patched desktop sortByOwner comparator to sort by URL")

    if changed:
        with open(main_js_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("✓ Successfully saved patched desktop main.js")
    else:
        print("• No changes applied (already patched or patterns not matched).")

def patch_desktop_biometrics(app_bundle_path):
    # In Linux desktop, the YubiKey biometric persistence is in app/main.js
    with open(app_bundle_path, "r", encoding="utf-8") as f:
        content = f.read()

    changed = False
    # Check if Secret Service fallback / persistence hook is needed
    # (Replaces os_biometrics_linux session handling)
    if "Bitwarden_biometric" not in content:
        # Add persistent Secret Service key label if not present
        if "bitwarden-biometrics" in content:
            content = content.replace("bitwarden-biometrics", "Bitwarden_biometric")
            changed = True
            print("✓ Enabled persistent secret label for YubiKey Linux unlock")

    if changed:
        with open(app_bundle_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("✓ Biometrics patch saved.")
    else:
        print("• Biometrics already patched or using native daemon.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: patch-desktop.py <extracted_dir_or_main.js> [--url] [--sort] [--yubikey]")
        sys.exit(1)

    target = sys.argv[1]
    url = "--url" in sys.argv or "-u" in sys.argv
    sort = "--sort" in sys.argv or "-s" in sys.argv
    yubi = "--yubikey" in sys.argv or "-y" in sys.argv

    # Default to all if none specified
    if not (url or sort or yubi):
        url = sort = yubi = True

    main_js = os.path.join(target, "app/main.js") if os.path.isdir(target) else target
    if os.path.exists(main_js):
        if url or sort:
            patch_desktop_main(main_js, enable_url=url, enable_sort=sort)
        if yubi:
            patch_desktop_biometrics(main_js)
    else:
        print(f"Error: file not found {main_js}")
        sys.exit(1)
