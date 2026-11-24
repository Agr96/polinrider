# Technical PRD — PolinRider Toolkit (Pure Bash Refactor)

- **Document version**: 1.0
- **Status**: Ready for implementation
- **Target runtime**: Pure Bash/Shell on Linux, macOS, and Git Bash/MSYS2 on Windows
- **Guiding principle**: read-only by default, explicit changes, never execute malware artifacts, exit codes only `0/1/2`.

---

## 0. Design Decisions & Constraints

| Decision | Explanation |
|---|---|
| Bash-only | All new logic is written in `*.sh`. Existing `.ps1` files are frozen as **legacy artifacts**, not the source of truth for new features. No new PowerShell files. |
| Windows | Windows support runs through Bash in Git Bash/MSYS2. If a Windows firewall operation is required, Bash calls `powershell.exe -NoProfile -Command ...` as an **external command** rather than keeping logic in a `.ps1`. If `powershell.exe` is unavailable, the `block` subcommand falls back to `--hosts-only` mode with a warning. |
| Bash baseline | **Bash 4.0+**. Stock macOS Bash 3.2 is unsupported; `doctor` must recommend `brew install bash` and use Homebrew's `/usr/bin/env bash`. Avoid `declare -n` (4.3+) to stay compatible. |
| Forbidden | `eval`, sourcing IOC files, `node`, `npm`, `python`, `perl`, or executing `*.do_not_execute`. All searches are textual. |
| Exit codes | Only `0`, `1`, `2`. Must never return raw hit counts like the legacy `check-polinrider-*` scripts or `canary-sentinel.sh --once`. |
| Source of truth | `iocs.txt` = domains/IPs for blocking. `config/signatures.env` = signature regexes and build-config targets for the scanner/cleaner/sentinel. `config.env` = local preferences and webhooks (secrets). |
| Compatibility | Legacy state formats are preserved: remote `CODE|repo|detail|ts|br_total|br_dirty`, local `SEV|label|detail`, alert TSV `epoch\tSEV\tSOURCE\tMSG`. |

---

## 1. Architecture & Bash Modularity

### 1.1 Target file structure

```text
.
├── bin/
│   └── polinrider              # the only dispatcher; chmod 0755
├── lib/
│   ├── core.sh                 # logging, die, run_cmd, trap, dependency guard
│   ├── config.sh               # config.env + signatures.env loader (allowlist)
│   ├── ioc.sh                  # parser for iocs.txt
│   ├── output.sh               # text/json renderers + colors
│   ├── scan.sh                 # Part A/B/C scanner
│   ├── block.sh                # hosts + firewall + DNS + rollback
│   ├── clean.sh                # repo cleanup (git rm / strip)
│   ├── canary.sh               # watch + sentinel + alert fan-out
│   ├── tui.sh                  # gum/dialog/plain adapter
│   └── legacy.sh               # shim for legacy check-*/block-* wrappers (transitional)
├── config/
│   ├── signatures.env          # SIG_*, BUILD_CFG_GLOBS, default repos, trusted actors
│   └── canary.env              # optional, overrides the watched repo list
├── config.env.example          # template, committed
├── config.env                  # local, 0600, gitignored
├── iocs.txt                    # blocking source of truth
├── docs/
│   └── PRD.md                  # this document
├── tests/
│   ├── run.sh                  # pure Bash test runner
│   ├── assert.sh
│   └── fixtures/
└── .gitignore                  # add: /config.env, *.polinrider-bak
```

Legacy wrappers (`block-iocs.sh`, `check-polinrider-*.sh`, `canary-watch.sh`, `canary-sentinel.sh`, `clean-polinrider-repo.sh`, `audit-sixsixnine.sh`) become **thin shims** that call `bin/polinrider <subcommand>` with equivalent flags. No duplicated logic.

### 1.2 Module contracts

| Module | Public functions | Side effects | Rules |
|---|---|---|---|
| `core.sh` | `log`, `ok`, `warn`, `die`, `dry`, `run_cmd`, `require_cmd`, `require_root`, `mktemp_dir`, `register_cleanup`, `cap_exit` | Cleanup trap and temp dir only | `die()` always exits `2` for config/dependency errors, `1` for operation failures. |
| `config.sh` | `config_load`, `config_validate`, `config_get`, `config_show` | None | Accept only allowlisted keys. `config_show` must redact webhooks. |
| `ioc.sh` | `ioc_parse`, `ioc_is_domain`, `ioc_is_ip` | None | Output through NUL-delimited files in the temp dir, not stdout that can break on spaces. |
| `output.sh` | `render_section`, `render_hit`, `render_review`, `render_ok`, `emit_json` | stdout/stderr | ANSI only when TTY and `NO_COLOR != 1`. JSON mode contains no ESC bytes. |
| `scan.sh` | `scan_repo_payloads`, `scan_fake_fonts`, `scan_tasksjacker`, `scan_host_evidence`, `scan_deep_logs`, `scan_all` | Read-only | No permanent `cd`; save `pwd` or use `git -C "$repo"`. |
| `block.sh` | `hosts_backup`, `hosts_strip_block`, `hosts_write_block`, `fw_block`, `fw_unblock`, `dns_flush`, `block_apply`, `block_rollback` | `/etc/hosts`, firewall, DNS cache | All changes go through `run_cmd`; `--dry-run` must not write. |
| `clean.sh` | `clean_vscode`, `clean_fonts`, `clean_gitignore`, `clean_config_payload`, `clean_all` | `git rm`, `git add`, working files | **Stage only**, never commit. `*.polinrider-bak` backups are still created and ignored. |
| `canary.sh` | `canary_remote_repo`, `canary_scan_branch`, `canary_local_scan`, `canary_watch_once`, `canary_alert` | state dir, alert log, webhooks | First-run baseline must not trigger alerts. |
| `tui.sh` | `ui_menu`, `ui_confirm`, `ui_choose`, `ui_picker`, `ui_spinner`, `ui_pager`, `ui_restore` | Terminal | Backends: `gum` → `dialog` → plain. Ctrl-C/ESC/Cancel always map to exit `1`. |

