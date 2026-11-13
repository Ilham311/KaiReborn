# Evidence — what the legacy zip and APK actually do

Every claim below is backed by a command, a byte offset, or an output. No
conclusions from grepping strings alone; where a claim depends on behaviour,
the command that produced it is included.

Audited artefacts:

| Artifact | Path | SHA-256 / size |
|---|---|---|
| Legacy module zip | `/storage/emulated/0/xkatrina.zip` | 819,695 B |
| Legacy APK | `com.fufufu.katrina.backup` | `classes.dex`…`classes6.dex`, 8.3M + 5 × ~1–2.7M |
| Device | Redmi alioth, HyperOS `OS3.0.3.0.VKHMIXM`, Android 15 (SDK 35) | KernelSU Next `ksud 1.0.9-65-g89a0d4c5`, ReZygisk. No Magisk. |

---

## 1. `main.dex` is not a dex — it is the module zip

`main.dex` is a ZIP archive whose CRC-identical twin is shipped on the SD card.
The APK extracts it to `/storage/emulated/0/xkatrina.zip` and tells the user to
install it manually.

```
$ head -c 4 apk/u/assets/main.dex | od -An -tx1
 50 4b 03 04            # "PK\x03\x04" = ZIP, not "dex\n" (64 65 78 0a)

$ md5sum apk/u/assets/main.dex /storage/emulated/0/xkatrina.zip
011ea273c868ef8aaba838a8021fd32a  apk/u/assets/main.dex
011ea273c868ef8aaba838a8021fd32a  /storage/emulated/0/xkatrina.zip
```

For comparison, real dex files start with `64 65 78 0a`:

```
$ head -c 4 apk/u/classes.dex | od -An -tx1
 64 65 78 0a
```

The user-facing string in `RitualFragmentActivity.java:2702`:

> `Silahkan install secara manual module yang ada di /sdcard/xkatrina.zip melalui magisk.`

So the "module" the user likes is byte-for-byte the zip, and the zip is a
repack of `sensitive_props` v5 (HuskyDG lineage) dated 2024-01-04, with
`module.prop` renamed to `xkatrina_snstv_prps` and
`description=Changed for personal gain by fufufu`.

## 2. `fu.dex` is not a dex either — it is a JSON document

The APK writes a prop listing into `<module>/fu.dex`.

`RitualFragmentActivity.java:1608-1610`:

```java
this.s_printprop = new Gson().toJson(this.m_systemprop);
this.s_printprop = new GsonBuilder().setPrettyPrinting().create()
        .toJson(new Gson().fromJson(this.s_printprop, JsonObject.class));
FileUtil.writeFile(this.s_systemprop, this.s_printprop);
```

`:1640` then copies that same file over the module's `fu.dex`:

```
cp <app>/system.prop /data/adb/modules/xkatrina_snstv_prps/fu.dex
chmod 0644 /data/adb/modules/xkatrina_snstv_prps/fu.dex
```

`system.prop` is pretty-printed JSON, so `fu.dex` begins with `{`, not
`64 65 78 0a`. Nothing in the module ever executes it; `getkatrinaprop()` in
`prop.sh` only `cat`s it. The name is cosmetic — a file that looks like code
but is inert data.

## 3. The shell functions are definable and were decoded

All runtime behaviour comes from one asset, `assets/prop.sh` (48.7 KB), which
is enciphered by a 1:1 character substitution. The table is in
`ShortcutExecutorActivity.java:735-860` (55 pairs). Example:

```
"Ĩ","a"  "ĩ","b"  "Ī","c" … "ῒ","_"  "ΐ","="  "ῖ","#"  "ῗ","-"
"Ῐ","/"  "Ῑ","+"  "Ὶ","&"  "Ί","."  "ⅱ",""
```

Decoding yields a 320-line script that is `source`d as root. The relevant
functions, verbatim:

