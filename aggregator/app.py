#!/usr/bin/env python3
"""
3x-ui Subscription Aggregator
Combines subscription URLs from multiple 3x-ui servers into one.
"""
import base64
import hashlib
import logging
import os
import secrets
import time
from functools import wraps
from pathlib import Path
from threading import Lock
from typing import Optional

import requests
import yaml
from flask import Flask, Response, abort, request

# ── Logging ──────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

# ── App ───────────────────────────────────────────────────────
app = Flask(__name__)

CONFIG_PATH = Path(__file__).parent / "config.yaml"

# ── Cache ─────────────────────────────────────────────────────
_cache: dict[str, tuple[str, float]] = {}  # key → (data, timestamp)
_cache_lock = Lock()


def load_config() -> dict:
    with open(CONFIG_PATH) as f:
        return yaml.safe_load(f)


# ── Cache helpers ────────────────────────────────────────────

def _cache_get(key: str, ttl: int) -> Optional[str]:
    with _cache_lock:
        if key in _cache:
            data, ts = _cache[key]
            if time.time() - ts < ttl:
                return data
    return None


def _cache_set(key: str, data: str) -> None:
    with _cache_lock:
        _cache[key] = (data, time.time())


# ── Subscription fetching ─────────────────────────────────────

def fetch_sub(server: dict) -> list[str]:
    """Fetch and decode a single subscription URL, return proxy lines."""
    url = server.get("sub_url", "").strip()
    if not url:
        log.warning("Server '%s' has no sub_url", server.get("name", "?"))
        return []

    verify_ssl = server.get("verify_ssl", True)
    timeout = server.get("timeout", 10)
    prefix = server.get("prefix", "")

    try:
        resp = requests.get(url, timeout=timeout, verify=verify_ssl)
        resp.raise_for_status()

        # Decode base64 (add padding just in case)
        raw = resp.content
        padded = raw + b"=" * (-len(raw) % 4)
        decoded = base64.b64decode(padded).decode("utf-8", errors="ignore")

        lines = [line.strip() for line in decoded.splitlines() if line.strip()]

        # Optionally inject prefix into remark (the part after #)
        if prefix:
            result = []
            for line in lines:
                if "#" in line:
                    uri, remark = line.rsplit("#", 1)
                    result.append(f"{uri}#{prefix}-{remark}")
                else:
                    result.append(line)
            return result

        return lines

    except requests.exceptions.SSLError:
        log.error("SSL error for '%s' — set verify_ssl: false in config", server.get("name"))
        return []
    except requests.exceptions.Timeout:
        log.error("Timeout fetching '%s'", server.get("name"))
        return []
    except Exception as e:  # noqa: BLE001
        log.error("Failed to fetch '%s': %s", server.get("name"), e)
        return []


def aggregate(servers: list[dict]) -> str:
    """Fetch all servers and combine into one base64 subscription."""
    all_lines: list[str] = []
    for server in servers:
        name = server.get("name", server.get("sub_url", "?"))
        lines = fetch_sub(server)
        log.info("Server '%s': %d proxies", name, len(lines))
        all_lines.extend(lines)

    combined = "\n".join(all_lines)
    return base64.b64encode(combined.encode()).decode()


# ── Rate limiting ─────────────────────────────────────────────

_rate: dict[str, list[float]] = {}
_rate_lock = Lock()

def rate_limit(max_req: int = 10, window: int = 60):
    """Simple in-memory rate limiter."""
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            ip = request.remote_addr or "unknown"
            now = time.time()
            with _rate_lock:
                hits = _rate.get(ip, [])
                hits = [t for t in hits if now - t < window]
                if len(hits) >= max_req:
                    log.warning("Rate limit hit: %s", ip)
                    abort(429)
                hits.append(now)
                _rate[ip] = hits
            return f(*args, **kwargs)
        return wrapper
    return decorator


# ── Routes ────────────────────────────────────────────────────

@app.route("/sub/<token>")
@rate_limit(max_req=20, window=60)
def subscription(token: str):
    config = load_config()

    expected_token = config.get("token", "")
    if not expected_token:
        log.error("No token set in config.yaml!")
        abort(500)

    # Constant-time comparison to prevent timing attacks
    if not secrets.compare_digest(token, expected_token):
        log.warning("Invalid token from %s", request.remote_addr)
        abort(404)  # 404 instead of 403 to not reveal endpoint existence

    ttl = config.get("cache_ttl", 300)
    cache_key = hashlib.md5(token.encode()).hexdigest()

    cached = _cache_get(cache_key, ttl)
    if cached:
        log.info("Serving cached subscription to %s", request.remote_addr)
        result = cached
    else:
        servers = config.get("servers", [])
        if not servers:
            log.error("No servers configured")
            abort(500)
        result = aggregate(servers)
        _cache_set(cache_key, result)
        log.info("Refreshed subscription (%d bytes)", len(result))

    return Response(
        result,
        content_type="text/plain; charset=utf-8",
        headers={
            # Tells clients total traffic quota (fake large number for unlimited feel)
            "Subscription-Userinfo": "upload=0; download=0; total=107374182400; expire=253388144000",
            "Profile-Update-Interval": str(ttl // 60),
        },
    )


@app.route("/health")
def health():
    return {"status": "ok", "time": int(time.time())}


# ── Entry point ───────────────────────────────────────────────

if __name__ == "__main__":
    config = load_config()
    host = config.get("host", "0.0.0.0")
    port = config.get("port", 8080)
    log.info("Starting aggregator on %s:%s", host, port)
    app.run(host=host, port=port, debug=False)
