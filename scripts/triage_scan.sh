#!/usr/bin/env bash
# triage_scan.sh — READ-ONLY static triage for an untrusted repo or skill.
#
# This script NEVER executes any code from the target. It only reads files with
# grep/find/file. It is a fast first pass whose job is to surface things a human
# (or the reviewing agent) must then read manually. A clean run is NOT proof of
# safety — it is the floor, not the ceiling. Always follow with the manual
# adversarial read described in SKILL.md.
#
# Usage:  bash triage_scan.sh <path-to-repo>
#
# Exit code is always 0 (this is triage, not a gate). The DECISION is made by the
# reviewing agent/human using this output plus the manual read.

set -uo pipefail
TARGET="${1:-}"
if [[ -z "$TARGET" || ! -d "$TARGET" ]]; then
  echo "usage: bash triage_scan.sh <path-to-repo>"; exit 2
fi
TARGET="${TARGET%/}"

SRC_INC=(--include=*.py --include=*.js --include=*.mjs --include=*.cjs --include=*.ts
         --include=*.tsx --include=*.jsx --include=*.sh --include=*.bash --include=*.zsh
         --include=*.rb --include=*.go --include=*.rs --include=*.php --include=*.pl
         --include=*.ps1 --include=*.psm1)
TXT_INC=(--include=*.md --include=*.mdx --include=*.markdown --include=*.txt
         --include=*.json --include=*.yml --include=*.yaml --include=*.toml --include=*.env*)

hr(){ printf '\n== %s ==\n' "$1"; }
g(){ grep -RIn --binary-files=without-match "$@" "$TARGET" 2>/dev/null | grep -v '/.git/' ; }
# go(): clean value extraction for -oE (no path:line prefix, .git excluded), deduped by caller
go(){ grep -rhoIE --binary-files=without-match --exclude-dir=.git "$@" "$TARGET" 2>/dev/null ; }

echo "######## TRIAGE: $TARGET ########"
echo "(read-only signature scan — manual review still required)"

hr "1. INVENTORY"
echo "Tracked files by extension:"
find "$TARGET" -type f -not -path '*/.git/*' 2>/dev/null \
  | sed 's/.*\.//; s#.*/##' | sort | uniq -c | sort -rn | head -30
echo; echo "Largest files (watch for vendored blobs / minified bundles):"
find "$TARGET" -type f -not -path '*/.git/*' -printf '%s\t%p\n' 2>/dev/null \
  | sort -rn | head -10 | awk '{printf "  %10d  %s\n",$1,$2}'

hr "2. NON-TEXT / BINARY / HIGH-ENTROPY BLOBS (unexplained binaries are a red flag)"
find "$TARGET" -type f -not -path '*/.git/*' 2>/dev/null | while read -r f; do
  case "$f" in *.png|*.jpg|*.jpeg|*.gif|*.svg|*.ico|*.woff*|*.ttf|*.pdf) continue;; esac
  if file "$f" 2>/dev/null | grep -qiE 'executable|ELF|Mach-O|PE32|shared object|archive data|compiled'; then
    echo "  BINARY: $f -> $(file -b "$f" 2>/dev/null)"
  fi
done
echo "  minified/bundled JS (can hide payloads):"
find "$TARGET" -type f \( -name '*.min.js' -o -name '*bundle*.js' \) -not -path '*/.git/*' 2>/dev/null | sed 's/^/    /' | head

hr "3. NPM INSTALL HOOKS (the #1 npm supply-chain vector — runs on 'npm install')"
grep -RnE '"(pre|post)?install"|"prepare"|"preprepare"|"postprepare"' "$TARGET" --include=package.json 2>/dev/null | grep -v '/.git/' || echo "  (none)"

hr "4. REMOTE-CODE-INTO-SHELL (curl|wget|iwr piped to an interpreter)"
g -E '(curl|wget|fetch|iwr|Invoke-WebRequest)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|d)?sh|python[0-9]?|node|perl|ruby' || echo "  (none)"

hr "5. DYNAMIC CODE EXECUTION / DESERIALIZATION"
echo "-- Python --"
g "${SRC_INC[@]}" -E '\b(eval|exec|compile)\s*\(|__import__\s*\(|os\.system\s*\(|subprocess\.[A-Za-z]+\([^)]*shell\s*=\s*True|pickle\.loads|yaml\.load\s*\((?!.*Loader)|marshal\.loads|ctypes|getattr\([^,]+,\s*[^)]*\)\s*\(' | head -25 || echo "  (none)"
echo "-- JS/TS --"
g "${SRC_INC[@]}" -E '\beval\s*\(|new\s+Function\s*\(|child_process|execSync|spawnSync|vm\.runIn|require\(\s*[`"'"'"']child_process|process\.binding' | head -25 || echo "  (none)"

