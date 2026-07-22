#!/usr/bin/env bash
# triage_scan.sh — READ-ONLY static triage for an untrusted repo or skill.
#
# This script NEVER executes code from the target. It only reads files with
# grep / find / file / wc. It does not follow symlinks (grep -r, find -P), skips
# common vendor and generated directories, and skips very large files in the
# binary pass. It is a fast first pass whose job is to surface things a human (or
# the reviewing agent) must then read manually. A clean run is NOT proof of
# safety — it is the floor, not the ceiling.
#
# It does NO online research. The "research current threats" step in SKILL.md is
# performed by the agent or human running the full workflow, not by this script.
#
# Optional resource limits (env vars, with sensible defaults):
#     TRUST_ISSUES_MAX_BYTES  per-file byte ceiling for the binary pass (default 5 MiB)
#     TRUST_ISSUES_MAX_FILES  file-count ceiling; over this the scan warns (default 50000)
#     TRUST_ISSUES_STRICT=1   abort (exit 3) instead of warning when the ceiling is hit
#
# Note on limits: a per-file size cap for the recursive content grep and an internal
# wall-clock deadline are NOT enforced here — neither is portable across GNU and BSD
# userlands in pure bash. For a hostile or very large target, run inside a sandbox and
# bound the wall-clock time yourself, e.g.:
#     timeout 120 bash triage_scan.sh <path>
#
# Usage:  bash triage_scan.sh [--json] [--output FILE] <path-to-repo>
# Exit:   0 = ran (triage is informational, not a gate); 2 = bad arguments; 3 = over limit in strict mode.
# --json  Output structured JSON instead of human-readable format (for CI/tool integration)
# --output FILE  Write output to FILE instead of stdout

set -uo pipefail

# Parse command-line options
JSON_MODE=0
OUTPUT_FILE=""
TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      echo "usage: bash triage_scan.sh [--json] [--output FILE] <path-to-repo>"
      echo "  --json              Output structured JSON instead of human-readable format"
      echo "  --output FILE       Write output to FILE instead of stdout"
      exit 0
      ;;
    --json)
      JSON_MODE=1
      shift
      ;;
    --output)
      shift
      if [[ -z "${1:-}" ]]; then
        echo "error: --output requires a filename" >&2; exit 2
      fi
      OUTPUT_FILE="$1"
      shift
      ;;
    -*)
      echo "error: unknown option: $1" >&2; exit 2
      ;;
    *)
      TARGET="$1"
      shift
      ;;
  esac
done

if [[ -z "${TARGET:-}" ]]; then
  echo "usage: bash triage_scan.sh [--json] [--output FILE] <path-to-repo>" >&2; exit 2
fi
if [[ ! -d "$TARGET" ]]; then
  echo "error: not a directory: $TARGET" >&2; exit 2
fi
# Canonicalize early: an absolute, symlink-resolved path can't be misread as an
# option (leading '-') or escape the tree via a symlinked target.
if ! TARGET="$(cd -- "$TARGET" 2>/dev/null && pwd -P)"; then
  echo "error: cannot access target" >&2; exit 2
fi

MAX_BYTES="${TRUST_ISSUES_MAX_BYTES:-$((5 * 1024 * 1024))}"   # per-file cap, binary pass
MAX_FILES="${TRUST_ISSUES_MAX_FILES:-50000}"                  # file-count ceiling
STRICT="${TRUST_ISSUES_STRICT:-0}"

validate_uint(){
  local name="$1" value="$2"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo "error: $name must be a non-negative integer" >&2
    exit 2
  fi
}

validate_bool(){
  local name="$1" value="$2"
  if [[ ! "$value" =~ ^[01]$ ]]; then
    echo "error: $name must be 0 or 1" >&2
    exit 2
  fi
}

