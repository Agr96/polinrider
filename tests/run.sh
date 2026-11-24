#!/usr/bin/env bash
# Prototype acceptance harness — Bash only, synthetic markers (never real payloads).
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/assert.sh"

BIN="$ROOT/bin/polinrider"
TMP=$(mktemp -d /tmp/polinrider-test.XXXXXX)
if [[ -z "${KEEP_TMP:-}" ]]; then
  trap 'rm -rf "$TMP"' EXIT
else
  printf 'test temp: %s\n' "$TMP" >&2
fi
mkdir -p "$TMP/fakebin" "$TMP/state" "$TMP/backups" "$TMP/roots" "$TMP/ghonly"
cp "$ROOT/tests/fixtures/fake-gh" "$TMP/fakebin/gh"
cp "$ROOT/tests/fixtures/fake-jq" "$TMP/fakebin/jq"
cp "$ROOT/tests/fixtures/fake-gh" "$TMP/ghonly/gh"
chmod 0755 "$TMP/fakebin"/* "$TMP/ghonly"/*

cat > "$TMP/config.env" <<EOF
STATE_DIR=$TMP/state
HOSTS_FILE=$TMP/hosts
BACKUP_DIR=$TMP/backups
ALERT_FILE=$TMP/state/alerts.log
IOC_FILE=$TMP/iocs.txt
EOF
chmod 0600 "$TMP/config.env"
export POLINRIDER_CONFIG="$TMP/config.env"
DEFAULT_PATH=$PATH
export CANARY_REPOS='owner/repo'

LAST_RC=0
run() {
  local out=$1; shift
  set +e
  if [[ -n "${TEST_TIMEOUT:-}" ]]; then
    timeout "$TEST_TIMEOUT" "$@" > "$out" 2>&1
  else
    "$@" > "$out" 2>&1
  fi
  LAST_RC=$?
  set -e
}
title() { printf '\n[%s] %s\n' "$1" "$2"; }
make_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email tester@example.invalid
  git -C "$1" config user.name tester
}

# --- CLI contract -------------------------------------------------------------
title AC-01 'help lists all subcommands'
run "$TMP/ac01" "$BIN" --help
assert_exit 0 "$LAST_RC" 'AC-01'
for s in scan block unblock verify clean watch sentinel audit config doctor; do
  assert_contains "$TMP/ac01" "$s" "AC-01 $s"
done

title AC-02 'unknown option'
run "$TMP/ac02" "$BIN" --bogus
assert_exit 2 "$LAST_RC" 'AC-02'
assert_contains "$TMP/ac02" 'unknown option: --bogus' 'AC-02'

title AC-03 'missing jq for watch'
run "$TMP/ac03" env PATH="$TMP/ghonly:/usr/bin:/bin" "$BIN" watch --once
assert_exit 2 "$LAST_RC" 'AC-03'
assert_contains "$TMP/ac03" "required tool 'jq' not found" 'AC-03'

title AC-04 'unknown config key'
printf 'PORT=80\n' > "$TMP/bad.env"
run "$TMP/ac04" "$BIN" --config "$TMP/bad.env" config validate
assert_exit 2 "$LAST_RC" 'AC-04'
assert_contains "$TMP/ac04" 'unknown config key: PORT' 'AC-04'

# --- IOC parsing / blocking ---------------------------------------------------
title AC-05 'path with spaces + V2 marker'
R="$TMP/roots/repo with space"
mkdir -p "$R"
printf 'var x = "Cot%%3t=shtP";\n' > "$R/tailwind.config.js"
run "$TMP/ac05" "$BIN" scan --repos "$R"
assert_exit 1 "$LAST_RC" 'AC-05'
assert_contains "$TMP/ac05" 'repo with space/tailwind.config.js' 'AC-05'

title AC-06 'IOC injection rejected'
printf 'evil.example\n198.51.100.42\na; rm -rf /\n' > "$TMP/iocs.bad"
run "$TMP/ac06" "$BIN" block --iocs "$TMP/iocs.bad" --hosts-only --hosts-file "$TMP/hosts" --backup-dir "$TMP/backups-bad"
assert_exit 2 "$LAST_RC" 'AC-06'
assert_contains "$TMP/ac06" 'invalid IOC line' 'AC-06'
assert_true "$([[ -d "$TMP/backups-bad" && -n "$(find "$TMP/backups-bad" -type f -print -quit)" ]] && echo 0 || echo 1)" 'AC-06 no backup written'

title AC-07 'dry-run leaves hosts untouched'
printf '127.0.0.1 localhost\n' > "$TMP/hosts"
cp "$TMP/hosts" "$TMP/hosts.orig"
printf 'evil.example # [HIGH]\n198.51.100.42\n' > "$TMP/iocs.txt"
run "$TMP/ac07" "$BIN" block --dry-run --hosts-only --hosts-file "$TMP/hosts" --backup-dir "$TMP/backups"
assert_exit 0 "$LAST_RC" 'AC-07'
assert_contains "$TMP/ac07" '[dry]' 'AC-07'
assert_file_unchanged "$TMP/hosts" "$TMP/hosts.orig" 'AC-07'

title AC-08/AC-09 'idempotent block and marker-only unblock'
run "$TMP/ac08" "$BIN" block --hosts-only --hosts-file "$TMP/hosts" --backup-dir "$TMP/backups"
assert_exit 0 "$LAST_RC" 'AC-08'
run "$TMP/ac08b" "$BIN" block --hosts-only --hosts-file "$TMP/hosts" --backup-dir "$TMP/backups"
assert_exit 0 "$LAST_RC" 'AC-08b'
assert_true "$(test "$(grep -c 'BEGIN polinrider' "$TMP/hosts")" = 1 && echo 1 || echo 0)" 'AC-08 one marker pair'
run "$TMP/ac09" "$BIN" unblock --hosts-only --hosts-file "$TMP/hosts" --backup-dir "$TMP/backups"
assert_exit 0 "$LAST_RC" 'AC-09'
assert_contains "$TMP/hosts" '127.0.0.1 localhost' 'AC-09 localhost preserved'
assert_not_contains "$TMP/hosts" 'BEGIN polinrider' 'AC-09 marker removed'

title AC-10 'firewall backend preference'
for fw in nft iptables ufw; do
  printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >> "$FAKE_FW_LOG"\n' "$fw" > "$TMP/fakebin/$fw"
  chmod 0755 "$TMP/fakebin/$fw"
done
export FAKE_FW_LOG="$TMP/fw.log"
: > "$FAKE_FW_LOG"
printf '198.51.100.42\n' > "$TMP/iocs.ip.txt"
run "$TMP/ac10" env PATH="$TMP/fakebin:$PATH" "$BIN" block --hosts-file "$TMP/hosts" --iocs "$TMP/iocs.ip.txt" --backup-dir "$TMP/backups"
assert_exit 0 "$LAST_RC" 'AC-10'
assert_contains "$TMP/ac10" 'firewall backend: nft' 'AC-10'
assert_contains "$FAKE_FW_LOG" 'nft' 'AC-10 fake nft invoked'

# --- scanner ------------------------------------------------------------------
title AC-11 'clean repo exits 0'
mkdir -p "$TMP/roots/clean"
printf '# clean\n' > "$TMP/roots/clean/README.md"
run "$TMP/ac11" "$BIN" scan --repos "$TMP/roots/clean"
assert_exit 0 "$LAST_RC" 'AC-11'
assert_contains "$TMP/ac11" 'No IOC matches and no items requiring review.' 'AC-11'

title AC-12 'TS payload signature'
printf 'const a = "rmcej%%otb%%";\n' > "$TMP/roots/clean/tailwind.config.ts"
run "$TMP/ac12" "$BIN" scan --repos "$TMP/roots/clean"
assert_exit 1 "$LAST_RC" 'AC-12'
assert_contains "$TMP/ac12" 'HIT:' 'AC-12'
rm -f "$TMP/roots/clean/tailwind.config.ts"

title AC-13 'canonical fake font (A2b regression)'
mkdir -p "$TMP/roots/font/public/fonts"
printf '(function(){ require("fs"); })();\n' > "$TMP/roots/font/public/fonts/fa-solid-400.woff2"
run "$TMP/ac13" "$BIN" scan --repos "$TMP/roots/font"
assert_exit 1 "$LAST_RC" 'AC-13'
assert_contains "$TMP/ac13" 'magic=' 'AC-13'

title AC-14 'TasksJacker tasks.json'
mkdir -p "$TMP/roots/tasks/.vscode"
printf '{"runOn":"folderOpen","command":"node public/fonts/fa-solid-400.woff2"}\n' > "$TMP/roots/tasks/.vscode/tasks.json"
run "$TMP/ac14" "$BIN" scan --repos "$TMP/roots/tasks"
assert_exit 1 "$LAST_RC" 'AC-14'
assert_contains "$TMP/ac14" 'HIT:' 'AC-14'

title AC-15 'allowAutomaticTasks is review-only'
mkdir -p "$TMP/roots/settings/.vscode"
printf '{"task.allowAutomaticTasks":true}\n' > "$TMP/roots/settings/.vscode/settings.json"
run "$TMP/ac15" "$BIN" scan --repos "$TMP/roots/settings"
assert_exit 0 "$LAST_RC" 'AC-15'
assert_contains "$TMP/ac15" 'REVIEW:' 'AC-15'
assert_not_contains "$TMP/ac15" 'HIT:' 'AC-15'

title AC-16 'TZ mismatch git history'
make_repo "$TMP/roots/tzrepo"
printf 'x\n' > "$TMP/roots/tzrepo/a.txt"
git -C "$TMP/roots/tzrepo" add a.txt
GIT_AUTHOR_DATE='2026-11-20T12:00:00 -0600' GIT_COMMITTER_DATE='2026-11-20T12:00:00 -0700' \
  git -C "$TMP/roots/tzrepo" commit -qm 'tz mismatch'
run "$TMP/ac16" "$BIN" scan --repos "$TMP/roots/tzrepo"
assert_exit 0 "$LAST_RC" 'AC-16'
assert_contains "$TMP/ac16" 'REVIEW repo:' 'AC-16'

title AC-17 'deep logs skipped without root'
run "$TMP/ac17" "$BIN" scan --full --repos "$TMP/roots/clean"
assert_exit 0 "$LAST_RC" 'AC-17'
assert_contains "$TMP/ac17" 'skip — re-run with sudo' 'AC-17'

# --- clean --------------------------------------------------------------------
title AC-18/AC-19 'clean stages only, second run is no-op'
REPO="$TMP/roots/cleanrepo"
make_repo "$REPO"
mkdir -p "$REPO/.vscode" "$REPO/public/fonts"
printf 'x\n' > "$REPO/README.md"
printf '{"a":1}\n' > "$REPO/.vscode/settings.json"
printf 'font\n' > "$REPO/public/fonts/fa-solid-400.woff2"
printf 'import { createRequire } from "module";\nconst x=1;\n\nglobal["!"]="8-1638-2";var a="rmcej%%otb%%";\n' > "$REPO/tailwind.config.js"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init
BEFORE=$(git -C "$REPO" rev-list --count HEAD)
run "$TMP/ac18" "$BIN" clean "$REPO"
assert_exit 0 "$LAST_RC" 'AC-18'
assert_git_staged "$REPO" '.vscode/settings.json' 'AC-18'
assert_git_staged "$REPO" 'public/fonts/fa-solid-400.woff2' 'AC-18'
assert_git_staged "$REPO" 'tailwind.config.js' 'AC-18'
assert_no_commit_created "$REPO" "$BEFORE" 'AC-18'
assert_true "$(test -f "$REPO/tailwind.config.js.polinrider-bak" && echo 1 || echo 0)" 'AC-18 backup'
assert_file_mode "$REPO/tailwind.config.js.polinrider-bak" 600 'AC-18 backup mode'
run "$TMP/ac19" "$BIN" clean "$REPO"
assert_exit 0 "$LAST_RC" 'AC-19'
assert_contains "$TMP/ac19" 'Nothing to remove' 'AC-19'

# --- canary -------------------------------------------------------------------
title AC-20/AC-21 'watch baseline then force-push alert'
export PATH="$TMP/fakebin:$DEFAULT_PATH"
printf '2026-11-23T22:00:00Z\tpush\tsam1am\trefs/heads/main\taaaaaaa\tbbbbbbb\n' > "$TMP/tsv.base"
FAKE_JQ_OUT="$TMP/tsv.base"; export FAKE_JQ_OUT
BEFORE=$(wc -l < "$TMP/state/alerts.log" | tr -d '[:space:]')
run "$TMP/ac20" "$BIN" watch --once
assert_exit 0 "$LAST_RC" 'AC-20'
AFTER=$(wc -l < "$TMP/state/alerts.log" | tr -d '[:space:]')
assert_true "$(test "$AFTER" = "$BEFORE" && echo 1 || echo 0)" 'AC-20 first run is baseline only'
printf '2026-11-23T22:00:00Z\tpush\tsam1am\trefs/heads/main\taaaaaaa\tbbbbbbb\n2026-11-23T23:00:00Z\tforce_push\tattacker\trefs/heads/main\tccccccc\tddddddd\n' > "$TMP/tsv.force"
FAKE_JQ_OUT="$TMP/tsv.force"; export FAKE_JQ_OUT
run "$TMP/ac21" "$BIN" watch --once
assert_exit 0 "$LAST_RC" 'AC-21'
assert_contains "$TMP/ac21" 'FORCE PUSH' 'AC-21'
unset FAKE_JQ_OUT

title AC-22/AC-23 'sentinel once limits exit code to 1'
PATH="$DEFAULT_PATH"; export PATH
R1="$TMP/roots/s1"; R2="$TMP/roots/s2"; R3="$TMP/roots/s3"
for d in "$R1" "$R2" "$R3"; do mkdir -p "$d"; printf 'var a="Cot%%3t=shtP";\n' > "$d/index.js"; done
run "$TMP/ac22" "$BIN" sentinel --once --repos "$R1" --repos "$R2" --repos "$R3"
assert_exit 1 "$LAST_RC" 'AC-22'
assert_contains "$TMP/ac22" 'critical: 3' 'AC-22'
mkdir -p "$TMP/roots/sclean"
printf 'clean\n' > "$TMP/roots/sclean/README.md"
run "$TMP/ac23" "$BIN" sentinel --once --repos "$TMP/roots/sclean"
assert_exit 0 "$LAST_RC" 'AC-23'
assert_contains "$TMP/ac23" 'disabled: need gh authenticated + jq' 'AC-23'

title AC-24 'selftest renders frames without network'
run "$TMP/ac24" env SENTINEL_SELFTEST=1 SENTINEL_COLS=100 SENTINEL_ROWS=30 "$BIN" sentinel
assert_exit 0 "$LAST_RC" 'AC-24'
assert_contains "$TMP/ac24" 'INTRUSION DETECTED' 'AC-24'

title AC-25 'terminal too small'
run "$TMP/ac25" env SENTINEL_COLS=69 SENTINEL_ROWS=19 "$BIN" sentinel
assert_exit 2 "$LAST_RC" 'AC-25'
assert_contains "$TMP/ac25" 'Sentinel needs at least 70x20' 'AC-25'

title AC-26 'SIGINT cleans up sentinel temp dir'
mkdir -p "$TMP/sigint-tmp"
set +e
TMPDIR="$TMP/sigint-tmp" SENTINEL_COLS=100 SENTINEL_ROWS=30 \
  timeout --preserve-status -s INT 2 "$BIN" sentinel --demo > "$TMP/ac26" 2>&1
AC26_RC=$?
set -e
assert_exit 1 "$AC26_RC" 'AC-26'
assert_true "$(test -z "$(find "$TMP/sigint-tmp" -mindepth 1 -maxdepth 1 -type d -name 'polinrider.*' -print -quit 2>/dev/null)" && echo 1 || echo 0)" 'AC-26 temp dir removed'

title AC-27/AC-28 'gum No and dialog Cancel abort without changes'
mkdir -p "$TMP/uibin"
printf '#!/usr/bin/env bash\n[[ "${1:-}" == confirm ]] && exit 1\nexit 0\n' > "$TMP/uibin/gum"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [[ "$a" == --yesno ]] && exit 1; done\nexit 0\n' > "$TMP/uibin/dialog"
chmod 0755 "$TMP/uibin"/*
printf '127.0.0.1 localhost\n' > "$TMP/hosts-ac27"
cp "$TMP/hosts-ac27" "$TMP/hosts-ac27.orig"
run "$TMP/ac27" env PATH="$TMP/uibin:$DEFAULT_PATH" \
  "$BIN" --ui-backend gum block --hosts-file "$TMP/hosts-ac27" --backup-dir "$TMP/backups-ac27"
assert_exit 1 "$LAST_RC" 'AC-27'
assert_contains "$TMP/ac27" 'cancelled by user' 'AC-27'
assert_file_unchanged "$TMP/hosts-ac27" "$TMP/hosts-ac27.orig" 'AC-27'

CANCEL_REPO="$TMP/roots/cleanrepo-cancel"
make_repo "$CANCEL_REPO"
mkdir -p "$CANCEL_REPO/.vscode"
printf '{"a":1}\n' > "$CANCEL_REPO/.vscode/settings.json"
git -C "$CANCEL_REPO" add -A
git -C "$CANCEL_REPO" commit -qm init
run "$TMP/ac28" env PATH="$TMP/uibin:$DEFAULT_PATH" \
  "$BIN" --ui-backend dialog clean "$CANCEL_REPO"
assert_exit 1 "$LAST_RC" 'AC-28'
assert_contains "$TMP/ac28" 'cancelled by user' 'AC-28'
assert_true "$(test -f "$CANCEL_REPO/.vscode/settings.json" && echo 1 || echo 0)" 'AC-28 file kept'
assert_true "$(test -z "$(git -C "$CANCEL_REPO" diff --cached --name-only)" && echo 1 || echo 0)" 'AC-28 index unchanged'

# --- output / permissions -----------------------------------------------------
title AC-29/AC-30 'no color and JSON lines'
run "$TMP/ac29" env NO_COLOR=1 "$BIN" scan --repos "$R1"
assert_exit 1 "$LAST_RC" 'AC-29'
if LC_ALL=C grep -q $'\033' "$TMP/ac29"; then _fail 'AC-29 ANSI escape found'; else _assert_pass; fi
run "$TMP/ac30" "$BIN" scan --json --repos "$R1"
assert_exit 1 "$LAST_RC" 'AC-30'
assert_true "$(awk '!/^\{"level":/{bad++} END{print (bad?0:1)}' "$TMP/ac30")" 'AC-30 JSON lines'

title AC-31 'permissions'
assert_file_mode "$TMP/config.env" 600 'AC-31 config'
assert_file_mode "$TMP/state" 700 'AC-31 state dir'
assert_true "$(f=$(find "$TMP/backups" -type f -print -quit); test -n "$f" && test "$(stat -c '%a' "$f")" = 600 && echo 1 || echo 0)" 'AC-31 backup mode'

title AC-32 'command substitution in IOC rejected before backup'
BM="$TMP/backups-ac32"
printf 'evil.example\n$(touch /tmp/pwned-proof)\n' > "$TMP/iocs.inject"
run "$TMP/ac32" "$BIN" block --iocs "$TMP/iocs.inject" --hosts-only --hosts-file "$TMP/hosts" --backup-dir "$BM"
assert_exit 2 "$LAST_RC" 'AC-32'
assert_true "$(test -z "$(find "$BM" -type f -print -quit 2>/dev/null)" && echo 1 || echo 0)" 'AC-32 no backup'

title SHIM 'legacy wrapper delegates'
run "$TMP/shim" "$ROOT/block-iocs.sh" --dry-run --hosts-only --hosts-file "$TMP/hosts" --backup-dir "$TMP/backups"
assert_exit 0 "$LAST_RC" 'SHIM'

test_summary
