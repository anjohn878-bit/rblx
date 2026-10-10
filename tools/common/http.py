"""Tiny stdlib HTTP helpers so the pipelines need no pip installs."""
import json
import os
import sys
import uuid
import urllib.error
import urllib.request


def require_env(*names):
    missing = [n for n in names if not os.environ.get(n)]
    if missing:
        sys.exit(
            "Missing environment variable(s): " + ", ".join(missing)
            + "\nSet them as secrets on your machine (see SETUP.md) - never paste keys into chat."
        )
    return [os.environ[n] for n in names]


def request(method, url, headers=None, body=None, timeout=120):
    req = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def json_request(method, url, payload=None, headers=None, timeout=120):
    h = {"Content-Type": "application/json", **(headers or {})}
    body = json.dumps(payload).encode() if payload is not None else None
    status, raw = request(method, url, h, body, timeout)
    try:
        data = json.loads(raw or b"{}")
    except json.JSONDecodeError:
        data = {"raw": raw.decode(errors="replace")}
    return status, data


def multipart(fields):
    """fields: list of (name, filename|None, content_type|None, bytes). Returns (body, content_type)."""
    boundary = uuid.uuid4().hex
    out = bytearray()
    for name, filename, ctype, data in fields:
        out += f"--{boundary}\r\n".encode()
        disp = f'form-data; name="{name}"'
        if filename:
            disp += f'; filename="{filename}"'
        out += f"Content-Disposition: {disp}\r\n".encode()
        if ctype:
            out += f"Content-Type: {ctype}\r\n".encode()
        out += b"\r\n" + data + b"\r\n"
    out += f"--{boundary}--\r\n".encode()
    return bytes(out), f"multipart/form-data; boundary={boundary}"