### 1.3 `set -euo pipefail` standard

Every entrypoint must:

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/core.sh"
```

Rules:

1. Libraries must never disable `-e`, `-u`, or `pipefail`.
2. Every optional variable must use `: "${VAR:=default}"` before use.
3. Commands that are allowed to fail must be written explicitly: `cmd || true` or `if ! cmd; then ... fi`.
4. Pipelines with `head` must be replaced with `awk 'NR<=N'` or given `|| true`, because `pipefail` + `head` triggers status `141` (SIGPIPE).
5. Functions that mean "not found" must deliberately return `1` and be called inside `if`, not as a plain statement.

### 1.4 `config.env` & `signatures.env`

`config.env` (0600, gitignored) — allowlisted keys:

```dotenv
IOC_FILE=./iocs.txt
HOSTS_FILE=/etc/hosts
BACKUP_DIR=
STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/polinrider
ALERT_FILE=
SCAN_ROOTS_FILE=
FIREWALL_BACKEND=auto
REMOTE_INTERVAL=300
LOCAL_INTERVAL=120
SCAN_BRANCHES=1
SHOW_MAP=1
UI_BACKEND=auto
LOG_FORMAT=text
NO_COLOR=0
CANARY_NTFY_TOPIC=
CANARY_DISCORD_URL=
CANARY_SLACK_URL=
CANARY_NATIVE=0
```

`config/signatures.env` (0644, committed) — allowlisted keys:

```dotenv
SIG_V1='rmcej%otb%'
SIG_V1_GLOBAL="global\\['!'\\]='8-1638-2'"
SIG_V2='Cot%3t=shtP'
SIG_TRON_ADDRS='TMfKQEd7TJJa5xNZJZ2Lep838vrzrs7mAP|TXfxHUet9pJVU1BgVkBAbrES4YUc1nGzcG'
SIG_BSC_TX='0xbe...|0x3f0...'
SIG_C2_IP='166\\.88\\.54\\.158'
SIG_C2_RPC='api\\.trongrid\\.io|...'
SIG_EVIL_NPM='tailwindcss-style-animate'
SIG_EVIL_UUID='e9b53a7c-2342-4b15-b02d-bd8b8f6a03f9'
BUILD_CFG_GLOBS='tailwind.config.* vite.config.* postcss.config.* next.config.* nuxt.config.* eslint.config.* svelte.config.* astro.config.* webpack.config.* rollup.config.*'
```

Parser requirements:

- Read line by line with `while IFS= read -r line || [[ -n "$line" ]]`.
- Ignore blank lines and `# comments`.
- Split `KEY=value` at the first `=`.
- Reject keys outside the allowlist with `[X] unknown config key: ...` → exit `2`.
- Strip matching single or double quotes only at the start and end of the value; command execution is never allowed.
- Environment variables (`CANARY_*`, `SENTINEL_*`, `NO_COLOR`, `XDG_STATE_HOME`) may override defaults, but still pass through the same `config_validate()` function.

### 1.5 "Pure" functions vs side-effect functions

- **Pure**: read only arguments and readonly `CFG_*`; return results via stdout or `printf -v out '%s' ...`. Examples: `ioc_is_domain`, `render_hit`, `fmt_age`, `sev_color`.
- **Side-effect**: must be prefixed with `apply_`, `write_`, `block_`, `unblock_`, `clean_`, `canary_`, or `ui_`. Examples: `apply_hosts_block`, `clean_all`.
- Global variables are used only for readonly configuration (`CFG_*`) and trap state (`__CLEANUP_*`). Hit/review counters live in `STATE_HITS` and `STATE_WARNS` and are incremented only by renderers.

### 1.6 State and temp layout

```text
$STATE_DIR/
├── canary/
│   ├── alerts.log             0600
│   ├── <repo__name>.last      0600
│   └── sentinel/              0700, per-session mktemp -d
│       ├── remote.state
│       ├── remote.meta
│       ├── local.state
│       ├── local.meta
│       ├── alerts.log
│       ├── seen/
│       ├── sig/
│       └── branches/
└── backups/
    └── hosts.bak.YYYYMMDD-HHMMSS  0600
```

