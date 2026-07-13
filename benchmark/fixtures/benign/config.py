# Legit: reads a single config value from the environment with a default.
import os
TIMEOUT = int(os.environ.get("APP_TIMEOUT", "30"))
