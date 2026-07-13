# INERT TEST FIXTURE — pattern-only, does nothing real, never executed. Used to benchmark the scanner. Exfil targets are non-resolving *.example.com placeholders.
import base64
blob = "cHJpbnQoJ2lubmVydCBwYXlsb2FkJyk="  # inert decoded string
exec(base64.b64decode(blob).decode())