All state files are created with `umask 077` at the start of `main()`.

---

## 2. CLI Contract & User Interface

### 2.1 Dispatcher

```text
polinrider <subcommand> [options] [positional]
polinrider --help
polinrider --version
```

Global flags (must be accepted both before and after the subcommand):

| Flag | Default | Effect |
|---|---|---|
| `--config PATH` | `./config.env` then `$XDG_CONFIG_HOME/polinrider/config.env` | Load an alternative config file. |
| `--dry-run` | off | `run_cmd` only prints `[dry]`. Applies to `block`, `unblock`, `clean`. |
| `--no-color` | `NO_COLOR` | Force output without ANSI. |
| `--json` | off | JSON output, one object per line; ignores colors. |
| `--quiet` | off | Only `[X]` and summaries. |
| `--verbose` | off | Show config paths and backend decisions. Must never print webhooks. |
| `--yes` | off | Skip `ui_confirm` prompts. |
| `-h`, `--help` | — | Show help, or subcommand help when given after a subcommand. |

### 2.2 Complete subcommand list

| Subcommand | Flags / arguments | Function | Side effects | Exit |
|---|---|---|---|---|
| `doctor` | — | Check Bash ≥ 4, required commands, TUI options, state dir permissions. | Creates the state dir | 0 all present; 2 if something is missing |
| `config show` | — | Show effective config with webhooks redacted. | none | 0 / 2 |
| `config validate` | — | Validate allowlist and values. | none | 0 / 2 |
| `scan` | `--repos PATH` (repeatable), `--full`, `--root PATH`, `--format text\|json` | Run Parts A/B/C. | **Read-only** | 0 clean; 1 if there is a `HIT`; 2 config/dependency error |
| `block` | `--iocs PATH`, `--hosts-only`, `--firewall auto\|nft\|iptables\|ufw\|pf\|none`, `--backup-dir PATH` | Apply hosts + firewall + DNS flush. | hosts, firewall, DNS | 0 success; 1 operation failure; 2 pre-flight |
| `unblock` | Same flags as `block` | Remove `polinrider`-marked blocks. | hosts, firewall, DNS | 0 / 1 / 2 |
| `verify` | `--domain HOST` (repeatable), `--timeout SEC` | Check resolution and connectivity after blocking. | none | 0 all 0.0.0.0/failed; 1 if any still resolves |
| `clean` | `ROOT` (default `.`), `--dry-run` | Remove `.vscode/`, `public/fonts/`, `.gitignore` artifacts, strip build-config payloads. | git index and working files | 0 nothing to do/staged successfully; 1 failure; 2 not a git repo |
| `watch` | `--once`, `--interval SEC`, `--repos-file PATH`, `--trusted-file PATH` | Headless GitHub activity watcher. | state + alert log | 0 always (errors → 2) |
| `sentinel` | `--once`, `--demo`, `--no-branches`, `--no-map`, `--no-color`, `--remote-interval SEC`, `--local-interval SEC`, `--repos PATH` | TUI console or single sweep. | state, alerts, terminal | 0 clean; 1 if CRIT; 2 pre-flight/terminal too small |
| `audit` | `--output PATH`, `--redact` (default on) | Read-only forensics like `audit-sixsixnine.sh`. | optional output file | 0 / 1 / 2 |
| `help` | `[subcommand]` | Help. | none | 0 |

Legacy aliases (shims; new modules must not use them):

```text
block-iocs.sh --dry-run        -> polinrider block --dry-run
block-iocs.sh --unblock        -> polinrider unblock
check-polinrider-linux.sh ...  -> polinrider scan --repos ...
canary-watch.sh                -> polinrider watch --once
canary-sentinel.sh --once      -> polinrider sentinel --once
clean-polinrider-repo.sh ROOT  -> polinrider clean ROOT
audit-sixsixnine.sh            -> polinrider audit
```

### 2.3 Non-negotiable `0/1/2` exit-code contract

| Code | Meaning | Example |
|---|---|---|
| `0` | Success, clean, or "Yes" confirmation. Includes `scan` with no HIT, `block --dry-run`, normal `watch`, accepted `gum confirm`, `dialog --yesno` Yes. | `polinrider scan` in a clean repo |
| `1` | Finding, operation failure, or user cancellation. Includes `scan` with HIT, `sentinel --once` with CRIT (capped from raw hit count), `gum confirm` No, `dialog` Cancel/ESC, Ctrl-C. | `polinrider sentinel --once` with 3 CRIT → still `1` |
| `2` | Usage / config / dependency / prerequisite error. Unknown flag, unknown config key, missing `jq`, not root during `block`, terminal < 70×20, not a git repo during `clean`. | `polinrider watch` without `gh` → `2` |

Helper function:

```bash
cap_exit() { # hit_count -> 0|1
  local n=$1
  (( n > 0 )) && return 1
  return 0
}
```

### 2.4 Terminal output format

Required prefixes (kept from the legacy scripts for familiarity):

