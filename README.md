# KaiReborn

A two-part, non-destructive replacement for the `xkatrina` module lineage.

- **`module/`** — a Magisk / KernelSU / KernelSU-Next / APatch module that
  fixes sensitive build properties *safely*: delete-before-set, verify after
  write, never invent a property, never remount a partition, never delete user
  data, no SELinux deny.
- **`app/`** — an Android app that audits and reports. Read-only by default.
  No network, no identifiers uploaded, no `pm clear`, no `rm`.

Built because the original pair fails in specific, reproducible ways on a
modern ROM. Every claim is evidenced in [docs/EVIDENCE.md](docs/EVIDENCE.md).

---

## Why not just fix the old zip

The old zip is `sensitive_props` v5 (2024-01-04) with a new `module.prop`. On
a HyperOS 3 / Android 15 / KernelSU-Next device it:

1. cannot be installed — its installer requires `zygisksu`;
2. disables itself or errors depending on which shell evaluates its version
   gate;
3. ships `deny gmscore_app keystore keystore_key *`, which KernelSU applies on
   **every** boot;
4. tries to remount `/`, `/product`, `/vendor` rw (all `dm-*`, all ro);
5. costs ~1.9 s of boot time to set properties that are already correct.

Fixing it in place means fighting all five. Rebuilding it means not having
them.

## Install

```
# module
adb push dist/KaiReborn-v1.0.0.zip /sdcard/
# then install from your root manager app

# app (optional)
adb install dist/KaiReborn-1.0.0.apk
```

The module works without the app. The app works without root for the audit
screens; the property-override button needs root.

## Design rules

| Rule | Reason |
|---|---|
| Never create an absent property | an extra `ro.*` on stock is itself a fingerprint |
| Delete the old `ro.*` before setting it | Magisk v22.1 changelog: setting without deleting is a bootloop source |
| Verify every write by reading it back | a silent failure must be a log line, not a boot loop |
| No `sepolicy.rule` at all | the root manager applies it unattended on every boot |
| No remount, no `rm` under `/data/system` | irreversible and unrelated to prop hygiene |
| No Zygisk dependency | prop changes do not need it |
| 3 incomplete boots → disable and explain | the failure must be visible |
| Batch `resetprop -f` | ~10.4 ms per process spawn measured on the test device |

## Layout

```
module/
  module.prop        metadata
  post-fs-data.sh    thin shim (survives an APK overwrite)
  guard.sh           the actual logic
  common.sh          platform probe, safe set, boot-loop guard
  service.sh         late stage + user overrides
  audit.sh           read-only audit, --json / --to-file
  action.sh          root-manager action button: safe ⇄ audit
  customize.sh       installer
app/
  AndroidManifest.xml
  src/com/kaireborn/audit/MainActivity.java
tools/
  build-apk.sh       javac + d8 + aapt2 + apksigner, no Gradle
  build-module.sh    zip with update-binary
docs/
  EVIDENCE.md        the audit this was built from
```

## Compatibility with the legacy app

The legacy APK overwrites `<module>/post-fs-data.sh`, writes `fu.dex` and
`resetprop.sh` into the module directory, and reads `module.prop`.

KaiReborn tolerates all of that:

- `post-fs-data.sh` is a thin shim; the logic lives in `guard.sh`, which the
  APK never writes.
- If the shim *is* replaced, `service.sh` detects the missing
  `state/early_ok` marker and re-runs the early stage as a late fallback.
- `fu.dex` and `resetprop.sh` are treated as opaque files.
- The module id differs (`kaireborn`), so both can be installed side by side
  while you migrate. `customize.sh` offers to disable the legacy module,
  because its `sepolicy.rule` keeps firing until it is disabled.

## Mode

`action.sh` toggles between:

- **safe** — apply the guarded property fixes (default)
- **audit** — observe only, never write

State lives in `state/mode`; the boot log in `logs/boot.log`; the audit
snapshot in `logs/audit.txt`.

## Uninstall

Remove the module from your root manager. Nothing outside the module directory
is touched, so there is nothing to restore. Compare with the legacy
`uninstall.sh`, which renames `install-recovery.sh` back and deletes LSPosed
log tags.

## License

GPL-3.0. The legacy zip shipped GPL-3.0 text; the deciphered `prop.sh` logic is
derived from `sensitive_props` (GPL-3.0) and HuskyDG's work.
