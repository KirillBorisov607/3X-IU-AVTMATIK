#!/usr/bin/env bash
# =============================================================
# 3x-ui Unified Setup Script
# Panel install + server hardening | Subscription aggregator
# Run: bash <(curl -Ls https://raw.githubusercontent.com/KirillBorisov607/3X-IU-AVTMATIK/master/install.sh)
# =============================================================

# Re-launch inside tmux/screen so SSH restart doesn't kill the session
if [[ -z "${INSIDE_SCREEN:-}" ]]; then
    apt-get update -qq 2>/dev/null || true
    apt-get install -y -qq tmux screen 2>/dev/null || true

    TMPSCRIPT=$(mktemp /tmp/3xui-install-XXXX.sh)
    curl -fsSL \
        https://raw.githubusercontent.com/KirillBorisov607/3X-IU-AVTMATIK/master/install.sh \
        -o "$TMPSCRIPT"
    chmod +x "$TMPSCRIPT"

    # Write a wrapper that exports INSIDE_SCREEN before running the main script.
    # Embedding "VAR=1 cmd" in a tmux command string is unreliable — the shell
    # tmux uses to interpret it may not export the variable properly.
    WRAPPER=$(mktemp /tmp/3xui-start-XXXX.sh)
    cat > "$WRAPPER" << WEOF
#!/usr/bin/env bash
export INSIDE_SCREEN=1
bash "$TMPSCRIPT"
EXIT_CODE=\$?
if [[ \$EXIT_CODE -ne 0 ]]; then
    echo ""
    echo "=== Script exited with code \$EXIT_CODE ==="
    echo "Check: cat /tmp/3xui-FAILED.txt"
    echo "Full log: cat /tmp/3xui-install.log"
    sleep 15
fi
WEOF
    chmod +x "$WRAPPER"

    if command -v tmux &>/dev/null; then
        echo ""
        echo "  Запуск в tmux (сессия: 3xui)..."
        echo "  Если соединение оборвётся: переподключись и выполни --> tmux attach -t 3xui"
        echo ""
        tmux kill-session -t 3xui 2>/dev/null || true
        tmux new-session -s 3xui "bash $WRAPPER"
        exit 0
    elif command -v screen &>/dev/null; then
        echo ""
        echo "  Запуск в screen (сессия: 3xui-install)..."
        echo "  Если соединение оборвётся: переподключись и выполни --> screen -r 3xui-install"
        echo ""
        screen -S 3xui-install "bash $WRAPPER"
        exit 0
    else
        echo "  [!] tmux/screen недоступны, запуск напрямую"
        INSIDE_SCREEN=1 bash "$TMPSCRIPT"
        exit 0
    fi
fi

set -eu
IFS=$'\n\t'

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

INSTALL_LOG="/tmp/3xui-install.log"
FAIL_MARKER="/tmp/3xui-FAILED.txt"

log()  { echo -e "${GREEN}[+]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  {
    echo -e "${RED}[x]${NC} $*" >&2
    { echo "FAILED at $(date)"; echo "die: $*"; echo ""; echo "Last 40 lines:"; tail -n 40 "$INSTALL_LOG" 2>/dev/null; } > "$FAIL_MARKER"
    exit 1
}
sep()  { echo -e "${CYAN}──────────────────────────────────────────────${NC}"; }

# Tee stdout+stderr to log. Safe without pipefail.
exec > >(tee -a "$INSTALL_LOG") 2>&1

# On error: print details AND write to FAIL_MARKER so it's readable after screen closes
error_handler() {
    local exit_code=$1 line=$2 command=$3
    echo ""
    echo -e "${RED}════════════════════════════════════════════════${NC}"
    echo -e "${RED}  ОШИБКА УСТАНОВКИ${NC}"
    echo -e "${RED}════════════════════════════════════════════════${NC}"
    echo -e "  Команда:  ${BOLD}${command}${NC}"
    echo -e "  Строка:   ${BOLD}${line}${NC}"
    echo -e "  Код:      ${BOLD}${exit_code}${NC}"
    echo ""
    echo -e "  После переподключения проверь:"
    echo -e "    ${BOLD}cat ${INSTALL_LOG}${NC}"
    echo -e "    ${BOLD}cat ${FAIL_MARKER}${NC}"
    echo -e "${RED}════════════════════════════════════════════════${NC}"
    # Write marker directly to disk — survives screen session close
    {
        echo "FAILED at $(date)"
        echo "Line: $line  |  Code: $exit_code"
        echo "Command: $command"
        echo ""
        echo "Last 40 lines of log:"
        tail -n 40 "$INSTALL_LOG" 2>/dev/null || true
    } > "$FAIL_MARKER"
}
trap 'error_handler $? $LINENO "$BASH_COMMAND"' ERR