```text
[*] Action: block  (OS: Linux, dry-run: 1)
[+] Loaded 42 domains and 3 IPs from ./iocs.txt
[dry] would append to /etc/hosts:
[!] No supported firewall tool found (nft, iptables, ufw). IP-level blocking skipped.
[X] required tool 'jq' not found
[?] /repo/.vscode/settings.json sets allowAutomaticTasks:true
```

Scanner:

```text
═══ PART A — REPO PAYLOAD SCAN ═══
── A1. JS payload signatures ──
  ⚠ HIT: /repo/frontend/tailwind.config.js
  ✓ no payload signatures

═══ SUMMARY ═══
  2 HIT(s), 1 for review
  A clean scan does not prove uninfection — Beavertail variants self-clean.
```

Rules:

- `HIT` increments `STATE_HITS`; `REVIEW` increments `STATE_WARNS` but **does not** change the exit code.
- `--json` produces lines such as:
  `{"level":"hit","section":"A1","path":"/repo/x.js","ts":"2026-11-23T22:10:00Z"}`
- `--quiet` hides `ok` and `note`, but the summary is still shown.
- `NO_COLOR=1`, `--no-color`, or stdout not being a TTY → no `\033[...m` bytes.

### 2.5 TUI menu / prompts (gum, dialog, fallback)

The TUI is **optional**. The default remains the hand-rolled ANSI console from the current `canary-sentinel.sh` (zero dependencies). `gum`/`dialog` are used only for interactive prompts and spinners, with a plain `read` fallback.

Context7 references used:

- `gum confirm`: exit `0` = Yes, `1` = No; accepts piped `y/n`; `--default false --timeout 5s` is available.
- `gum choose`: selection goes to stdout; `--label-delimiter ':'` separates label and value; cancel produces an interrupt → map to `1`.
- `gum file --directory --path DIR`: returns an absolute path; exit `1` when nothing is chosen, `130` on Ctrl-C → both map to `1`.
- `gum spin --title "..." --show-error -- <cmd>`: spinner on stderr, returns the child's exit code; suitable for `block`/`scan`.
- `gum log --structured --level warn --formatter json`: used only when `LOG_FORMAT=json`.
- `gum pager`: used for long `audit` output.
- `NO_COLOR`, `CLICOLOR`, `CLICOLOR_FORCE` automatically control ANSI (Gum documentation).
- `dialog`/`whiptail`: `--yesno` returns `0` for Yes, `1` for No/Cancel/ESC (Debian documentation). `--inputbox` writes to stderr, so an fd swap is needed:

```bash
exec 3>&1
choice=$(dialog --title "PolinRider" --menu "Choose action:" 15 60 6 \
  1 "Scan" 2 "Block" 3 "Unblock" 4 "Clean" 5 "Sentinel" 6 "Exit" \
  2>&1 1>&3) || { exec 3>&-; return 1; }
exec 3>&-
```

Backend resolver:

```text
UI_BACKEND=auto:
  if [[ -t 0 && -t 1 ]]; then
     gum?    -> gum
     dialog? -> dialog
   fi
   -> plain numbered read
```

Required menu:

```text
PolinRider Toolkit
  1) Scan now (read-only)
  2) Block C2 (dry-run first)
  3) Unblock / rollback
  4) Clean repo (stage only)
  5) Sentinel (live console)
  6) Watch (headless)
  7) Audit & export
  8) Config / doctor
  9) Exit
```

---

## 3. Functional Specifications & Data Flow

### F-01 — Initialization & config load

| Aspect | Specification |
|---|---|
| Input | `bin/polinrider ...`, env, `config.env`, `config/signatures.env` |
| Process | `set -euo pipefail`, `umask 077`, `config_load`, `config_validate`, `require_cmd bash grep find awk sed`, `register_cleanup` |
| Side effects | Creates `$STATE_DIR` with mode `0700` |
| Output | `[*] Config: ...` only with `--verbose` |
| Exit | `2` if config is invalid |

### F-02 — Parsing `iocs.txt`

| Aspect | Specification |
|---|---|
| Input | `IOC_FILE` |
| Process | Strip after `#`, trim, classify: IPv4/IPv6 → `IPS`, everything else → `DOMAINS`. Domain validation: `^[A-Za-z0-9.-]{1,253}$`, must not start or end with `-` or `.`, must not contain `;`, `$`, backtick, space, `/`, `\`, `\|`. |
| Side effects | Writes NUL-delimited files in the temp dir |
| Output | `[+] Loaded N domains and M IPs from PATH` |
| Exit | `2` for invalid lines; `# comment` lines and still-commented `[PRECAUTION]` lines are ignored |

### F-03 — Scan repo payloads (Part A)

