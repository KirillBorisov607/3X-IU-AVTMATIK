#!/usr/bin/env bash
# =============================================================
# 3x-ui Complete Server Setup
# OS: Ubuntu 20.04/22.04/24.04 | Debian 11/12
# Run: sudo bash install.sh
# =============================================================
set -euo pipefail
IFS=$'\n\t'

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()   { echo -e "${GREEN}[+]${NC} $*"; }
info()  { echo -e "${BLUE}[i]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
die()   { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
sep()   { echo -e "${CYAN}──────────────────────────────────────────────${NC}"; }

# ── Defaults ──────────────────────────────────────────────────
PANEL_PORT=2053
PANEL_PATH=""
PANEL_USER="admin"
PANEL_PASS=""
NEW_SSH_PORT=2222
OLD_SSH_PORT=22
SERVER_LABEL=""
LOG_FILE="/root/3xui-credentials.log"
INBOUND_PORTS=()   # populated during prompt_config

# =============================================================
# 1. PREFLIGHT
# =============================================================

check_root() {
    [[ $EUID -eq 0 ]] || die "Run as root: sudo bash install.sh"
}

detect_os() {
    [[ -f /etc/os-release ]] || die "Cannot detect OS"
    # shellcheck source=/dev/null
    source /etc/os-release
    case "$ID" in
        ubuntu|debian) : ;;
        *) die "Unsupported OS: $ID. Use Ubuntu 20.04+ or Debian 11+." ;;
    esac
    log "OS: $PRETTY_NAME"
}

# =============================================================
# 2. INTERACTIVE CONFIG
# =============================================================

