# Security Policy

Trust Issues is a tool for *reviewing* untrusted code. If you find a security issue in
**this repository itself** (not in code it reviews), please report it privately rather
than opening a public issue:

- Preferred: open a private **GitHub Security Advisory** (Security tab → "Report a
  vulnerability"). Enable "Private vulnerability reporting" in repo settings to allow this.

Please include where the issue lives (file/line), how to reproduce it, and the impact you
believe it has. Expect an acknowledgement within a few days.

## Note on the benchmark fixtures
`benchmark/fixtures/malicious/` contains **inert** samples used to test the scanner. They
are pattern-only, never executed, and their exfil targets are non-resolving
`*.example.com` placeholders. They contain no working exploit and no real secrets. Your
antivirus may still flag the directory on clone — that is expected for a security tool's
test corpus.