| Sub-ID | Input | Process | Output |
|---|---|---|---|
| A1 | All `.js/.mjs/.cjs/.ts/.tsx/.jsx/.vue/.svelte` files under `SCAN_ROOTS`, maxdepth 8, excluding `node_modules/.git/dist/build/.next/.nuxt/venv` | `grep -lE "$SIG_*"` | `HIT` per file |
| A2 | `.woff2/.woff/.ttf` | Compare 4 magic bytes (`774f4632`, `774f4646`, `00010000\|74727565\|4f54544f`); if wrong **and** content contains `require\|process.\|child_process\|SIG_*` → HIT | `HIT path (magic=..., looks like JS)` |
| A2b | `public/fonts/fa-solid-400.woff2` | Magic is not `774f4632` **or** `file -b` contains `text` → HIT | `HIT ...` |
| A3 | `.vscode/tasks.json` | `runOn:folderOpen` + (`node ... .woff\|ttf\|eot` or `curl\|wget \| sh` or C2/UUID) → HIT; only `folderOpen` → REVIEW | `HIT`/`REVIEW` |
| A3b | `.vscode/tasks.json` | `node[[:space:]]+(./)?public/fonts/fa-solid-400.woff2` → HIT | `HIT` |
| A4 | `.vscode/settings.json` | `task.allowAutomaticTasks:true` → REVIEW | `REVIEW` |
| A5 | Repo text | `temp_auto_push.bat\|temp_interactive_push.bat` → HIT | `HIT` |
| A6 | `package.json` | `tailwindcss-style-animate` → HIT | `HIT` |
| A7 | `*.json` | Weaponized UUID → HIT | `HIT` |
| A8 | `.git` under the root | `git -C "$repo" log --all -n 500 --format=...`, compare author vs committer TZ offsets for the same identity → REVIEW | `REVIEW repo:` + 3 lines |

Implementation note: the legacy macOS scanner used a single inventory (`INV`); the **legacy Linux scanner referenced `$INV` without defining it**, so A2b silently always reported "clear" under `set -u`. The refactor must use a single `build_inventory()` for all OSes.

### F-04 — Scan host evidence (Part B) & deep logs (Part C)

| Part | Source | Detection |
|---|---|---|
| B1 | `~/.npm`, `/tmp`, `/var/tmp`, `~/.cache`, `/dev/shm` (Linux); `~/Library/...` (mac); `%TEMP%` (via Bash/MSYS path) | Staging directories `[user]$[host]_YYMMDD_HHMMSS` |
| B2 | Same | `_credentials.json`, `_sysenv.json`, `_sysenv.env`, `_info.json` |
| B3 | `$HOME`, `/tmp` | Zip files `*\$*_*#<hex>.zip` |
| B4 | Fixed paths | `tmp7A863DD1.tmp` |
| B5–B8 | systemd/cron/rc/autostart (Linux), LaunchAgents (mac), Run/Startup/WMI (Windows via MSYS) | IOC references |
| B9 | `*.py/*.js/*.sh` ≤ 180 days | IOC content, `portalocker`, lock file |
| B10 | `ps auxww` | Node loading a font / C2 host |
| B11 | `ss`/`lsof`/`Get-NetTCPConnection` via wrapper | Connections to `166.88.54.158` |
| B12 | **Passive only** | Do not probe IOC DNS; that creates false positives |
| B13 | shell/PSReadLine history | IOC strings |
| B14–B15 | browser DBs & wallets | Informational `note`, not HIT |
| C | `--full` + root | `journalctl`/`log show`/Sysmon 3&1/PS 4104/Defender; if non-root → `[!] skip — re-run with sudo`, **exit remains 0** |

### F-05 — Block

Required sequence:

1. `preflight`: root/admin, `IOC_FILE` exists, firewall backend available.
2. `hosts_backup`: `cp -p "$HOSTS_FILE" "$BACKUP_DIR/hosts.bak.$TS"`, then `chmod 0600`.
3. `hosts_strip_block`: remove everything between the `# === BEGIN polinrider IOC block ===` and `# === END polinrider IOC block ===` markers.
4. `hosts_write_block`: write `0.0.0.0 domain` and `:: domain` for every domain.
5. `fw_block`: choose backend `nft > iptables > ufw > pf > powershell.exe > none`.
   - Linux nft: table `inet polinrider`, sets `iocs`/`iocs6`, chain `out`, drop rules.
   - iptables: comment `polinrider`, idempotent via `-C` then `-A`.
   - macOS pf: anchor `/etc/pf.anchors/polinrider_iocs`, reference in `/etc/pf.conf`.
   - Windows via Bash: `powershell.exe -NoProfile -Command "New-NetFirewallRule ... -Group polinrider"`.
6. `dns_flush`: `dscacheutil`/`killall -HUP mDNSResponder`, `resolvectl`, or `ipconfig /flushdns`.
7. Optional automatic `verify` using the first sample domain.
8. If any of steps 3–6 fails → `block_rollback()` removes the newly created block and rules, unless `--keep-partial`.

| Input | Output | Exit |
|---|---|---|
| `polinrider block --dry-run` | `[dry] would append ...`, `/etc/hosts` unchanged | 0 |
| `polinrider block --hosts-only` | `[+] Wrote N domains ...`, firewall untouched | 0 |
| `polinrider block` without root | `[X] must be run as root` | 2 |

### F-06 — Unblock / rollback

