# lib/ioc.sh — parse iocs.txt into NUL-delimited files (spaces are safe).

IOC_DOMAINS_FILE=""
IOC_IPS_FILE=""

ioc_is_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local o oldifs=$IFS
  local -a octets=()
  IFS='.'
  read -r -a octets <<< "$1"
  IFS=$oldifs
  [[ ${#octets[@]} -eq 4 ]] || return 1
  for o in "${octets[@]}"; do
    [[ "$o" =~ ^[0-9]+$ ]] && (( o <= 255 )) || return 1
  done
  return 0
}

ioc_is_ipv6() {
  [[ "$1" == *:* ]] || return 1
  [[ "$1" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
  return 0
}

ioc_is_ip() { ioc_is_ipv4 "$1" || ioc_is_ipv6 "$1"; }

ioc_is_domain() {
  local d=$1
  (( ${#d} >= 1 && ${#d} <= 253 )) || return 1
  [[ "$d" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
  [[ "$d" != -* && "$d" != *- && "$d" != .* && "$d" != *. && "$d" != *..* ]] || return 1
  return 0
}

ioc_parse() {
  local file=${1:-$CFG_IOC_FILE} line raw
  [[ -f "$file" ]] || die 2 "IOC file not found: $file"
  IOC_DOMAINS_FILE="$CLEANUP_DIR/ioc.domains"
  IOC_IPS_FILE="$CLEANUP_DIR/ioc.ips"
  : > "$IOC_DOMAINS_FILE"
  : > "$IOC_IPS_FILE"
  local ndom=0 nip=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    raw="${line%%#*}"
    raw="${raw#"${raw%%[![:space:]]*}"}"
    raw="${raw%"${raw##*[![:space:]]}"}"
    [[ -z "$raw" ]] && continue
    if ioc_is_ip "$raw"; then
      printf '%s\0' "$raw" >> "$IOC_IPS_FILE"
      nip=$((nip + 1))
    elif ioc_is_domain "$raw"; then
      printf '%s\0' "$raw" >> "$IOC_DOMAINS_FILE"
      ndom=$((ndom + 1))
    else
      die 2 "invalid IOC line: $raw"
    fi
  done < "$file"
  IOC_DOMAINS_N=$ndom
  IOC_IPS_N=$nip
  ok "Loaded $ndom domains and $nip IPs from $file"
}

ioc_each_domain() {
  local callback=$1 f
  while IFS= read -r -d '' f; do
    "$callback" "$f"
  done < "$IOC_DOMAINS_FILE"
}

ioc_each_ip() {
  local callback=$1 f
  while IFS= read -r -d '' f; do
    "$callback" "$f"
  done < "$IOC_IPS_FILE"
}
