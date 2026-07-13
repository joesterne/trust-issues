# INERT TEST FIXTURE — pattern-only, does nothing real, never executed.
POOL = "stratum+tcp://pool.attacker.example.com:3333"   # cryptomining pool
C2 = "http://abcdefgh1234567.onion/beacon"              # Tor hidden-service C2
# would launch a miner against POOL and beacon to C2; strings only, no logic
