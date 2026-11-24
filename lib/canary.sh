# lib/canary.sh — headless watcher + sentinel workers (state format preserved).

CANARY_REPOS_ARR=()
CANARY_TRUSTED_ARR=()
R_STATE=''
L_STATE=''
ALERTS=''
SEEN_DIR=''
BRANCH_DIR=''
BR_TOTAL=0
BR_DIRTY=0

_set_words() { # sets global array named $1 from IFS-space string $2
  local name=$1 s=$2
  local -a tmp=()
  local oldifs=$IFS
  IFS=' '
  read -r -a tmp <<< "$s"
  IFS=$oldifs
  # Populate through a fixed dispatch (no eval, no declare -n).
  local f="$CLEANUP_DIR/words.$name"
  : > "$f"
  local w
  for w in "${tmp[@]}"; do
    [[ -n "$w" ]] && printf '%s\0' "$w" >> "$f"
  done
  array_from_nul_file "$name" "$f"
}

# No eval: caller passes the array name, we populate through a NUL loop in a subshell-free way.
array_from_nul_file() {
  local name=$1 f=$2 w
  local -a vals=()
  while IFS= read -r -d '' w; do vals+=("$w"); done < "$f"
  case "$name" in
    CANARY_REPOS_ARR) CANARY_REPOS_ARR=("${vals[@]}") ;;
    CANARY_TRUSTED_ARR) CANARY_TRUSTED_ARR=("${vals[@]}") ;;
  esac
}

canary_init() {
  mkdir -p -- "$CFG_STATE_DIR/canary"
  chmod 0700 "$CFG_STATE_DIR/canary" 2>/dev/null || true
  local repos trusted
  if [[ -n "${CANARY_REPOS:-}" ]]; then
    repos="$CANARY_REPOS"
  elif [[ -n "${CFG_CANARY_REPOS:-}" ]]; then
    repos="$CFG_CANARY_REPOS"
  elif [[ -n "${CFG_CANARY_REPO_FILE:-}" && -f "${CFG_CANARY_REPO_FILE:-}" ]]; then
    repos=$(grep -vE '^[[:space:]]*(#|$)' "$CFG_CANARY_REPO_FILE" | tr '\n' ' ')
  elif [[ -n "${CANARY_REPOS:-}" ]]; then
    repos="$CANARY_REPOS"
  else
    repos=''
  fi
  [[ -n "$repos" ]] || repos="${CANARY_REPOS:-}"
  _set_words CANARY_REPOS_ARR "$repos"

  trusted="${CANARY_TRUSTED_ACTORS:-}"
  if [[ -n "${CFG_CANARY_TRUSTED_FILE:-}" && -f "${CFG_CANARY_TRUSTED_FILE:-}" ]]; then
    trusted=$(grep -vE '^[[:space:]]*(#|$)' "$CFG_CANARY_TRUSTED_FILE" | tr '\n' ' ')
  elif [[ -n "${CFG_CANARY_TRUSTED_ACTORS:-}" ]]; then
    trusted="$CFG_CANARY_TRUSTED_ACTORS"
  elif [[ -n "${CANARY_TRUSTED_ACTORS:-}" ]]; then
    trusted="$CANARY_TRUSTED_ACTORS"
  fi
  [[ -n "$trusted" ]] || trusted='sam1am github-actions[bot] dependabot[bot] renovate[bot]'
  _set_words CANARY_TRUSTED_ARR "$trusted"
  return 0
}

is_trusted() {
  local a=$1 t
  for t in "${CANARY_TRUSTED_ARR[@]}"; do
    [[ "$a" == "$t" ]] && return 0
  done
  return 1
}

canary_ts_to_ms() {
  local t=$1 v
  v=$(date -u -d "$t" +%s%3N 2>/dev/null) && { printf '%s' "$v"; return 0; }
  v=$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$t" +%s 2>/dev/null) && { printf '%s' "$((v * 1000))"; return 0; }
  return 1
}