- Remove only marked blocks; other `/etc/hosts` lines must remain intact.
- Remove the nft `polinrider` table, iptables/ip6tables rules commented `polinrider`, ufw rules commented `polinrider`, the pf anchor, and Windows Firewall rules in the `polinrider` group.
- Backups are not deleted.
- Idempotent: unblocking twice → `[*] Nothing to remove` and exit `0`.

### F-07 — Verify

- Input: domains from `--domain` or the first domain in `iocs.txt`.
- Success when `getent hosts DOMAIN` returns `0.0.0.0` or nothing, and `curl --max-time 3 https://DOMAIN` fails.
- Concise output: `[+] api.trongrid.io -> 0.0.0.0 (blocked)`.
- Exit `1` if any domain still resolves to a real IP.

### F-08 — Clean repo

| Step | Action | Consequence |
|---|---|---|
| 1 | Validate `[ -d .git ]` at `ROOT` | Not a repo → exit `2` |
| 2 | `git rm -r .vscode` if present | Stage deletion |
| 3 | `git rm -r public/fonts` if present | Stage deletion |
| 4 | Remove lines containing `temp_auto_push.bat`, `temp_interactive_push.bat`, `.gitignore` from `.gitignore` | Stage modification |
| 5 | For each `BUILD_CFG_GLOBS`: if it matches `SIG_*`, copy to `file.polinrider-bak` (0600), then remove from the first `global[` to EOF and remove the two `createRequire` shim lines using `awk`, not `perl` | Stage modification; backup contains live payload |
| 6 | Ensure `*.polinrider-bak` is in `.gitignore` | Prevents `git add -A` |
| 7 | Print `Staged. Review with: git status && git diff --cached` and `Do NOT open this repo in VS Code until merged.` | No commit, no editor opened |

If nothing changes: `Nothing to remove ...` → exit `0`.

### F-09 — Watch

- `canary_remote_repo`: `gh api repos/$repo/activity -F per_page=30`, parsed with `jq`.
- Events: `force_push` → CRIT; `push`/`branch_creation`/`pr_merge` by an untrusted actor → WARN.
- `last_seen_ms` is stored in `$STATE_DIR/canary/<repo__name>.last`.
- **First run**: if `last == 0`, baseline only, no alert.
- Alert channels: log file, `ntfy.sh`, Discord, Slack, native notifications. Webhooks are never printed.
- `watch --once` always exits `0` unless a dependency/config error → `2`.

### F-10 — Sentinel

- Remote worker: activity + per-branch tree scan. `SUSPECT_PATH_RE` filters `fa-*.woff2`, `.vscode/tasks.json`, `temp_*_push.bat`, `package.json`. Blob paths are encoded for `#`/`?` before `gh api contents?ref=SHA`.
- Per-`(repo,branch)` SHA cache is valid for one process; the first sweep is the most expensive.
- Local worker: 8 categories with progress `10..100` and dedup via `$SIG_DIR/<cat>`.
- Threat: `CRIT` → `CRITICAL`, `WARN` → `ELEVATED`, otherwise `NOMINAL`.
- `--once`: summarize results, `hits=$(grep -c $'\tCRIT\t' ...)`, then `cap_exit "$hits"`.
- `SENTINEL_SELFTEST=N`: seed fake state, render `N` frames, do not start workers/network, exit `0`.
- TUI minimum `70×20`; smaller → `[X] Sentinel needs at least 70x20` + exit `2`.
- Keys: `q` quit, `p` pause/resume (SIGSTOP/CONT workers), `r` remote now, `l` local now, `a` acknowledge alarm.

---

## 4. Error Handling, Edge Cases & Security

### 4.1 Dependency matrix

| Command | Required for | If missing |
|---|---|---|
| `bash >= 4.0`, `grep`, `find`, `awk`, `sed`, `stat`, `ps` | everything | exit `2` |
| `xxd` | font magic scan | fallback `od -An -tx1 -N4` |
| `file` | detecting text `fa-solid-400.woff2` | fallback: treat the file as suspicious when the magic is wrong |
| `gh` + `jq` | `watch`, remote `sentinel` | remote disabled with `[!]`, `watch` → exit `2`, local `sentinel` still runs |
| `nft`/`iptables`/`ufw`/`pfctl` | firewall | `[!]` + continue hosts-only |
| `gum`/`dialog` | interactive prompts | `read` fallback |
| `curl` | webhooks & verify | webhooks skipped, verify failure → `1` |

`doctor` must print an `OK/MISSING/OPTIONAL` table and the suggestion `brew install bash jq gh gum`.

### 4.2 Input validation & injection prevention

1. **Remove `eval`**. The legacy `block-iocs.sh` used `do_or_dry "cp -p '$HOSTS_FILE' ..."`; replace it with:

```bash
run_cmd() {
  if (( CFG_DRY_RUN )); then
    printf '\033[1;36m[dry]\033[0m %q ' "$@"; printf '\n'
    return 0
  fi
  "$@"
}
```

