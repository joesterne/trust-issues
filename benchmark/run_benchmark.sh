#!/usr/bin/env bash
# run_benchmark.sh — measure what the triage scanner actually catches.
#
# Honest by design. The headline number is RECALL on known-malicious samples:
# of the malicious techniques in fixtures/, how many does the grep-based triage
# flag? We also report how many BENIGN samples surface a flag (the manual-review
# workload — high recall means some benign code gets surfaced, and that's the
# point of a triage layer, not a bug), and we spotlight any malicious sample that
# slips through, because "the scanner said nothing" is never proof of safety.
#
# Nothing here executes a fixture. Each sample is copied into a temp dir and
# scanned read-only.
#
# Usage:  bash benchmark/run_benchmark.sh

set -uo pipefail
CHECK=0
[[ "${1:-}" == "--check" ]] && CHECK=1   # CI mode: exit 1 if a NON-evasive malicious sample is missed
HERE="$(cd "$(dirname "$0")" && pwd)"
SCAN="$HERE/../scripts/triage_scan.sh"
MAL="$HERE/fixtures/malicious"
BEN="$HERE/fixtures/benign"

flagged() {  # returns 0 (flagged) if the scan surfaces any signal for this sample
  local sample="$1" tmp out sig
  tmp="$(mktemp -d)"
  cp -R "$sample" "$tmp/"
  out="$(bash "$SCAN" "$tmp" 2>/dev/null)"
  # look only at the signal sections (3..13), never the inventory/summary
  sig="$(printf '%s\n' "$out" | sed -n '/== 3\./,/== SUMMARY/p')"
  rm -rf "$tmp"
  # a "hit" is any line that references the scanned temp path (path-printing
  # sections) — inventory is excluded by the slice above
  printf '%s\n' "$sig" | grep -q "$tmp"
}

echo "############################################"
echo "#         Trust Issues — benchmark         #"
echo "############################################"
echo

printf "MALICIOUS FIXTURES (want: FLAGGED)\n"
printf "  %-28s %s\n" "sample" "result"
mal_total=0 mal_hit=0 missed=""
for s in "$MAL"/*; do
  mal_total=$((mal_total+1))
  name="$(basename "$s")"
  if flagged "$s"; then
    printf "  %-28s \033[32mFLAGGED\033[0m\n" "$name"; mal_hit=$((mal_hit+1))
  else
    printf "  %-28s \033[31mMISSED\033[0m\n" "$name"; missed="$missed $name"
  fi
done

echo
printf "BENIGN FIXTURES (flag = surfaced for manual review)\n"
printf "  %-28s %s\n" "sample" "result"
ben_total=0 ben_flag=0 noisy=""
for s in "$BEN"/*; do
  ben_total=$((ben_total+1))
  name="$(basename "$s")"
  if flagged "$s"; then
    printf "  %-28s \033[33mSURFACED\033[0m\n" "$name"; ben_flag=$((ben_flag+1)); noisy="$noisy $name"
  else
    printf "  %-28s quiet\n" "$name"
  fi
done

recall=$(( mal_total ? 100*mal_hit/mal_total : 0 ))
echo
echo "--------------------------------------------"
echo "RESULTS"
echo "  Malicious recall:      $mal_hit / $mal_total  (${recall}%)"
echo "  Missed (evasion):     ${missed:- none}"
echo "  Benign surfaced:       $ben_flag / $ben_total for manual review:${noisy:- none}"
echo "--------------------------------------------"
cat <<'NOTE'
How to read these numbers:
- Recall below 100% is expected. The evasive fixture is built to defeat pattern
  matching, the same way real scanner-evasion works, so missing it is a designed
  outcome that argues for the manual five-persona read and for sandboxing.
- "Benign surfaced" is the manual-review workload rather than a failure. The scanner
  is tuned for recall, and the reasoning pass clears the legitimate cases such as a
  scheduler using spawnSync, a regex calling .exec(), or a config reading one env var.
- A clean scan on its own does not clear the code.
NOTE

# CI gate: fail only if a malicious sample that is NOT meant to be evasive was missed.
if [[ "$CHECK" == "1" ]]; then
  unexpected=""
  for m in $missed; do
    case "$m" in *evasive*) : ;; *) unexpected="$unexpected $m" ;; esac
  done
  if [[ -n "$unexpected" ]]; then
    echo; echo "CI FAIL: unexpected miss(es):$unexpected" >&2
    exit 1
  fi
  echo; echo "CI OK: no unexpected misses."
fi
