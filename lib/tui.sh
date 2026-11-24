# lib/tui.sh — optional gum/dialog adapters with plain-read fallback.
# The hand-rolled console remains the default; no TUI tool is required.

ui_detect_backend() {
  local b=${CFG_UI_BACKEND:-auto}
  if [[ "$b" != auto ]]; then
    printf '%s\n' "$b"
    return 0
  fi
  if [[ -t 0 && -t 1 ]]; then
    if have gum; then printf 'gum\n'; return 0; fi
    if have dialog || have whiptail; then printf 'dialog\n'; return 0; fi
  fi
  printf 'plain\n'
}

ui_restore() {
  if [[ -t 1 ]]; then
    printf '\033[?25h\033[?1049l' 2>/dev/null || true
  fi
  stty echo 2>/dev/null || true
}

ui_confirm() {
  local msg=$1 backend explicit=0
  (( CFG_YES )) && return 0
  [[ "${CFG_UI_BACKEND:-auto}" != auto ]] && explicit=1
  backend=$(ui_detect_backend)
  case "$backend" in
    gum)
      if gum confirm --default false "$msg" >/dev/null 2>&1; then return 0; fi
      return 1 ;;
    dialog)
      local dlg=dialog
      have dialog || dlg=whiptail
      if "$dlg" --title 'PolinRider' --yesno "$msg" 9 60 2>/dev/null; then return 0; fi
      return 1 ;;
    *)
      # Non-interactive automation with default backend: no prompt, proceed.
      # An explicitly requested plain backend still treats missing input as cancel.
      [[ -t 0 ]] || { (( explicit )) && return 1; return 0; }
      local ans=''
      printf '%s [y/N] ' "$msg" >&2
      read -r ans || return 1
      [[ "$ans" =~ ^[Yy] ]] && return 0
      return 1 ;;
  esac
}

