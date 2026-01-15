#!/bin/bash

################################################################################
# Script : clamav_update.sh
# Description : Mise à jour automatique des signatures ClamAV + Reporting
# Auteur : DevOps Team
# Date : 2026-01-15
################################################################################

# ============================================================================
# CONFIGURATION
# ============================================================================

LOG_FILE="/var/log/clamav/freshclam.log"
LOG_DIR="/var/log/clamav"
PID_FILE="/var/run/clamav/freshclam.pid"

# Configuration du serveur central
CENTRAL_SERVER="10.10.0.127"
CENTRAL_USER="ansible"
REPORT_FILE="/var/log/clamav-reports/update-reports.log"

# ============================================================================
# FONCTIONS
# ============================================================================

create_log_dir() {
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
        chmod 755 "$LOG_DIR"
    fi
}

check_freshclam() {
    if ! command -v freshclam &> /dev/null; then
        echo "❌ ERREUR : freshclam n'est pas installé"
        exit 2
    fi
}

check_running() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "⚠️  freshclam déjà en cours (PID: $PID)"
            return 1
        else
            rm -f "$PID_FILE"
        fi
    fi
    return 0
}

stop_freshclam_service() {
    if systemctl is-active --quiet clamav-freshclam 2>/dev/null; then
        echo "🛑 Arrêt du service clamav-freshclam..."
        systemctl stop clamav-freshclam
        STOPPED_SERVICE=1
    fi
}

start_freshclam_service() {
    if [ "$STOPPED_SERVICE" -eq 1 ]; then
        echo "🔄 Redémarrage du service clamav-freshclam..."
        systemctl start clamav-freshclam
    fi
}

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

send_report() {
    local status=$1
    local hostname=$(hostname)
    local ip_address=$(hostname -I | awk '{print $1}')
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    local symbol=""
    case $status in
        "OK") symbol="✅" ;;
        "ERREUR") symbol="❌" ;;
        "EN_COURS") symbol="⏳" ;;
    esac
    
    local report_line="$timestamp | $ip_address | $hostname | $symbol UPDATE_$status"
    
    echo "$report_line" | ssh -o ConnectTimeout=10 -o BatchMode=yes \
        ${CENTRAL_USER}@${CENTRAL_SERVER} \
        "cat >> ${REPORT_FILE}" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log_message "📤 Rapport envoyé au serveur central"
    else
        log_message "⚠️  Impossible d'envoyer le rapport au serveur central"
    fi
}

# ============================================================================
# SCRIPT PRINCIPAL
# ============================================================================

echo "════════════════════════════════════════════════════════════════"
echo "🔄 MISE À JOUR CLAMAV - $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════════"

check_freshclam
create_log_dir

STOPPED_SERVICE=0
stop_freshclam_service

if ! check_running; then
    log_message "⏳ Processus déjà en cours, abandon"
    start_freshclam_service
    send_report "EN_COURS"
    exit 2
fi

log_message "🔄 DÉBUT DE LA MISE À JOUR"
log_message "🖥️  Machine : $(hostname) ($(hostname -I | awk '{print $1}'))"
log_message "════════════════════════════════════════════════════════════════"

START_TIME=$(date +%s)

freshclam --verbose --log="$LOG_FILE" 2>&1 | tee -a "$LOG_FILE"
UPDATE_RESULT=$?

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_message "════════════════════════════════════════════════════════════════"
log_message "⏱️  Durée : ${DURATION} secondes"
log_message "📊 RÉSUMÉ"

start_freshclam_service

case $UPDATE_RESULT in
    0)
        log_message "✅ MISE À JOUR RÉUSSIE"
        echo ""
        echo "✅ Signatures à jour"
        send_report "OK"
        exit 0
        ;;
    *)
        log_message "❌ ERREUR (code: $UPDATE_RESULT)"
        echo ""
        echo "❌ Erreur de mise à jour"
        send_report "ERREUR"
        exit 1
        ;;
esac
