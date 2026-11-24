# lib/output.sh — text/JSON renderers. All finding counters live here.

_json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  printf '%s' "$s"
}

emit_json() {
  local level=$1 section=$2 path=$3 detail=${4:-}
  local ts
  ts=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  printf '{"level":"%s","section":"%s","path":"%s","detail":"%s","ts":"%s"}\n' \
    "$(_json_escape "$level")" "$(_json_escape "$section")" \
    "$(_json_escape "$path")" "$(_json_escape "$detail")" "$ts"
}

out_section() {
  if (( CFG_JSON )); then
    emit_json section "$1" "" ""
  else
    printf '\n%s═══ %s ═══%s\n' "$(color '38;5;37')" "$1" "$(color 0)"
  fi
}

out_sub() {
  if (( CFG_JSON )); then
    emit_json sub "$1" "" ""
  elif (( ! CFG_QUIET )); then
    printf '\n%s── %s ──%s\n' "$(color '38;5;240')" "$1" "$(color 0)"
  fi
}

out_hit() {
  STATE_HITS=$((STATE_HITS + 1))
  if (( CFG_JSON )); then
    emit_json hit "${1:-A0}" "${2:-}" "${3:-}"
  elif [[ "${1:-}" == A8 ]]; then
    printf '  %s⚠ HIT repo:%s %s\n' "$(color '1;31')" "$(color 0)" "${2:-$1}"
  else
    printf '  %s⚠ HIT:%s %s%s\n' "$(color '1;31')" "$(color 0)" "${2:-$1}" "${3:+ — $3}"
  fi
}

out_review() {
  STATE_WARNS=$((STATE_WARNS + 1))
  if (( CFG_JSON )); then
    emit_json review "${1:-A0}" "${2:-}" "${3:-}"
  elif [[ "${1:-}" == A8 ]]; then
    printf '  %s? REVIEW repo:%s %s\n' "$(color '1;33')" "$(color 0)" "${2:-$1}"
  else
    printf '  %s? REVIEW:%s %s%s\n' "$(color '1;33')" "$(color 0)" "${2:-$1}" "${3:+ — $3}"
  fi
}

out_ok() {
  if (( CFG_JSON )); then
    emit_json ok "${1:-}" "" "${2:-}"
  elif (( ! CFG_QUIET )); then
    printf '  %s✓%s %s\n' "$(color '1;32')" "$(color 0)" "${2:-$1}"
  fi
}

out_note() {
  if (( CFG_JSON )); then
    emit_json note "${1:-}" "" "${2:-}"
  elif (( ! CFG_QUIET )); then
    printf '  %s·%s %s\n' "$(color '38;5;240')" "$(color 0)" "${2:-$1}"
  fi
}

out_summary() {
  if (( CFG_JSON )); then
    emit_json summary summary "" "hits=$STATE_HITS reviews=$STATE_WARNS"
  else
    printf '\n%s═══ SUMMARY ═══%s\n' "$(color '38;5;37')" "$(color 0)"
    printf '  %d HIT(s), %d for review\n' "$STATE_HITS" "$STATE_WARNS"
    if (( STATE_HITS == 0 && STATE_WARNS == 0 )); then
      printf '  %sNo IOC matches and no items requiring review.%s\n' \
        "$(color '1;32')" "$(color 0)"
    fi
    printf '  %sA clean scan does not prove uninfection — Beavertail variants self-clean.%s\n' \
      "$(color '38;5;240')" "$(color 0)"
  fi
}
