"""Inert fixture for uncommon exploit-prone bug classes.

This file is never executed by the benchmark. It intentionally contains static
patterns that a reviewer should inspect: archive traversal, user-controlled
regex/SSRF, disabled TLS verification, weak randomness, and raw SQL formatting.
"""

import random
import re
import sqlite3
import tarfile
from pathlib import Path

import requests


def unpack_upload(archive_path, destination):
    # Vulnerable shape: archive entries could contain ../ traversal paths.
    with tarfile.open(archive_path) as archive:
        archive.extractall(destination)


def fetch_callback(request):
    # Vulnerable shape: user-controlled URL plus disabled TLS verification.
    url = request.args["url"]
    return requests.get(url, verify=False, timeout=3).text


def search(request):
    # Vulnerable shape: attacker-controlled regular expression can cause ReDoS.
    pattern = re.compile(request.args["pattern"])
    return bool(pattern.match("a" * 1000))


def reset_token():
    # Vulnerable shape: non-crypto randomness for a security token.
    return str(random.random()).replace(".", "")


def lookup_user(request, db: sqlite3.Connection):
    # Vulnerable shape: string formatting into SQL.
    user_id = request.args["id"]
    return db.execute("SELECT * FROM users WHERE id = %s" % user_id).fetchone()


def write_tmp(name, body):
    # Vulnerable shape: predictable shared temp path.
    Path("/tmp/" + name).write_text(body)
