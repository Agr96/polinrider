# lib/core.sh — primitives for every PolinRider entrypoint.
# Contract: the caller has already executed `set -euo pipefail`.
# This library MUST NOT disable -e, -u or pipefail.

: "${STATE_HITS:=0}"
: "${STATE_WARNS:=0}"
: "${CFG_DRY_RUN:=0}"
: "${CFG_QUIET:=0}"
: "${CFG_VERBOSE:=0}"
: "${CFG_JSON:=0}"
: "${CFG_NO_COLOR:=0}"

PR_CORE_COLOR=1
if [[ "${CFG_NO_COLOR:-0}" == 1 || "${NO_COLOR:-0}" != 0 || ! -t 1 ]]; then
  PR_CORE_COLOR=0
fi

# color < ANSI code > -> emits escape only when colours are enabled.
color() {
  (( PR_CORE_COLOR )) && printf '\033[%sm' "$1"
  return 0
}

log()  { printf '%s[*]%s %s\n'  "$(color '1;34')" "$(color 0)" "$*"; }
ok()   { printf '%s[+]%s %s\n'  "$(color '1;32')" "$(color 0)" "$*"; }
warn() { printf '%s[!]%s %s\n'  "$(color '1;33')" "$(color 0)" "$*" >&2; }
err()  { printf '%s[X]%s %s\n'  "$(color '1;31')" "$(color 0)" "$*" >&2; }
dry()  { printf '%s[dry]%s %s\n' "$(color '1;36')" "$(color 0)" "$*"; }
note() { printf '%s[·]%s %s\n'  "$(color '2')" "$(color 0)" "$*"; }

# die [exit_code] <message...> — code defaults to 2 (usage/config/dependency).
die() {
  local code=2
  if [[ $1 =~ ^[0-9]+$ ]] && (( $# > 1 )); then
    code=$1
    shift
  fi
  err "$*"
  exit "$code"
}

have() { command -v "$1" >/dev/null 2>&1; }

require_cmd() {
  local tool
  for tool in "$@"; do
    have "$tool" || die 2 "required tool '$tool' not found"
  done
}

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die 2 "must be run as root (or with sudo)"
}

require_min_bash() {
  [[ "${BASH_VERSINFO[0]}" -ge 4 ]] || \
    die 2 "Bash 4.0+ required (found ${BASH_VERSION:-unknown}); on macOS: brew install bash"
}

# cap_exit <raw_count> -> exit status restricted to 0 or 1.
cap_exit() {
  local n=${1:-0}
  (( n > 0 )) && return 1
  return 0
}

# run_cmd <argv...> — the ONLY way commands with side effects are executed.
# Quoting is preserved (no eval, no string concatenation).
run_cmd() {
  if (( CFG_DRY_RUN )); then
    printf '%s[dry]%s' "$(color '1;36')" "$(color 0)"
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

# write_file <destination> <source_file> — guarded replacement of a whole file.
write_file() {
  local dest=$1 src=$2
  if (( CFG_DRY_RUN )); then
    printf '%s[dry]%s would write %q from %q\n' \
      "$(color '1;36')" "$(color 0)" "$dest" "$src"
    return 0
  fi
  cat "$src" > "$dest"
}

# --- cleanup / signal handling ------------------------------------------------
CLEANUP_DIR=""
WORKER_PIDS=()
BLOCK_APPLIED=0

register_cleanup() {
  CLEANUP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/polinrider.XXXXXX")
  trap '__on_signal' INT TERM HUP
  trap '__cleanup' EXIT
}

__on_signal() { exit 1; }

__cleanup() {
  local rc=$?
  trap - EXIT INT TERM HUP
  local pid
  for pid in "${WORKER_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  if declare -F ui_restore >/dev/null 2>&1; then
    ui_restore
  fi
  if (( BLOCK_APPLIED )) && declare -F block_rollback >/dev/null 2>&1; then
    block_rollback || true
  fi
  if [[ -n "$CLEANUP_DIR" && -d "$CLEANUP_DIR" ]]; then
    rm -rf -- "$CLEANUP_DIR"
  fi
  return "$rc"
}
