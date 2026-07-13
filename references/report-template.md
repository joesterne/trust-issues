# Report Template

Use this structure. Keep it concentrated: a sharp report beats an exhaustive checklist.
Lead with the verdict-relevant facts. Not every section applies to every repo; mark
inapplicable ones "N/A" rather than padding.

---

# Security Review — <repo/skill name>

**Source:** <url>  **Commit reviewed:** <sha>  **Date:** <date>  **Reviewer:** Trust Issues

## 1. High-Level Assessment
- **Verdict:** NO-GO | GO WITH MITIGATIONS | GO
- **Scores (X/10):** Security · Maintainability · Supply-Chain Risk · Operational Risk
  (for the risk scores, higher = riskier; state it so the direction is unambiguous).
- **Probability malicious code exists:** <low/medium/high + one-line basis>
- **Probability of accidental vulnerabilities:** <low/medium/high>
- **Overall confidence:** <low/medium/high> (static review of one commit)
- **What it claims to do / what it can actually touch:** network, filesystem, secrets,
  subprocess, install hooks. Flag every gap between claim and capability.
- **Attack surface summary:** <2-4 sentences — where an attacker would aim>
- **Threat-landscape note:** relevant findings from the current-attacks web search;
  whether the author/package appears in any live advisory.

## 2. Critical Findings
For every high-severity or highly suspicious issue, use the full attack-scenario shape:

### [SEV: Critical/High/Medium/Low/Info] — <threat name>
- **Confidence:** Confirmed | Likely | Possible | Speculative  *(never present speculation as fact)*
- **Location:** `path/to/file:line`
- **Framework:** the OWASP/CWE/ATT&CK/etc. class it maps to
- **Attack scenario:** path → prerequisites → likelihood → impact → difficulty →
  detection difficulty
- **Recommended fix / mitigation** (with a short code example where it helps)

(Repeat per finding. If none: say so, and do NOT inflate the verdict beyond the evidence.)

## 3. Suspicious Indicators
Not definitively malicious, but worth a human's eyes: unexplained binaries, odd
endpoints, obfuscated strings, over-broad scopes, agent directives worth a second read,
dependency oddities, magic constants, disabled/commented-out code. One line each.

## 4. Coverage Notes (what was and was NOT examined)
State which lenses applied and which were N/A (e.g. "no IaC present," "pure software, no
hardware/firmware surface," "no CI workflows"). Honesty about scope is part of the report.

## 5. Final Report
- **Executive summary** (for a non-engineer decision-maker).
- **Technical summary.**
- **Top findings** (ranked; up to 25 for a large/complex repo, fewer if that's all there is).
- **Quick wins** (cheap, high-value fixes).
- **Long-term refactoring** (structural improvements).
- **Malware / backdoor / supply-chain indicators** (or "none observed").
- **Recommended security roadmap.**
- **Audit-readiness estimate — would this pass:** internal enterprise review · open-source
  audit · government review · financial-institution review · defense-contractor review?
  (yes / with-fixes / no, one line each — best estimate, not a certification.)

## 6. Verdict & Required Mitigations
- Restate the verdict in plain language.
- If GO WITH MITIGATIONS, list concrete conditions (sandbox only, no secrets mounted,
  pin commit <sha>, deny network egress except <domain>, review deps X/Y, etc.).
- **Stop-immediately list:** anything that should make a researcher halt and investigate
  now, even if not yet provably malicious.
- **Residual-risk statement:** this is a static review of one commit; it cannot prove the
  absence of well-hidden or novel malware. The primary defenses remain sandboxing and
  least privilege.

## 7. Record
- Store: source URL + reviewed commit SHA + verdict + date.
- Re-review required when the version/commit changes.
