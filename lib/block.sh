# lib/block.sh — hosts / firewall / DNS blocking with marker-only rollback.

MARKER_BEGIN='# === BEGIN polinrider IOC block ==='
MARKER_END='# === END polinrider IOC block ==='
PF_ANCHOR_NAME='polinrider_iocs'
PF_ANCHOR_FILE="/etc/pf.anchors/${PF_ANCHOR_NAME}"

hosts_backup() {
  local ts bak
  ts=$(date +'%Y%m%d-%H%M%S')
  bak="$CFG_BACKUP_DIR/hosts.bak.$ts"
  [[ -f "$CFG_HOSTS_FILE" ]] || die 1 "hosts file not found: $CFG_HOSTS_FILE"
  run_cmd cp -p "$CFG_HOSTS_FILE" "$bak"
  if (( ! CFG_DRY_RUN )); then chmod 0600 "$bak"; fi
  ok "backed up $CFG_HOSTS_FILE to $bak"
}

hosts_strip_block() {
  local src="$CLEANUP_DIR/hosts.stripped"
  awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
    $0 == b { inside=1; next }
    $0 == e { inside=0; next }
    !inside { print }
  ' "$CFG_HOSTS_FILE" > "$src"
  write_file "$CFG_HOSTS_FILE" "$src"
}

hosts_write_block() {
  local src="$CLEANUP_DIR/hosts.block" d
  {
    cat "$CFG_HOSTS_FILE"
    printf '%s\n' "$MARKER_BEGIN"
    while IFS= read -r -d '' d; do
      printf '0.0.0.0 %s\n' "$d"
      printf ':: %s\n' "$d"
    done < "$IOC_DOMAINS_FILE"
    printf '%s\n' "$MARKER_END"
  } > "$src"
  write_file "$CFG_HOSTS_FILE" "$src"
  ok "wrote $IOC_DOMAINS_N hosts entries to $CFG_HOSTS_FILE"
}

fw_detect() {
  local c
  case "$CFG_FIREWALL_BACKEND" in
    none) printf 'none\n'; return 0 ;;
    auto)
      for c in nft iptables ufw pfctl powershell.exe; do
        if have "$c"; then printf '%s\n' "$c"; return 0; fi
      done
      printf 'none\n'; return 0 ;;
    pf) have pfctl && printf 'pf\n' || printf 'none\n'; return 0 ;;
    powershell) have powershell.exe && printf 'powershell\n' || printf 'none\n'; return 0 ;;
    *) have "$CFG_FIREWALL_BACKEND" && printf '%s\n' "$CFG_FIREWALL_BACKEND" || printf 'none\n'; return 0 ;;
  esac
}

_fw_each_ip() {
  local callback=$1 ip
  while IFS= read -r -d '' ip; do
    "$callback" "$ip"
  done < "$IOC_IPS_FILE"
}

_fw_nft_ip() {
  local ip=$1 family='iocs4' type='ipv4_addr'
  [[ "$ip" == *:* ]] && { family='iocs6'; type='ipv6_addr'; }
  run_cmd nft add element inet polinrider "$family" "{ $ip }"
}

_fw_nft() {
  run_cmd nft add table inet polinrider || return 1
  run_cmd nft 'add set inet polinrider iocs4 { type ipv4_addr; }' || return 1
  run_cmd nft 'add set inet polinrider iocs6 { type ipv6_addr; }' || return 1
  _fw_each_ip _fw_nft_ip || return 1
  run_cmd nft 'add chain inet polinrider out { type filter hook output priority 0; policy accept; }' || return 1
  run_cmd nft add rule inet polinrider out 'ip daddr @iocs4 drop' || return 1
  run_cmd nft add rule inet polinrider out 'ip6 daddr @iocs6 drop' || return 1
  ok 'nft: polinrider table active'
}

_fw_iptables_ip() {
  local ip=$1
  if ! iptables -C OUTPUT -d "$ip" -j DROP 2>/dev/null; then
    run_cmd iptables -A OUTPUT -d "$ip" -m comment --comment polinrider -j DROP
  fi
}

_fw_iptables() {
  run_cmd iptables -N POLINRIDER 2>/dev/null || true
  _fw_each_ip _fw_iptables_ip || return 1
  if ! iptables -C OUTPUT -j POLINRIDER 2>/dev/null; then
    run_cmd iptables -I OUTPUT -j POLINRIDER
  fi
  if have ip6tables; then
    local ip
    while IFS= read -r -d '' ip; do
      [[ "$ip" == *:* ]] || continue
      if ! ip6tables -C OUTPUT -d "$ip" -j DROP 2>/dev/null; then
        run_cmd ip6tables -A OUTPUT -d "$ip" -m comment --comment polinrider -j DROP
      fi
    done < "$IOC_IPS_FILE"
  fi
  ok 'iptables: polinrider rules active'
}

_fw_ufw_ip() {
  local ip=$1
  run_cmd ufw deny out to "$ip" comment polinrider || true
}

_fw_ufw() {
  _fw_each_ip _fw_ufw_ip || return 1
  ok 'ufw: polinrider rules active'
}

