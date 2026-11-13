#!/system/bin/sh
# KaiReborn — boot entrypoint.
#
# IMPORTANT COMPATIBILITY CONTRACT
# The legacy Katrina APK overwrites <module>/post-fs-data.sh with its own
# template (it copies a full script over this path). Anything we put here can
# be destroyed by that app. Therefore everything that must survive lives in
# guard.sh / common.sh, and this file is deliberately a thin shim: it only
# loads the guard if it is still present.
#
# If guard.sh is missing, we do nothing at all. Doing nothing is safe.

MODDIR="${0%/*}"
[ -n "$MODDIR" ] || MODDIR="/data/adb/modules/kaireborn"

# If the legacy APK dropped its own template here, it will not have written
# this marker, and guard.sh stays in charge.
if [ -f "$MODDIR/guard.sh" ]; then
  . "$MODDIR/common.sh"
  . "$MODDIR/guard.sh"
  kr_guard_post_fs_data
fi

# Legacy-name compatibility: the APK writes fu.dex (actually a JSON doc, see
# docs/EVIDENCE.md) and expects resetprop.sh to exist in the module dir.
if [ -f "$MODDIR/resetprop.sh" ] && [ -f "$MODDIR/fu.dex" ]; then
  . "$MODDIR/resetprop.sh" 2>/dev/null
fi
