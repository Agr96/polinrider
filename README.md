# PolinRider Toolkit

> **Trace. Block. Clean. Verify.**
>
> Read-only by default. Explicit by design. Auditable by anyone.

PolinRider is a Bash-only incident-response toolkit for EtherHiding-style malware that
fetches its stage-2 payload from public blockchain RPC endpoints (TRON / BSC / Aptos).
It turns a messy investigation into four calm actions: **scan** repositories and hosts,
**block** known C2 at the hosts/firewall/DNS layers, **clean** infected repos by staging
changes only, and **verify** the result.

It is built for people who need to move fast without executing suspicious code:
developers, incident responders, founders, students, visitors at demo tables, and
coworking communities. Every change is dry-runnable, every config file is parsed with an
allowlist, and the annotated artifact `decoded-malware-analysis.js.do_not_execute` is
**never executed**. The `.ps1` files are frozen legacy artifacts, not the source of truth
for new work.

## Pitching at a glance

| Audience | Start here | What they get |
|---|---|---|
| **Visitor** | [Safe demo for visitors](#safe-demo-for-visitors) | A 60-second read-only walkthrough with synthetic alarms, no root, no network, no payload. |
| **Sponsor** | [For sponsors](#for-sponsors) | A maintenance story with guardrails: funding never changes detection truth. |
| **Partner** | [For partners and coworking spaces](#for-partners-and-coworking-spaces) | A single dispatcher and `0/1/2` exit codes that fit events, training, CI, and runbooks. |
| **Coworking space** | [For partners and coworking spaces](#for-partners-and-coworking-spaces) | A Security Corner kit with a QR poster, opt-in blocking, and clear unblock steps. |

Full positioning, visual system, voice rules, tier examples, and boilerplate live in
[`docs/BRAND_IDENTITY.md`](docs/BRAND_IDENTITY.md).

### 30-second pitch

Malware that hides its loader on public blockchains is hard to spot and risky to
investigate. PolinRider turns that investigation into plain Bash: a read-only scan, a
dry-run block, a stage-only cleanup, and a watcher for new repo activity. The blocking
list and detection rules are text files you can audit. It is safe enough to demo in a
coworking space and predictable enough to put in CI.

## Safe demo for visitors

No root, no network calls, no payload execution:

```bash
./bin/polinrider doctor
./bin/polinrider scan --repos .          # read-only; 0 clean, 1 on a HIT
SENTINEL_SELFTEST=1 SENTINEL_COLS=100 SENTINEL_ROWS=30 ./bin/polinrider sentinel
./bin/polinrider block --dry-run         # prints [dry] actions only
./bin/polinrider config show             # webhooks redacted
```

On a real terminal, `./bin/polinrider sentinel --demo` shows the live console with
synthetic alarms. Keys: `q` quit, `p` pause/resume, `r` remote sweep, `l` local sweep,
`a` acknowledge.

Run without a subcommand on an interactive terminal to get the hand-rolled menu.
`gum` and `dialog` are optional adapters; the plain `read` fallback always works.

## Quick start (Linux, macOS, Git Bash / MSYS2)

```bash
cd /path/to/polinrider
cp config.env.example config.env && chmod 0600 config.env   # optional

./bin/polinrider doctor                       # check runtime + tools
./bin/polinrider scan --repos ~/code          # read-only scan
./bin/polinrider block --dry-run              # show what would change
sudo ./bin/polinrider block                   # apply hosts + firewall + DNS flush
sudo ./bin/polinrider unblock                 # remove only polinrider-marked blocks
./bin/polinrider verify --domain api.trongrid.io
```

On Windows, prefer Git Bash / MSYS2 and the same dispatcher. The existing PowerShell
scripts remain available for legacy use but are not updated by this prototype.

## CLI contract

```text
bin/polinrider <subcommand> [options] [positional]
bin/polinrider --help
bin/polinrider --version
```

Global flags are accepted **before or after** the subcommand:

| Flag | Effect |
|---|---|
| `--config PATH` / `$POLINRIDER_CONFIG` | Load an alternative allowlist config file. |
| `--dry-run` | Print `[dry]` actions; no changes. Applies to `block`, `unblock`, `clean`. |
| `--no-color` / `$NO_COLOR=1` | Disable ANSI colors. |
| `--json` / `--format json` | One JSON object per line; ignores colors. |
| `--quiet` | Only errors and summaries. |
| `--verbose` | Print config/signature paths and backend decisions; never prints webhooks. |
| `--yes` / `-y` | Skip confirmation prompts. |
| `--ui-backend BACKEND` | Force `auto`, `gum`, `dialog`, `plain`, or `read` for interactive prompts. |
| `-h`, `--help` | Show help (or subcommand help when given after a subcommand). |

Subcommands:

| Subcommand | Common options | Behavior |
|---|---|---|
| `doctor` | — | Check Bash ≥ 4, required tools, optional TUI tools, state dir permissions. |
| `config show` / `config validate` | — | Show effective config with webhooks redacted / validate allowlist. |
| `scan` | `--repos PATH` (repeatable), `--root PATH`, `--full`, `--format text\|json` | Part A/B/C read-only scan. `HIT` exits 1, `REVIEW` does not affect exit code. |
| `block` | `--iocs PATH`, `--hosts-only`, `--firewall auto\|nft\|iptables\|ufw\|pf\|none`, `--backup-dir PATH` | Apply hosts entries, firewall rules, DNS flush. Root needed only for a system hosts file. |
| `unblock` | same flags | Remove only blocks between the `BEGIN/END polinrider` markers; idempotent. |
| `verify` | `--domain HOST` (repeatable), `--timeout SEC` | Confirm blocked domains no longer resolve. |
| `clean ROOT` | `--dry-run` | Remove `.vscode/`, `public/fonts/`, `.gitignore` artifacts and strip injected build-config payloads. **Stages only — never commits.** |
| `watch` | `--once`, `--interval SEC`, `--repos-file PATH`, `--trusted-file PATH` | Headless GitHub activity watcher (force-push / untrusted actor alerts). |
| `sentinel` | `--once`, `--demo`, `--no-branches`, `--no-map`, `--remote-interval SEC`, `--local-interval SEC`, `--repos PATH` | Live 70×20+ console, or a single headless sweep. |
| `audit` | `--output PATH`, `--redact` | Read-only forensic summary with tokens redacted. |
| `help` | `[subcommand]` | Show help. |

Extra flags for automation/tests: `--hosts-file PATH`, `--backup-dir PATH` and
`--keep-partial` on `block`/`unblock`. A caller-supplied hosts file is user-owned, so
root is not required.

### Exit codes

Only three codes are used, everywhere (including cancel/interrupt paths):

| Code | Meaning |
|---|---|
| `0` | Success / clean / dry-run / confirmed Yes. |
| `1` | Finding, failed operation, or user cancellation. `sentinel --once` caps multiple critical hits to `1`. |
| `2` | Usage, unknown config key, missing dependency, not root for system hosts, terminal < 70×20, not a git repo for `clean`. |

## Sources of truth and safety model

- `iocs.txt` — domains/IPs to **block**. Edit this file; no code changes needed.
- `config/signatures.env` — regexes and globs used for **detection and cleanup**.
- `config.env` (local, `0600`, gitignored) — preferences and webhook secrets. Start
  from `config.env.example`.
- `bin/polinrider` — the single dispatcher. Root shell wrappers delegate through
  `lib/legacy.sh` and contain no duplicated logic.

The runtime is pure Bash: no `eval`, no `node`/`python`/`perl`, and no execution or
transformation of `decoded-malware-analysis.js.do_not_execute` into executable code.
All analysis is textual.

## Legacy shims

| Legacy command | New command |
|---|---|
| `block-iocs.sh --dry-run` | `bin/polinrider block --dry-run` |
| `block-iocs.sh --unblock` | `bin/polinrider unblock` |
| `check-polinrider-linux.sh ...` | `bin/polinrider scan --repos ...` |
| `check-polinrider-mac.sh ...` | `bin/polinrider scan --repos ...` |
| `canary-watch.sh` | `bin/polinrider watch --once` |
| `canary-sentinel.sh --once` | `bin/polinrider sentinel --once` |
| `clean-polinrider-repo.sh ROOT` | `bin/polinrider clean ROOT` |
| `audit-sixsixnine.sh` | `bin/polinrider audit` |

## Configuration

`config.env` is parsed line by line with an allowlist; it is **never sourced** and
command substitution is not executed. Unknown keys exit `2`. Environment variables
(for example `CANARY_REPOS`, `CANARY_TRUSTED_ACTORS`, `NO_COLOR`, `XDG_STATE_HOME`)
override committed defaults. Webhooks and the trusted-actor list are redacted by
`config show` and `--verbose`.

`config/signatures.env` holds the shared detection regexes and `BUILD_CFG_GLOBS`
(including `eslint.config.*`), so scanner, cleaner and sentinel agree. `config/canary.env`
holds the default watch list. State and backups default to
`${XDG_STATE_HOME:-$HOME/.local/state}/polinrider` with mode `0700`; backups and
`config.env` are `0600`.

## What the scan looks for

- **Part A — repo payloads:** V1 (`rmcej%otb%`, `global['!']='8-1638-2'`) and V2
  (`Cot%3t=shtP`) markers in JS/TS/Vue/Svelte files; fake `fa-solid-400.woff2` fonts
  containing ASCII JavaScript; TasksJacker `.vscode/tasks.json` with `runOn:folderOpen`;
  `task.allowAutomaticTasks: true` (review only); malicious npm dependency; weaponized
  UUID; git author/committer timezone mismatch.
- **Part B — host evidence:** Beavertail staging dirs, `_credentials.json` / `_sysenv.*`
  exfil files, exfil zips, lock file `tmp7A863DD1.tmp`, persistence references,
  dropper-shaped files, suspicious processes and connections, shell history.
- **Part C — deep logs (`--full`):** `journalctl` / `log show` / Sysmon / PowerShell
  4104 / Defender history. Non-root runs skip this with a warning and keep exit `0`.

A clean scan does not prove uninfection: Beavertail variants can self-clean after
exfiltration. Keep `iocs.txt` blocked at the network layer regardless.

## Continuous monitoring

```bash
./bin/polinrider watch --once                 # one headless sweep (cron/CI)
./bin/polinrider watch --interval 300         # long-running headless watcher
./bin/polinrider sentinel --once --repos ~/code
./bin/polinrider sentinel --demo              # synthetic alarm preview
./bin/polinrider sentinel                     # live console (q/p/r/l/a keys)
```

Remote surveillance needs authenticated `gh` and `jq`; without them `watch` exits `2`
while `sentinel` disables remote checks and still scans locally. Useful env vars:
`SENTINEL_REMOTE_INTERVAL`, `SENTINEL_LOCAL_INTERVAL`, `CANARY_REPOS`,
`CANARY_TRUSTED_ACTORS`, `CANARY_NTFY_TOPIC`, `CANARY_DISCORD_URL`,
`CANARY_SLACK_URL`, `CANARY_NATIVE=1`. `SENTINEL_SELFTEST=N` renders `N` frames
without network access.

## Blocking details

`block` writes IPv4 (`0.0.0.0`) and IPv6 (`::`) hosts entries inside marker comments,
backs up the hosts file to `BACKUP_DIR/hosts.bak.YYYYMMDD-HHMMSS` (`0600`), chooses
the first available firewall backend (`nft` → `iptables` → `ufw` → `pf` → PowerShell),
and flushes the DNS cache. Re-running is idempotent. `unblock` removes only marked
blocks and preserves unrelated lines such as `127.0.0.1 localhost`.

The timestamped backups are kept for manual comparison/restore. Firewall rules are
usually not persistent across reboot; re-run from a boot service or persist the rules
yourself.

## Verification

```bash
dig +short api.trongrid.io        # should print 0.0.0.0 or nothing
getent hosts bsc-dataseed.binance.org
curl -v --max-time 3 https://api.trongrid.io 2>&1 | head   # should fail fast
```

Windows: `Resolve-DnsName api.trongrid.io`, `nslookup bsc-dataseed.binance.org`,
`Test-NetConnection api.trongrid.io -Port 443`.

## Caveats

- `block` does **not** remove malware from repos. Scan first, then `clean ROOT`, review
  `git diff --cached`, and commit yourself.
- It does not protect machines you have not run it on, and does not survive re-imaging.
- It does not replace credential rotation.
- DoH/DoT bypasses hosts-file blocking; the firewall rules still block by IP.
- Legitimate dApp development against TRON/BSC will be affected — comment out
  `[HIGH]`/`[PRECAUTION]` entries you need in `iocs.txt`.
- A clean scan is not proof of uninfection.

## Tests

The harness uses only synthetic markers and fake `gh`/`jq` tools; no network calls and
no real payloads:

```bash
TEST_TIMEOUT=20 ./tests/run.sh       # AC-01…AC-32, currently 89 assertions
KEEP_TMP=1 ./tests/run.sh            # keep the fixture directory for debugging
bash -n bin/polinrider lib/*.sh *.sh tests/run.sh tests/assert.sh tests/fixtures/*
```

## For sponsors

Sponsorship funds maintenance, documentation, and outreach — never detection truth.
Sponsors cannot add, remove, or soften entries in `iocs.txt` or
`config/signatures.env`, and webhooks or trusted-actor lists are never printed.

| Example tier | Fit | Recognition |
|---|---|---|
| Visitor Pass | Trying the demo | Community-visitor listing |
| Supporter | Individuals and small teams | Name in the README supporters list |
| Guardian | Security vendors, infra providers | Logo link and release changelog mention |
| Sentinel | Foundations, coworking groups | Co-branded workshop slot and named partner entry |

Names are illustrative; see the full guardrails and copy templates in
[`docs/BRAND_IDENTITY.md`](docs/BRAND_IDENTITY.md#sponsorship-story).

Proof points to quote: **89 assertions, 0 failures**, no runtime `eval`/`node`/`python`/
`perl`, stage-only `clean`, `0600` secrets, and exit codes capped to `0/1/2`.

## For partners and coworking spaces

PolinRider fits as an event demo, a training module, a CI gate, or a coworking
**Security Corner**. The recommended kit is a QR poster to this README, a synthetic
fixture repo, a printed `block --dry-run` / `unblock` card, and a 15-minute
**Patch & Parse** session.

> Bring a repo. See what the scanner sees. Change nothing until you say so.

Partner models, workshop agenda, and visitor script are in
[`docs/BRAND_IDENTITY.md`](docs/BRAND_IDENTITY.md#partnership-story) and
[`docs/BRAND_IDENTITY.md`](docs/BRAND_IDENTITY.md#coworking-story).

## Files

| File | Purpose |
|---|---|
| `bin/polinrider` | Single dispatcher / CLI. |
| `lib/*.sh` | Core, config, IOC, scan, block, clean, canary, TUI and legacy helper modules. |
| `config/signatures.env`, `config/canary.env` | Committed detection/watch defaults. |
| `config.env.example`, `config.env` | Local config template / private config (`0600`, gitignored). |
| `iocs.txt` | Blocking source of truth (domains/IPs with confidence tags). |
| `*.sh` at repo root | Legacy shims listed above. |
| `*.ps1` | Frozen legacy Windows scripts; not used by the Bash prototype. |
| `decoded-malware-analysis.js.do_not_execute` | Analysis artifact — **never run**. |
| `malware-investigation.md`, `docs/PRD.md` | Investigation narrative and approved technical spec. |
| `docs/BRAND_IDENTITY.md` | English brand identity, pitch copy, sponsorship/partner/coworking story. |
| `tests/` | Acceptance harness and fixtures. |

## Brand

All public copy follows [`docs/BRAND_IDENTITY.md`](docs/BRAND_IDENTITY.md):
**Trace. Block. Clean. Verify.**