echo ""
echo -e "${YELLOW}[!]${NC} Если соединение оборвётся — переподключись и проверь:"
echo    "    cat ${INSTALL_LOG}    (полный лог)"
echo    "    cat ${FAIL_MARKER}   (детали ошибки)"
echo ""

# =============================================================
# TRANSLATIONS
# =============================================================
declare -A S

load_ru() {
    S[choose_mode]="Что установить?"
    S[opt_panel]="1) Панель 3x-ui (установка + защита сервера)"
    S[opt_agg]="2) Агрегатор подписок"
    S[choose_agg]="Действие с агрегатором:"
    S[opt_agg_install]="1) Установить агрегатор"
    S[opt_agg_add]="2) Добавить подписку к существующему агрегатору"
    S[ask_ssh]="Новый SSH порт [2222]: "
    S[ask_panel_port]="Порт панели (внутренний) [2053]: "
    S[ask_nginx_port]="Порт для доступа к панели через HTTPS [8443]: "
    S[ask_user]="Логин панели [admin]: "
    S[ask_pass]="Пароль панели [авто]: "
    S[gen_pass]="Сгенерирован пароль: "
    S[ask_label]="Метка сервера [hostname]: "
    S[ask_inbound]="Порты inbound'ов через пробел (напр: 443 80 8080/udp) [пропустить]: "
    S[inbound_hint]="Форматы: PORT  PORT/tcp  PORT/udp"
    S[ask_agg_port]="Порт агрегатора [8080]: "
    S[ask_token]="Токен доступа [авто]: "
    S[ask_sub_name]="Название сервера (напр. US-1): "
    S[ask_sub_url]="Subscription URL из панели 3x-ui: "
    S[ask_prefix]="Префикс прокси (напр. US): "
    S[ask_ssl]="Отключить проверку SSL? [y/N]: "
    S[confirm]="Продолжить? [y/N]: "
    S[done]="Готово!"
    S[checklist]="Чеклист после установки:"
    S[check1]="Проверить SSH на новом порту (не закрывай эту сессию!)"
    S[check2]="Удалить старый SSH порт: ufw delete allow 22/tcp"
    S[check3]="Удалить файл с данными: rm /root/3xui-credentials.log"
    S[check4]="Добавить клиентов в панели, скопировать их Subscription URL"
    S[check5]="Добавить Subscription URL в агрегатор"
    S[warn_session]="Не закрывай текущую сессию до проверки нового SSH порта!"
    S[warn_log]="Удали /root/3xui-credentials.log после сохранения данных!"
    S[sub_added]="Подписка добавлена, агрегатор перезапущен."
    S[agg_edit]="Отредактируй конфиг и запусти: systemctl start sub-aggregator"
    S[err_root]="Запустите от root: sudo bash install.sh"
    S[err_os]="Неподдерживаемая ОС. Нужен Ubuntu 20.04+ или Debian 11+."
    S[err_no_agg]="Агрегатор не установлен. Сначала выбери пункт 1."
    S[err_port]="Неверный порт: "
    S[aborted]="Отменено."
}

load_en() {
    S[choose_mode]="What to install?"
    S[opt_panel]="1) 3x-ui Panel (install + server hardening)"
    S[opt_agg]="2) Subscription aggregator"
    S[choose_agg]="Aggregator action:"
    S[opt_agg_install]="1) Install aggregator"
    S[opt_agg_add]="2) Add subscription to existing aggregator"
    S[ask_ssh]="New SSH port [2222]: "
    S[ask_panel_port]="Panel internal port [2053]: "
    S[ask_nginx_port]="Panel HTTPS access port [8443]: "
    S[ask_user]="Panel username [admin]: "
    S[ask_pass]="Panel password [auto]: "
    S[gen_pass]="Generated password: "
    S[ask_label]="Server label [hostname]: "
    S[ask_inbound]="Inbound ports space-separated (e.g. 443 80 8080/udp) [skip]: "
    S[inbound_hint]="Formats: PORT  PORT/tcp  PORT/udp"
    S[ask_agg_port]="Aggregator port [8080]: "
    S[ask_token]="Access token [auto]: "
    S[ask_sub_name]="Server name (e.g. US-1): "
    S[ask_sub_url]="Subscription URL from 3x-ui panel: "
    S[ask_prefix]="Proxy name prefix (e.g. US): "
    S[ask_ssl]="Disable SSL verification? [y/N]: "
    S[confirm]="Proceed? [y/N]: "
    S[done]="Done!"
    S[checklist]="Post-install checklist:"
    S[check1]="Test SSH on the new port (keep this session open!)"
    S[check2]="Remove old SSH port: ufw delete allow 22/tcp"
    S[check3]="Delete credentials file: rm /root/3xui-credentials.log"
    S[check4]="Add clients in panel, copy their Subscription URLs"
    S[check5]="Add Subscription URLs to the aggregator"
    S[warn_session]="Keep this session open until you verify the new SSH port!"
    S[warn_log]="Delete /root/3xui-credentials.log after saving credentials!"
    S[sub_added]="Subscription added, aggregator restarted."
    S[agg_edit]="Edit config then run: systemctl start sub-aggregator"
    S[err_root]="Run as root: sudo bash install.sh"
    S[err_os]="Unsupported OS. Use Ubuntu 20.04+ or Debian 11+."
    S[err_no_agg]="Aggregator not installed. Run option 1 first."
    S[err_port]="Invalid port: "
    S[aborted]="Aborted."
}

