# tests/assert.sh — minimal Bash assertions (no Bats, no external test runner).

ASSERT_FAILURES=0
ASSERT_TOTAL=0

_assert_pass() {
  ASSERT_TOTAL=$((ASSERT_TOTAL + 1))
}

_fail() {
  ASSERT_TOTAL=$((ASSERT_TOTAL + 1))
  ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  printf '    FAIL: %s\n' "$*" >&2
}

assert_exit() {
  local expected=$1 actual=$2 msg=${3:-exit code}
  if [[ "$actual" == "$expected" ]]; then _assert_pass
  else _fail "$msg: expected $expected, got $actual"; fi
}

assert_contains() {
  local file=$1 needle=$2 msg=${3:-output}
  if [[ -f "$file" ]] && grep -qF -- "$needle" "$file"; then _assert_pass
  else _fail "$msg: missing '$needle'"; fi
}

assert_not_contains() {
  local file=$1 needle=$2 msg=${3:-output}
  if [[ ! -f "$file" ]] || ! grep -qF -- "$needle" "$file"; then _assert_pass
  else _fail "$msg: unexpected '$needle'"; fi
}

assert_file_unchanged() {
  local a=$1 b=$2 msg=${3:-file}
  if cmp -s "$a" "$b"; then _assert_pass
  else _fail "$msg: file changed"; fi
}

assert_file_mode() {
  local path=$1 mode=$2 msg=${3:-mode} actual
  if [[ ! -e "$path" ]]; then _fail "$msg: $path does not exist"; return; fi
  actual=$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path" 2>/dev/null || printf '?')
  if [[ "$actual" == "$mode" ]]; then _assert_pass
  else _fail "$msg: expected $mode, got $actual"; fi
}

assert_git_staged() {
  local repo=$1 path=$2 msg=${3:-git index}
  if git -C "$repo" diff --cached --name-only 2>/dev/null | grep -qF -- "$path"; then _assert_pass
  else _fail "$msg: '$path' not staged"; fi
}

assert_no_commit_created() {
  local repo=$1 before=$2 msg=${3:-no commit} after
  after=$(git -C "$repo" rev-list --count HEAD 2>/dev/null || printf '0')
  if [[ "$after" == "$before" ]]; then _assert_pass
  else _fail "$msg: commit count changed $before -> $after"; fi
}

assert_true() {
  local cond=$1 msg=${2:-condition}
  if [[ "$cond" == 1 ]]; then _assert_pass; else _fail "$msg"; fi
}

test_summary() {
  printf '\n%d assertions, %d failures\n' "$ASSERT_TOTAL" "$ASSERT_FAILURES"
  (( ASSERT_FAILURES == 0 ))
}
