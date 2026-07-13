# Legit: calls a documented, first-party API over HTTPS.
import requests
def get_posts(handle):
    return requests.post("https://api.example-product.com/v1/posts", json={"handle": handle}).json()
