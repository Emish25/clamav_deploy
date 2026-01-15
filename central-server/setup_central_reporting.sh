#!/bin/bash

################################################################################
# Script : setup_central_reporting.sh
# Description : Configuration du serveur central de reporting ClamAV
# Serveur : 10.10.0.127
# Auteur : DevOps Team
################################################################################

set -e

echo "════════════════════════════════════════════════════════════════"
echo "🖥️  CONFIGURATION DU SERVEUR CENTRAL DE REPORTING"
echo "════════════════════════════════════════════════════════════════"

# ============================================================================
# VARIABLES
# ============================================================================

REPORT_DIR="/var/log/clamav-reports"
REPORT_USER="ansible"
WEB_DIR="/var/www/html/clamav-reports"

# ============================================================================
# CRÉATION DE L'UTILISATEUR
# ============================================================================

if ! id "$REPORT_USER" &>/dev/null; then
    echo "👤 Création de l'utilisateur $REPORT_USER..."
    useradd -m -s /bin/bash "$REPORT_USER"
    echo "✅ Utilisateur créé"
else
    echo "✅ Utilisateur $REPORT_USER existe déjà"
fi

# ============================================================================
# CRÉATION DES RÉPERTOIRES
# ============================================================================

echo "📁 Création du répertoire de rapports..."
mkdir -p "$REPORT_DIR"
chown "$REPORT_USER":"$REPORT_USER" "$REPORT_DIR"
chmod 755 "$REPORT_DIR"