validate_uint TRUST_ISSUES_MAX_BYTES "$MAX_BYTES"
validate_uint TRUST_ISSUES_MAX_FILES "$MAX_FILES"
validate_bool TRUST_ISSUES_STRICT "$STRICT"
PRUNE=( -path '*/.git/*' -o -path '*/node_modules/*' -o -path '*/vendor/*'
        -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/.venv/*'
        -o -path '*/venv/*' -o -path '*/.next/*' -o -path '*/target/*' )
EXCLUDES=( --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor
           --exclude-dir=dist --exclude-dir=build --exclude-dir=.venv
           --exclude-dir=venv --exclude-dir=.next --exclude-dir=target )

SRC_INC=( --include=*.py --include=*.js --include=*.mjs --include=*.cjs --include=*.ts
          --include=*.tsx --include=*.jsx --include=*.sh --include=*.bash --include=*.zsh
          --include=*.rb --include=*.go --include=*.rs --include=*.php --include=*.pl
          --include=*.ps1 --include=*.psm1 )
TXT_INC=( --include=*.md --include=*.mdx --include=*.markdown --include=*.txt
          --include=*.json --include=*.yml --include=*.yaml --include=*.toml --include=*.env* )

# JSON output accumulator. Findings are persisted to a temp file because many
# scan helpers run inside pipeline subshells; shell variables updated there would
# be lost before json_output runs.
declare -a JSON_CATEGORIES
JSON_TMP="$(mktemp "${TMPDIR:-/tmp}/trust-issues-json.XXXXXX")"
trap 'rm -f "$JSON_TMP"' EXIT
SCAN_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 'unknown')"
SCRIPT_VERSION="$(cat "$(dirname "$0")/../VERSION" 2>/dev/null || echo 'unknown')"

# Redirect output if --output FILE was specified. Refuse directories and missing
# parents so a typo cannot silently create output in an unexpected location.
if [[ -n "$OUTPUT_FILE" ]]; then
  OUTPUT_PARENT="$(dirname -- "$OUTPUT_FILE")"
  if [[ ! -d "$OUTPUT_PARENT" ]]; then
    echo "error: output directory does not exist: $OUTPUT_PARENT" >&2; exit 2
  fi
  if [[ -d "$OUTPUT_FILE" ]]; then
    echo "error: output path is a directory: $OUTPUT_FILE" >&2; exit 2
  fi
  if [[ -L "$OUTPUT_FILE" ]]; then
    echo "error: refusing to write output through a symlink: $OUTPUT_FILE" >&2; exit 2
  fi
  exec 1>"$OUTPUT_FILE" 2>&1
fi

# In JSON mode, save stdout to FD 3 for JSON output, then suppress all human output
if [[ $JSON_MODE -eq 1 ]]; then
  exec 3>&1      # save stdout to FD 3
  exec 1>/dev/null 2>&1   # suppress human output
fi

# Output functions
hr(){
  CURRENT_CATEGORY="$1"
  json_add_category "$CURRENT_CATEGORY"
  if [[ $JSON_MODE -eq 0 ]]; then
    printf '\n== %s ==\n' "$1"
  fi
}

json_add_category(){
  local category="$1"
  if [[ $JSON_MODE -eq 1 ]]; then
    JSON_CATEGORIES+=("$category")
  fi
}

json_sanitize_field(){
  # Keep the TSV accumulator line-oriented and printable. Tabs/newlines are
  # normalized by callers; any remaining C0 control bytes are represented with a
  # visible JSON-style escape before the finding is persisted for serialization.
  printf '%s' "$1" | LC_ALL=C perl -pe 's/([\x00-\x1F])/sprintf("\\u%04X", ord($1))/eg'
}

json_add_finding(){
  local category="$1"
  local finding="$2"
  if [[ $JSON_MODE -eq 1 ]]; then
    # Append to a temp file instead of shell variables so findings produced inside
    # pipeline subshells are not lost. Tabs/newlines are normalized for TSV safety.
    category="${category//$'\t'/ }"
    finding="${finding//$'\t'/ }"
    finding="${finding//$'\n'/ }"
    category="$(json_sanitize_field "$category")"
    finding="$(json_sanitize_field "$finding")"
    printf '%s\t%s\n' "$category" "$finding" >> "$JSON_TMP"
  fi
}

output_line(){
  local line="$*"
  if [[ $JSON_MODE -eq 0 ]]; then
    echo "$line"
  elif [[ -n "${CURRENT_CATEGORY:-}" ]]; then
    json_add_finding "$CURRENT_CATEGORY" "$line"
  fi
}

# g(): recursive content grep. -r (not -R) does not follow symlinks while
# recursing; -I skips binary files; vendor/generated dirs are excluded; the '--'
# guards a target whose name might begin with '-'.
g(){ grep -rInI "${EXCLUDES[@]}" "$@" -- "$TARGET" 2>/dev/null; }
# go(): value-only extraction (-o, no path prefix) for de-duplication by callers.
go(){ grep -rhoIE "${EXCLUDES[@]}" "$@" -- "$TARGET" 2>/dev/null; }

# cap N: stream stdin, print up to N matching lines, then report the true total.
# Implemented in awk so it counts without buffering the whole input in memory —
# important when scanning a purpose-built denial-of-service tree.
cap(){
  awk -v n="${1:-10}" '
    { c++; if (c <= n) print }
    END {
      if (c == 0)      { print "  (none)" }
      else if (c > n)  { printf "  … showing %d of %d matches\n", n, c }
    }' | while IFS= read -r line; do
      if [[ $JSON_MODE -eq 0 ]]; then
        printf '%s\n' "$line"
      elif [[ -n "${CURRENT_CATEGORY:-}" && "$line" != "  (none)" && "$line" != "  … showing "* ]]; then
        json_add_finding "$CURRENT_CATEGORY" "$line"
      fi
    done
}
# strip non-printable characters from a displayed path (report-integrity: an
# adversarial filename cannot smear the output). Does not affect what is scanned.
clean_paths(){ LC_ALL=C sed 's/[^[:print:]]/?/g'; }

# tfind: null-delimited find over the target, no symlink following, pruning the
# vendor/generated dirs. Extra predicates are passed as arguments.
tfind(){ find -P "$TARGET" '(' "${PRUNE[@]}" ')' -prune -o "$@" -print0 2>/dev/null; }

json_escape(){
  # Escape special characters for JSON string values
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g; s/\r/\\r/g'
}

json_output(){
  # Output findings as structured JSON for CI/tool integration
  # Use FD 3 when in JSON mode (to bypass stdout suppression)
  local out_fd=1
  [[ $JSON_MODE -eq 1 ]] && out_fd=3
  
  {
    printf '{\n'
    printf '  "version": 1,\n'
    printf '  "scanner": "trust-issues",\n'
    printf '  "scanner_version": "%s",\n' "$(json_escape "$SCRIPT_VERSION")"
    printf '  "target": "%s",\n' "$(json_escape "$TARGET")"
    printf '  "scan_timestamp": "%s",\n' "$SCAN_TIMESTAMP"
    printf '  "total_findings": %d,\n' "$(wc -l < "$JSON_TMP" | tr -d ' ')"
    printf '  "findings": {\n'
    
    local first=1
    for cat in "${JSON_CATEGORIES[@]}"; do
      if [[ $first -eq 0 ]]; then printf ',\n'; fi
      printf '    "%s": ' "$(json_escape "$cat")"
      printf '['
      local first_finding=1
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ $first_finding -eq 0 ]]; then printf ','; fi
        printf '"%s"' "$(json_escape "$line")"
        first_finding=0
      done < <(awk -F '\t' -v cat="$cat" '$1 == cat { print substr($0, length($1) + 2) }' "$JSON_TMP")
      printf ']'
      first=0
    done
    printf '\n'
    printf '  },\n'
    printf '  "notes": "read-only signature scan — manual review still required; this script does no online research"\n'
    printf '}\n'
  } >&"$out_fd"
}

HAVE_P=0; printf 'x\n' | grep -qP 'x' 2>/dev/null && HAVE_P=1

output_line "######## TRIAGE: $TARGET ########"
output_line "(read-only signature scan — manual review still required; this script does no online research)"

hr "1. INVENTORY"
echo "File types present:"
tfind -type f | tr '\0' '\n' | sed 's/.*\.//; s#.*/##' | sort | uniq -c | sort -rn | head -30
echo; echo "Largest files (watch for vendored blobs / minified bundles):"
find -P "$TARGET" '(' "${PRUNE[@]}" ')' -prune -o -type f -exec wc -c {} + 2>/dev/null \
  | grep -vE '[[:space:]]total$' | sort -rn | head -10 \
  | awk '{n=$1; $1=""; sub(/^[[:space:]]+/,""); printf "  %12d  %s\n", n, $0}'
NFILES="$(tfind -type f | tr -cd '\0' | wc -c | tr -d ' ')"
echo; echo "Files in scope: $NFILES  (ceiling TRUST_ISSUES_MAX_FILES=$MAX_FILES)"
if (( 10#$NFILES > 10#$MAX_FILES )); then
  echo "  ⚠ over the file-count ceiling — content scans may be slow; run in a sandbox under 'timeout'."
  if [[ "$STRICT" == 1 ]]; then echo "  strict mode: aborting."; exit 3; fi
fi

hr "2. NON-TEXT / BINARY / HIGH-ENTROPY BLOBS (unexplained binaries are a red flag)"
tfind -type f | while IFS= read -r -d '' f; do
  case "$f" in *.png|*.jpg|*.jpeg|*.gif|*.svg|*.ico|*.webp|*.woff*|*.ttf|*.otf|*.pdf) continue;; esac
  sz="$(wc -c < "$f" 2>/dev/null || echo 0)"
  if (( 10#$sz > 10#$MAX_BYTES )); then continue; fi
  kind="$(file -b "$f" 2>/dev/null || true)"
  if printf '%s\n' "$kind" | grep -qiE 'executable|ELF|Mach-O|PE32|shared object|archive data|compiled'; then
    printf '  BINARY: %s -> %s\n' "$f" "$kind"
  fi
done | clean_paths | cap 20
echo "  minified / bundled JS (can hide payloads):"
tfind -type f '(' -name '*.min.js' -o -name '*bundle*.js' ')' | tr '\0' '\n' | clean_paths | sed 's/^/    /' | cap 10

hr "3. NPM INSTALL HOOKS (the #1 npm supply-chain vector — runs on 'npm install')"
g --include=package.json -E '"(pre|post)?install"|"prepare"|"preprepare"|"postprepare"' | cap 15

hr "4. REMOTE-CODE-INTO-SHELL (curl|wget|iwr piped to an interpreter)"
g -E '(curl|wget|fetch|iwr|Invoke-WebRequest)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|d)?sh|python[0-9]?|node|perl|ruby' | cap 15

hr "5. DYNAMIC CODE EXECUTION / DESERIALIZATION"
echo "-- Python --"
g "${SRC_INC[@]}" -E '\b(eval|exec|compile)\s*\(|__import__\s*\(|os\.system\s*\(|subprocess\.[A-Za-z]+\([^)]*shell\s*=\s*True|pickle\.loads|yaml\.load\s*\(|marshal\.loads|ctypes|getattr\([^,]+,\s*[^)]*\)\s*\(' | cap 25
echo "-- JS/TS --"
g "${SRC_INC[@]}" -E '\beval\s*\(|new\s+Function\s*\(|child_process|execSync|spawnSync|vm\.runIn|require\(\s*[`"'"'"']child_process|process\.binding' | cap 25

hr "6. BASE64 / HEX / OBFUSCATED BLOBS DECODED THEN RUN"
g "${SRC_INC[@]}" -E '(base64|b64decode|atob|fromCharCode|unhexlify|bytes\.fromhex|Buffer\.from\([^)]*base64)' | cap 20
echo "  long inline base64-looking strings (>120 chars):"
go "${SRC_INC[@]}" -E '[A-Za-z0-9+/]{120,}={0,2}' | sort -u | cap 10

hr "7. CREDENTIAL / SECRET HARVESTING (reads of local secret stores)"
g -E '\.ssh|id_rsa|id_ed25519|\.aws/credentials|\.aws/config|\.npmrc|\.netrc|\.docker/config|keychain|security[[:space:]]+find-generic|/etc/passwd|/etc/shadow|LocalStorage|Cookies?/|login\.keychain|gnome-keyring|libsecret|browser.*[Pp]assword' | cap 20
echo "  dumps / exfil of environment variables (bulk access or env shipped to a call):"
g "${SRC_INC[@]}" -E 'dict\(os\.environ|os\.environ\.(copy|items|keys)\(|os\.environ\)|(json|data|params|body)\s*=\s*[^\n]*os\.environ|requests\.(post|get|put|patch)\([^\n]*environ|process\.env\b[^.]*(JSON|Object\.(keys|entries|values)|for\b|\.\.\.)|Object\.(keys|entries)\(process\.env|printenv|env\s*\|' | cap 12

hr "8. NETWORK EGRESS — every endpoint (compare against the repo's STATED purpose)"
echo "-- URLs in source --"
go "${SRC_INC[@]}" -E 'https?://[a-zA-Z0-9._~:/?#@!$&*+,;=%-]+' | sort -u | cap 40
echo "-- raw IP addresses (hardcoded IPs / possible C2) --"
go "${SRC_INC[@]}" -E '([0-9]{1,3}\.){3}[0-9]{1,3}(:[0-9]+)?' | sort -u | grep -vE '127\.0\.0\.1|0\.0\.0\.0' | cap 20
echo "-- inbound listeners / reverse-shell shapes --"
g "${SRC_INC[@]}" -E '\.listen\(|createServer|bind\(\(|socket\.(bind|listen)|/dev/tcp/|nc\s+-e|ncat|bash\s+-i' | cap 12

hr "9. SECRETS LEAKED INSIDE THE REPO (someone committed a live key)"
g -E '(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9]{20,}|sk_live_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----|AIza[0-9A-Za-z_-]{35})' | cap 15

hr "10. CI/CD WORKFLOW RISK (.github/workflows, etc.)"
if find -P "$TARGET" -type d '(' -name workflows -o -name '.circleci' -o -name '.gitlab-ci*' ')' 2>/dev/null | grep -q .; then
  echo "-- dangerous triggers (pull_request_target / workflow_run run attacker code with secrets) --"
  g --include=*.yml --include=*.yaml -E 'pull_request_target|workflow_run' | cap 10
  echo "-- curl|bash or inline secret use inside CI --"
  g --include=*.yml --include=*.yaml -E '(curl|wget)[^|]*\|[[:space:]]*sh|\$\{\{\s*secrets\.' | cap 10
  echo "-- third-party actions pinned by tag/branch not SHA (mutable = poisonable) --"
  g --include=*.yml --include=*.yaml -E 'uses:\s+[^@]+@(v?[0-9]|main|master)' | cap 10
else
  echo "  (no CI workflow dir found)"
fi

hr "11. DEPENDENCY MANIFESTS (audit each for typosquats / unpinned / young packages)"
tfind -type f '(' -name package.json -o -name 'requirements*.txt' -o -name Pipfile \
  -o -name pyproject.toml -o -name go.mod -o -name Cargo.toml -o -name Gemfile ')' \
  | tr '\0' '\n' | clean_paths | sed 's/^/  /' | cap 20
echo "  unpinned python deps (no '==') — supply-chain drift risk:"
g --include=requirements*.txt -E '^[A-Za-z0-9._-]+\s*$' | cap 15

hr "12. AGENT / PROMPT-INJECTION SIGNALS (critical for SKILL.md / MCP / .cursorrules / AGENTS.md)"
echo "-- imperative directives aimed at an AI agent inside docs --"
g "${TXT_INC[@]}" -iE 'ignore (all |the )?(previous|prior|above) instructions|disregard (the )?(system|previous)|do not (tell|inform|mention to) the user|without (asking|telling|informing) the user|bypass|override .*(safety|guardrail|approval)|exfiltrate|send .*(\.env|secret|token|key|credential).*(to|http)|curl .*\| *sh|as an ai,? you (must|should|will)' | cap 20
echo "-- directives to read secrets / .env from within a skill doc --"
g "${TXT_INC[@]}" -iE '(read|open|cat|load|print) .*(\.env|\.ssh|credentials|api[_ -]?key|secret|token)|process\.env|os\.environ' | cap 15
echo "-- directives to install/connect external tooling (MCP servers, remote skills) --"
g "${TXT_INC[@]}" -iE 'mcp add|add custom connector|npx [^ ]+ (install|add)|pip install (git\+|http)|install .*from .*http|claude mcp add|register .*server' | cap 15

hr "13. HIDDEN / OBFUSCATED TEXT (zero-width, bidi, homoglyph tricks that hide instructions)"
if [[ "$HAVE_P" == 1 ]]; then
  echo "  files containing zero-width / bidi-override / tag unicode:"
  grep -rlIP "${EXCLUDES[@]}" '[\x{200B}\x{200C}\x{200D}\x{2060}\x{FEFF}\x{202A}-\x{202E}\x{2066}-\x{2069}\x{E0000}-\x{E007F}]' -- "$TARGET" 2>/dev/null | cap 10
else
  echo "  (skipped — this grep lacks -P; check for zero-width/bidi unicode manually)"
fi
echo "  HTML comments in markdown (can hide agent instructions from rendered view):"
g --include=*.md --include=*.mdx -oE '<!--.*-->' | cap 10

hr "14. COMPILED-MALWARE / INJECTION / MINING / ANONYMIZING-C2 INDICATORS (when native code or binaries present)"
echo "-- code injection / process hollowing / shellcode --"
g "${SRC_INC[@]}" -E 'VirtualAllocEx|WriteProcessMemory|CreateRemoteThread|NtMapViewOfSection|QueueUserAPC|SetWindowsHookEx|ptrace\(|LD_PRELOAD|mprotect\([^)]*PROT_EXEC|reflectiveloader|process[_ ]?hollow' | cap 12
echo "-- anti-analysis (anti-debug / anti-VM / anti-sandbox) --"
g "${SRC_INC[@]}" -E 'IsDebuggerPresent|CheckRemoteDebugger|anti[_-]?(vm|debug|sandbox)|vmware|virtualbox|qemu|sbiedll|sandboxie' | cap 10
echo "-- anonymizing / covert C2 / mining --"
g "${SRC_INC[@]}" -E '\.onion\b|stratum\+tcp|xmrig|minerd|coinhive|i2p\b|torify|dga_|domain_?generation' | cap 10
echo "-- keylogging / clipboard / wallet targeting --"
g "${SRC_INC[@]}" -E 'GetAsyncKeyState|pynput|keylog|pyperclip|clipboard.*(get|paste)|wallet\.dat|metamask|electrum' | cap 10
echo "-- destructive wipes --"
g "${SRC_INC[@]}" -E 'rm\s+-rf\s+/(\s|$|\*)|shred\s+-|cipher\s+/w|mkfs\.|dd\s+if=/dev/(zero|urandom)\s+of=/dev/' | cap 8

hr "15. UNCOMMON BUG CLASSES / EXPLOIT-PRONE FOOTGUNS"
echo "-- archive extraction / path traversal / unsafe filesystem joins --"
g "${SRC_INC[@]}" -E 'extractall\s*\(|ZipFile|TarFile|tarfile\.open|archive\.extract|adm-zip|unzipper|\.pipe\(.*createWriteStream|path\.join\([^)]*(req\.|request\.|params|query|body)|\.\./|\.\.\\|send_file\s*\(|send_from_directory\s*\(' | cap 20
echo "-- unsafe temp files / TOCTOU-prone permission changes --"
g "${SRC_INC[@]}" -E 'mktemp\s+-u|tempnam\s*\(|tmpnam\s*\(|NamedTemporaryFile\([^)]*delete\s*=\s*False|/tmp/[A-Za-z0-9_.-]+|chmod\s+777|chown\s+.*(/tmp|/var/tmp)|access\([^)]*\).*open\(' | cap 15
echo "-- ReDoS / regex supplied by users or suspicious nested quantifiers --"
g "${SRC_INC[@]}" -E 'RegExp\([^)]*(req\.|request\.|params|query|body)|re\.compile\([^)]*(request|params|query|input)|\([^)]*[+*][^)]*\)[+*]|\[[^]]+\][+*][+*]' | cap 15
echo "-- XXE / unsafe XML parsers / entity expansion --"
g "${SRC_INC[@]}" -E 'xml\.etree|lxml\.etree|BeautifulSoup\([^)]*xml|DocumentBuilderFactory|SAXParserFactory|XmlReader|DOCTYPE|ENTITY|resolve_entities\s*=\s*True|no_network\s*=\s*False' | cap 15
echo "-- SSRF metadata endpoints / user-controlled outbound requests --"
g "${SRC_INC[@]}" -E '169\.254\.169\.254|metadata\.google\.internal|100\.100\.100\.200|requests\.(get|post|put|patch|delete)\([^)]*(request|params|query|input)|fetch\([^)]*(req\.|request\.|params|query|body)|axios\.[a-z]+\([^)]*(req\.|request\.|params|query|body)' | cap 20
echo "-- disabled TLS verification / weak randomness / hardcoded crypto footguns --"
g "${SRC_INC[@]}" -E 'verify\s*=\s*False|rejectUnauthorized\s*:\s*false|NODE_TLS_REJECT_UNAUTHORIZED|InsecureSkipVerify|check_hostname\s*=\s*False|ssl\._create_unverified_context|Math\.random\(|random\.random\(|md5\s*\(|sha1\s*\(|AES.MODE_ECB|createCipher\s*\(' | cap 20
echo "-- SQL/template/prototype pollution sinks --"
g "${SRC_INC[@]}" -E 'SELECT .*\+|INSERT .*\+|UPDATE .*\+|DELETE .*\+|execute\([^)]*%|cursor\.execute\([^)]*\+|render_template_string|Template\([^)]*(request|params|query|input)|innerHTML\s*=|Object\.assign\([^)]*(req\.body|request\.body)|__proto__|constructor\.prototype' | cap 20

if [[ $JSON_MODE -eq 0 ]]; then
  hr "SUMMARY"
  output_line "Triage complete across 15 categories. This scan flags candidates only. Now do the"
  output_line "manual adversarial read (SKILL.md steps 3-5): open every executable entrypoint, every"
  output_line "SKILL.md / agent doc, every CI workflow, and every network call, and reason about"
  output_line "intent. A clean triage does not clear the repo."
else
  echo ""
  json_output
fi
