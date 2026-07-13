# Coverage Map

This maps a maximalist 20-part adversarial-review checklist onto Trust Issues, so the
"does it check X?" question is auditable instead of a promise. Status key:

- **Core** — a first-class part of the workflow / scanner, run every review.
- **Catalog** — enumerated in `references/threat-catalog.md` for the manual read.
- **If-applicable** — invoked only when the repo has that surface (IaC, firmware,
  native network code). Forcing it on a pure skill repo would be noise, and the report
  says "N/A" honestly.
- **Report** — produced in the output per `references/report-template.md`.

| Part | Topic | Status | Where |
|---|---|---|---|
| 1 | High-level assessment, 4 scores, probabilities, confidence | Report | `report-template.md` §1 |
| 2 | Malware review (backdoors, injection, C2, mining, ransomware, rootkits, stego, obfuscation) | Core + Catalog | scanner §2-9; `threat-catalog.md` §1, §7 |
| 3 | Secure-coding standards (OWASP, CWE, ATT&CK, NIST SSDF, MISRA, SEI CERT…) | Catalog | `threat-catalog.md` §2, §9 |
| 4 | Cryptography (weak hashing, ECB, hardcoded keys/IVs, TLS/JWT, key storage) | Catalog | `threat-catalog.md` §2 |
| 5 | Authentication/authorization (creds, OAuth/JWT, IDOR, RBAC/ABAC, priv-esc) | Catalog | `threat-catalog.md` §2 |
| 6 | Network security (HTTP/TLS, SSRF, CSRF, CORS, smuggling, sockets/listeners) | Core + Catalog | scanner §8; `threat-catalog.md` §2, §8 |
| 7 | Memory safety (overflows, UAF, TOCTOU, races, thread safety) | Catalog | `threat-catalog.md` §1 |
| 8 | Dependencies (CVEs, typosquat, dep-confusion, install hooks, lockfiles, transitive) | Core + Catalog | scanner §3, §11; `threat-catalog.md` §3 |
| 9 | Build pipeline (Actions/GitLab/Jenkins, Docker, signing, secrets, runner/perms) | Core + Catalog | scanner §10; `threat-catalog.md` §3 |
| 10 | Infrastructure (Docker/Terraform/K8s/Helm/Ansible, IAM, secrets) | If-applicable | `threat-catalog.md` §8 |
| 11 | Software-engineering (architecture, DoS/complexity, deserialization, plugin sec) | Catalog | `threat-catalog.md` §1, §2 |
| 12 | CISO (regulatory: HIPAA/PCI/SOC2/ISO/GDPR/SOX/FERPA, least priv, audit, 3rd-party) | Catalog + Report | `threat-catalog.md` §4; `report-template.md` §5 |
| 13 | Network engineer (segmentation, firewall/VPN/NAT, amplification, in/outbound) | If-applicable | `threat-catalog.md` §8 |
| 14 | Hardware/embedded (firmware, secure boot, TPM/HSM, JTAG/UART, DMA, side channels) | If-applicable | `threat-catalog.md` §8 |
| 15 | Secrets (passwords, tokens, SSH/AWS/Azure/GCP keys, PEM/PFX, DB creds) | Core | scanner §9 |
| 16 | Suspicious code (unusual, confusing, dead, magic constants, blobs, hidden dev tools) | Core + Report | scanner §2, §12-13; `report-template.md` §3 |
| 17 | Legacy/deprecation (old crypto, deprecated APIs, newly-exploitable patterns) | Catalog | `threat-catalog.md` §10 |
| 18 | Attack scenarios (path, prereqs, likelihood, impact, difficulty, detection, fix, sev) | Report | `report-template.md` §2 |
| 19 | Confidence tiers (Confirmed / Likely / Possible / Speculative) | Report | `report-template.md` §2 |
| 20 | Final report (exec + technical summary, top-25, quick wins, roadmap, audit pass/fail) | Report | `report-template.md` §5-6 |

## Plus one part generic checklists miss

The prompts above are written for *code*. Skills, MCP servers, and plugins are code **plus
natural-language instructions an AI will execute**. Trust Issues adds a fifth persona and a
scanner category dedicated to **prompt injection and hidden instructions** inside
`SKILL.md` / MCP tool descriptions / `AGENTS.md` (scanner §12-13; `threat-catalog.md` §5).
That is the highest-probability attack vector for an agent skill and is absent from the
generic 20-part checklist.

## Honest scope statement

Parts 13 and 14 (network-engineering, hardware/embedded) and much of Part 10 (heavy IaC)
are **out of scope for a pure software/skill repo** and are only invoked when the target
actually ships that surface. A review that pretends to audit firmware side-channels in a
100-line skill is theater. When a lens does not apply, the report says so in §4 rather than
inventing findings. Everything security-relevant to skills, repos, packages, and MCP
servers — which is what this tool is for — is Core or Catalog and runs every time.