ui_choose() {
  local msg=$1; shift
  local -a items=("$@")
  local backend sel dlg args=() i n ans
  backend=$(ui_detect_backend)
  case "$backend" in
    gum)
      sel=$(gum choose "${items[@]}") || return 1
      printf '%s\n' "$sel"
      return 0 ;;
    dialog)
      dlg=dialog; have dialog || dlg=whiptail
      args=(--title 'PolinRider' --menu "$msg" $(( ${#items[@]} + 8 )) 60 10)
      for ((i = 0; i < ${#items[@]}; i++)); do args+=("$((i + 1))" "${items[i]}"); done
      exec 3>&1
      sel=$("$dlg" "${args[@]}" 2>&1 1>&3) || { exec 3>&-; return 1; }
      exec 3>&-
      printf '%s\n' "$sel"
      return 0 ;;
    *)
      [[ -t 0 ]] || return 1
      printf '%s\n' "$msg" >&2
      for ((i = 0; i < ${#items[@]}; i++)); do printf '  %d) %s\n' "$((i + 1))" "${items[i]}" >&2; done
      read -r ans || return 1
      [[ "$ans" =~ ^[0-9]+$ ]] || return 1
      n=$((ans - 1))
      (( n >= 0 && n < ${#items[@]} )) || return 1
      printf '%s\n' "${items[n]}"
      return 0 ;;
  esac
}

ui_picker() {
  local dir=${1:-$PWD} backend sel
  backend=$(ui_detect_backend)
  if [[ "$backend" == gum ]] && have gum; then
    sel=$(gum file --directory --path "$dir" 2>/dev/null) || return 1
    printf '%s\n' "$sel"
    return 0
  fi
  [[ -d "$dir" ]] || return 1
  printf '%s\n' "$dir"
}

ui_spinner() {
  local title=$1; shift
  if [[ "$(ui_detect_backend)" == gum ]] && have gum; then
    gum spin --title "$title" --show-error -- "$@"
    return $?
  fi
  "$@"
}

ui_pager() {
  local file=$1
  if [[ "$(ui_detect_backend)" == gum ]] && have gum; then
    gum pager < "$file"
  else
    cat "$file"
  fi
}

ui_menu() {
  local sel
  sel=$(ui_choose 'PolinRider Toolkit' \
    'Scan now (read-only)' \
    'Block C2 (dry-run first)' \
    'Unblock / rollback' \
    'Clean repo (stage only)' \
    'Sentinel (live console)' \
    'Watch (headless)' \
    'Audit & export' \
    'Config / doctor' \
    'Exit') || return 1
  case "$sel" in
    'Scan now (read-only)') printf 'scan\n' ;;
    'Block C2 (dry-run first)') printf 'block\n' ;;
    'Unblock / rollback') printf 'unblock\n' ;;
    'Clean repo (stage only)') printf 'clean\n' ;;
    'Sentinel (live console)') printf 'sentinel\n' ;;
    'Watch (headless)') printf 'watch\n' ;;
    'Audit & export') printf 'audit\n' ;;
    'Config / doctor') printf 'doctor\n' ;;
    'Exit') printf 'exit\n' ;;
    *) printf '%s\n' "$sel" ;;
  esac
}

# --- hand-rolled sentinel console --------------------------------------------
sentinel_frame_line() {
  local text=$1 cols=${SENTINEL_COLS:-80}
  printf '║ %-*s ║\n' "$((cols - 4))" "$text"
}

sentinel_render() {
  local cols=${SENTINEL_COLS:-80} rows=${SENTINEL_ROWS:-24} threat=NOMINAL line n=0
  if grep -q $'\tCRIT\t' "$ALERTS" 2>/dev/null; then
    threat='INTRUSION DETECTED'
  elif grep -q $'\tWARN\t' "$ALERTS" 2>/dev/null; then
    threat='ELEVATED'
  fi
  if [[ -t 1 ]]; then printf '\033[H\033[2J'; fi
  printf '╔'; printf '═%.0s' $(seq 1 $((cols - 2))); printf '╗\n'
  sentinel_frame_line 'POLINRIDER // THREAT SENTINEL'
  sentinel_frame_line "THREAT LEVEL: $threat"
  if [[ "$threat" == 'INTRUSION DETECTED' ]]; then
    sentinel_frame_line '*** INTRUSION DETECTED — INVESTIGATE NOW ***'
  fi
  sentinel_frame_line "remote: ${#CANARY_REPOS_ARR[@]} repos   branches: $BR_TOTAL   infected: $BR_DIRTY"
  sentinel_frame_line '── RECENT FINDINGS ──'
  while IFS='|' read -r sev src detail msg; do
    [[ -n "$sev" ]] || continue
    sentinel_frame_line "[$sev] $detail — $msg"
    n=$((n + 1))
    (( n < 9 )) || break
  done < <(cat "$R_STATE" "$L_STATE" 2>/dev/null || true)
  sentinel_frame_line 'keys: q quit  p pause  r remote  l local  a ack'
  while (( n < 12 )); do sentinel_frame_line ''; n=$((n + 1)); done
  printf '╚'; printf '═%.0s' $(seq 1 $((cols - 2))); printf '╝\n'
}

sentinel_tui() {
  local interval_r=$1 interval_l=$2 remote_ok=$3; shift 3
  local -a roots=("$@")
  local tick=0 key='' paused=0 i
  if [[ -n "${SENTINEL_SELFTEST:-}" ]]; then
    for ((i = 0; i < SENTINEL_SELFTEST; i++)); do sentinel_render; done
    return 0
  fi
  if [[ -t 1 ]]; then printf '\033[?1049h\033[?25l'; fi
  while :; do
    tick=$((tick + 1))
    if (( ! paused )); then
      if (( remote_ok )) && (( tick % interval_r == 0 )); then canary_remote_sweep || true; fi
      if (( tick % interval_l == 0 )); then canary_local_sweep "${roots[@]}" || true; fi
    fi
    sentinel_render
    key=''
    if IFS= read -r -t 1 -n 1 key; then
      case "$key" in
        q) break ;;
        p) paused=$((1 - paused)) ;;
        r) (( remote_ok )) && canary_remote_sweep || true ;;
        l) canary_local_sweep "${roots[@]}" || true ;;
        a) : > "$ALERTS" ;;
      esac
    fi
  done
  return 0
}
