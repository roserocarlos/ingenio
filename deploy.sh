#!/bin/bash
# =============================================================================
# Ingenio+ — Deploy completo en un comando
# Uso: sudo bash deploy.sh
#
# Hace todo:
#   1. Configura hostname → ingenioplus
#   2. Instala Docker y dependencias
#   3. Crea red Docker, permisos, mDNS
#   4. Copia .env desde .env.example
#   5. Levanta el stack completo
#   6. Espera e inicializa InfluxDB + Keycloak
# =============================================================================

set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}━━ $1 ━━${NC}"; }
wait_bar(){ echo -ne "${YELLOW}[!]${NC} Esperando $1..."; for i in $(seq 1 $2); do sleep 1; echo -n "."; done; echo " listo"; }

[[ $EUID -ne 0 ]] && err "Ejecutar como root: sudo bash deploy.sh"

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DEPLOY_DIR"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║         Ingenio+ — Deploy automático v12             ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── 1. Hostname fijo ──────────────────────────────────────────────────────────
section "1. Hostname"
CURRENT=$(hostname)
if [ "$CURRENT" != "ingenioplus" ]; then
    hostnamectl set-hostname ingenioplus
    echo "127.0.1.1 ingenioplus" >> /etc/hosts
    log "Hostname cambiado a: ingenioplus"
else
    log "Hostname ya es: ingenioplus"
fi

# ── 2. Docker ─────────────────────────────────────────────────────────────────
section "2. Docker"
if ! command -v docker &>/dev/null; then
    warn "Instalando Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker && systemctl start docker
    log "Docker instalado"
else
    log "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
fi

# ── 3. Red Docker ─────────────────────────────────────────────────────────────
section "3. Red Docker"
docker network inspect apps &>/dev/null || docker network create apps
log "Red 'apps' lista"

# ── 4. Dependencias ───────────────────────────────────────────────────────────
section "4. Dependencias"
apt-get install -y -qq avahi-daemon avahi-utils 2>/dev/null || true
systemctl enable avahi-daemon && systemctl start avahi-daemon
pip3 install paho-mqtt requests -q --break-system-packages 2>/dev/null || true
log "avahi-daemon activo → ingenioplus.local"

# ── 5. Permisos ───────────────────────────────────────────────────────────────
section "5. Permisos de directorios"
mkdir -p emqx/{data,log} && chown -R 1000:1000 emqx/
mkdir -p openremote/data/{postgresql,manager}
chown -R 70:70 openremote/data/postgresql
chown -R 1000:1000 openremote/data/manager
mkdir -p influxdb/{data,config} && chown -R 1000:1000 influxdb/
mkdir -p nodered/data && chown -R 1000:1000 nodered/
mkdir -p nginx/html && chown -R 101:101 nginx/html
mkdir -p grafana/data && chown -R 472:472 grafana/
mkdir -p caddy/{data,config} portainer_data
mkdir -p chirpstack/data/{postgresql,redis}
log "Permisos configurados"

# ── 6. .env ───────────────────────────────────────────────────────────────────
section "6. Variables de entorno"
if [ ! -f .env ]; then
    cp .env.example .env
    log ".env creado desde .env.example"
else
    log ".env ya existe — manteniendo configuración actual"
fi
chmod 600 .env

# ── 7. keycloak.conf ─────────────────────────────────────────────────────────
section "7. Keycloak"
mkdir -p keycloak
sed -i "s|^hostname=.*|hostname=ingenioplus.local|" keycloak/keycloak.conf
sed -i "s|^OR_HOSTNAME=.*|OR_HOSTNAME=ingenioplus.local|" .env
log "keycloak.conf → ingenioplus.local"

# ── 8. Aliases ────────────────────────────────────────────────────────────────
section "8. Aliases bash"
ALIASES_FILE="/root/.bashrc"
if ! grep -q "alias ingenio=" "$ALIASES_FILE" 2>/dev/null; then
    cat >> "$ALIASES_FILE" << ALIASEOF

# ── Ingenio+ ──────────────────────────────────────────────────────────────────
alias ingenio='docker compose -f ${DEPLOY_DIR}/docker-compose.yml'
alias ingenio-ps='docker compose -f ${DEPLOY_DIR}/docker-compose.yml ps'
alias ingenio-up='docker compose -f ${DEPLOY_DIR}/docker-compose.yml up -d'
alias ingenio-down='docker compose -f ${DEPLOY_DIR}/docker-compose.yml down'
alias ingenio-or='docker compose -f ${DEPLOY_DIR}/docker-compose.yml logs -f openremote-manager'
alias ingenio-emqx='docker compose -f ${DEPLOY_DIR}/docker-compose.yml logs -f emqx'
alias ingenio-nr='docker compose -f ${DEPLOY_DIR}/docker-compose.yml logs -f nodered'
alias ingenio-influx='docker compose -f ${DEPLOY_DIR}/docker-compose.yml logs -f influxdb'
alias ingenio-chirp='docker compose -f ${DEPLOY_DIR}/docker-compose.yml logs -f chirpstack'
alias ingenio-sim='cd ${DEPLOY_DIR} && python3 scripts/simulador_sensor.py'
alias cdingenia='cd ${DEPLOY_DIR}'
ALIASEOF
    log "Aliases agregados"
fi
source "$ALIASES_FILE" 2>/dev/null || true
chmod +x scripts/*.sh 2>/dev/null || true

# ── 9. Levantar stack ─────────────────────────────────────────────────────────
section "9. Levantando stack (descarga de imágenes ~10 min)"
docker compose -f docker-compose.yml up -d
log "Stack iniciado"

# ── 10. Esperar e inicializar ─────────────────────────────────────────────────
section "10. Inicializando servicios"
wait_bar "OpenRemote y Keycloak" 120
bash scripts/init_influxdb.sh

# ── Resumen ───────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║            Ingenio+ — Deploy completado              ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  OpenRemote:  http://ingenioplus.local/manager/      ║"
echo "║  Portal:      http://ingenioplus.local:8087          ║"
echo "║  ChirpStack:  http://ingenioplus.local:8090          ║"
echo "║  Grafana:     http://ingenioplus.local:3000          ║"
echo "║  EMQX:        http://ingenioplus.local:18083         ║"
echo "║  Node-RED:    http://ingenioplus.local:1880          ║"
echo "║  Portainer:   http://ingenioplus.local:9000          ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  Usuario: admin  |  Password: ver .env               ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
log "Deploy completado — ingenioplus.local activo en la red"
