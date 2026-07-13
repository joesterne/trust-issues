# Contributing to Trust Issues

The most valuable contributions here are **new ways to catch bad code** and **new
examples of bad code to catch**. Attackers iterate monthly, so this project is never
"done."

## Great first contributions

- **A new evasion fixture.** Drop an inert malicious sample into
  `benchmark/fixtures/malicious/` (exfil targets must be non-resolving
  `*.example.com`, payloads are strings not working attacks). Re-run
  `bash benchmark/run_benchmark.sh`. If the scanner misses a *realistic* pattern,
  that is a real gap.
- **A scanner rule** in `scripts/triage_scan.sh` that closes a miss. Add or extend a
  section, keep it read-only, and prove it with a fixture.
- **A threat-catalog entry** in `references/threat-catalog.md` for a technique the
  five-persona read should hunt.
- **A benign fixture** that a naive rule would wrongly panic about, to keep us honest
  about the review workload.

## Ground rules

1. **Read-only forever.** Nothing in this repo may execute the target under review.
   The scanner greps, it does not run. This invariant is non-negotiable.
2. **No working malware.** Fixtures are inert by construction. If a sample could do
   real harm when run, it does not belong here.
3. **Dogfood.** Before you open a PR, run the scanner on your own change
   (`bash scripts/triage_scan.sh .`) and the benchmark. CI does this too.
4. **One change per branch/PR.** Small, focused changes are easier to review and to
   revert. Use a short-lived branch (`feat/…`, `fix/…`, `docs/…`) and Conventional
   Commit messages.

## Workflow

```bash
git checkout -b feat/catch-dns-tunneling
# ...make the change + add a fixture...
bash benchmark/run_benchmark.sh
git commit -m "feat(scanner): flag DNS-tunneling exfil shapes"
git push -u origin feat/catch-dns-tunneling
# open a PR; CI must pass; we squash-merge
```

## Recording Security Reviews

When you perform a five-persona adversarial review of a skill, MCP server, or other artifact using this tool's SKILL.md framework:

1. Run the scanner with JSON output: `bash scripts/triage_scan.sh --json --output scan_TARGET.json <path>`
2. Conduct the five-persona manual review following SKILL.md (Acquire → Research → Scan → Reason → Decide)
3. Document your findings in `reviews/` using the schema defined in `references/reviews-schema.md`
4. See `references/example-review.json` for a complete example

The reviews schema captures: verdict (approved/conditional/rejected), risk level, scanner findings, manual analysis summary, any conditions for approval, and links to supporting artifacts. This creates an audit trail for reproducible security decisions.

## Commit style

Conventional Commits (`type(scope): summary`). It keeps the history readable and lets
the changelog write itself. Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`,
`sec`.

## Reporting a real vulnerability

If you find a genuine security issue in this repo (not in code it reviews), open a
private GitHub Security Advisory rather than a public issue.