canary_send_alert() {
  local sev=$1 repo=$2 summary=$3 details=${4:-}
  local ts line
  ts=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  line="[$ts] [$sev] $repo — $summary"
  printf '%s\n' "$line"
  printf '%s\n' "$line" >> "$CFG_ALERT_FILE"
  [[ -n "$details" ]] && printf '    %s\n' "$details" >> "$CFG_ALERT_FILE"

  if [[ -n "${CFG_CANARY_NTFY_TOPIC:-}" ]] && have curl; then
    local prio=default
    [[ "$sev" == CRITICAL ]] && prio=urgent
    [[ "$sev" == WARN ]] && prio=high
    curl -fsS -X POST "https://ntfy.sh/${CFG_CANARY_NTFY_TOPIC}" \
      -H "Title: Canary: $repo" -H "Priority: $prio" -H 'Tags: warning,github' \
      -d "$summary"$'\n'"$details" >/dev/null 2>&1 || true
  fi
  if [[ -n "${CFG_CANARY_DISCORD_URL:-}" ]] && have curl && have jq; then
    local payload
    payload=$(jq -nc --arg c "[$sev] **$repo** — $summary"$'\n'"$details" '{content:$c}' 2>/dev/null) || payload=''
    [[ -n "$payload" ]] && curl -fsS -X POST -H 'Content-Type: application/json' \
      -d "$payload" "$CFG_CANARY_DISCORD_URL" >/dev/null 2>&1 || true
  fi
  if [[ -n "${CFG_CANARY_SLACK_URL:-}" ]] && have curl && have jq; then
    local payload
    payload=$(jq -nc --arg c "[$sev] *$repo* — $summary"$'\n'"$details" '{text:$c}' 2>/dev/null) || payload=''
    [[ -n "$payload" ]] && curl -fsS -X POST -H 'Content-Type: application/json' \
      -d "$payload" "$CFG_CANARY_SLACK_URL" >/dev/null 2>&1 || true
  fi
  if [[ "${CFG_CANARY_NATIVE:-0}" == 1 ]]; then
    if have notify-send; then notify-send -u critical "Canary: $repo" "$summary" 2>/dev/null || true
    elif have osascript; then osascript -e "display notification \"$summary\" with title \"Canary: $repo\"" >/dev/null 2>&1 || true
    fi
  fi
  return 0
}

sentinel_emit() {
  [[ -n "$ALERTS" ]] || return 0
  printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$1" "$2" "$3" >> "$ALERTS"
}

canary_check_repo() {
  local repo=$1
  local state_file="$CFG_STATE_DIR/canary/${repo//\//__}.last"
  local last=0 activity ts atype actor ref before after ts_ms newest details line
  [[ -f "$state_file" ]] && last=$(cat "$state_file" 2>/dev/null || printf '0')
  [[ "$last" =~ ^[0-9]+$ ]] || last=0
  if ! activity=$(gh api -X GET "repos/$repo/activity" -F per_page=30 2>&1); then
    if [[ "$activity" == *'"Not Found"'* ]]; then return 0; fi
    canary_send_alert ERROR "$repo" 'gh api failed' "$activity"
    return 1
  fi
  newest=$last
  while IFS=$'\t' read -r ts atype actor ref before after; do
    [[ -z "$ts" ]] && continue
    ts_ms=$(canary_ts_to_ms "$ts") || continue
    (( ts_ms > newest )) && newest=$ts_ms
    (( ts_ms <= last )) && continue
    (( last == 0 )) && continue
    details="actor=$actor ref=$ref ${before:0:7}..${after:0:7} at $ts"
    case "$atype" in
      force_push)
        canary_send_alert CRITICAL "$repo" 'FORCE PUSH detected (PolinRider attack signature)' "$details"
        sentinel_emit CRIT "$repo" "FORCE PUSH by $actor"
        ;;
      push)
        if ! is_trusted "$actor"; then
          canary_send_alert WARN "$repo" "push from untrusted actor '$actor'" "$details"
          sentinel_emit WARN "$repo" "push by $actor"
        fi
        ;;
      branch_creation|branch_deletion|pr_merge)
        if ! is_trusted "$actor"; then
          canary_send_alert WARN "$repo" "$atype by untrusted actor '$actor'" "$details"
          sentinel_emit WARN "$repo" "$atype by $actor"
        fi
        ;;
    esac
  done < <(printf '%s\n' "$activity" | jq -r '.[] | [.timestamp, .activity_type, .actor.login, (.ref//""), (.before//""), (.after//"")] | @tsv' 2>/dev/null || true)
  printf '%s\n' "$newest" > "$state_file"
  return 0
}

