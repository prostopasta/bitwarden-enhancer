#!/usr/bin/env python3
import os
import sys
import re

def patch_web_vault(main_js_path, enable_url=True, enable_sort=True):
    with open(main_js_path, "r", encoding="utf-8") as f:
        content = f.read()

    changed = False

    if enable_url:
        # 1. Update row function te to show launchUri instead of org-badge
        row_target = 'function te(e,t){if(1&e&&(w.j41(0,"td",11),w.nrm(1,"app-org-badge",23),w.nI1(2,"orgNameFromId"),w.k0s()),2&e){const e=w.XpG();w.Y8G("ngClass",e.RowHeightClass),w.R7$(),w.Y8G("disabled",e.disabled)("organizationId",e.cipher.organizationId)("organizationName",w.i5U(2,4,e.cipher.organizationId,e.organizations))}}'
        row_repl = 'function te(e,t){if(1&e&&(w.j41(0,"td",11),w.j41(1,"span",10),w.EFF(2),w.k0s(),w.k0s()),2&e){const e=w.XpG();w.Y8G("ngClass",e.RowHeightClass),w.R7$(2),w.SpI("",e.launchUri||"","")}}'
        if row_target in content:
            content = content.replace(row_target, row_repl, 1)
            changed = True
            print("✓ Patched web-vault row to display launchUri")

        # 2. Update header function B to URL text
        # Old: function B(e,t){1&e&&(b.j41(0,"th",8),b.EFF(1),b.nI1(2,"i18n"),b.k0s()),2&e&&(b.R7$(),b.JRh(b.bMT(2,1,"owner")))}
        old_fn_b = 'function B(e,t){1&e&&(b.j41(0,"th",8),b.EFF(1),b.nI1(2,"i18n"),b.k0s()),2&e&&(b.R7$(),b.JRh(b.bMT(2,1,"owner")))}'
        if old_fn_b in content:
            # Replaced with URL
            if enable_sort:
                repl_fn_b = 'function B(e,t){if(1&e&&(b.j41(0,"th",8),b.EFF(1),b.k0s()),2&e){const i=b.XpG();b.Y8G("fn",i.sortByUrl),b.R7$(),b.SpI(" ","URL"," ")}}'
            else:
                repl_fn_b = 'function B(e,t){1&e&&(b.j41(0,"th",8),b.EFF(1),b.k0s()),2&e&&(b.R7$(),b.SpI(" ","URL"," "))}'
            content = content.replace(old_fn_b, repl_fn_b, 1)
            changed = True
            print("✓ Patched web-vault header B to display URL")

    if enable_sort:
        # 3. Add bitSortable to consts[8]
        t_const8 = '["bitCell","",1,"tw-hidden","tw-w-2/5","lg:tw-table-cell"]'
        r_const8 = '["bitCell","","bitSortable","url",1,"tw-hidden","tw-w-2/5","lg:tw-table-cell",3,"fn"]'
        if t_const8 in content:
            content = content.replace(t_const8, r_const8, 1)
            changed = True
            print("✓ Enabled bitSortable='url' in web-vault table consts")

        # 4. Add sortByUrl to Y class
        t_sort = "this.sortByName=(e,t,i)=>{const n=this.prioritizeCollections(e,t);return 0!==n?n:this.compareNames(e,t)}"
        r_sort = "this.sortByUrl=(e,t,i)=>{const r=this.prioritizeCollections(e,t);if(0!==r)return r;const u=e=>e.cipher?(v.n.getLaunchUri(e.cipher)||\"\"):e.collection?(e.collection.name||\"\"):\"\";return u(e).localeCompare(u(t))}," + t_sort
        if t_sort in content and "this.sortByUrl=" not in content:
            content = content.replace(t_sort, r_sort, 1)
            changed = True
            print("✓ Added sortByUrl comparator to web-vault VaultItemsComponent")

        # 5. Fix Name sorting in personal vault: b.vxM(t.showAdminActions?7:8) -> b.vxM(7)
        t_vxm = "b.vxM(t.showAdminActions?7:8)"
        r_vxm = "b.vxM(7)                     "
        if t_vxm in content:
            content = content.replace(t_vxm, r_vxm, 1)
            changed = True
            print("✓ Enabled interactive Name column sorting for personal vault in web-vault")

    if changed:
        with open(main_js_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("✓ Successfully saved patched web-vault bundle")
    else:
        print("• Web vault bundle already patched or patterns not matched.")

def patch_locales(locales_dir):
    ru_path = os.path.join(locales_dir, "ru/messages.json")
    if os.path.exists(ru_path):
        with open(ru_path, "r", encoding="utf-8") as f:
            ru = f.read()
        target = '"owner": {\n    "message": "Владелец"'
        if target in ru:
            ru = ru.replace(target, '"owner": {\n    "message": "URL"')
            with open(ru_path, "w", encoding="utf-8") as f:
                f.write(ru)
            print("✓ Updated ru/messages.json 'owner' -> 'URL'")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: patch-web-vault.py <path_to_web_vault_dir_or_main_js> [--url] [--sort]")
        sys.exit(1)

    target = sys.argv[1]
    url = "--url" in sys.argv or "-u" in sys.argv
    sort = "--sort" in sys.argv or "-s" in sys.argv
    if not (url or sort):
        url = sort = True

    if os.path.isdir(target):
        # find main.*.js in app/
        app_dir = os.path.join(target, "app")
        main_files = [os.path.join(app_dir, f) for f in os.listdir(app_dir) if f.startswith("main.") and f.endswith(".js")] if os.path.exists(app_dir) else []
        for mf in main_files:
            patch_web_vault(mf, enable_url=url, enable_sort=sort)
        locales_dir = os.path.join(target, "locales")
        if os.path.exists(locales_dir) and url:
            patch_locales(locales_dir)
    elif os.path.isfile(target):
        patch_web_vault(target, enable_url=url, enable_sort=sort)
