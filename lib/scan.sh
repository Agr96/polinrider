# lib/scan.sh — read-only scanner (Part A repo payloads, B host evidence, C logs).
# Collects ONE inventory for all checks; never uses an undefined $INV.

SCAN_INVENTORY=""
MAX_FINDINGS=50

build_inventory() {
  local root
  SCAN_INVENTORY="$CLEANUP_DIR/inventory"
  : > "$SCAN_INVENTORY"
  for root in "$@"; do
    [[ -d "$root" ]] || continue
    find "$root" -maxdepth 8 -type f \
      -not -path '*/node_modules/*' -not -path '*/.git/*' \
      -not -path '*/venv/*' -not -path '*/.venv/*' \
      -not -path '*/dist/*' -not -path '*/build/*' \
      -not -path '*/.next/*' -not -path '*/.nuxt/*' \
      -print0 >> "$SCAN_INVENTORY" 2>/dev/null || true
  done
  return 0
}

_file_magic() {
  local f=$1
  if have xxd; then
    head -c 4 "$f" 2>/dev/null | xxd -p | tr -d '\n'
  else
    head -c 4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n'
  fi
}

scan_repo_payloads() {
  local f found n magic want desc
  out_section 'PART A — REPO PAYLOAD SCAN'

  out_sub 'A1. JS payload signatures in tracked source files'
  found=0; n=0
  while IFS= read -r -d '' f; do
    case "$f" in
      *.js|*.mjs|*.cjs|*.ts|*.tsx|*.jsx|*.vue|*.svelte) ;;
      *) continue ;;
    esac
    if grep -qE "$SIG_PAYLOAD" "$f" 2>/dev/null; then
      out_hit A1 "$f" 'JS payload signature'
      found=1; n=$((n + 1))
      (( n < MAX_FINDINGS )) || break
    fi
  done < "$SCAN_INVENTORY"
  (( found )) || out_ok A1 'no payload signatures'

  out_sub 'A2. Fake font/asset payloads (wrong magic + signature)'
  found=0; n=0
  while IFS= read -r -d '' f; do
    case "$f" in
      *.woff2) want='774f4632' ;;
      *.woff)  want='774f4646' ;;
      *.ttf)   want='00010000|74727565|4f54544f' ;;
      *) continue ;;
    esac
    magic=$(_file_magic "$f")
    if [[ -n "$magic" ]] && ! printf '%s' "$magic" | grep -qE "^($want)$"; then
      if grep -qE "$SIG_PAYLOAD|require|process\.|child_process" "$f" 2>/dev/null; then
        out_hit A2 "$f" "magic=$magic, looks like JS not font"
        found=1; n=$((n + 1))
        (( n < MAX_FINDINGS )) || break
      fi
    fi
  done < "$SCAN_INVENTORY"
  (( found )) || out_ok A2 'no fake font files'

  # A2b — fixed: this used an undefined $INV in the legacy Linux scanner.
  out_sub 'A2b. PolinRider canonical fake font (public/fonts/fa-solid-400.woff2)'
  found=0
  while IFS= read -r -d '' f; do
    case "$f" in
      */fa-solid-400.woff2|fa-solid-400.woff2) ;;
      *) continue ;;
    esac
    [[ -f "$f" ]] || continue
    magic=$(_file_magic "$f")
    desc="magic=$magic"
    if [[ "$magic" != 774f4632* ]]; then
      if grep -qE "$SIG_PAYLOAD|$TASKSJACKER_CMD_RE|rmcej" "$f" 2>/dev/null || \
         [[ "$(file -b "$f" 2>/dev/null)" == *'text'* ]]; then
        out_hit A2b "$f" "$desc, ASCII/JS font"
        found=1
      fi
    fi
  done < "$SCAN_INVENTORY"
  (( found )) || out_ok A2b 'no PolinRider fa-solid-400.woff2 payload file'

  out_sub 'A3. Malicious .vscode/tasks.json with auto-execute (TasksJacker)'
  found=0; n=0
  while IFS= read -r -d '' f; do
    case "$f" in */.vscode/tasks.json) ;; *) continue ;; esac
    if grep -qE 'runOn["'"'"' ]*:["'"'"' ]*folderOpen' "$f" 2>/dev/null; then
      if grep -qE "node[[:space:]]+.*\.(woff|ttf|eot)|curl[^|]*\| *(bash|sh|zsh)|wget[^|]*\| *(bash|sh|zsh)|$SIG_C2_VERCEL|$SIG_C2_RPC|$SIG_EVIL_UUID" "$f" 2>/dev/null; then
        out_hit A3 "$f" 'folderOpen auto-task with executable payload'
        found=1; n=$((n + 1))
        (( n < MAX_FINDINGS )) || break
      else
        out_review A3 "$f" 'runOn:folderOpen — manual review'
      fi
    fi
  done < "$SCAN_INVENTORY"
  (( found )) || out_ok A3 'no folderOpen auto-tasks with payload'

  out_sub 'A3b. Canonical TasksJacker command in tasks.json'
  found=0
  while IFS= read -r -d '' f; do
    case "$f" in */.vscode/tasks.json) ;; *) continue ;; esac
    if grep -qE "$TASKSJACKER_CMD_RE" "$f" 2>/dev/null; then
      out_hit A3b "$f" 'executes fake woff2 via node'
      found=1
    fi
  done < "$SCAN_INVENTORY"
  (( found )) || out_ok A3b 'no canonical TasksJacker command'

  out_sub 'A4. .vscode/settings.json with task.allowAutomaticTasks:true'
  found=0
  while IFS= read -r -d '' f; do
    case "$f" in */.vscode/settings.json) ;; *) continue ;; esac
    if grep -qE '"task\.allowAutomaticTasks"[[:space:]]*:[[:space:]]*true' "$f" 2>/dev/null; then
      out_review A4 "$f" 'sets allowAutomaticTasks:true'
      found=1
    fi
  done < "$SCAN_INVENTORY"
  (( found )) || out_ok A4 'no allowAutomaticTasks:true'

  out_sub 'A5. Propagation script names referenced'
  found=0; n=0
  while IFS= read -r -d '' f; do
    case "$f" in
      *.md|*.json|*.yml|*.yaml|*.sh|*.bat|*.cmd|*.ps1|*.txt|*.js|*.mjs|*.cjs|*.ts|.gitignore) ;;
      *) continue ;;
    esac
    if grep -qE 'temp_auto_push\.bat|temp_interactive_push\.bat' "$f" 2>/dev/null; then
      out_hit A5 "$f" 'propagation dropper reference'
      found=1; n=$((n + 1))
      (( n < MAX_FINDINGS )) || break
    fi
  done < "$SCAN_INVENTORY"
  (( found )) || out_ok A5 'no propagation refs'

  out_sub 'A6. Malicious npm dependency in package.json'
  found=0
  while IFS= read -r -d '' f; do
    case "$f" in */package.json|package.json) ;; *) continue ;; esac
    if grep -qF "$SIG_EVIL_NPM" "$f" 2>/dev/null; then
      out_hit A6 "$f" "$SIG_EVIL_NPM"
      found=1
    fi
  done < "$SCAN_INVENTORY"
  (( found )) || out_ok A6 'no malicious npm dep'

  out_sub 'A7. Weaponized take-home UUIDs'
  found=0
  while IFS= read -r -d '' f; do
    case "$f" in *.json) ;; *) continue ;; esac
    if grep -qE "$SIG_EVIL_UUID" "$f" 2>/dev/null; then
      out_hit A7 "$f" 'weaponized UUID'
      found=1
    fi
  done < "$SCAN_INVENTORY"
  (( found )) || out_ok A7 'no take-home UUIDs'

  out_sub 'A8. Git history: TZ-mismatch spoofing fingerprint'
  found=0
  local root gitdir repo sus
  for root in "${SCAN_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r -d '' gitdir; do
      repo="${gitdir%/.git}"
      sus=$(git -C "$repo" log --all -n 500 --format='%h|%ai|%ci|%ae|%ce|%s' 2>/dev/null | awk -F'|' '
        { atz=substr($2,length($2)-4); ctz=substr($3,length($3)-4);
          if (atz != ctz && $4 == $5) print $1" "atz"/"ctz" "$4" "substr($6,1,50) }' | awk 'NR<=3') || true
      if [[ -n "$sus" ]]; then
        out_review A8 "$repo" "TZ-mismatch commits"
        while IFS= read -r desc; do out_note A8 "      $desc"; done <<< "$sus"
        found=1
      fi
    done < <(find "$root" -maxdepth 4 -name .git -type d -print0 2>/dev/null || true)
  done
  (( found )) || out_ok A8 'no TZ-mismatch commits'
  return 0
}

