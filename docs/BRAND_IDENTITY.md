# PolinRider Brand Identity

English source of truth for how PolinRider is described to visitors, sponsors, partners,
and coworking spaces. Product behavior remains defined in `docs/PRD.md`; blocking truth
remains in `iocs.txt`; detection truth remains in `config/signatures.env`.

---

## Brand at a glance

| Field | Value |
|---|---|
| Name | PolinRider |
| Styled as | `PolinRider` — one word, capital **P** and **R** |
| Pronunciation | POH-lin RY-der |
| Category | Open-source security triage toolkit; coworking-safe demo station |
| Primary tagline | **Trace. Block. Clean. Verify.** |
| Supporting line | **Read-only by default. Explicit by design. Auditable by anyone.** |
| Product surface | `bin/polinrider` dispatcher, with optional `gum` / `dialog` adapters |
| Repository | This repository |
| Current stage | Product-grade open-source prototype with a 32-scenario acceptance harness |

**Positioning statement**

For developers, incident responders, founders, and shared-workspace communities who need
to investigate blockchain-hidden payloads without executing them, PolinRider is a pure
Bash toolkit that turns a messy investigation into four calm actions: scan, block, clean,
and verify. Unlike heavyweight endpoint agents or ad-hoc shell snippets, PolinRider keeps
its blocking list and detection rules as plain text, makes every change dry-runnable, and
never touches the analysis artifact during a scan.

---

## Brand promise

> Nothing suspicious runs. Nothing changes until you say so. Nothing is hidden from review.

| Promise | What it means in the product | What you can say out loud |
|---|---|---|
| Safe to demo | No `eval`, no `node`/`python`/`perl`, no execution of `*.do_not_execute`; tests use synthetic markers. | "You can watch a live investigation without touching the payload." |
| Explicit by design | `--dry-run`, confirmations, stage-only `clean`, and a strict `0/1/2` exit-code contract. | "Every change is previewed, confirmed, and reversible." |
| Auditable by anyone | `iocs.txt` and `config/signatures.env` are text files; webhooks are redacted. | "You can review exactly what we block and why." |

---

## Audience map

| Audience | Their real question | Core message | Call to action |
|---|---|---|---|
| **Visitor** | "Can I understand this in a minute without risking my laptop?" | A read-only scan, a synthetic alarm preview, and a dry-run block show the whole story. | Run the 60-second demo below. |
| **Sponsor** | "Will my support fund real, reviewable maintenance?" | Sponsorship funds maintenance and outreach, never changes detection truth. | Pick a tier and connect through the repository. |
| **Partner** | "Can this fit our event, curriculum, CI, or runbook?" | One dispatcher, text-based sources of truth, and predictable exit codes are easy to integrate. | Propose an event, workspace, distribution, or research pilot. |
| **Coworking space** | "How do we give members a useful security ritual without creating incidents?" | A Security Corner with read-only scans, opt-in blocking, and clear unblock steps. | Host a 15-minute Patch & Parse session. |

---

## Messaging pillars

1. **Safe by construction** — pure Bash, allowlist config parsing, synthetic fixtures, and
   a hard rule that the `.do_not_execute` artifact is textual only.
2. **Text as source of truth** — `iocs.txt` for blocking, `config/signatures.env` for
   detection, `config.env` for local secrets. No hidden database, no sourced config.
3. **Operator-grade interfaces** — one dispatcher, `--dry-run`, `--json`, `--quiet`,
   `--yes`, and exit codes capped to `0/1/2`, including cancel paths.
4. **Community-ready** — hand-rolled console by default, `gum`/`dialog` optional, and a
   plain `read` fallback that works anywhere Bash runs.

---

## Elevator pitches

### 10 seconds

PolinRider is a Bash-only toolkit that finds blockchain-hidden malware, blocks its
endpoints, stages a clean repo, and verifies the result — without ever running the payload.

### 30 seconds

Malware that hides its stage-2 loader on public blockchain RPC endpoints is hard to spot
and risky to investigate. PolinRider turns that investigation into plain Bash: a read-only
scan, a dry-run block, a stage-only cleanup, and a watcher for new repo activity. The
blocking list and detection rules are text files you can audit. It is safe enough to demo
in a coworking space and predictable enough to put in CI.

### 2 minutes

Start with the problem: a repo can look clean while an obfuscated loader fetches its next
stage from TRON, BSC, or Aptos RPC endpoints. Opening the suspicious file to "check it" is
exactly the mistake we want to avoid.

