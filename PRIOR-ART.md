# Prior Art

This kind of tool already exists in several forms, and it's worth being clear about
what's out there and where Trust Issues fits, rather than implying it appeared from
nowhere. Here's the landscape and how this one differs.

## What already exists

- **claude-world/claude-skill-antivirus** — a signature scanner with multiple detection
  engines that flags malicious patterns, data exfiltration, and dangerous ops across a
  large corpus of skills. The most direct "antivirus for skills" analog.
- **huifer/skill-security-scan** — a CLI that scans Claude skills for risky patterns
  before install.
- **Repello AI "SkillCheck"** — a browser-based scanner for agent skill files with
  prompt-injection detection, policy-violation checks, payload analysis, and severity
  scoring. Closest commercial cousin on the prompt-injection front.
- **Snyk "Skill Inspector" / Agent Scan** — dependency- and skill-oriented scanning from
  an established security vendor.
- **Marketplace-side scanning** (e.g. skillsdirectory.com) — directories that claim to
  scan every skill they list.

## The problem all of them share

Independent research has shown that signature-based skill scanners are **routinely
evaded**: reshaped malware slipped past eight popular scanners across roughly 1,600 real
malicious skills. Meanwhile real campaigns (e.g. the one nicknamed "ClawHavoc") planted
hundreds of malicious skills that installed info-stealers on victims who trusted a green
checkmark. A clean scan has been actively weaponized as false assurance.

## Where Trust Issues is different

Not "a better antivirus." A different shape of defense:

1. **Reasoning over signatures.** The grep scanner is an intentionally-loud first pass,
   not the verdict. The core is a five-persona adversarial read where a model reasons
   about intent. Our own benchmark ships a sample built to beat the grep, and we report
   the miss, precisely because signatures are beatable.
2. **Agent-native threats are first-class.** Prompt injection and hidden instructions
   inside `SKILL.md` / `AGENTS.md` / MCP tool descriptions are the primary hunt, not an
   afterthought bolted onto a code scanner.
3. **Fresh threat intel every run.** A mandatory step searches for current-month attack
   techniques before reviewing, so the tool does not freeze on its ship date.
4. **Honest about limits.** It states plainly that static review cannot prove the
   absence of novel malware, and that sandboxing plus least privilege are the real
   defenses, so a clean result is never treated as a guarantee.

## How to help instead of duplicate

If you maintain one of the tools above, the most useful thing here is probably the
prompt-injection persona (`references/threat-catalog.md` §5) and the honest benchmark
methodology (`benchmark/`). PRs that port those ideas upstream are more valuable than
another standalone scanner, and we will happily link to yours.