_fw_pf() {
  local src="$CLEANUP_DIR/pf.anchor" conf="$CLEANUP_DIR/pf.conf" line
  {
    printf '# polinrider IOC block\n'
    while IFS= read -r -d '' ip; do printf 'block drop out quick from any to %s\n' "$ip"; done < "$IOC_IPS_FILE"
  } > "$src"
  write_file "$PF_ANCHOR_FILE" "$src" || return 1
  if have pfctl; then
    grep -q "anchor \"$PF_ANCHOR_NAME\"" /etc/pf.conf 2>/dev/null || {
      { cat /etc/pf.conf 2>/dev/null; printf 'anchor "%s"\n' "$PF_ANCHOR_NAME"; } > "$conf"
      write_file /etc/pf.conf "$conf" || return 1
    }
    run_cmd pfctl -e 2>/dev/null || true
    run_cmd pfctl -a "$PF_ANCHOR_NAME" -f "$PF_ANCHOR_FILE" || return 1
  fi
  ok 'pf: polinrider anchor active'
}

_fw_ps_ip() {
  local ip=$1 ps
  ps="New-NetFirewallRule -DisplayName 'polinrider-$ip' -Direction Outbound -RemoteAddress '$ip' -Action Block -Group polinrider -ErrorAction SilentlyContinue"
  run_cmd powershell.exe -NoProfile -Command "$ps"
}

_fw_powershell() {
  _fw_each_ip _fw_ps_ip || return 1
  ok 'powershell.exe: polinrider firewall group active'
}

fw_block() {
  local backend; backend=$(fw_detect)
  if [[ "$backend" == none ]]; then
    warn 'No supported firewall tool found (nft, iptables, ufw, pf, powershell.exe). IP-level blocking skipped.'
    return 0
  fi
  if (( IOC_IPS_N == 0 )); then
    out_note 'firewall' "no IPs in IOC file; backend $backend unused"
    return 0
  fi
  log "firewall backend: $backend"
  case "$backend" in
    nft) _fw_nft ;;
    iptables) _fw_iptables ;;
    ufw) _fw_ufw ;;
    pf) _fw_pf ;;
    powershell) _fw_powershell ;;
    *) warn "unsupported backend: $backend"; return 1 ;;
  esac
}

dns_flush() {
  local os; os=$(uname -s)
  case "$os" in
    Darwin)
      run_cmd dscacheutil -flushcache 2>/dev/null || true
      run_cmd killall -HUP mDNSResponder 2>/dev/null || true ;;
    Linux)
      if have resolvectl; then run_cmd resolvectl flush-caches 2>/dev/null || true
      elif have systemd-resolve; then run_cmd systemd-resolve --flush-caches 2>/dev/null || true
      fi ;;
    MINGW*|MSYS*|CYGWIN*) run_cmd ipconfig /flushdns 2>/dev/null || true ;;
  esac
  ok 'DNS cache flush requested'
}

fw_unblock() {
  local backend ip
  backend=$(fw_detect)
  case "$backend" in
    nft) run_cmd nft delete table inet polinrider 2>/dev/null || true ;;
    iptables)
      while IFS= read -r -d '' ip; do
        run_cmd iptables -D OUTPUT -d "$ip" -m comment --comment polinrider -j DROP 2>/dev/null || true
      done < "$IOC_IPS_FILE"
      run_cmd iptables -F POLINRIDER 2>/dev/null || true
      run_cmd iptables -X POLINRIDER 2>/dev/null || true ;;
    ufw)
      while IFS= read -r -d '' ip; do
        run_cmd ufw delete deny out to "$ip" 2>/dev/null || true
      done < "$IOC_IPS_FILE" ;;
    pf)
      run_cmd pfctl -a "$PF_ANCHOR_NAME" -F rules 2>/dev/null || true
      run_cmd rm -f "$PF_ANCHOR_FILE" 2>/dev/null || true ;;
    powershell)
      run_cmd powershell.exe -NoProfile -Command 'Remove-NetFirewallRule -Group polinrider -ErrorAction SilentlyContinue' 2>/dev/null || true ;;
  esac
  return 0
}

block_rollback() {
  local changed=0
  if grep -qF "$MARKER_BEGIN" "$CFG_HOSTS_FILE" 2>/dev/null; then
    hosts_strip_block && changed=1
  fi
  fw_unblock || true
  dns_flush || true
  if (( changed )); then
    ok 'removed polinrider hosts block'
  else
    ok 'Nothing to remove'
  fi
  BLOCK_APPLIED=0
  return 0
}

block_apply() {
  local keep_partial=$1
  BLOCK_APPLIED=0
  hosts_backup || return 1
  hosts_strip_block || return 1
  hosts_write_block || return 1
  BLOCK_APPLIED=1
  if ! fw_block; then
    if (( keep_partial )); then
      warn 'firewall step failed; keeping partial state (--keep-partial)'
    else
      err 'firewall step failed; rolling back'
      block_rollback || true
      return 1
    fi
  fi
  dns_flush || true
  BLOCK_APPLIED=0
  ok 'block applied'
  return 0
}

block_verify() {
  local timeout=$1; shift
  local d resolved failed=0
  for d in "$@"; do
    [[ -n "$d" ]] || continue
    resolved=''
    if have getent; then
      resolved=$(getent hosts "$d" 2>/dev/null | awk '{print $1; exit}' || true)
    fi
    if [[ -z "$resolved" || "$resolved" == '0.0.0.0' || "$resolved" == '::' ]]; then
      ok "$d -> ${resolved:-no answer} (blocked)"
    else
      err "$d -> $resolved (still resolving)"
      failed=1
    fi
    if have curl && curl -fsS --max-time "$timeout" "https://$d" >/dev/null 2>&1; then
      err "$d is still reachable over HTTPS"
      failed=1
    fi
  done
  return "$failed"
}