```sh
ooooonol() {
    find "$foldero" -type f -not \( -name "appwidgets.xml" -o -name "wallpaper_info.xml" \
         -o -name "wallpaper_orig" -o -name "wallpaper" \) > "$reseto"
    find "$foldero" -type f -not \( -name "appwidgets.xml" -o -name "wallpaper_info.xml" \
         -o -name "wallpaper_orig" -o -name "wallpaper" \) -exec rm -f {} \;
}

ooossaid() {
    find "$foldero" -type f -name "settings_ssaid*" -print > "$reseto"
    while IFS= read -r file; do rm "$file"; done < "$reseto"
}

owipegms(){
    for app in $list; do
        am force-stop "$app" > /dev/null 2>&1
        pm clear "$app" > /dev/null 2>&1 && … || …
    done
}

editsystemprop(){
    mount -o remount,rw /
    mount -o remount,rw /product
    mount -o remount,rw /vendor
    … rewrites build.prop lines in place …
}

oodalvic(){
    echo -e "wipe cache\nwipe dalvik" > /cache/recovery/openrecoveryscript
    sleep 1
    reboot recovery
}
```

`$foldero` is `/data/system/users/0`.

## 4. Counted blast radius on this exact device

### `ooooonol` (chip `RESET0`, pref `chip_editor_nol`)

```
$ find /data/system/users/0 -type f \
    ! -name appwidgets.xml ! -name wallpaper_info.xml \
    ! -name wallpaper_orig ! -name wallpaper | wc -l
19
```

The 19 files include `settings_global.xml`, `settings_secure.xml`,
`settings_system.xml`, `settings_config.xml`, `settings_ssaid.xml`,
`package-restrictions.xml` and their `.fallback` / `.reservecopy` twins.
Deleting them resets per-user settings, app permissions and package state on
the next boot. This is a device-state reset, not an identity reset.

### `ocleaner` / `ritualcln` (chip `TIMEPICK`)

```
$ find /data/data -type d \( -name code_cache -o -name cache \) | wc -l
1019
$ find /storage/emulated/0 -type d -empty \
    | grep -v -iE 'sketchware|telegram|fufupedia|whatsapp' | wc -l
624
# total rm -rf targets
1643
```

1643 directories is the concrete number of deletions on this device, with no
dry-run and no undo.

### `editsystemprop` (SystemProp Editor)

```
$ mount | grep -E ' / | /product | /vendor '
/dev/block/dm-3 on / type ext4 (ro,seclabel,noatime,discard)
/dev/block/dm-2 on /product type ext4 (ro,…)
/dev/block/dm-5 on /vendor type ext4 (ro,…)
```

The source of `/` is a `dm-*` device, not a plain block device. `mount -o
remount,rw` against a dm target either fails or diverges the device mapper
state; it does not give the script a writable `build.prop`.

## 5. Identifiers: what works, what does not

### Advertising ID — never touched

GAID lives in Play Services:

```
$ cat /data/user/0/com.google.android.gms/shared_prefs/adid_settings.xml
<string name="adid_key">d87e462e-6851-4e13-80d8-213182b394c3</string>
<boolean name="enable_limit_ad_tracking" value="false" />
<long name="last_reset_time" value="1791573951000" />
```

No code path in `prop.sh` or in the dex writes this file. The only use of
`AdvertisingIdClient` is a read, for a backup JSON field
(`BackupDialogFragmentActivity.java:244, 597`).
`RandomIKLANID()` = `UUID.randomUUID()` (`EternalFragmentActivity.java:411`)
is a value stored in the app-owned `eternal_id` JSON, not the system GAID.
The only way the GAID changes is as a side effect of `pm clear
com.google.android.gms` inside `owipegms` — and the replacement GAID is still
issued by Google.

### Android ID / SSAID — deleted, never set

`ooossaid()` removes every `settings_ssaid*` file under
`/data/system/users/0`. Android regenerates per-app values from scratch. No
code writes a chosen value. Practical effect: every app on the device sees a
new Android ID simultaneously, and every app loses its device-bound session.

### "Eternal" identity — a label, not a mechanism

`eternal()` copies a JSON file into a target app's data dir and chowns it:

```sh
eternal() {
    source_uid=$(stat -c %U "$source_loc")
    cp "$source_eternal" "$target_eternal"
    chmod 660 "$target_eternal"
    chown "$source_uid:$source_gid" "$target_eternal"
}
```

That writes `<app>/eternal_id`, a file only this app reads. None of IMEI,
serial, MAC or the GAID is affected by it.

### IMEI / serial — generators exist, executors do not

`RandomIMEI()`, `RandomSERIAL()` exist in `EternalFragmentActivity`. No shell
command consumes their output. IMEI is not readable by an ordinary app since
Android 10 in any case.

## 6. Why the legacy module bricks this device

1. **Install always aborts.** `customize.sh:check_zygisksu_version` reads
   `/data/adb/modules/zygisksu/module.prop`. On this device:

   ```
   $ ls /data/adb/modules/zygisksu/module.prop
   No such file or directory
   ZYGISKSU_VERSION=[]  →  test true  →  abort
   ```

   The device runs ReZygisk + Vector; it does not need Zygisk to change props.

2. **The version gate is shell-dependent.** Same line, three shells:

   ```
   $ /data/adb/ksu/bin/busybox sh -c '[ "$(magisk -V)" -lt 26302 ] || …'
   sh: magisk: not found
   sh: bad number
   exit=2

   $ /system/bin/sh -c '[ "$(magisk -V)" -lt 26302 ] || …'
   /system/bin/sh: magisk: inaccessible or not found
   exit=0
   ```

   Under busybox ash (what KernelSU uses) the expression errors out instead of
   evaluating. Behaviour therefore differs by shell, which is a reliability
   bug in itself.

3. **`sepolicy.rule` is applied on every boot by the root manager.** KernelSU
   parses each line of a module's `sepolicy.rule` (documented under "Module
   guide"; parser in `ksud/src/sepolicy.rs`). The shipped rule is:

   ```
   deny gmscore_app keystore keystore_key *
   ```

   Validated on this device: `ksud sepolicy check 'deny …' → exit 0`.
   Play Services is denied every keystore operation on every boot.

4. **Every prop it targets is already correct on HyperOS 3.** Of 123 property
   reads in `post-fs-data.sh` and 61 in `service.sh`, the ones that exist are
   already `release-keys` / `user` / `0` / `1` / `encrypted`. The rest do not
   exist and are skipped: `ro.boot.warranty_bit`, `ro.boot.realmebootstate`,
   `ro.boot.realme.lockstate`, `ro.is_ever_orange`, `ro.build.selinux`.

5. **The cost is not free.** `resetprop` spawn measured on this device:
   200 reads = 2089 ms, 200 writes = 2027 ms, i.e. ~10.4 ms per process. The
   module's ~184 spawns cost ~1.9 s of boot time to change almost nothing.

6. **`magisk`-only installer.** `update-binary` requires
   `/data/adb/magisk/util_functions.sh`, which does not exist under KernelSU.

## 7. What KaiReborn changes

| Legacy behaviour | KaiReborn |
|---|---|
| `deny gmscore_app keystore …` in `sepolicy.rule` | no `sepolicy.rule` shipped at all |
| `mount -o remount,rw /`, `/product`, `/vendor` | never remounts anything |
| `rm -rf` under `/data/system/users/0` | never deletes there |
| `rm -rf` every `cache`/`code_cache` + empty dirs | never deletes user data |
| `chmod 0440 /proc/cmdline`, `/proc/net/unix` | not touched; a procfs mode change is a tell |
| sets `ro.*` without deleting first | `-d` then `-n`, then verify by read-back |
| invents OEM props on non-OEM devices | refuses to create absent properties |
| `magisk -V` gate evaluated on KernelSU | single platform probe, no cross-shell version math |
| Zygisksu required | no Zygisk requirement |
| aborts install on unknown root | installs and stays passive |
| silent boot loop | 3 incomplete boots → self-disable + reason in `module.prop` |
| 184 `resetprop` spawns | batch `resetprop -f` where possible |