PolinRider approaches it in four steps. **Scan** reads repository and host evidence using
centralized signatures; it flags fake fonts, TasksJacker config, suspicious build files,
git timezone mismatches, and staging artifacts. **Block** writes `0.0.0.0` and `::` hosts
entries between clear markers, picks the available firewall backend, and flushes DNS —
only after a dry-run and confirmation. **Clean** removes the injected artifacts and strips
payloads from build configs, but only stages changes with `git rm`/`git add`; a human
reviews `git diff --cached` and commits. **Verify** checks that blocked endpoints no
longer resolve.

For **visitors**, that is a calm 60-second demo with synthetic alarms and no network
calls. For **sponsors**, it is maintainable open-source infrastructure with a published
source of truth and no pay-to-change rules. For **partners**, the single dispatcher and
`0/1/2` exit codes drop into events, training, CI, and runbooks. For **coworking spaces**,
it becomes a Security Corner: a repeatable, opt-in ritual that members can learn in fifteen
minutes and undo with `unblock`.

A clean scan is not proof of uninfection — variants can self-clean — so PolinRider says
that plainly and keeps the endpoints blocked at the network layer.

---

## Visual identity

### Wordmark

Use the wordmark **PolinRider**, not a newly invented mascot. When a compact mark is
needed, use the monospace prompt form `PR>` — a nod to the Bash prompt and to the
dispatcher. Do not stretch, recolor per sponsor, or replace the capital **R**.

```text
PR> PolinRider
    Trace. Block. Clean. Verify.
```

### Color system

| Token | Hex | Meaning | Primary use |
|---|---|---|---|
| Signal Ink | `#0B1020` | Deep navy, authority | Backgrounds, headings |
| Rider Cyan | `#22D3EE` | Signal, motion | Links, active state, `PR>` mark |
| Alert Amber | `#F59E0B` | Attention, review | `REVIEW`, `[!]` warnings |
| Clean Green | `#34D399` | Safe, staged, confirmed | `[+]`, success summaries |
| Critical Red | `#FB7185` | Finding, cancel, failure | `HIT`, `[X]`, errors |
| Paper | `#F8FAFC` | Neutral text surface | Body copy, light theme |

Terminal output must stay readable without color: `NO_COLOR=1`, `--no-color`, or a
non-TTY stdout removes all ANSI bytes. The text prefixes carry the meaning:

| Prefix | Meaning | Color when allowed |
|---|---|---|
| `[*]` | Action / context | Rider Cyan |
| `[+]` | Loaded / succeeded | Clean Green |
| `[!]` | Warning / skipped | Alert Amber |
| `[X]` | Error / dependency / cancel | Critical Red |
| `[?]` | Item for review | Alert Amber |

### Typography

- **Headings:** Space Grotesk, fallback to system sans-serif.
- **Body:** Inter, fallback to system sans-serif.
- **Commands and logs:** JetBrains Mono, fallback to `ui-monospace`, `Menlo`, `Consolas`.
- Keep taglines in sentence case; keep CLI flags in monospace.

### Layout rules

- Lead with the promise, then the proof. Never open with tool internals.
- Show one safe command before asking for commitment.
- Put sources of truth and exit codes near any technical claim.
- Reserve red for real findings or failures; do not use it for decoration.
- No flashing alerts, no countdown urgency, no fear-first copy.

---

## Voice and tone

Calm, precise, plain English. The product deals with incidents; the brand should lower the
temperature, not raise it.

| Do | Don't |
|---|---|
| "A clean scan does not prove uninfection." | "Your machine is 100% safe now." |
| "Changes are staged for review." | "We fixed everything automatically." |
| "Sponsors fund maintenance, not detection truth." | "Sponsors decide what is malicious." |
| "Run this read-only demo first." | "Just run the script and trust us." |
| "Root is needed only for a system hosts file." | "Requires admin." |

---

## Sponsorship story

### Sponsor promise

Sponsors keep PolinRider independent, auditable, and easy to teach. Sponsorship never
changes `iocs.txt`, `config/signatures.env`, or the exit-code contract. Webhooks and
trusted-actor lists are never printed in `config show` or `--verbose`.

### Example tiers

These names are illustrative; set prices locally before publication.

| Tier | Best for | Recognition | Non-recognition commitment |
|---|---|---|---|
| Visitor Pass | Anyone trying the demo | Listed as a community visitor in the README | No logo required |
| Supporter | Individuals and small teams | Name in the README supporters list | No influence on detections |
| Guardian | Security vendors, infra providers | Logo link plus a changelog mention per release | No paid removal from IOC/signature files |
| Sentinel | Foundations, coworking groups | Co-branded workshop slot and named partner entry | Public notes for any sponsored scope |

### Sponsorship guardrails