hr "6. BASE64 / HEX / OBFUSCATED BLOBS DECODED THEN RUN"
g "${SRC_INC[@]}" -E '(base64|b64decode|atob|fromCharCode|unhexlify|bytes\.fromhex|Buffer\.from\([^)]*base64)' | head -20 || echo "  (none)"
echo "  long inline base64-looking strings (>120 chars):"
go "${SRC_INC[@]}" -E '[A-Za-z0-9+/]{120,}={0,2}' | sort -u | head -10 || echo "  (none)"

hr "7. CREDENTIAL / SECRET HARVESTING (reads of local secret stores)"
g -E '\.ssh|id_rsa|id_ed25519|\.aws/credentials|\.aws/config|\.npmrc|\.netrc|\.docker/config|keychain|security[[:space:]]+find-generic|/etc/passwd|/etc/shadow|LocalStorage|Cookies?/|login\.keychain|gnome-keyring|libsecret|browser.*[Pp]assword' | head -20 || echo "  (none)"
echo "  dumps/exfil of environment variables (bulk access / env shipped to a call):"
g "${SRC_INC[@]}" -E 'dict\(os\.environ|os\.environ\.(copy|items|keys)\(|os\.environ\)|(json|data|params|body)\s*=\s*[^\n]*os\.environ|requests\.(post|get|put|patch)\([^\n]*environ|process\.env\b[^.]*(JSON|Object\.(keys|entries|values)|for\b|\.\.\.)|Object\.(keys|entries)\(process\.env|printenv|env\s*\|' | head -12 || echo "  (none)"

hr "8. NETWORK EGRESS — every endpoint (compare against the repo's STATED purpose)"
echo "-- URLs in source --"
go "${SRC_INC[@]}" -E 'https?://[a-zA-Z0-9._~:/?#@!$&*+,;=%-]+' | sort -u | head -40 || echo "  (none)"
echo "-- raw IP addresses (hardcoded IPs / possible C2) --"
go "${SRC_INC[@]}" -E '([0-9]{1,3}\.){3}[0-9]{1,3}(:[0-9]+)?' | sort -u | grep -vE '127\.0\.0\.1|0\.0\.0\.0' | head -20 || echo "  (none)"
echo "-- inbound listeners / reverse-shell shapes --"
g "${SRC_INC[@]}" -E '\.listen\(|createServer|bind\(\(|socket\.(bind|listen)|/dev/tcp/|nc\s+-e|ncat|bash\s+-i' | head -12 || echo "  (none)"

hr "9. SECRETS LEAKED INSIDE THE REPO (someone committed a live key)"
g -E '(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9]{20,}|sk_live_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----|AIza[0-9A-Za-z_-]{35})' | head -15 || echo "  (none)"

hr "10. CI/CD WORKFLOW RISK (.github/workflows, etc.)"
WF=$(find "$TARGET" -type d \( -name workflows -o -name '.circleci' -o -name '.gitlab-ci*' \) -not -path '*/.git/*' 2>/dev/null)
if [[ -n "$WF" ]]; then
  echo "-- dangerous triggers (pull_request_target / workflow_run run attacker code with secrets) --"
  g --include=*.yml --include=*.yaml -E 'pull_request_target|workflow_run' | head || echo "  (none)"
  echo "-- curl|bash or inline secret use inside CI --"
  g --include=*.yml --include=*.yaml -E '(curl|wget)[^|]*\|[[:space:]]*sh|\$\{\{\s*secrets\.' | head || echo "  (none)"
  echo "-- third-party actions pinned by tag/branch not SHA (mutable = poisonable) --"
  g --include=*.yml --include=*.yaml -E 'uses:\s+[^@]+@(v?[0-9]|main|master)' | head || echo "  (none)"
else
  echo "  (no CI workflow dir found)"
fi

