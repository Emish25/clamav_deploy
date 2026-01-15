#!/bin/bash

################################################################################
# Script : clamav_scan.sh
# Description : Scan antivirus automatique avec ClamAV + Reporting centralisé
# Auteur : DevOps Team
# Date : 2026-01-15
################################################################################

# ============================================================================
# CONFIGURATION
# ============================================================================

# Répertoire à scanner
SCAN_DIRS="/"

# Fichier de log local
LOG_FILE="/var/log/clamav/clamav-scan.log"
LOG_DIR="/var/log/clamav"

# Options de scan (exclure les répertoires système)
CLAMSCAN_OPTIONS="--recursive --infected --log=$LOG_FILE --exclude-dir=^/sys --exclude-dir=^/proc --exclude-dir=^/dev --exclude-dir=^/run"

# Configuration du serveur central
CENTRAL_SERVER="10.10.0.127"
CENTRAL_USER="ansible"
REPORT_FILE="/var/log/clamav-reports/scan-reports.log"

# ============================================================================
# FONCTIONS
# ============================================================================

create_log_dir() {
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
        chmod 755 "$LOG_DIR"
    fi
}

check_clamav() {
    if ! command -v clamscan &> /dev/null; then
        echo "❌ ERREUR : clamscan n'est pas installé"
        exit 2
    fi
}

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Fonction pour envoyer le rapport au serveur central
send_report() {
    local status=$1
    local hostname=$(hostname)
    local ip_address=$(hostname -I | awk '{print $1}')
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Symbole pour le statut
    local symbol=""
    case $status in
        "OK") symbol="✅" ;;
        "VIRUS") symbol="🚨" ;;
        "ERREUR") symbol="❌" ;;
    esac
    
    # Format : Date | IP | Hostname | Statut
    local report_line="$timestamp | $ip_address | $hostname | $symbol $status"
    
    # Envoyer via SSH au serveur central
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
echo "🛡️  SCAN ANTIVIRUS CLAMAV - $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════════"

check_clamav
create_log_dir

log_message "🔍 DÉBUT DU SCAN ANTIVIRUS"
log_message "📂 Répertoire scanné : $SCAN_DIRS"
log_message "🖥️  Machine : $(hostname) ($(hostname -I | awk '{print $1}'))"
log_message "════════════════════════════════════════════════════════════════"

START_TIME=$(date +%s)

# Exécution du scan
clamscan $CLAMSCAN_OPTIONS "$SCAN_DIRS"
SCAN_RESULT=$?

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# ============================================================================
# RÉSUMÉ ET REPORTING
# ============================================================================

log_message "════════════════════════════════════════════════════════════════"
log_message "⏱️  Durée totale : ${DURATION} secondes ($(($DURATION / 60)) minutes)"
log_message "📊 RÉSUMÉ DU SCAN"

case $SCAN_RESULT in
    0)
        log_message "✅ SCAN TERMINÉ : Aucun virus détecté"
        echo ""
        echo "✅ Résultat : AUCUN VIRUS DÉTECTÉ"
        send_report "OK"
        exit 0
        ;;
    1)
        log_message "⚠️  ALERTE : VIRUS DÉTECTÉ !"
        log_message "🔍 Consultez le log : $LOG_FILE"
        echo ""
        echo "🚨 ALERTE : VIRUS DÉTECTÉ !"
        echo "📄 Log : $LOG_FILE"
        send_report "VIRUS"
        exit 1
        ;;
    *)
        log_message "❌ ERREUR : Le scan a échoué (code: $SCAN_RESULT)"
        echo ""
        echo "❌ Erreur lors du scan (code: $SCAN_RESULT)"
        send_report "ERREUR"
        exit 2
        ;;
esac
