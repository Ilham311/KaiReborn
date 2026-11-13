#!/system/bin/sh
# KaiReborn — installer.
# Deliberately permissive: this module works on Magisk, KernelSU,
# KernelSU-Next and APatch, and does not require Zygisk of any kind.
# The legacy installer aborted unless /data/adb/modules/zygisksu existed,
# which made it uninstallable on a ReZygisk device.

SKIPUNZIP=0

ui_print "- KaiReborn installer"

enforce_install_from_app() {
  if [ "$BOOTMODE" = "true" ]; then
    ui_print "- Installing from app"
  else
    ui_print "! Install from the root manager app, not recovery"
    abort "! Recovery is not supported"
  fi
}

platform_check() {
  if [ -n "$KSU" ] || [ -d /data/adb/ksu ]; then
    ui_print "- KernelSU detected (KSU_VER_CODE=${KSU_VER_CODE:-?}, kernel=${KSU_KERNEL_VER_CODE:-?})"
    [ -x /data/adb/ksud ] && ui_print "- ksud present"
    return 0
  fi
  if [ -n "$APATCH" ] || [ -d /data/adb/ap ]; then
    ui_print "- APatch detected"
    return 0
  fi
  if [ -d /data/adb/magisk ]; then
    ui_print "- Magisk detected (${MAGISK_VER_CODE:-?})"
    return 0
  fi
  ui_print "! Unknown root implementation"
  ui_print "! The module will install but stay passive until it finds resetprop"
}

abi_check() {
  case "$ARCH" in
    arm|arm64|x86|x64) ui_print "- Platform: $ARCH ($ABI)" ;;
    *) abort "! Unsupported platform: $ARCH" ;;
  esac
}

api_check() {
  if [ "${API:-0}" -lt 30 ]; then
    ui_print "! Android $API is below the supported floor (30)"
    ui_print "! Continuing: the module only reads/writes properties"
  fi
}

cleanup_legacy() {
  # If the old module is still installed, its sepolicy.rule still applies a
  # blanket keystore deny on every boot. Offer to neutralise it.
  if [ -d /data/adb/modules/xkatrina_snstv_prps ]; then
    ui_print "! Legacy xkatrina_snstv_prps found"
    ui_print "! Its sepolicy.rule denies keystore to GMS on every boot"
    ui_print "! Disabling it now to prevent Play Services crash loops"
    touch /data/adb/modules/xkatrina_snstv_prps/disable 2>/dev/null
    ui_print "- legacy module disabled (files kept, nothing deleted)"
  fi
}

enforce_install_from_app
abi_check
api_check
platform_check
cleanup_legacy

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/guard.sh" 0 0 0755
set_perm "$MODPATH/common.sh" 0 0 0755
set_perm "$MODPATH/audit.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/kai" 0 0 0755
set_perm_recursive "$MODPATH/scripts" 0 0 0755 0755

mkdir -p "$MODPATH/state" "$MODPATH/logs" 2>/dev/null
echo "safe" > "$MODPATH/state/mode"
chmod 0755 "$MODPATH/state"

ui_print "- Installed. No sepolicy.rule shipped on purpose."
ui_print "- CLI: sh $MODPATH/kai help"
ui_print "- Default mode is 'safe'. Writes need 'kai mode full'."