prompt_config() {
    sep
    echo -e "${BOLD}  3x-ui Server Setup & Hardening${NC}"
    sep

    read -rp "$(echo -e "  ${YELLOW}New SSH port${NC} [2222]: ")" _in
    NEW_SSH_PORT="${_in:-2222}"
    [[ "$NEW_SSH_PORT" =~ ^[0-9]+$ ]] || die "Invalid port"

    read -rp "$(echo -e "  ${YELLOW}Panel port${NC} [2053]: ")" _in
    PANEL_PORT="${_in:-2053}"

    read -rp "$(echo -e "  ${YELLOW}Panel username${NC} [admin]: ")" _in
    PANEL_USER="${_in:-admin}"

    read -rp "$(echo -e "  ${YELLOW}Panel password${NC} [auto-generate]: ")" -s _in; echo
    if [[ -z "$_in" ]]; then
        PANEL_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 20)
        info "  Generated password: ${BOLD}${PANEL_PASS}${NC}"
    else
        PANEL_PASS="$_in"
    fi

    PANEL_PATH="/$(openssl rand -hex 8)"

    read -rp "$(echo -e "  ${YELLOW}Server label${NC} [hostname]: ")" _in
    SERVER_LABEL="${_in:-$(hostname -s)}"

    echo ""
    info "  Inbound ports for proxy traffic (VLESS, VMess, Trojan, etc.)"
    info "  Format: PORT or PORT/tcp or PORT/udp  —  space-separated"
    info "  Example: 443 8443 2087/tcp 443/udp"
    read -rp "$(echo -e "  ${YELLOW}Inbound ports${NC} [skip]: ")" _in
    if [[ -n "$_in" ]]; then
        read -ra INBOUND_PORTS <<< "$_in"
    fi

    sep
    info "  SSH port:      $NEW_SSH_PORT"
    info "  Panel port:    $PANEL_PORT"
    info "  Panel user:    $PANEL_USER"
    info "  Label:         $SERVER_LABEL"
    if [[ ${#INBOUND_PORTS[@]} -gt 0 ]]; then
        info "  Inbound ports: ${INBOUND_PORTS[*]}"
    else
        info "  Inbound ports: (none — add manually with ufw allow)"
    fi
    sep
    read -rp "  Proceed? [y/N]: " _confirm
    [[ "${_confirm,,}" == "y" ]] || die "Aborted."
}

# =============================================================
# 3. SYSTEM UPDATE
# =============================================================

update_system() {
    log "Updating packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get upgrade -y -qq -o Dpkg::Options::="--force-confold"
    apt-get install -y -qq \
        curl wget git vim htop unzip \
        net-tools lsof jq ca-certificates \
        gnupg2 ufw fail2ban iptables-persistent \
        openssl unattended-upgrades
    log "Packages updated."
}

# =============================================================
# 4. KERNEL SECURITY (sysctl)
# =============================================================

harden_sysctl() {
    log "Applying kernel security parameters..."
    cat > /etc/sysctl.d/99-3xui.conf << 'EOF'
# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 8192

# IP spoofing / source routing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# ICMP protection
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Log martians (suspicious packets)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Filesystem hardening
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.suid_dumpable = 0

# Performance tuning for proxy workloads
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 250000
net.ipv4.tcp_max_tw_buckets = 1440000
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
EOF
    sysctl -p /etc/sysctl.d/99-3xui.conf > /dev/null
    log "Kernel parameters applied."
}

# =============================================================
# 5. SSH HARDENING
# =============================================================

harden_ssh() {
    log "Hardening SSH (port → $NEW_SSH_PORT)..."

    cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%s)"

    # Create drop-in config
    mkdir -p /etc/ssh/sshd_config.d
    cat > /etc/ssh/sshd_config.d/99-hardened.conf << EOF
Port $NEW_SSH_PORT
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 30
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitEmptyPasswords no
ClientAliveInterval 300
ClientAliveCountMax 2
IgnoreRhosts yes
HostbasedAuthentication no
PermitUserEnvironment no
Protocol 2
UsePAM yes
EOF

    # Ensure Include line exists in main config
    grep -q "^Include /etc/ssh/sshd_config.d" /etc/ssh/sshd_config \
        || echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config

    # Validate before applying
    sshd -t || die "SSH config test failed — check /etc/ssh/sshd_config.d/99-hardened.conf"

    log "SSH hardened. Will restart after firewall is configured."
    warn "Keep this session open until you confirm SSH works on port $NEW_SSH_PORT!"
}

# =============================================================
# 6. FIREWALL (UFW + iptables)
# =============================================================

setup_firewall() {
    log "Configuring firewall..."

    ufw --force reset

    ufw default deny incoming
    ufw default allow outgoing
    ufw default deny forward

    # Allow NEW SSH port (must be first!)
    ufw allow "${NEW_SSH_PORT}/tcp" comment "SSH"
    ufw limit "${NEW_SSH_PORT}/tcp" comment "SSH rate-limit"

    # Keep OLD port temporarily for safety
    ufw allow "${OLD_SSH_PORT}/tcp" comment "OLD SSH — remove after testing"

    # 3x-ui panel
    ufw allow "${PANEL_PORT}/tcp" comment "3x-ui panel"

    # Inbound ports for proxy traffic
    for entry in "${INBOUND_PORTS[@]}"; do
        # Normalize: if no slash, default to tcp
        if [[ "$entry" == */* ]]; then
            port="${entry%/*}"
            proto="${entry##*/}"
        else
            port="$entry"
            proto="tcp"
        fi

        if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
            warn "Skipping invalid port: $entry"
            continue
        fi
        if [[ "$proto" != "tcp" && "$proto" != "udp" ]]; then
            warn "Skipping invalid protocol: $entry (use tcp or udp)"
            continue
        fi

        ufw allow "${port}/${proto}" comment "inbound"
        log "Opened port ${port}/${proto}"
    done

    # Block NULL, XMAS, FIN port scans (via iptables, before UFW)
    iptables -I INPUT -p tcp --tcp-flags ALL NONE -j DROP
    iptables -I INPUT -p tcp --tcp-flags ALL ALL  -j DROP
    iptables -I INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP
    iptables -I INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP

    # SYN flood rate limiting
    iptables -A INPUT -p tcp --syn -m limit --limit 30/s --limit-burst 150 -j ACCEPT
    iptables -A INPUT -p tcp --syn -j DROP

    # Connection tracking: drop invalid packets
    iptables -I INPUT -m conntrack --ctstate INVALID -j DROP

    # Save iptables rules
    netfilter-persistent save > /dev/null 2>&1

    ufw --force enable
    log "Firewall configured."
}

# =============================================================
# 7. FAIL2BAN
# =============================================================

setup_fail2ban() {
    log "Configuring Fail2ban..."

    # Global defaults
    cat > /etc/fail2ban/jail.d/00-defaults.local << 'EOF'
[DEFAULT]
banaction  = iptables-multiport
bantime    = 3600
findtime   = 600
maxretry   = 5
ignoreip   = 127.0.0.1/8 ::1
EOF

    # SSH jail
    cat > /etc/fail2ban/jail.d/01-sshd.local << EOF
[sshd]
enabled  = true
port     = $NEW_SSH_PORT
filter   = sshd
logpath  = %(sshd_log)s
backend  = %(sshd_backend)s
maxretry = 3
bantime  = 86400
findtime = 300
EOF

    # 3x-ui panel jail
    cat > /etc/fail2ban/jail.d/02-3xui.local << EOF
[3xui-panel]
enabled  = true
port     = $PANEL_PORT
filter   = 3xui
logpath  = /var/log/3xui-access.log
maxretry = 5
bantime  = 86400
findtime = 600
EOF

    # 3x-ui filter (matches nginx-style access logs written by 3x-ui)
    cat > /etc/fail2ban/filter.d/3xui.conf << 'EOF'
[Definition]
failregex = ^<HOST> .* "POST .*/login" 4\d\d
            ^<HOST> .* "POST .*/xui/login" 4\d\d
ignoreregex =
datepattern = {^LN-BEG}%%Y/%%m/%%d %%H:%%M:%%S
EOF

    systemctl enable --now fail2ban
    systemctl restart fail2ban
    log "Fail2ban configured."
}

# =============================================================
# 8. INSTALL 3x-ui
# =============================================================

install_3xui() {
    log "Installing 3x-ui panel..."

    # Download and run official installer non-interactively
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) << 'EOF'

EOF

    sleep 3
    systemctl is-active x-ui > /dev/null 2>&1 || die "3x-ui service failed to start"

    # Apply settings via CLI
    x-ui setting -username "$PANEL_USER"
    x-ui setting -password "$PANEL_PASS"
    x-ui setting -port "$PANEL_PORT"
    x-ui setting -webBasePath "${PANEL_PATH}"

    # Enable access log for fail2ban
    x-ui setting -accessLogPath "/var/log/3xui-access.log"

    systemctl restart x-ui
    sleep 2

    log "3x-ui installed on port $PANEL_PORT."
}

# =============================================================
# 9. AUTO SECURITY UPDATES
# =============================================================

setup_autoupdates() {
    log "Enabling automatic security updates..."

    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Mail "root";
EOF

    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    systemctl enable unattended-upgrades
    log "Auto security updates enabled."
}

# =============================================================
# 10. FINALIZE
# =============================================================

restart_services() {
    log "Restarting SSH..."
    systemctl restart sshd
    log "All services running."
}

print_summary() {
    local PUBLIC_IP
    PUBLIC_IP=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null || \
                curl -s --connect-timeout 5 https://ifconfig.me 2>/dev/null || \
                echo "UNKNOWN")

    sep
    echo -e "${BOLD}${GREEN}  Installation Complete!${NC}"
    sep
    printf "  %-16s %s\n" "Server:"   "$SERVER_LABEL ($PUBLIC_IP)"
    printf "  %-16s %s\n" "SSH:"      "ssh -p $NEW_SSH_PORT root@$PUBLIC_IP"
    printf "  %-16s %s\n" "Panel URL:"   "http://$PUBLIC_IP:$PANEL_PORT${PANEL_PATH}"
    printf "  %-16s %s\n" "Username:" "$PANEL_USER"
    printf "  %-16s %s\n" "Password:" "$PANEL_PASS"
    if [[ ${#INBOUND_PORTS[@]} -gt 0 ]]; then
        printf "  %-16s %s\n" "Open ports:" "${INBOUND_PORTS[*]}"
    fi
    sep
    echo -e "${YELLOW}  CHECKLIST:${NC}"
    echo "   1. Test new SSH:   ssh -p $NEW_SSH_PORT root@$PUBLIC_IP"
    echo "   2. Remove old SSH: ufw delete allow $OLD_SSH_PORT/tcp"
    echo "   3. Open panel, add inbounds and clients"
    echo "   4. Copy client subscription URL from panel"
    echo "   5. Add it to aggregator/config.yaml"
    sep

    # Save credentials
    {
        echo "========================================="
        echo "3x-ui Install Log — $(date)"
        echo "========================================="
        echo "Server:     $SERVER_LABEL"
        echo "Public IP:  $PUBLIC_IP"
        echo "SSH port:   $NEW_SSH_PORT"
        echo "Panel URL:  http://$PUBLIC_IP:$PANEL_PORT${PANEL_PATH}"
        echo "Panel path: ${PANEL_PATH}"
        echo "Username:   $PANEL_USER"
        echo "Password:   $PANEL_PASS"
        echo "========================================="
    } >> "$LOG_FILE"
    chmod 600 "$LOG_FILE"

    info "  Credentials saved → $LOG_FILE"
    warn "  Delete $LOG_FILE after copying credentials to a password manager!"
}

# =============================================================
# MAIN
# =============================================================
main() {
    check_root
    detect_os
    prompt_config

    log "Starting setup..."

    update_system
    harden_sysctl
    harden_ssh
    setup_firewall
    setup_fail2ban
    install_3xui
    setup_autoupdates
    restart_services
    print_summary
}

main "$@"