scan_host_evidence() {
  local f found n
  out_section 'PART B — HOST EXECUTION-EVIDENCE SCAN'
  local -a hosts=(/tmp /var/tmp "$HOME/.npm" "$HOME/.cache" "$HOME/.local/share")
  [[ -d /dev/shm ]] && hosts+=(/dev/shm)
  local os; os=$(uname -s)
  if [[ "$os" == Darwin ]]; then hosts+=("$HOME/Library/Caches" "$HOME/Library/Application Support"); fi

  out_sub 'B1/B2. Exfil staging dirs and credential dumps'
  found=0; n=0
  for f in "${hosts[@]}"; do
    [[ -d "$f" ]] || continue
    while IFS= read -r -d '' d; do
      out_hit B1 "$d" 'exfil staging directory name'
      found=1; n=$((n + 1))
      (( n < MAX_FINDINGS )) || break
    done < <(find "$f" -maxdepth 5 -type d \
      -name '*[$]*_[0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]*' \
      -print0 2>/dev/null || true)
    while IFS= read -r -d '' d; do
      out_hit B2 "$d" 'credential/env dump artifact'
      found=1; n=$((n + 1))
      (( n < MAX_FINDINGS )) || break
    done < <(find "$f" -maxdepth 6 -type f \
      \( -name '_credentials.json' -o -name '_sysenv.json' -o -name '_sysenv.env' -o -name '_info.json' \) \
      -print0 2>/dev/null || true)
  done
  (( found )) || out_ok B1 'no exfil staging dirs or credential dumps'

  out_sub 'B3. Exfil zip archives'
  found=0
  for f in /tmp "$HOME"; do
    [[ -d "$f" ]] || continue
    while IFS= read -r -d '' d; do
      out_hit B3 "$d" 'suspicious exfil zip'
      found=1
    done < <(find "$f" -maxdepth 4 -type f -name '*.zip' -print0 2>/dev/null | while IFS= read -r -d '' z; do
      [[ "$z" =~ \$ ]] && printf '%s\0' "$z"
    done || true)
  done
  (( found )) || out_ok B3 'no exfil zips'

  out_sub 'B4. Known temporary artifact'
  found=0
  for f in /tmp/tmp7A863DD1.tmp "$HOME/tmp7A863DD1.tmp"; do
    if [[ -e "$f" ]]; then out_hit B4 "$f" 'known artifact'; found=1; fi
  done
  (( found )) || out_ok B4 'no known tmp artifact'

  out_sub 'B10. Processes loading fonts / contacting C2'
  found=0
  if have ps; then
    local line
    while IFS= read -r line; do
      out_hit B10 "$line" 'suspicious process'
      found=1
    done < <(ps auxww 2>/dev/null | grep -E 'fa-solid-400\.woff2|166\.88\.54\.158' | grep -v grep | awk 'NR<=10' || true)
  fi
  (( found )) || out_ok B10 'no suspicious processes'

  out_sub 'B11. Network connections to C2 IP'
  found=0
  local conn=''
  if have ss; then
    conn=$(ss -tunp 2>/dev/null | grep -F '166.88.54.158' | awk 'NR<=5' || true)
  elif have lsof; then
    conn=$(lsof -nP -i 2>/dev/null | grep -F '166.88.54.158' | awk 'NR<=5' || true)
  fi
  if [[ -n "$conn" ]]; then
    while IFS= read -r line; do out_hit B11 "$line" 'C2 connection'; found=1; done <<< "$conn"
  else
    out_ok B11 'no C2 connections'
  fi

  out_sub 'B12. Passive IOC check only (no DNS probing)'
  out_note B12 'DNS probing of IOC domains is intentionally disabled (false positives)'
  return 0
}

