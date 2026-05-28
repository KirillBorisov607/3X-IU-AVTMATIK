# 3x-ui Automated Setup

Automated installation and hardening script for [3x-ui](https://github.com/mhsanaei/3x-ui) panel, plus a subscription aggregator that combines multiple servers into a single subscription URL.

## Requirements

- Ubuntu 20.04 / 22.04 / 24.04 or Debian 11 / 12
- Root access
- Python 3.10+ (for the aggregator)

## Quick Start

### 1. Install 3x-ui on each server

Upload the script and run it on each VPS:

```bash
scp install.sh root@YOUR_SERVER_IP:/root/
ssh root@YOUR_SERVER_IP
bash install.sh
```

The script will ask for:
- New SSH port (default: 2222)
- Panel port (default: 2053)
- Panel username and password

Everything else is configured automatically.

### 2. Deploy the subscription aggregator

The aggregator runs on one server and combines subscriptions from all your 3x-ui instances into a single URL.

**Edit the config first:**

```bash
nano aggregator/config.yaml
```

Set your token and add each server's subscription URL:

```yaml
token: "your-long-random-token-here"   # openssl rand -hex 32

servers:
  - name: "Server-1 (US)"
    sub_url: "http://1.2.3.4:2053/panelpath/sub/client-uuid"
    prefix: "US"
    verify_ssl: false

  - name: "Server-2 (DE)"
    sub_url: "http://5.6.7.8:2053/panelpath/sub/client-uuid"
    prefix: "DE"
    verify_ssl: false
```

**How to find your subscription URL in 3x-ui:**
1. Open the panel
2. Go to a client's settings
3. Copy the subscription link from the "Subscription" tab

**Deploy the aggregator:**

```bash
scp -r aggregator/ root@YOUR_AGG_SERVER:/root/aggregator/
ssh root@YOUR_AGG_SERVER
cd /root/aggregator
bash setup.sh
```

### 3. Add one URL to your clients

```
http://AGG_SERVER_IP:8080/sub/YOUR_TOKEN
```

Add this single URL to any proxy client (v2rayN, Hiddify, Sing-box, etc.). It will return proxies from all your servers combined.

## What install.sh does

| Step | Description |
|------|-------------|
| System update | apt upgrade, install essential tools |
| sysctl hardening | SYN cookies, anti-spoofing, disable ICMP redirects |
| SSH hardening | Custom port, key-only auth, MaxAuthTries 3 |
| UFW firewall | Default deny, whitelist only required ports, rate limit |
| iptables rules | Block NULL/XMAS/FIN scans, SYN flood protection |
| Fail2ban | SSH jail (ban 24h after 3 attempts), panel jail |
| 3x-ui install | Official installer + CLI configuration |
| Auto-updates | Unattended security upgrades |

After installation, credentials are saved to `/root/3xui-credentials.log`. Delete this file after copying credentials to a password manager.

## What the aggregator does

- Fetches subscription content from each configured 3x-ui server
- Decodes base64, merges proxy lists, re-encodes base64
- Caches results for 5 minutes (configurable) to avoid hammering servers
- Serves the combined result at `/sub/<token>`
- Rate limits requests per IP
- Returns 404 for invalid tokens (does not reveal endpoint existence)

## File structure

```
.
├── install.sh                     # Server setup script
└── aggregator/
    ├── app.py                     # Flask aggregator application
    ├── config.yaml                # Server list and token config
    ├── requirements.txt           # Python dependencies
    ├── setup.sh                   # Aggregator deployment script
    └── sub-aggregator.service     # systemd unit file
```

## Security notes

- Generate a strong token: `openssl rand -hex 32`
- The aggregator returns 404 (not 403) for invalid tokens
- The systemd service runs under a dedicated unprivileged user
- `verify_ssl: false` is needed if your panel uses a self-signed certificate

## After installation checklist

1. Test SSH on the new port before closing the current session
2. Remove the old SSH port from UFW: `ufw delete allow 22/tcp`
3. Delete the credentials log file: `rm /root/3xui-credentials.log`
4. Add clients in the 3x-ui panel and copy their subscription URLs
5. Add subscription URLs to `aggregator/config.yaml`