2. Quote every path: `find "$root" ...`, `grep -qE "$SIG" "$f"`, `git -C "$repo"`.
3. Multi-path uses arrays, not strings: `ROOTS=(...)`; config uses `SCAN_ROOTS_FILE` with one path per line so spaces are supported.
4. Filenames from `find` are read with `-print0` + `while IFS= read -r -d '' f`.
5. Reject IOCs containing shell characters; see F-02.
6. GitHub branch/repo names are only used as `gh api` arguments after validating `^[A-Za-z0-9._/-]+$`; the cache slug is created with `tr -c 'A-Za-z0-9._-' '_'`.
7. Config values are never sourced; the parser itself assigns `CFG_*`.

### 4.3 File permissions

```bash
chmod 0755 bin/polinrider tests/run.sh
chmod 0644 lib/*.sh config/*.env config.env.example docs/PRD.md iocs.txt
chmod 0600 config.env
chmod 0700 "$STATE_DIR" "$STATE_DIR/canary"
chmod 0600 "$STATE_DIR"/canary/alerts.log "$STATE_DIR"/backups/hosts.bak.*
chmod 0600 ./*.polinrider-bak 2>/dev/null || true
```

`.gitattributes` is preserved: `*.ps1` CRLF, `*.sh` LF, `*.do_not_execute` LF.

### 4.4 Traps, rollback, and cancellation

```bash
register_cleanup() {
  __CLEANUP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/polinrider.XXXXXX")
  trap '__cleanup' EXIT INT TERM HUP
}

__cleanup() {
  local rc=$?
  trap - EXIT INT TERM HUP
  for pid in "${__WORKER_PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  ui_restore
  rm -f "$R_TRIGGER" "$L_TRIGGER" 2>/dev/null || true
  [[ -n "${__CLEANUP_DIR:-}" ]] && rm -rf "$__CLEANUP_DIR"
  return "$rc"
}
```

`ui_restore` is mandatory: `printf '\033[?25h\033[?1049l'`, `stty echo 2>/dev/null || true`.

Additional rules:

- Ctrl-C on `gum file` (130), `gum choose` (interrupt), `dialog` cancel, or a failed `read` → exit `1`, not `130`.
- If `block` fails midway, `block_rollback` is called automatically from the trap only when `__BLOCK_APPLIED=1`.
- `clean` must not call `git commit`; if it fails midway, simply report which files were already staged.

### 4.5 Existing defects that must be fixed

| Defect | Evidence | Fix |
|---|---|---|
| Linux A2b uses undefined `$INV` | `check-polinrider-linux.sh:101` → `bash: INV: unbound variable`, fallback `find` does not run, A2b incorrectly reports "clear" | Consolidate `build_inventory()` in `scan.sh` for all OSes |
| Duplicate signatures | IOC constants exist in 4+ files; macOS `BUILD_CFG_GLOB` ≠ cleaner `BUILD_CFGS` (`eslint.config.*` missing in the cleaner) | Move to `config/signatures.env` |
| `sentinel --once` exit code can exceed 1 | `exit "$hits"` in `canary-sentinel.sh:498` | `cap_exit "$hits"` |
| `set -e` + `grep \| head` risks SIGPIPE 141 | Many pipelines in the scanner | Use `awk 'NR<=N'` or `|| true` |
| `eval` in dry-run | `do_or_dry()` in `block-iocs.sh:71` | `run_cmd "$@"` |
| Hosts backup claimed "first run" but created on every run | README/header vs `backup_hosts()` | Document as every run (safer) |
| PS 5.1 `-Depth` ignored when used with `-Include` | Microsoft `Get-ChildItem` documentation | Not used in new Bash code; legacy note only |

### 4.6 Secrecy & logging

- Discord/Slack/NTFY webhooks and `CANARY_TRUSTED_ACTORS` must not appear in `--verbose` or `config show`; display `https://***/***`.
- `audit` must preserve `gh` token redaction like the legacy script.
- Do not enable `set -x` unless `POLINRIDER_DEBUG=1`, and even then only in `tests/`.
- `decoded-malware-analysis.js.do_not_execute` must not enter scanner or cleaner globs.

---

## 5. Acceptance Criteria & Test Scenarios

### 5.1 Harness

`tests/run.sh` is pure Bash, without Bats:

```bash
source tests/assert.sh
export POLINRIDER_CONFIG=tests/fixtures/config.env
TMP=$(mktemp -d /tmp/polinrider-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
run_case AC_01 "..." 'bin/polinrider --help'
```

Minimal assertion functions: `assert_exit`, `assert_contains`, `assert_not_contains`, `assert_file_unchanged`, `assert_file_mode`, `assert_git_staged`, `assert_no_commit_created`.

Fixtures use **synthetic markers**, not real payloads.

### 5.2 Test checklist

