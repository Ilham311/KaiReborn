#!/system/bin/sh
# KaiReborn — the part that survives an APK overwrite of post-fs-data.sh.
#
# Design rules, each one traced to a real failure in docs/EVIDENCE.md:
#  1. No SELinux deny of any kind. Legacy shipped
#       deny gmscore_app keystore keystore_key *
#     KernelSU applies every line of sepolicy.rule at every boot, so that one
#     line detonates Play Services on every single boot.
#  2. No /data remount rw, no remount of /product or /vendor.
#  3. No deletion of files under /data/system/users/*.
#  4. No removal of cache/ or code_cache/ directories.
#  5. No chmod on /proc/cmdline or /proc/net/unix (a permission difference on
#     procfs is itself a detection signal, and the legacy chmod was a tell).
#  6. Every property write is delete-then-set, then verified by reading back.

kr_guard_post_fs_data() {
  kr_boot_begin || return 0

  local mode; mode="$(kr_mode)"
  kr_log "guard: mode=$mode"

  kr_guard_early

  kr_log "guard: post-fs-data done"
}

# Early-stage property work. Split out on purpose: if the legacy APK replaces
# post-fs-data.sh with its own template (it does), this function never runs at
# the early stage. service.sh calls it again as a late fallback and marks the
# state file so the next boot knows the early stage was skipped.
kr_guard_early() {
  local mode; mode="$(kr_mode)"
  [ "$mode" = "audit" ] && { kr_log "early: audit mode, no writes"; return 0; }

  # Properties that must be set before zygote. Kept byte-for-byte compatible
  # with what the legacy module tried to accomplish, minus the unsafe bits.
  kr_set ro.debuggable 0
  kr_set ro.secure 1
  kr_set ro.build.type user
  kr_set ro.build.tags release-keys
  # Strip custom-ROM taste from build props, but only where the ROM actually
  # ships the property (kr_set refuses to invent absent props).
  local p
  for p in ro.build.description ro.build.fingerprint ro.build.flavor \
           ro.product.name ro.product.bootimage.name; do
    kr_strip_tokens "$p" "aosp_" "lineage_" "lineageos."
    kr_strip_tokens "$p" "test-keys" "release-keys"
    kr_strip_tokens "$p" "userdebug" "user"
  done

  local prefix
  for prefix in system system_ext product vendor odm oem vendor_dlkm odm_dlkm; do
    kr_set "ro.${prefix}.build.tags" release-keys
    kr_set "ro.${prefix}.build.type" user
    kr_strip_tokens "ro.${prefix}.build.fingerprint" "test-keys" "release-keys"
    kr_strip_tokens "ro.${prefix}.build.fingerprint" "userdebug" "user"
    kr_strip_tokens "ro.${prefix}.build.description" "test-keys" "release-keys"
    kr_strip_tokens "ro.${prefix}.build.description" "userdebug" "user"
  done

  # Restore vbmeta claims only when the ROM already has the property, so we
  # never add a key that stock does not have.
  kr_set ro.boot.vbmeta.device_state locked
  kr_set ro.boot.flash.locked 1
  kr_set ro.boot.verifiedbootstate green
  kr_set ro.boot.veritymode enforcing
  kr_set vendor.boot.verifiedbootstate green
  kr_set vendor.boot.vbmeta.device_state locked

  echo "$(date '+%s')" > "$KR_STATE/early_ok" 2>/dev/null
}

# Replace substrings inside a property value without ever introducing one.
kr_strip_tokens() {
  local name="$1" RP cur new
  shift
  RP="$(kr_resetprop)" || return 1
  cur="$("$RP" -v "$name" 2>/dev/null)"
  [ -n "$cur" ] || return 2

  new="$cur"
  while [ $# -ge 2 ]; do
    new="$(printf '%s' "$new" | sed "s|$1|$2|g")"
    shift 2
  done
  [ "$new" = "$cur" ] && return 0
  kr_set "$name" "$new"
}

kr_guard_service() {
  kr_log "service: start impl=$(kr_root_impl)"

  # Late fallback. If post-fs-data.sh was replaced by the legacy APK template,
  # the early stage never ran, so run it now. It is a subset of what post-fs-data
  # would have done and is idempotent, so running it twice is harmless.
  if [ ! -f "$KR_STATE/early_ok" ]; then
    kr_log "service: early stage was skipped (post-fs-data replaced?) — running fallback"
    kr_guard_early
    if [ -f "$KR_STATE/early_ok" ]; then
      kr_set_description "[Active] early-stage fallback used. See logs/boot.log"
    fi
  fi

  # Recovery-boot leftovers: only rewrite when the value already exists.
  kr_set ro.bootmode unknown
  kr_set ro.boot.bootmode unknown
  kr_set ro.boot.mode unknown
  kr_set vendor.bootmode unknown
  kr_set vendor.boot.bootmode unknown
  kr_set vendor.boot.mode unknown

  # MIUI / HyperOS cross-region flash marker.
  kr_strip_tokens ro.boot.hwc CN GLOBAL
  kr_strip_tokens ro.boot.hwcountry China GLOBAL

  # Banking / Play compat knobs, only if present.
  kr_set sys.oem_unlock_allowed 0
  kr_set ro.oem_unlock_supported 0
  kr_set ro.secureboot.devicelock 1
  kr_set ro.secureboot.lockstate locked
  kr_set ro.crypto.state encrypted

  kr_set init.svc.flash_recovery stopped

  # Samsung / Realme / OnePlus branches: harmless when absent, and kr_set
  # refuses to create them, so this cannot fabricate OEM props on a Xiaomi.
  local p
  for p in ro.boot.warranty_bit ro.warranty_bit ro.vendor.boot.warranty_bit \
           ro.vendor.warranty_bit; do kr_set "$p" 0; done
  kr_set ro.boot.realmebootstate green
  kr_set ro.boot.realme.lockstate 1
  kr_set ro.is_ever_orange 0

  # hidden-api policy cleanup is a settings write, not a prop; do it only when
  # the row exists so we do not create new rows.
  for g in hidden_api_policy hidden_api_policy_pre_p_apps hidden_api_policy_p_apps; do
    if settings get global "$g" 2>/dev/null | grep -qv null; then
      settings delete global "$g" >/dev/null 2>&1
      kr_log "settings: deleted global $g"
    fi
  done

  kr_boot_ok
  kr_set_description "[Active] sensitive-prop guard, mode=$(kr_mode). See logs/boot.log"
  kr_log "service: done"
}

# Audit-only entrypoint: report drift, change nothing.
kr_guard_audit() {
  local RP
  RP="$(kr_resetprop)" || { echo "no resetprop"; return 1; }
  echo "impl=$(kr_root_impl)"
  echo "mode=$(kr_mode)"
  echo
  printf '%-42s %s\n' "PROPERTY" "VALUE"
  for p in ro.build.type ro.build.tags ro.build.keys ro.debuggable ro.secure \
           ro.build.fingerprint ro.build.description ro.build.flavor \
           ro.crypto.state sys.oem_unlock_allowed ro.oem_unlock_supported \
           ro.boot.verifiedbootstate ro.boot.vbmeta.device_state \
           ro.boot.flash.locked ro.boot.veritymode init.svc.flash_recovery; do
    printf '%-42s %s\n' "$p" "$("$RP" -v "$p" 2>/dev/null)"
  done
  echo
  echo "drift candidates (custom-ROM traces in any prop):"
  "$RP" 2>/dev/null | grep -E 'lineage|aosp_|eng\.|dev-keys|test-keys|userdebug' \
    | head -40 || echo "  none"
}
