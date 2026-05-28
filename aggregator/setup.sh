#!/usr/bin/env bash
# =============================================================
# Subscription Aggregator Setup
# Run on the server where aggregator will live (can be any VPS)
# Usage: sudo bash setup.sh
# =============================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo bash setup.sh"

INSTALL_DIR="/opt/sub-aggregator"
SERVICE_USER="subaggregate"
AGG_PORT=8080

log "Installing Python and dependencies..."
apt-get update -qq
apt-get install -y -qq python3 python3-pip python3-venv

log "Creating service user..."
id "$SERVICE_USER" &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"

log "Copying aggregator files..."
mkdir -p "$INSTALL_DIR"
cp app.py config.yaml requirements.txt "$INSTALL_DIR/"
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

log "Creating Python virtual environment..."
python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install -q --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install -q -r "$INSTALL_DIR/requirements.txt"

log "Setting up log directory..."
mkdir -p /var/log/sub-aggregator
chown "$SERVICE_USER:$SERVICE_USER" /var/log/sub-aggregator

log "Installing systemd service..."
cp sub-aggregator.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable sub-aggregator

# Open firewall port
if command -v ufw &>/dev/null; then
    ufw allow "${AGG_PORT}/tcp" comment "Sub aggregator"
fi

# Check if config has been edited
if grep -q "CHANGE_ME" "$INSTALL_DIR/config.yaml"; then
    warn ""
    warn "IMPORTANT: Edit $INSTALL_DIR/config.yaml before starting!"
    warn "  1. Set a strong token (openssl rand -hex 32)"
    warn "  2. Add your 3x-ui server subscription URLs"
    warn ""
    warn "Then run: systemctl start sub-aggregator"
else
    systemctl start sub-aggregator
    sleep 2
    systemctl is-active sub-aggregator \
        && log "Aggregator is running on port $AGG_PORT" \
        || warn "Service may have failed — check: journalctl -u sub-aggregator -n 50"
fi

log ""
log "Your aggregator subscription URL will be:"
PUBLIC_IP=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null || echo "YOUR_IP")
TOKEN=$(grep "^token:" "$INSTALL_DIR/config.yaml" | awk '{print $2}' | tr -d '"')
log "  http://$PUBLIC_IP:$AGG_PORT/sub/$TOKEN"