| ID | Setup → Command | Expected | Exit |
|---|---|---|---|
| AC-01 | `bin/polinrider --help` | Contains the list `scan, block, unblock, verify, clean, watch, sentinel, audit, config, doctor` | 0 |
| AC-02 | `bin/polinrider --bogus` | `[X] unknown option: --bogus` + usage | 2 |
| AC-03 | `PATH` without `jq`; `bin/polinrider watch --once` | `[X] required tool 'jq' not found` | 2 |
| AC-04 | config containing `PORT=80` | `[X] unknown config key: PORT` | 2 |
| AC-05 | `--repos "/tmp/repo with space"` containing a V2 marker | `HIT: /tmp/repo with space/...` (full path) | 1 |
| AC-06 | `iocs.txt` contains `evil.example # [HIGH]`, `198.51.100.42`, `# comment`, `a; rm -rf /` | 1 domain + 1 IP; injection line rejected | 2 |
| AC-07 | Hash `/etc/hosts` recorded; `block --dry-run` | Identical hash; `[dry] would append` present | 0 |
| AC-08 | `block --hosts-only` twice | One BEGIN/END marker pair; backups increase by 2 | 0 |
| AC-09 | `unblock` on hosts with line `127.0.0.1 localhost` | localhost line preserved; markers removed | 0 |
| AC-10 | Fake `nft`, `iptables`, `ufw` on PATH | Log selects `nft` | 0 |
| AC-11 | Clean repo; `scan --repos FIXTURE` | `No IOC matches and no items requiring review.` | 0 |
| AC-12 | `.ts` file containing `rmcej%otb%` | `HIT` with file path | 1 |
| AC-13 | `public/fonts/fa-solid-400.woff2` containing ASCII JS | `HIT (magic=..., ASCII)` — proves the Linux A2b bug is fixed | 1 |
| AC-14 | `.vscode/tasks.json` with `runOn:folderOpen` + `node public/fonts/fa-solid-400.woff2` | `HIT` | 1 |
| AC-15 | `.vscode/settings.json` with only `allowAutomaticTasks:true` | `REVIEW`, no `HIT` | 0 |
| AC-16 | Git fixture with author TZ `-0600`, committer `-0700`, same email | `REVIEW repo:` | 0 |
| AC-17 | `scan --full` as non-root | `[!] skip — re-run with sudo`, scan still completes | 0 |
| AC-18 | Repo fixture with infected `.vscode/`, `public/fonts/`, `tailwind.config.js`; `clean ROOT` | `git diff --cached` shows D/A/M; `git log -1` unchanged; `.polinrider-bak` ignored | 0 |
| AC-19 | Repeat AC-18 | `Nothing to remove ...` | 0 |
| AC-20 | First `watch --once` with fake `gh` | `.last` file created, `alerts.log` unchanged | 0 |
| AC-21 | Baseline then fake `force_push` event | `[CRITICAL] FORCE PUSH ...` line | 0 |
| AC-22 | `sentinel --once` with 3 CRIT | `[HIT ]` output for each; `Alerts ... (critical: 3)` | 1 |
| AC-23 | `sentinel --once` without `gh`/`jq` | `── REMOTE ── (disabled: need gh authenticated + jq)`, local still shown | 0 |
| AC-24 | `SENTINEL_SELFTEST=1 SENTINEL_COLS=100 SENTINEL_ROWS=30 bin/polinrider sentinel` | Render frames, contain `INTRUSION DETECTED`, no network | 0 |
| AC-25 | Terminal `69x19`; `sentinel` | `[X] Sentinel needs at least 70x20` | 2 |
| AC-26 | Run sentinel, send `SIGINT` | Temp dir removed, workers stopped, cursor & `stty echo` restored | 1 |
| AC-27 | `gum confirm` answered `n` on `block` | No hosts changes | 1 |
| AC-28 | `dialog --yesno` Cancel on `clean` | No `git rm` | 1 |
| AC-29 | `NO_COLOR=1 scan` | No `\033` bytes in stdout | 0/1 depending on finding |
| AC-30 | `scan --json` | `jq -c .` succeeds for every line; no ANSI | 0/1 |
| AC-31 | After `block` | `stat -c %a config.env` = `600`; state dir `700`; hosts backup `600` | 0 |
| AC-32 | `block` with an IOC file containing `$()` | Rejected before the backup is created | 2 |

### 5.3 Definition of Done

- [ ] All legacy wrappers only `exec bin/polinrider ...`, with no duplicated logic.
- [ ] No `eval`, `node`, `python`, `perl`, or execution of `*.do_not_execute` in new code.
- [ ] Exit codes are only `0/1/2` on every path, including Ctrl-C and `gum`/`dialog`.
- [ ] AC-01…AC-32 pass on Linux; AC-13, AC-18, AC-24, AC-26 also pass on macOS/Git Bash.
- [ ] `README.md` updated with shim aliases and the new exit-code contract.
- [ ] `AGENTS.md` updated: `iocs.txt` remains the blocking source; `config/signatures.env` is the detection source; do not run analysis artifacts.

---

## Appendix — Context7 References Used

- `/charmbracelet/gum` — `gum confirm`, `gum choose`, `gum file`, `gum spin`, `gum log`, `gum pager`, `NO_COLOR`/`CLICOLOR` variables.
- `/websites/debian_doc` — behavior of `whiptail/dialog --yesno` (`0` = Yes, `1` = No/Cancel) and fd swap for `--inputbox`.
- Microsoft `Get-ChildItem` PowerShell 5.1 documentation — `-Depth` was added in 5.0 but has no effect when used together with `-Include`; noted as the reason for not porting PS1 logic to the new Bash code.