s() { printf '%s' "${S[$1]:-$1}"; }

# =============================================================
# PREFLIGHT
# =============================================================

check_root() { [[ $EUID -eq 0 ]] || die "$(s err_root)"; }

detect_os() {
    [[ -f /etc/os-release ]] || die "$(s err_os)"
    source /etc/os-release
    case "$ID" in ubuntu|debian) ;; *) die "$(s err_os)";; esac
}

# =============================================================
# STEP 1 — Language
# =============================================================

select_language() {
    sep
    echo -e "  ${BOLD}Language / Язык${NC}"
    sep
    echo "  1) Русский"
    echo "  2) English"
    sep
    read -rp "  > " _in
    case "$_in" in
        1|ru|RU|р|Р) load_ru ;;
        2|en|EN|*)   load_en ;;
    esac
}

# =============================================================
# STEP 2 — Mode
# =============================================================

select_mode() {
    sep
    echo -e "  ${BOLD}$(s choose_mode)${NC}"
    sep
    echo "  $(s opt_panel)"
    echo "  $(s opt_agg)"
    sep
    read -rp "  > " _in
    case "$_in" in
        1) MODE="panel" ;;
        2) MODE="aggregator" ;;
        *) MODE="panel" ;;
    esac
}

select_agg_action() {
    sep
    echo -e "  ${BOLD}$(s choose_agg)${NC}"
    sep
    echo "  $(s opt_agg_install)"
    echo "  $(s opt_agg_add)"
    sep
    read -rp "  > " _in
    case "$_in" in
        1) AGG_ACTION="install" ;;
        2) AGG_ACTION="add_sub" ;;
        *) AGG_ACTION="install" ;;
    esac
}

# =============================================================
# PANEL — config prompt
# =============================================================

PANEL_PORT=2053
PANEL_NGINX_PORT=8443
PANEL_PATH=""
PANEL_USER="admin"
PANEL_PASS=""
NEW_SSH_PORT=2222
OLD_SSH_PORT=22
SERVER_LABEL=""
INBOUND_PORTS=()
LOG_FILE="/root/3xui-credentials.log"
SSH_SVC="ssh"   # detected in harden_ssh(); Ubuntu 24.04 = ssh, older = sshd

