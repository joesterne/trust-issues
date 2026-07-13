# Architecture

A candid architectural review of Trust Issues, written the way an enterprise architect
would sign off on it: what is sound, what the trade-offs are, and what to refactor *when*
(not just *whether*). The guiding principle is that good architecture also means not
over-engineering a small tool before its scale justifies it.

## 1. System context and trust boundary

The single most important architectural fact is the trust boundary, and the invariant
that protects it:

```
        UNTRUSTED                     |            TRUSTED
 ┌───────────────────────┐           |     ┌────────────────────────────┐
 │  target repo / skill  │  read     │     │  triage_scan.sh (engine)   │
 │  (assume hostile)     │ ────────► │     │  READ-ONLY: grep/find/file │
 └───────────────────────┘   only    |     │  never executes target     │
                                      |     └─────────────┬──────────────┘
                                      |                   │ candidates
                                      |     ┌─────────────▼──────────────┐
                                      |     │  5-persona reasoning read  │
                                      |     │  (LLM + threat-catalog)    │
                                      |     └─────────────┬──────────────┘
                                      |                   │
                                      |     ┌─────────────▼──────────────┐
                                      |     │  verdict: GO/MITIGATE/NO-GO│
                                      |     │  + persisted review record │
                                      |     └────────────────────────────┘
```

**Invariant: target code never executes during review.** Every component is designed
around it. This is what makes the tool safe to run against genuinely malicious input,
and it is the property any change must preserve.

## 2. Component decomposition (separation of concerns)

The skill follows the recommended three-tier "progressive disclosure" model, which maps
cleanly onto classic separation of concerns:

| Layer | Artifact | Responsibility | Changes when |
|---|---|---|---|
| Orchestration | `SKILL.md` | The workflow: acquire → research → scan → reason → decide | The *process* changes |
| Knowledge (data) | `references/threat-catalog.md`, `report-template.md` | What to hunt, how to report | New threats/techniques |
| Deterministic engine | `scripts/triage_scan.sh` | Fast, repeatable static triage | New detection rules |
| Verification | `benchmark/` | Prove the engine catches what it claims | New fixtures/regressions |

This is genuinely sound: orchestration is decoupled from knowledge, the deterministic
part is isolated from the reasoning part, and the whole thing has an executable test
harness. Most "vibecoded" skills are a single monolithic `SKILL.md`; this is not.

## 3. What is architecturally strong

- **Defense in depth.** Three independent layers (signature triage, LLM reasoning,
  sandbox + least privilege) so no single layer is a single point of failure. The design
  explicitly assumes the scanner will be evaded and does not rely on it.
- **Fail-safe default.** The default posture is "assume hostile," and a clean result does
  not flip that to "safe." The design stays cautious even when nothing shows up.
- **Data-driven extension points.** Threats (`threat-catalog.md`) and tests (`fixtures/`)
  are data, so the two things that change most often can grow without touching control
  flow. The env-exfil fix landed as a fixture first, then a rule. That is the extension
  model working as intended.
- **Verifiable claims.** Shipping the benchmark corpus makes the recall number auditable,
  which is itself an architectural stance (observability over assertion).

## 4. Honest weaknesses and a phased refactor roadmap

Yes, there are things to refactor for flexibility and scale. The discipline is to
sequence them by real need, not do them all now.

| # | Issue | Refactor | Priority | Why not now |
|---|---|---|---|---|
| W1 | `triage_scan.sh` mixes **engine + rules + presentation** in one file | Extract detection patterns into a versioned data file (e.g. `rules/*.rules`) the engine loads; keep a thin renderer | Phase 2 | At ~13 rule groups the coupling is legible; a rules-engine now adds abstraction with no payoff. Do it when rule count or contributor volume demands. |
| W2 | Human-readable output only | Add a `--json` mode (findings as structured records) so CI and other tools can consume it | Phase 1 | Cheap, high value for integration and the review record |
| W3 | **Platform portability**: relies on GNU grep (`-P` for the unicode check) | Guard the `-P` path, offer a ripgrep backend, document the dependency | Phase 1 | Partly handled (section 13 degrades gracefully); finish it |
| W4 | No **versioning/provenance** | Add `VERSION` + a plugin manifest so installs and audit records pin a reviewed version | Phase 1 | Needed before this is depended on at scale |
| W5 | Review-record persistence is described in `SKILL.md` but has no schema | Define a `reviews/*.json` schema (source, commit SHA, verdict, date) so re-clones are not re-reviewed and version bumps force a re-review | Phase 2 | Works as a documented convention until automated |
| W6 | The 5-persona read is **context-bound** on very large repos | Document (and later script) a map-reduce pass: subagents per subtree, then a merge | Phase 2 | Only matters for large targets; agents can already fan out manually |

### The anti-over-engineering note

W1 is the tempting one, and the deliberate call is **not** to convert a 200-line bash
triage into a plugin rules-engine yet. That would trade a legible, auditable script for
indirection that a reviewer then has to trust. For a security tool, auditability of the
engine itself is a feature. Refactor when the rules outgrow the file, not before.

## 5. Scalability posture

- **Horizontal (more targets):** each review is independent and stateless, so throughput
  scales by running more reviews in parallel. No shared state to contend on.
- **Vertical (bigger targets):** bounded by the reasoning layer's context, addressed by
  the W6 map-reduce roadmap.
- **Rule growth:** addressed by W1 (rules-as-data) when justified.
- **Contributor growth:** addressed by the data-driven extension points plus CI
  (`.github/workflows/`) that runs the self-scan and benchmark on every PR, so quality
  does not degrade as more hands touch it.

## 6. Verdict

Architecturally sound for its purpose and size, with a clear trust boundary, real
separation of concerns, defense in depth, and a fail-safe default. The refactors above
are about *scaling* it, not fixing a broken foundation, and they are sequenced so the
tool never loses the property that makes it trustworthy: it reasons about hostile code
without ever running it.
