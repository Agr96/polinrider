# Agent instructions — PolinRider

- **Blocking source of truth:** `iocs.txt`. Only add/remove domains and IPs there;
  do not hardcode C2 indicators in scripts.
- **Detection source of truth:** `config/signatures.env` (regexes, `BUILD_CFG_GLOBS`).
  Keep scanner, cleaner and sentinel using the same values. `config/canary.env` holds
  the committed watch list; `config.env` is local/secret and gitignored (`0600`).
- **Single entry point:** `bin/polinrider`. Legacy `*.sh` wrappers must stay thin and
  delegate through `lib/legacy.sh`. Do not duplicate logic in wrappers.
- **Never execute malware artifacts.** Do not run, import, `source`, or transform into
  executable code any `*.do_not_execute` file. All analysis is textual.
- Runtime is pure Bash. Do not introduce `eval`, `node`, `npm`, `python`, `perl`, or
  execution of analysis artifacts. `set -euo pipefail` is mandatory in every
  executable; libraries must never disable it.
- Config files are parsed with an allowlist, never sourced. Unknown keys and invalid
  values exit `2`. Webhooks and trusted actors must be redacted in `config show` and
  `--verbose`.
- Exit codes are only `0` (success/clean), `1` (finding/failure/cancel), `2`
  (usage/config/dependency/prerequisite). Cap raw hit counts with `cap_exit`.
- `clean` stages changes only (`git rm`/`git add`), never commits. Backups use mode
  `0600` and `*.polinrider-bak` stays gitignored.
- Tests must use synthetic markers plus fake `gh`/`jq` tools — no real payloads and no
  network calls. Run `TEST_TIMEOUT=20 ./tests/run.sh` after changes.
- The hand-rolled console is the default TUI; `gum`/`dialog` are optional adapters
  with a plain `read` fallback. Map Ctrl-C/Esc/Cancel to exit `1`.