scan_deep_logs() {
  local full=$1; shift
  (( full )) || return 0
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    note '[!] skip — re-run with sudo for Part C (deep logs)'
    return 0
  fi
  out_section 'PART C — DEEP LOG SEARCH (requires root)'
  local os; os=$(uname -s)
  local hits=0 line
  if [[ "$os" == Linux ]] && have journalctl; then
    while IFS= read -r line; do
      out_hit C "$line" 'IOC in journal'
      hits=$((hits + 1))
    done < <(journalctl --no-pager -n 2000 2>/dev/null | grep -E "$SIG_ALL" | awk 'NR<=20' || true)
  elif [[ "$os" == Darwin ]] && have log; then
    while IFS= read -r line; do
      out_hit C "$line" 'IOC in unified log'
      hits=$((hits + 1))
    done < <(log show --last 1h --style compact 2>/dev/null | grep -E "$SIG_ALL" | awk 'NR<=20' || true)
  else
    out_note C 'no supported deep-log source on this host'
  fi
  (( hits )) || out_ok C 'no deep-log IOC matches'
  return 0
}

scan_all() {
  local full=$1; shift
  SCAN_ROOTS=("$@")
  build_inventory "${SCAN_ROOTS[@]}"
  scan_repo_payloads
  scan_host_evidence
  scan_deep_logs "$full"
  out_summary
  return 0
}
