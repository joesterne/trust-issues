# Benchmark

Most scanners quote an accuracy number without shipping the test set. This one ships
the corpus so the number is checkable.

## What it measures

- **Malicious recall** — of the known-malicious fixtures, how many does the read-only
  triage scanner flag? This is the headline number.
- **Benign surfaced** — how many benign fixtures trip a flag. This is the *manual-review
  workload*, not a false-positive rate. Triage is deliberately tuned for recall; the
  five-persona reasoning pass is what clears legitimate-but-loud code (a scheduler using
  `spawnSync`, a regex `.exec()`, a config reading one env var).
- **Evasion** — at least one malicious fixture is built to defeat pattern matching. It
  *should* be missed. Reporting that miss is the point: it is the standing argument for
  the manual read and the sandbox, and a guard against green-checkmark theater.

## Run it

```bash
bash benchmark/run_benchmark.sh
```

Nothing in `fixtures/` is ever executed. Each sample is copied into a temp dir and
scanned read-only. The malicious fixtures are **inert**: exfiltration targets are
non-resolving `*.example.com` placeholders and payloads are strings, not working
attacks. They exist so the scanner has something realistic to catch.

## Current baseline

| Metric | Result |
|---|---|
| Malicious recall | 10 / 11 (91%) |
| Missed (by design) | `evasive_obfuscated.py`, which assembles `os.environ` and its network call at runtime so no literal pattern matches |
| Benign surfaced for review | 4 / 8 |

## How to extend it

Adding a fixture is the best kind of contribution. Drop an inert sample into
`fixtures/malicious/` (with an exfil target under `*.example.com`) or
`fixtures/benign/`, re-run, and watch what the scanner does. If it misses a *realistic*
malicious pattern (not an intentionally-evasive one), that is a scanner bug worth a PR
against `scripts/triage_scan.sh`. This is literally how the env-exfil detector got
fixed: a fixture caught the gap first.