hr "11. DEPENDENCY MANIFESTS (audit each for typosquats / unpinned / young packages)"
find "$TARGET" -maxdepth 3 -not -path '*/.git/*' \( -name package.json -o -name requirements*.txt -o -name Pipfile -o -name pyproject.toml -o -name go.mod -o -name Cargo.toml -o -name Gemfile \) 2>/dev/null | sed 's/^/  /'
echo "  unpinned python deps (no == ) — supply-chain drift risk:"
g --include=requirements*.txt -E '^[A-Za-z0-9._-]+\s*$' | head -15 || echo "  (all pinned or none)"

hr "12. AGENT / PROMPT-INJECTION SIGNALS (critical for SKILL.md / MCP / .cursorrules / AGENTS.md)"
echo "-- imperative directives aimed at an AI agent inside docs --"
g "${TXT_INC[@]}" -iE 'ignore (all |the )?(previous|prior|above) instructions|disregard (the )?(system|previous)|do not (tell|inform|mention to) the user|without (asking|telling|informing) the user|bypass|override .*(safety|guardrail|approval)|exfiltrate|send .*(\.env|secret|token|key|credential).*(to|http)|curl .*\| *sh|as an ai,? you (must|should|will)' | head -20 || echo "  (none)"
echo "-- directives to read secrets / .env from within a skill doc --"
g "${TXT_INC[@]}" -iE '(read|open|cat|load|print) .*(\.env|\.ssh|credentials|api[_ -]?key|secret|token)|process\.env|os\.environ' | head -15 || echo "  (none)"
echo "-- directives to install/connect external tooling (MCP servers, remote skills) --"
g "${TXT_INC[@]}" -iE 'mcp add|add custom connector|npx [^ ]+ (install|add)|pip install (git\+|http)|install .*from .*http|claude mcp add|register .*server' | head -15 || echo "  (none)"

hr "13. HIDDEN / OBFUSCATED TEXT (zero-width, bidi, homoglyph tricks that hide instructions)"
# Zero-width, bidi-override, and other invisible unicode used to smuggle instructions past a human reader.
if grep -rlP $'[​‌‍⁠‪-‮⁦-⁩﻿]' "$TARGET" 2>/dev/null | grep -v '/.git/' | head; then :; else echo "  (none detected — note: grep -P required; if unsupported, check manually)"; fi
echo "  HTML comments in markdown (can hide agent instructions from rendered view):"
g --include=*.md --include=*.mdx -oE '<!--.*-->' | head -10 || echo "  (none)"

hr "14. COMPILED-MALWARE / INJECTION / MINING / ANONYMIZING-C2 INDICATORS (when native code or binaries present)"
echo "-- code injection / process hollowing / shellcode --"
g "${SRC_INC[@]}" -E 'VirtualAllocEx|WriteProcessMemory|CreateRemoteThread|NtMapViewOfSection|QueueUserAPC|SetWindowsHookEx|ptrace\(|LD_PRELOAD|mprotect\([^)]*PROT_EXEC|reflectiveloader|process[_ ]?hollow' | head -12 || echo "  (none)"
echo "-- anti-analysis (anti-debug / anti-VM / anti-sandbox) --"
g "${SRC_INC[@]}" -E 'IsDebuggerPresent|CheckRemoteDebugger|anti[_-]?(vm|debug|sandbox)|vmware|virtualbox|qemu|sbiedll|sandboxie' | head -10 || echo "  (none)"
echo "-- anonymizing / covert C2 / mining --"
g "${SRC_INC[@]}" -E '\.onion\b|stratum\+tcp|xmrig|minerd|coinhive|i2p\b|torify|dga_|domain_?generation' | head -10 || echo "  (none)"
echo "-- keylogging / clipboard / wallet targeting --"
g "${SRC_INC[@]}" -E 'GetAsyncKeyState|pynput|keylog|pyperclip|clipboard.*(get|paste)|wallet\.dat|metamask|electrum' | head -10 || echo "  (none)"
echo "-- destructive wipes --"
g "${SRC_INC[@]}" -E 'rm\s+-rf\s+/(\s|$|\*)|shred\s+-|cipher\s+/w|mkfs\.|dd\s+if=/dev/(zero|urandom)\s+of=/dev/' | head -8 || echo "  (none)"

hr "SUMMARY"
echo "Triage complete. This scan flags candidates only. Now do the manual adversarial"
echo "read (SKILL.md steps 3-5): open every executable entrypoint, every SKILL.md/agent"
echo "doc, every CI workflow, and every network call, and reason about intent. A clean"
echo "triage does not clear the repo."