- No sponsor can add, remove, or soften a detection in exchange for funding.
- No webhook, token, or trusted-actor list is exposed in public copy.
- Sponsor links go outward from the README; no inline tracking pixels in docs.
- Security claims must reference the acceptance harness, not the sponsor.

---

## Partnership story

| Model | Partner does | PolinRider provides | Success signal |
|---|---|---|---|
| Event partner | Hosts a demo table or talk | 60-second script, poster copy, synthetic fixtures | Visitors run the demo themselves |
| Workspace partner | Adds a Security Corner | QR poster, unblock instructions, sponsor wall | Monthly session attendance |
| Distribution partner | Ships the toolkit in an image or curriculum | Dispatcher docs, exit-code contract, allowlist config | Fewer one-off shell variants |
| Research partner | Contributes detection scenarios | `config/signatures.env` conventions and synthetic tests | New AC case with no real payload |

---

## Coworking story

Position PolinRider as a **Security Corner**, not as a perimeter product.

**The kit**

1. A one-page poster with a QR code to this README and the safe demo.
2. A synthetic fixture repo — no real payloads — for the scan step.
3. A printed `block --dry-run` / `unblock` card so members know how to undo opt-in changes.
4. A 15-minute **Patch & Parse** session: scan, read one finding, dry-run block, review.
5. A sponsor wall that credits supporters without implying detection influence.

**Coworking message**

> Bring a repo. See what the scanner sees. Change nothing until you say so.

---

## Visitor demo

### 60-second script

No root, no network calls, no payload execution:

```bash
./bin/polinrider doctor
./bin/polinrider scan --repos .          # read-only; 0 clean, 1 on a HIT
SENTINEL_SELFTEST=1 SENTINEL_COLS=100 SENTINEL_ROWS=30 ./bin/polinrider sentinel
./bin/polinrider block --dry-run         # prints [dry] actions only
./bin/polinrider config show             # webhooks redacted
```

On a real terminal, `./bin/polinrider sentinel --demo` shows the live console with
synthetic alarms. `q` quits, `p` pauses, `r`/`l` trigger sweeps, and `a` acknowledges.

### 15-minute workshop agenda

| Minutes | Step | Output |
|---|---|---|
| 0–2 | Explain the blockchain-loader problem | Shared vocabulary |
| 2–5 | Run `doctor` and read-only `scan` | A real report on a synthetic repo |
| 5–8 | Show the sentinel self-test frames | One CRIT, capped to exit `1` |
| 8–11 | Run `block --dry-run` | Understand markers and backups |
| 11–13 | Read `unblock` card | Everyone knows how to revert |
| 13–15 | State the caveat and invite sponsorship/partnership | Honest close, clear CTA |

---

## Proof points to quote

- **89 assertions, 0 failures** across AC-01…AC-32 in `tests/run.sh`.
- Pure Bash: no `eval`, `node`, `npm`, `python`, or `perl` in the runtime.
- `*.do_not_execute` files are never executed or transformed into executable code.
- `clean` stages with `git rm`/`git add` and never commits.
- `config.env` is parsed with an allowlist and never sourced; secrets are `0600`.
- Exit codes are only `0`, `1`, and `2`, including Ctrl-C and `gum`/`dialog` cancel.
- A clean scan is explicitly **not** proof of uninfection.

---

## Boilerplate

**Short (25 words).** PolinRider is a pure-Bash toolkit that scans for blockchain-hidden
malware, blocks its endpoints, stages a clean repo, and verifies the result.

**Medium (50 words).** PolinRider turns EtherHiding-style investigations into read-only
scans, dry-run blocks, stage-only cleanup, and continuous watch. Blocking truth lives in
`iocs.txt`, detection truth in `config/signatures.env`, and every action returns `0`, `1`,
or `2`.

**Long (100 words).** PolinRider is an open-source, Bash-only incident-response toolkit
for malware that hides stage-2 loaders on public blockchain RPC endpoints. It scans repos
and hosts without executing suspicious files, writes reversible hosts and firewall blocks
after confirmation, stages repository cleanup for human review, and watches GitHub
activity for force pushes and untrusted actors. The hand-rolled console works with zero
dependencies; `gum` and `dialog` are optional adapters. Sponsors fund maintenance, not
detection truth.

**Social bio.** Pure Bash security triage: trace, block, clean, verify. Read-only by
default.

**Email signature line.** PolinRider — Read-only by default. Explicit by design.

---

## Copy governance

- Keep all project and pitch copy in **English**.
- Keep `iocs.txt` and `config/signatures.env` as the source of truth; do not restate IOC
  values in marketing copy.
- Never describe a clean scan as proof of uninfection.
- If positioning changes, update this file and the README in the same commit.
- If a visual asset is added later, derive its colors and tone from this document.
