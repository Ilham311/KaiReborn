#!/system/bin/sh
# KaiReborn — identity profiles.
#
# The legacy "Eternal" feature generated random values (ANDROIDID, IMEI,
# BLUETHOOTNAME, DEVICENAME, SERIAL ...) and wrote them into a JSON blob that
# only its own app read. Nothing system-visible changed.
#
# KaiReborn keeps the idea and makes it real where the platform allows it:
#
#   properties  -> applied through the guarded resetprop path (verify-after-set)
#   device name -> settings put global device_name / secure bluetooth_name
#   Android ID  -> NOT spoofable. Only regenerable (ops.sh ssaid).
#   IMEI/serial -> NOT addressable. No code path offered.
#
# A profile is a plain file: state/profile/<name>.prop with NAME=VALUE lines.

kr_profile_dir() { echo "$KR_STATE/profile"; }

kr_profile_list() {
  local d; d="$(kr_profile_dir)"
  mkdir -p "$d" 2>/dev/null
  [ -d "$d" ] || return 0
  for f in "$d"/*.prop; do
    [ -f "$f" ] || continue
    printf '%-20s %s entries\n' "$(basename "$f" .prop)" "$(grep -c '=' "$f" 2>/dev/null)"
  done
}

kr_profile_show() {
  local n="$1" f
  f="$(kr_profile_dir)/$n.prop"
  [ -f "$f" ] || { echo "no such profile: $n"; return 1; }
  cat "$f"
}

kr_profile_apply() {
  local n="$1" mode="${2:-plan}" f
  f="$(kr_profile_dir)/$n.prop"
  [ -f "$f" ] || { echo "no such profile: $n"; return 1; }

  echo "── profile: $n ($mode) ──"
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    local k="${line%%=*}" v="${line#*=}"
    echo "  $k = $v"
    [ "$mode" = "apply" ] && kr_set "$k" "$v"
  done < "$f"

  # Device name lives in settings, not properties.
  local dn
  dn="$(sed -n 's/^ro\.product\.model=//p' "$f" | head -1)"
  [ -n "$dn" ] || return 0
  if [ "$mode" = "apply" ]; then
    settings put global device_name "$dn" 2>/dev/null
    settings put secure bluetooth_name "$dn" 2>/dev/null
    echo "  device name -> $dn"
    kr_log "profile $n applied"
  else
    echo "  would set device name -> $dn"
  fi
}

kr_profile_create() {
  local n="$1"; shift
  local d; d="$(kr_profile_dir)"; mkdir -p "$d" 2>/dev/null
  local f="$d/$n.prop"
  [ -f "$f" ] && { echo "profile exists: $n (edit $f)"; return 1; }
  : > "$f"
  # Seed from the values currently reported by the platform, so a profile is a
  # snapshot you can edit, not a random fantasy.
  local p
  for p in ro.product.manufacturer ro.product.model ro.product.brand \
           ro.product.device ro.product.name ro.build.fingerprint \
           ro.build.description ro.build.version.release ro.build.version.sdk \
           ro.build.tags ro.build.type; do
    local v; v="$(kr_get "$p")"
    [ -n "$v" ] && echo "$p=$v" >> "$f"
  done
  echo "created: $f"
  echo "edit it, then: $0 profile apply $n --apply"
}
