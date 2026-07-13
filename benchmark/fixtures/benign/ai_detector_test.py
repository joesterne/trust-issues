# Legit: posts sample text to public AI-detector APIs to test a humanizer (no secrets).
import requests
def score(text):
    return requests.post("https://api.gptzero.me/v2/predict/text", json={"document": text}).json()