prompt_panel() {
    sep
    read -rp "  $(s ask_ssh)"         _in; NEW_SSH_PORT="${_in:-2222}"
    read -rp "  $(s ask_panel_port)"  _in; PANEL_PORT="${_in:-2053}"
    read -rp "  $(s ask_nginx_port)"  _in; PANEL_NGINX_PORT="${_in:-8443}"
    read -rp "  $(s ask_user)"        _in; PANEL_USER="${_in:-admin}"

    read -rp "  $(s ask_pass)" -s _in; echo
    if [[ -z "$_in" ]]; then
        PANEL_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 20)
        info "  $(s gen_pass)${BOLD}${PANEL_PASS}${NC}"
    else
        PANEL_PASS="$_in"
    fi

    PANEL_PATH="/$(openssl rand -hex 10)"

    read -rp "  $(s ask_label)" _in; SERVER_LABEL="${_in:-$(hostname -s)}"

    echo ""
    info "  $(s inbound_hint)"
    read -rp "  $(s ask_inbound)" _in
    # IFS=$'\n\t' is active — override to space so "443 80 8080" splits correctly
    [[ -n "$_in" ]] && IFS=' ' read -ra INBOUND_PORTS <<< "$_in"

    sep
    info "  SSH:          $NEW_SSH_PORT"
    info "  Panel internal: $PANEL_PORT"
    info "  Panel HTTPS:  $PANEL_NGINX_PORT"
    info "  Panel path:   $PANEL_PATH"
    info "  User:         $PANEL_USER"
    [[ ${#INBOUND_PORTS[@]} -gt 0 ]] && info "  Inbounds:     ${INBOUND_PORTS[*]}"
    sep
    read -rp "  $(s confirm)" _c
    [[ "${_c,,}" == "y" ]] || die "$(s aborted)"
}

# =============================================================
# PANEL — install steps
# =============================================================

update_system() {
    export DEBIAN_FRONTEND=noninteractive
    export UCF_FORCE_CONFFOLD=1
    export NEEDRESTART_MODE=a
    export NEEDRESTART_SUSPEND=1

    # Silence needrestart (Ubuntu 22.04/24.04) — all || true so missing files don't crash
    log "[1/3] Preparing apt..."
    mkdir -p /etc/needrestart/conf.d 2>/dev/null || true
    printf '$nrconf{restart} = '"'"'a'"'"';\n' \
        > /etc/needrestart/conf.d/99-auto.conf 2>/dev/null || true
    if [[ -f /etc/needrestart/needrestart.conf ]]; then
        sed -i "s/^#\?\\\$nrconf{restart}.*$/\\\$nrconf{restart} = 'a';/" \
            /etc/needrestart/needrestart.conf 2>/dev/null || true
    fi
    # Pre-seed debconf for iptables-persistent — || true because package may not exist yet
    echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" \
        | debconf-set-selections 2>/dev/null || true
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" \
        | debconf-set-selections 2>/dev/null || true

    log "[2/3] apt-get update..."
    apt-get update -qq 2>&1 || warn "apt-get update had errors, continuing"

    # Skip full upgrade — unattended-upgrades (installed below) handles ongoing security patches.
    # Full upgrade is the #1 cause of script crashes: kernel updates, grub prompts, OOM on small VPS.

    log "[3/3] Installing required packages..."
    apt-get install -y \
        -o Dpkg::Options::="--force-confold" \
        -o Dpkg::Options::="--force-confdef" \
        curl wget git vim htop unzip \
        net-tools lsof jq ca-certificates \
        gnupg2 ufw fail2ban \
        openssl nginx unattended-upgrades \
        2>&1 || die "apt-get install failed — check: cat ${INSTALL_LOG}"

    log "Packages ready."
}

harden_sysctl() {
    log "sysctl hardening..."
    cat > /etc/sysctl.d/99-3xui.conf << 'EOF'
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.suid_dumpable = 0
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 250000
net.ipv4.tcp_max_tw_buckets = 1440000
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
EOF
    sysctl -p /etc/sysctl.d/99-3xui.conf > /dev/null
}

harden_ssh() {
    log "SSH hardening (port $NEW_SSH_PORT)..."

    # Ubuntu 24.04 uses 'ssh.service'; older Ubuntu/Debian use 'sshd.service'
    if systemctl list-units --full --all 2>/dev/null | grep -q '\bsshd\.service\b'; then
        SSH_SVC="sshd"
    else
        SSH_SVC="ssh"
    fi
    log "SSH service name: $SSH_SVC"

    cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%s)"
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
    grep -q "^Include /etc/ssh/sshd_config.d" /etc/ssh/sshd_config \
        || echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
    sshd -t || die "SSH config test failed"
}

setup_firewall() {
    log "UFW + iptables..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw default deny forward

    ufw allow "${NEW_SSH_PORT}/tcp" comment "SSH"
    ufw limit "${NEW_SSH_PORT}/tcp"
    ufw allow "${OLD_SSH_PORT}/tcp" comment "OLD SSH - remove after test"

    # Panel access via nginx (NOT the raw panel port — that stays on localhost only)
    ufw allow "${PANEL_NGINX_PORT}/tcp" comment "3x-ui panel HTTPS"

    # Inbound ports
    for entry in "${INBOUND_PORTS[@]}"; do
        if [[ "$entry" == */* ]]; then
            port="${entry%/*}"; proto="${entry##*/}"
        else
            port="$entry"; proto="tcp"
        fi
        [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -gt 0 ]] && [[ "$port" -lt 65536 ]] || {
            warn "$(s err_port)$entry"; continue
        }
        [[ "$proto" == "tcp" || "$proto" == "udp" ]] || {
            warn "$(s err_port)$entry (bad proto)"; continue
        }
        ufw allow "${port}/${proto}" comment "inbound"
        log "Opened ${port}/${proto}"
    done

    # iptables: drop scan packets
    iptables -I INPUT -p tcp --tcp-flags ALL NONE    -j DROP
    iptables -I INPUT -p tcp --tcp-flags ALL ALL     -j DROP
    iptables -I INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP
    iptables -I INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
    iptables -I INPUT -m conntrack --ctstate INVALID -j DROP
    # SYN flood
    iptables -A INPUT -p tcp --syn -m limit --limit 30/s --limit-burst 150 -j ACCEPT
    iptables -A INPUT -p tcp --syn -j DROP

    # Persist custom iptables rules without iptables-persistent (conflicts with ufw on Ubuntu 24.04)
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4

    # Restore rules at boot via systemd
    cat > /etc/systemd/system/iptables-restore.service << 'EOF'
[Unit]
Description=Restore custom iptables rules
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable iptables-restore

    ufw --force enable
}

setup_fail2ban() {
    log "Fail2ban..."
    cat > /etc/fail2ban/jail.d/00-defaults.local << 'EOF'
[DEFAULT]
banaction = iptables-multiport
bantime   = 86400
findtime  = 600
maxretry  = 5
ignoreip  = 127.0.0.1/8 ::1
EOF
    cat > /etc/fail2ban/jail.d/01-sshd.local << EOF
[sshd]
enabled  = true
port     = $NEW_SSH_PORT
maxretry = 3
bantime  = 86400
findtime = 300
EOF
    cat > /etc/fail2ban/jail.d/02-3xui.local << EOF
[3xui]
enabled  = true
port     = $PANEL_NGINX_PORT
filter   = 3xui
logpath  = /var/log/nginx/3xui-access.log
maxretry = 5
EOF
    cat > /etc/fail2ban/filter.d/3xui.conf << 'EOF'
[Definition]
failregex = ^<HOST> .* "POST .*/login" 4\d\d
ignoreregex =
EOF
    systemctl enable --now fail2ban
    systemctl restart fail2ban
}

setup_nginx() {
    log "nginx reverse proxy + decoy page..."

    # Install nginx-extras for header manipulation (hides server fingerprint)
    apt-get install -y -qq nginx libnginx-mod-http-headers-more-filter 2>/dev/null \
        || apt-get install -y -qq nginx-extras 2>/dev/null \
        || true

    # Self-signed TLS cert
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/panel.key \
        -out    /etc/nginx/ssl/panel.crt \
        -subj   "/CN=localhost" \
        > /dev/null 2>&1

    # Decoy page — looks like a dev team's internal testing portal
    mkdir -p /var/www/decoy
    cat > /var/www/decoy/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Dev Portal — Internal</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{
    background:#0f1117;
    color:#e2e8f0;
    font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
    min-height:100vh;
    display:flex;
    align-items:center;
    justify-content:center;
    padding:24px;
  }
  .card{
    background:#1a1d27;
    border:1px solid #2d3148;
    border-radius:12px;
    padding:48px 40px;
    max-width:480px;
    width:100%;
    text-align:center;
    box-shadow:0 24px 48px rgba(0,0,0,.4);
  }
  .icon{
    width:64px;height:64px;
    background:#1e2235;
    border-radius:50%;
    display:flex;align-items:center;justify-content:center;
    margin:0 auto 24px;
    border:2px solid #2d3148;
  }
  .icon svg{color:#f59e0b}
  h1{font-size:1.25rem;font-weight:600;margin-bottom:12px;color:#f1f5f9}
  p{font-size:.9rem;color:#94a3b8;line-height:1.6;margin-bottom:8px}
  .badge{
    display:inline-block;
    background:#1e2235;
    border:1px solid #2d3148;
    border-radius:6px;
    padding:4px 10px;
    font-size:.75rem;
    color:#64748b;
    margin-top:24px;
    letter-spacing:.05em;
  }
  .btn{
    display:inline-block;
    margin-top:28px;
    padding:10px 24px;
    background:#1e2235;
    border:1px solid #374151;
    border-radius:8px;
    color:#94a3b8;
    font-size:.85rem;
    cursor:pointer;
    text-decoration:none;
    transition:border-color .2s,color .2s;
  }
  .btn:hover{border-color:#6366f1;color:#e2e8f0}
</style>
</head>
<body>
<div class="card">
  <div class="icon">
    <svg width="28" height="28" fill="none" stroke="currentColor" stroke-width="2"
         stroke-linecap="round" stroke-linejoin="round" viewBox="0 0 24 24">
      <path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/>
      <line x1="12" y1="9" x2="12" y2="13"/>
      <line x1="12" y1="17" x2="12.01" y2="17"/>
    </svg>
  </div>
  <h1>Restricted Area</h1>
  <p>This is an internal testing environment for our development team.</p>
  <p>You don't have access to this resource. If you got here by accident — just close this tab, no harm done.</p>
  <p style="margin-top:12px;font-size:.8rem;color:#475569">If you're a team member and something looks off, reach out to the infrastructure team.</p>
  <a class="btn" onclick="window.close();history.back();return false" href="#">Leave this page</a>
  <div class="badge">ENV: STAGING &nbsp;·&nbsp; BUILD: ci-2024 &nbsp;·&nbsp; ACCESS: RESTRICTED</div>
</div>
</body>
</html>
HTMLEOF

    # Global nginx hardening: hide version and server name
    sed -i 's/# server_tokens off;/server_tokens off;/' /etc/nginx/nginx.conf \
        || grep -q "server_tokens off" /etc/nginx/nginx.conf \
        || sed -i '/http {/a\\tserver_tokens off;' /etc/nginx/nginx.conf

    rm -f /etc/nginx/sites-enabled/default

    # Detect if more_set_headers module is available
    local header_cmd=""
    nginx -V 2>&1 | grep -q "headers-more" && header_cmd="more_set_headers \"Server: Apache/2.4.57\";"

    cat > /etc/nginx/sites-available/3xui << EOF
server {
    listen ${PANEL_NGINX_PORT} ssl;
    server_name _;

    ssl_certificate      /etc/nginx/ssl/panel.crt;
    ssl_certificate_key  /etc/nginx/ssl/panel.key;
    ssl_protocols        TLSv1.2 TLSv1.3;
    ssl_ciphers          ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout  1d;
    ssl_session_cache    shared:SSL:10m;

    access_log /var/log/nginx/3xui-access.log;
    error_log  /var/log/nginx/3xui-error.log;

    # Remove real server signature, look like something else
    ${header_cmd}
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "no-referrer" always;

    # Serve decoy page for any unknown path
    root /var/www/decoy;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Only the secret path reaches the real panel
    location ${PANEL_PATH}/ {
        proxy_pass         http://127.0.0.1:${PANEL_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_set_header   Upgrade           \$http_upgrade;
        proxy_set_header   Connection        "upgrade";
        proxy_read_timeout 120s;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/3xui /etc/nginx/sites-enabled/3xui
    nginx -t || die "nginx config test failed"
    systemctl enable --now nginx
    systemctl reload nginx
}

install_3xui() {
    log "Installing 3x-ui (official installer — ignore the URL it prints, we override everything after)..."
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) << 'EOF'

EOF
    sleep 3
    systemctl is-active x-ui > /dev/null 2>&1 || die "x-ui service failed to start"

    log "Applying custom settings (port / credentials / path / listen IP)..."
    x-ui setting -username    "$PANEL_USER"
    x-ui setting -password    "$PANEL_PASS"
    x-ui setting -port        "$PANEL_PORT"
    x-ui setting -webBasePath "${PANEL_PATH}"
    x-ui setting -listenIP    "127.0.0.1"

    systemctl restart x-ui
    sleep 2
    log "3x-ui configured. Real panel URL is in the summary below."
}

setup_autoupdates() {
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
    systemctl enable unattended-upgrades
}

print_panel_summary() {
    local ip
    ip=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null || echo "UNKNOWN")

    sep
    echo -e "  ${BOLD}${GREEN}  Установка завершена!${NC}"
    sep
    echo -e "  ${BOLD}Сервер:${NC}"
    printf "    %-20s %s\n" "Метка:"        "$SERVER_LABEL"
    printf "    %-20s %s\n" "IP:"           "$ip"
    echo ""
    echo -e "  ${BOLD}SSH:${NC}"
    printf "    %-20s %s\n" "Команда:"      "ssh -p $NEW_SSH_PORT root@$ip"
    printf "    %-20s %s\n" "Порт:"         "$NEW_SSH_PORT"
    echo ""
    echo -e "  ${BOLD}Панель 3x-ui:${NC}"
    printf "    %-20s %s\n" "URL:"          "https://$ip:$PANEL_NGINX_PORT${PANEL_PATH}/"
    printf "    %-20s %s\n" "Логин:"        "$PANEL_USER"
    printf "    %-20s %s\n" "Пароль:"       "$PANEL_PASS"
    printf "    %-20s %s\n" "Внутр. порт:"  "$PANEL_PORT (только localhost)"
    printf "    %-20s %s\n" "HTTPS порт:"   "$PANEL_NGINX_PORT"
    echo ""
    echo -e "  ${BOLD}Открытые порты:${NC}"
    printf "    %-20s %s\n" "$NEW_SSH_PORT/tcp"          "SSH"
    printf "    %-20s %s\n" "$PANEL_NGINX_PORT/tcp"      "Панель (nginx)"
    for entry in "${INBOUND_PORTS[@]}"; do
        [[ "$entry" == */* ]] && proto="" || entry="${entry}/tcp"
        printf "    %-20s %s\n" "$entry" "inbound"
    done
    echo ""
    echo -e "  ${BOLD}Защита:${NC}"
    printf "    %-20s %s\n" "Fail2ban:"     "SSH (3 попытки), панель (5 попыток)"
    printf "    %-20s %s\n" "UFW:"          "активен, всё закрыто кроме списка выше"
    printf "    %-20s %s\n" "Decoy страница:" "https://$ip:$PANEL_NGINX_PORT/"
    sep
    warn "  Удали файл с данными: rm /root/3xui-credentials.log"
    sep

    {
        echo "3x-ui install — $(date)"
        echo "Server:     $SERVER_LABEL ($ip)"
        echo "SSH:        ssh -p $NEW_SSH_PORT root@$ip"
        echo "Panel URL:  https://$ip:$PANEL_NGINX_PORT${PANEL_PATH}/"
        echo "Username:   $PANEL_USER"
        echo "Password:   $PANEL_PASS"
        echo "Inbounds:   ${INBOUND_PORTS[*]:-none}"
    } >> "$LOG_FILE"
    chmod 600 "$LOG_FILE"
    info "  Данные сохранены в /root/3xui-credentials.log"
}

verify_ssh() {
    local ip
    ip=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null || echo "YOUR_IP")

    sep
    warn "  SSH перезапускается на порту $NEW_SSH_PORT"
    warn "  Открой НОВУЮ вкладку MobaXterm и проверь подключение:"
    echo ""
    echo -e "  ${BOLD}  ssh -p $NEW_SSH_PORT root@$ip${NC}"
    echo ""
    systemctl restart "$SSH_SVC"
    echo ""
    read -rp "  Подключение на порту $NEW_SSH_PORT работает? [y/N]: " _ok
    if [[ "${_ok,,}" != "y" ]]; then
        warn "  Откатываю SSH на порт 22..."
        sed -i "s/^Port $NEW_SSH_PORT/Port 22/" /etc/ssh/sshd_config.d/99-hardened.conf
        systemctl restart "$SSH_SVC"
        ufw delete allow "${NEW_SSH_PORT}/tcp" 2>/dev/null || true
        die "SSH откатан на порт 22. Проверь настройки и запусти скрипт заново."
    fi
    log "SSH проверен. Удаляю старый порт 22 из файрволла."
    ufw delete allow "22/tcp" 2>/dev/null || true
    sep
}

run_panel() {
    prompt_panel
    update_system
    harden_sysctl
    harden_ssh
    setup_firewall
    setup_fail2ban
    setup_nginx
    install_3xui
    setup_autoupdates
    verify_ssh
    print_panel_summary
}

# =============================================================
# AGGREGATOR — install
# =============================================================

AGG_PORT=8080
AGG_TOKEN=""
AGG_DIR="/opt/sub-aggregator"
AGG_USER="subaggregate"
REPO_RAW="https://raw.githubusercontent.com/KirillBorisov607/3X-IU-AVTMATIK/master"

prompt_agg_install() {
    sep
    read -rp "  $(s ask_agg_port)" _in; AGG_PORT="${_in:-8080}"

    read -rp "  $(s ask_token)" -s _in; echo
    if [[ -z "$_in" ]]; then
        AGG_TOKEN=$(openssl rand -hex 32)
        info "  $(s gen_pass)${BOLD}${AGG_TOKEN}${NC}"
    else
        AGG_TOKEN="$_in"
    fi

    sep
    info "  Port:  $AGG_PORT"
    sep
    read -rp "  $(s confirm)" _c
    [[ "${_c,,}" == "y" ]] || die "$(s aborted)"
}

install_aggregator() {
    log "Installing aggregator..."
    apt-get update -qq
    apt-get install -y -qq python3 python3-pip python3-venv curl

    id "$AGG_USER" &>/dev/null \
        || useradd --system --no-create-home --shell /usr/sbin/nologin "$AGG_USER"

    mkdir -p "$AGG_DIR"

    curl -fsSL "${REPO_RAW}/aggregator/app.py"                 -o "$AGG_DIR/app.py"
    curl -fsSL "${REPO_RAW}/aggregator/requirements.txt"       -o "$AGG_DIR/requirements.txt"
    curl -fsSL "${REPO_RAW}/aggregator/sub-aggregator.service" -o /etc/systemd/system/sub-aggregator.service

    # Write config with chosen token and port
    cat > "$AGG_DIR/config.yaml" << EOF
token: "$AGG_TOKEN"
host: "0.0.0.0"
port: $AGG_PORT
cache_ttl: 300
servers: []
EOF

    python3 -m venv "$AGG_DIR/venv"
    "$AGG_DIR/venv/bin/pip" install -q --upgrade pip
    "$AGG_DIR/venv/bin/pip" install -q -r "$AGG_DIR/requirements.txt"

    mkdir -p /var/log/sub-aggregator
    chown -R "$AGG_USER:$AGG_USER" "$AGG_DIR" /var/log/sub-aggregator

    # Patch service file with correct port
    sed -i "s/0.0.0.0:8080/0.0.0.0:${AGG_PORT}/" /etc/systemd/system/sub-aggregator.service

    systemctl daemon-reload
    systemctl enable --now sub-aggregator

    command -v ufw &>/dev/null && ufw allow "${AGG_PORT}/tcp" comment "sub-aggregator"
}

print_agg_summary() {
    local ip
    ip=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null || echo "UNKNOWN")

    sep
    echo -e "  ${BOLD}${GREEN}$(s done)${NC}"
    sep
    printf "  %-14s %s\n" "Subscription:" "http://$ip:$AGG_PORT/sub/$AGG_TOKEN"
    sep
    info "  $(s check5)"
    echo "   curl -s http://$ip:$AGG_PORT/health"
    sep
}

run_agg_install() {
    prompt_agg_install
    install_aggregator
    print_agg_summary
}

# =============================================================
# AGGREGATOR — add subscription
# =============================================================

SUB_NAME=""
SUB_URL=""
SUB_PREFIX=""
SUB_NO_SSL="false"

prompt_add_sub() {
    [[ -f "$AGG_DIR/config.yaml" ]] || die "$(s err_no_agg)"
    sep
    read -rp "  $(s ask_sub_name)"   SUB_NAME
    read -rp "  $(s ask_sub_url)"    SUB_URL
    read -rp "  $(s ask_prefix)"     SUB_PREFIX
    read -rp "  $(s ask_ssl)"        _ssl
    [[ "${_ssl,,}" == "y" ]] && SUB_NO_SSL="true" || SUB_NO_SSL="false"
    sep
    read -rp "  $(s confirm)" _c
    [[ "${_c,,}" == "y" ]] || die "$(s aborted)"
}

add_subscription() {
    log "Adding subscription..."

    # Use Python (already installed with aggregator) to edit YAML
    python3 - << PYEOF
import yaml, sys

path = "$AGG_DIR/config.yaml"
with open(path) as f:
    cfg = yaml.safe_load(f) or {}

if 'servers' not in cfg or cfg['servers'] is None:
    cfg['servers'] = []

cfg['servers'].append({
    'name':       "$SUB_NAME",
    'sub_url':    "$SUB_URL",
    'prefix':     "$SUB_PREFIX",
    'verify_ssl': $( [[ "$SUB_NO_SSL" == "true" ]] && echo "False" || echo "True" ),
    'timeout':    10,
})

with open(path, 'w') as f:
    yaml.dump(cfg, f, allow_unicode=True, default_flow_style=False)

print("OK")
PYEOF

    systemctl restart sub-aggregator
    info "$(s sub_added)"

    sep
    local token
    token=$(python3 -c "import yaml; print(yaml.safe_load(open('$AGG_DIR/config.yaml'))['token'])")
    local ip
    ip=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null || echo "UNKNOWN")
    local port
    port=$(python3 -c "import yaml; print(yaml.safe_load(open('$AGG_DIR/config.yaml')).get('port', 8080))")
    printf "  Subscription URL: http://%s:%s/sub/%s\n" "$ip" "$port" "$token"
    sep
}

run_add_sub() {
    prompt_add_sub
    add_subscription
}

# =============================================================
# MAIN
# =============================================================

main() {
    check_root
    detect_os
    select_language
    select_mode

    case "$MODE" in
        panel)
            run_panel
            ;;
        aggregator)
            select_agg_action
            case "$AGG_ACTION" in
                install) run_agg_install ;;
                add_sub) run_add_sub ;;
            esac
            ;;
    esac
}

main "$@"