touch "$REPORT_DIR/scan-reports.log"
touch "$REPORT_DIR/update-reports.log"
chown "$REPORT_USER":"$REPORT_USER" "$REPORT_DIR"/*.log
chmod 644 "$REPORT_DIR"/*.log

echo "✅ Répertoire créé : $REPORT_DIR"

# ============================================================================
# CONFIGURATION SSH
# ============================================================================

echo "🔑 Configuration SSH..."
mkdir -p /home/$REPORT_USER/.ssh
chmod 700 /home/$REPORT_USER/.ssh
touch /home/$REPORT_USER/.ssh/authorized_keys
chmod 600 /home/$REPORT_USER/.ssh/authorized_keys
chown -R "$REPORT_USER":"$REPORT_USER" /home/$REPORT_USER/.ssh

echo "✅ SSH configuré"

# ============================================================================
# SCRIPT DE VISUALISATION
# ============================================================================

echo "📝 Création du script de visualisation..."
cat > /usr/local/bin/view-clamav-reports <<'VIEWSCRIPT'
#!/bin/bash

REPORT_DIR="/var/log/clamav-reports"

echo "════════════════════════════════════════════════════════════════"
echo "📊 RAPPORTS CLAMAV - $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Compter les statuts
total_scans=$(wc -l < "$REPORT_DIR/scan-reports.log" 2>/dev/null || echo "0")
scans_ok=$(grep -c "✅ OK" "$REPORT_DIR/scan-reports.log" 2>/dev/null || echo "0")
scans_virus=$(grep -c "🚨 VIRUS" "$REPORT_DIR/scan-reports.log" 2>/dev/null || echo "0")
scans_erreur=$(grep -c "❌ ERREUR" "$REPORT_DIR/scan-reports.log" 2>/dev/null || echo "0")

echo "📊 STATISTIQUES DES SCANS"
echo "────────────────────────────────────────────────────────────────"
echo "Total des scans      : $total_scans"
echo "✅ Scans OK          : $scans_ok"
echo "🚨 Virus détectés    : $scans_virus"
echo "❌ Erreurs           : $scans_erreur"
echo ""

echo "🔍 DERNIERS SCANS (20 derniers)"
echo "────────────────────────────────────────────────────────────────"
tail -20 "$REPORT_DIR/scan-reports.log" 2>/dev/null | while IFS='|' read -r date ip hostname status; do
    printf "%-20s | %-15s | %-20s | %s\n" "$date" "$ip" "$hostname" "$status"
done || echo "Aucun rapport disponible"

echo ""
echo "🔄 DERNIÈRES MISES À JOUR (20 dernières)"
echo "────────────────────────────────────────────────────────────────"
tail -20 "$REPORT_DIR/update-reports.log" 2>/dev/null | while IFS='|' read -r date ip hostname status; do
    printf "%-20s | %-15s | %-20s | %s\n" "$date" "$ip" "$hostname" "$status"
done || echo "Aucun rapport disponible"

echo ""
echo "════════════════════════════════════════════════════════════════"
VIEWSCRIPT

chmod +x /usr/local/bin/view-clamav-reports
echo "✅ Script créé : view-clamav-reports"

# ============================================================================
# INSTALLATION NGINX (OPTIONNEL)
# ============================================================================

read -p "📦 Installer nginx pour l'interface web ? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "📦 Installation de nginx..."
    apt update -qq
    apt install -y nginx >/dev/null 2>&1
    
    mkdir -p "$WEB_DIR"
    
    # Page HTML
    cat > "$WEB_DIR/index.html" <<'HTMLPAGE'
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🛡️ ClamAV - Rapports Centralisés</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', system-ui, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            color: #eee;
            padding: 20px;
        }
        .container { max-width: 1600px; margin: 0 auto; }
        h1 { 
            text-align: center;
            color: #0f3;
            margin-bottom: 30px;
            font-size: 2.5rem;
            text-shadow: 0 0 20px rgba(0,255,51,0.5);
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: linear-gradient(135deg, #16213e 0%, #1a1a2e 100%);
            padding: 20px;
            border-radius: 15px;
            text-align: center;
            border: 2px solid rgba(0,255,51,0.2);
            transition: all 0.3s;
        }
        .stat-card:hover {
            transform: translateY(-5px);
            border-color: rgba(0,255,51,0.6);
            box-shadow: 0 10px 30px rgba(0,255,51,0.3);
        }
        .stat-value {
            font-size: 3rem;
            font-weight: bold;
            color: #0f3;
            text-shadow: 0 0 10px rgba(0,255,51,0.5);
        }
        .stat-label {
            color: #aaa;
            margin-top: 10px;
            font-size: 0.9rem;
        }
        .card {
            background: linear-gradient(135deg, #16213e 0%, #1a1a2e 100%);
            border-radius: 15px;
            padding: 25px;
            margin-bottom: 25px;
            border: 2px solid rgba(0,255,51,0.2);
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
        }
        .card h2 {
            color: #0f3;
            margin-bottom: 20px;
            font-size: 1.5rem;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .table-container {
            overflow-x: auto;
            background: #0f1419;
            border-radius: 10px;
            padding: 15px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.9rem;
        }
        th {
            background: rgba(0,255,51,0.1);
            color: #0f3;
            padding: 12px;
            text-align: left;
            font-weight: 600;
            border-bottom: 2px solid rgba(0,255,51,0.3);
        }
        td {
            padding: 10px 12px;
            border-bottom: 1px solid rgba(255,255,255,0.05);
        }
        tr:hover {
            background: rgba(0,255,51,0.05);
        }
        .status {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 20px;
            font-weight: bold;
            font-size: 0.85rem;
        }
        .status-ok { background: rgba(0,255,51,0.2); color: #0f3; }
        .status-virus { background: rgba(255,51,0,0.2); color: #f30; }
        .status-error { background: rgba(255,170,0,0.2); color: #fa0; }
        .refresh-btn {
            position: fixed;
            bottom: 30px;
            right: 30px;
            background: #0f3;
            color: #000;
            border: none;
            padding: 15px 30px;
            border-radius: 50px;
            cursor: pointer;
            font-size: 1rem;
            font-weight: bold;
            box-shadow: 0 4px 20px rgba(0,255,51,0.4);
            transition: all 0.3s;
        }
        .refresh-btn:hover {
            transform: scale(1.05);
            box-shadow: 0 6px 30px rgba(0,255,51,0.6);
        }
        .loading {
            text-align: center;
            padding: 40px;
            color: #0f3;
            font-size: 1.2rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🛡️ ClamAV - Rapports Centralisés</h1>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-value" id="total-scans">-</div>
                <div class="stat-label">Total Scans</div>
            </div>
            <div class="stat-card">
                <div class="stat-value" style="color: #0f3;" id="scans-ok">-</div>
                <div class="stat-label">✅ Scans OK</div>
            </div>
            <div class="stat-card">
                <div class="stat-value" style="color: #f30;" id="scans-virus">-</div>
                <div class="stat-label">🚨 Virus Détectés</div>
            </div>
            <div class="stat-card">
                <div class="stat-value" style="color: #fa0;" id="scans-error">-</div>
                <div class="stat-label">❌ Erreurs</div>
            </div>
        </div>
        
        <div class="card">
            <h2>🔍 Derniers Scans (30 derniers)</h2>
            <div class="table-container">
                <table id="scan-table">
                    <thead>
                        <tr>
                            <th>Date/Heure</th>
                            <th>IP</th>
                            <th>Hostname</th>
                            <th>Statut</th>
                        </tr>
                    </thead>
                    <tbody id="scan-tbody">
                        <tr><td colspan="4" class="loading">Chargement...</td></tr>
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="card">
            <h2>🔄 Dernières Mises à Jour (30 dernières)</h2>
            <div class="table-container">
                <table id="update-table">
                    <thead>
                        <tr>
                            <th>Date/Heure</th>
                            <th>IP</th>
                            <th>Hostname</th>
                            <th>Statut</th>
                        </tr>
                    </thead>
                    <tbody id="update-tbody">
                        <tr><td colspan="4" class="loading">Chargement...</td></tr>
                    </tbody>
                </table>
            </div>
        </div>
    </div>
    
    <button class="refresh-btn" onclick="loadReports()">🔄 Actualiser</button>
    
    <script>
        function parseStatus(status) {
            status = status.trim();
            if (status.includes('✅') || status.includes('OK')) {
                return '<span class="status status-ok">✅ OK</span>';
            } else if (status.includes('🚨') || status.includes('VIRUS')) {
                return '<span class="status status-virus">🚨 VIRUS</span>';
            } else if (status.includes('❌') || status.includes('ERREUR')) {
                return '<span class="status status-error">❌ ERREUR</span>';
            }
            return '<span class="status">' + status + '</span>';
        }
        
        function loadReports() {
            // Charger les scans
            fetch('/clamav-reports-data/scan-reports.log')
                .then(r => r.text())
                .then(data => {
                    const lines = data.trim().split('\n').filter(l => l).slice(-30).reverse();
                    const tbody = document.getElementById('scan-tbody');
                    
                    if (lines.length === 0) {
                        tbody.innerHTML = '<tr><td colspan="4">Aucun rapport disponible</td></tr>';
                        return;
                    }
                    
                    let html = '';
                    let total = 0, ok = 0, virus = 0, error = 0;
                    
                    lines.forEach(line => {
                        const parts = line.split('|').map(p => p.trim());
                        if (parts.length >= 4) {
                            html += `<tr>
                                <td>${parts[0]}</td>
                                <td>${parts[1]}</td>
                                <td>${parts[2]}</td>
                                <td>${parseStatus(parts[3])}</td>
                            </tr>`;
                            
                            total++;
                            if (parts[3].includes('OK')) ok++;
                            else if (parts[3].includes('VIRUS')) virus++;
                            else if (parts[3].includes('ERREUR')) error++;
                        }
                    });
                    
                    tbody.innerHTML = html;
                    
                    // Mettre à jour les stats (basé sur tous les rapports, pas seulement les 30 derniers)
                    const allLines = data.trim().split('\n').filter(l => l);
                    let allTotal = 0, allOk = 0, allVirus = 0, allError = 0;
                    allLines.forEach(line => {
                        allTotal++;
                        if (line.includes('✅') || line.includes('OK')) allOk++;
                        else if (line.includes('🚨') || line.includes('VIRUS')) allVirus++;
                        else if (line.includes('❌') || line.includes('ERREUR')) allError++;
                    });
                    
                    document.getElementById('total-scans').textContent = allTotal;
                    document.getElementById('scans-ok').textContent = allOk;
                    document.getElementById('scans-virus').textContent = allVirus;
                    document.getElementById('scans-error').textContent = allError;
                })
                .catch(e => {
                    document.getElementById('scan-tbody').innerHTML = 
                        '<tr><td colspan="4">Erreur de chargement</td></tr>';
                });
            
            // Charger les mises à jour
            fetch('/clamav-reports-data/update-reports.log')
                .then(r => r.text())
                .then(data => {
                    const lines = data.trim().split('\n').filter(l => l).slice(-30).reverse();
                    const tbody = document.getElementById('update-tbody');
                    
                    if (lines.length === 0) {
                        tbody.innerHTML = '<tr><td colspan="4">Aucun rapport disponible</td></tr>';
                        return;
                    }
                    
                    let html = '';
                    lines.forEach(line => {
                        const parts = line.split('|').map(p => p.trim());
                        if (parts.length >= 4) {
                            html += `<tr>
                                <td>${parts[0]}</td>
                                <td>${parts[1]}</td>
                                <td>${parts[2]}</td>
                                <td>${parseStatus(parts[3])}</td>
                            </tr>`;
                        }
                    });
                    
                    tbody.innerHTML = html;
                })
                .catch(e => {
                    document.getElementById('update-tbody').innerHTML = 
                        '<tr><td colspan="4">Erreur de chargement</td></tr>';
                });
        }
        
        // Charger au démarrage
        loadReports();
        
        // Auto-refresh toutes les 60 secondes
        setInterval(loadReports, 60000);
    </script>
</body>
</html>
HTMLPAGE

    # Créer un alias pour les logs
    ln -sf "$REPORT_DIR" /var/www/html/clamav-reports-data
    
    # Configuration nginx
    cat > /etc/nginx/sites-available/clamav-reports <<'NGINXCONF'
server {
    listen 80;
    server_name _;
    
    root /var/www/html;
    index index.html;
    
    location /clamav-reports {
        alias /var/www/html/clamav-reports;
        index index.html;
    }
    
    location /clamav-reports-data {
        alias /var/log/clamav-reports;
        autoindex off;
    }
}
NGINXCONF

    ln -sf /etc/nginx/sites-available/clamav-reports /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t && systemctl restart nginx
    systemctl enable nginx >/dev/null 2>&1
    
    echo "✅ Nginx configuré"
    echo "🌐 Interface web : http://10.10.0.127/clamav-reports/"
fi

# ============================================================================
# RÉSUMÉ
# ============================================================================

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ CONFIGURATION TERMINÉE"
echo "════════════════════════════════════════════════════════════════"
echo "📁 Rapports : $REPORT_DIR"
echo "👤 Utilisateur : $REPORT_USER"
echo "📊 Commande : view-clamav-reports"
echo ""
echo "📌 PROCHAINES ÉTAPES :"
echo "  1. Déployez Ansible sur vos serveurs"
echo "  2. Les clés SSH seront ajoutées automatiquement"
echo "  3. Les rapports apparaîtront ici après les premiers scans"
echo "════════════════════════════════════════════════════════════════"