canary_watch_sweep() {
  local before=0 after=0 repo
  [[ -f "$CFG_ALERT_FILE" ]] && before=$(wc -l < "$CFG_ALERT_FILE" | tr -d '[:space:]')
  for repo in "${CANARY_REPOS_ARR[@]}"; do
    canary_check_repo "$repo" || true
  done
  after=$(wc -l < "$CFG_ALERT_FILE" | tr -d '[:space:]')
  if (( CFG_VERBOSE )); then
    log "checked ${#CANARY_REPOS_ARR[@]} repos, $((after - before)) new alert(s)"
  fi
  return 0
}

canary_watch() {
  local once=$1 interval=$2
  require_cmd gh jq
  gh auth status >/dev/null 2>&1 || die 2 'gh CLI is not authenticated. Run gh auth login first.'
  canary_init
  (( ${#CANARY_REPOS_ARR[@]} )) || die 2 'no repositories configured to watch'
  if (( once )); then
    canary_watch_sweep
    return 0
  fi
  while :; do
    canary_watch_sweep || true
    sleep "$interval"
  done
}

# --- sentinel ----------------------------------------------------------------
canary_scan_branch() {
  local repo=$1 branch=$2 sha=$3 tree paths path enc content slug
  slug=$(printf '%s|%s' "$repo" "$branch" | tr -c 'A-Za-z0-9._-' '_')
  [[ -f "$BRANCH_DIR/$slug" ]] && [[ "$(cat "$BRANCH_DIR/$slug")" == "$sha" ]] && return 0
  printf '%s' "$sha" > "$BRANCH_DIR/$slug"
  tree=$(gh api "repos/$repo/git/trees/$sha?recursive=1" 2>/dev/null) || return 0
  paths=$(printf '%s\n' "$tree" | jq -r '.tree[]?|select(.type=="blob")|.path' 2>/dev/null | grep -E "$SUSPECT_PATH_RE" | awk 'NR<=12' || true)
  [[ -n "$paths" ]] || return 0
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    enc=${path//\#/%23}
    enc=${enc//\?/%3F}
    content=$(gh api -H 'Accept: application/vnd.github.raw' "repos/$repo/contents/$enc?ref=$sha" 2>/dev/null) || continue
    [[ -z "$content" ]] && continue
    if printf '%s' "$content" | grep -qaE "$SIG_ALL"; then
      printf 'CRIT|%s|%s@%s:%s|payload in blob\n' "$repo" "$repo" "$branch" "$path" >> "$R_STATE"
      sentinel_emit CRIT "$repo" "infected branch $branch: $path"
      BR_DIRTY=$((BR_DIRTY + 1))
    fi
  done <<< "$paths"
  return 0
}

canary_remote_sweep() {
  local repo branches branch sha line
  for repo in "${CANARY_REPOS_ARR[@]}"; do
    canary_check_repo "$repo" || true
    [[ "${CFG_SCAN_BRANCHES:-1}" == 1 ]] || continue
    branches=$(gh api "repos/$repo/branches?per_page=100" 2>/dev/null | jq -r '.[]|[.name,.commit.sha]|@tsv' 2>/dev/null || true)
    [[ -n "$branches" ]] || continue
    while IFS=$'\t' read -r branch sha; do
      [[ -n "$branch" && -n "$sha" ]] || continue
      BR_TOTAL=$((BR_TOTAL + 1))
      canary_scan_branch "$repo" "$branch" "$sha" || true
    done <<< "$branches"
  done
  return 0
}

canary_local_sweep() {
  local root f n=0
  : > "$L_STATE"
  for root in "$@"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r -d '' f; do
      if grep -qaE "$SIG_ALL" "$f" 2>/dev/null; then
        printf 'CRIT|local|%s|IOC signature in file\n' "$f" >> "$L_STATE"
        sentinel_emit CRIT local "$f"
        n=$((n + 1))
        (( n < 30 )) || break
      fi
    done < <(find "$root" -maxdepth 6 -type f \
      -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/.do_not_execute' \
      -print0 2>/dev/null || true)
  done
  return 0
}

sentinel_init_state() {
  R_STATE="$CLEANUP_DIR/remote.state"
  R_META="$CLEANUP_DIR/remote.meta"
  L_STATE="$CLEANUP_DIR/local.state"
  L_META="$CLEANUP_DIR/local.meta"
  ALERTS="$CLEANUP_DIR/alerts.log"
  SEEN_DIR="$CLEANUP_DIR/seen"
  SIG_DIR="$CLEANUP_DIR/sig"
  BRANCH_DIR="$CLEANUP_DIR/branches"
  : > "$R_STATE"; : > "$L_STATE"; : > "$ALERTS"
  printf 'idle|0|0|\n' > "$R_META"
  printf 'idle|0|0|\n' > "$L_META"
  mkdir -p "$SEEN_DIR" "$SIG_DIR" "$BRANCH_DIR"
  BR_TOTAL=0; BR_DIRTY=0
  canary_init
}

sentinel_seed_demo() {
  printf 'CRIT|demo|demo-repo|seeded force push\n' >> "$R_STATE"
  printf 'WARN|demo|demo-repo|seeded untrusted push\n' >> "$R_STATE"
  printf 'CRIT|local|/tmp/fake/fa-solid-400.woff2|seeded fake font\n' >> "$L_STATE"
  sentinel_emit CRIT demo 'seeded force push'
  sentinel_emit CRIT local 'seeded fake font'
}

sentinel_summary() {
  local hits=0 line cr=0 wn=0
  out_section 'SENTINEL — SWEEP SUMMARY'
  while IFS='|' read -r sev src detail msg; do
    [[ -n "$sev" ]] || continue
    case "$sev" in
      CRIT) cr=$((cr + 1)); printf '  %s[HIT ]%s %s — %s\n' "$(color '1;31')" "$(color 0)" "$detail" "$msg" ;;
      WARN) wn=$((wn + 1)); printf '  %s[WARN]%s %s — %s\n' "$(color '1;33')" "$(color 0)" "$detail" "$msg" ;;
    esac
  done < <(cat "$R_STATE" "$L_STATE" 2>/dev/null || true)
  hits=$(grep -c $'\tCRIT\t' "$ALERTS" 2>/dev/null || true)
  [[ "$hits" =~ ^[0-9]+$ ]] || hits=0
  printf '  branches scanned: %s   infected: %s\n' "$BR_TOTAL" "$BR_DIRTY"
  printf '\nAlerts this sweep: %s  (critical: %s)\n' "$(wc -l < "$ALERTS" | tr -d '[:space:]')" "$hits"
  return 0
}

canary_sentinel() {
  local once=$1 demo=$2 interval_r=$3 interval_l=$4; shift 4
  local -a roots=("$@")
  sentinel_init_state
  if (( demo )); then sentinel_seed_demo; fi
  if [[ -n "${SENTINEL_SELFTEST:-}" ]] && (( ! demo )); then sentinel_seed_demo; fi

  local remote_ok=0
  if have gh && have jq && gh auth status >/dev/null 2>&1; then remote_ok=1; fi

  if (( once )); then
    if (( remote_ok )); then
      canary_remote_sweep
    else
      printf '\n── REMOTE ── (disabled: need gh authenticated + jq)\n'
    fi
    if (( demo )); then
      out_note 'local' 'demo mode: local findings are synthetic'
    else
      canary_local_sweep "${roots[@]}"
    fi
    sentinel_summary
    hits=$(grep -c $'\tCRIT\t' "$ALERTS" 2>/dev/null || true)
    if cap_exit "${hits:-0}"; then return 0; fi
    return 1
  fi

  # Live TUI: validate terminal size, then hand over to tui.sh.
  local cols rows
  cols=${SENTINEL_COLS:-0}; rows=${SENTINEL_ROWS:-0}
  if [[ "$cols" == 0 || "$rows" == 0 ]] && have stty; then
    IFS=' ' read -r rows cols < <(stty size 2>/dev/null || printf '24 80\n') || true
  fi
  [[ "$cols" =~ ^[0-9]+$ ]] || cols=0
  [[ "$rows" =~ ^[0-9]+$ ]] || rows=0
  if (( cols < 70 || rows < 20 )) && [[ -z "${SENTINEL_SELFTEST:-}" ]]; then
    die 2 'Sentinel needs at least 70x20'
  fi
  sentinel_tui "$interval_r" "$interval_l" "$remote_ok" "${roots[@]}"
}
