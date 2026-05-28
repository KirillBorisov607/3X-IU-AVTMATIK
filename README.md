# 3x-ui Automated Setup

Unified setup script for [3x-ui](https://github.com/mhsanaei/3x-ui) panel and subscription aggregator.

One script handles everything: language selection, mode selection, server hardening, panel installation hidden behind nginx, and subscription management.

## Requirements

- Ubuntu 20.04 / 22.04 / 24.04 or Debian 11 / 12
- Root access

## Usage

Run on any server:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/KirillBorisov607/3X-IU-AVTMATIK/master/install.sh)
```

The script will ask:

1. **Language** — Russian or English
2. **Mode** — Panel or Aggregator
3. If Aggregator — Install fresh or Add subscription to existing

## Panel mode

Installs 3x-ui with full server hardening. The panel is hidden behind nginx and accessible only via a secret random path over HTTPS.

What the script configures:

| Component | Description |
|-----------|-------------|
| sysctl | SYN cookies, anti-spoofing, martian logging, performance tuning |
| SSH | Custom port, key-only auth, MaxAuthTries 3 |
| UFW | Default deny, whitelist only required ports, rate limit on SSH |
| iptables | Drop NULL/XMAS/FIN scans, SYN flood protection, invalid packets |
| Fail2ban | SSH (3 attempts, 24h ban), panel login (5 attempts) |
| nginx | HTTPS reverse proxy on custom port, returns 444 for all paths except the secret one |
| 3x-ui | Official installer, bound to localhost only, secret base path |
| Auto-updates | Unattended security upgrades |

Panel access after install:

```
https://SERVER_IP:NGINX_PORT/SECRET_PATH/
```

The secret path is randomly generated during installation. Direct access to the internal panel port is blocked — only nginx can reach it.

After installation:
1. Test SSH on the new port before closing the current session
2. Remove old SSH port: `ufw delete allow 22/tcp`
3. Delete credentials file: `rm /root/3xui-credentials.log`
4. Add clients in the panel, copy their Subscription URLs
5. Add Subscription URLs to the aggregator

## Aggregator mode

### Option 1 — Install aggregator

Deploys the subscription aggregator service. It fetches subscriptions from all configured 3x-ui servers and merges them into a single URL.

After install, use `Add subscription` to add servers one by one.

### Option 2 — Add subscription

Adds a new 3x-ui server subscription to an existing aggregator installation. Prompts for server name, subscription URL, and proxy prefix. Restarts the service automatically.

The combined subscription URL:

```
http://AGG_SERVER_IP:AGG_PORT/sub/TOKEN
```

Add this URL to any proxy client (v2rayN, Hiddify, Sing-box, etc.) — it returns proxies from all servers.

## How to get a subscription URL from 3x-ui

1. Open the panel
2. Go to client settings
3. Copy the Subscription link from the Subscription tab

It looks like: `https://IP:PORT/PATH/sub/CLIENT-UUID`

## File structure

```
.
├── install.sh                     # Unified setup script
└── aggregator/
    ├── app.py                     # Flask aggregator application
    ├── config.yaml                # Server list and token config
    ├── requirements.txt           # Python dependencies
    ├── setup.sh                   # Redirects to install.sh
    └── sub-aggregator.service     # systemd unit file
```

## Security notes

- The panel port is bound to localhost — not reachable from outside
- nginx sits in front and only forwards the secret path
- All other paths return 444 (TCP close, no response)
- Fail2ban watches nginx logs for login failures
- Aggregator token uses constant-time comparison to prevent timing attacks
- Aggregator returns 404 for invalid tokens (does not reveal endpoint existence)
- Generate token: `openssl rand -hex 32`
