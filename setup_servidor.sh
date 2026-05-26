#!/bin/bash
# =============================================================================
# Ingenio+ — Configuración del servidor v11
# Compatible con Debian 12/13, Ubuntu 22+
# Hardware: OMW-N2C19 J1900 / Mini PC N2840 / cualquier x86_64
#
# Uso: sudo bash setup_servidor.sh
# =============================================================================

set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}── $1 ──${NC}"; }

[[ $EUID -ne 0 ]] && err "Ejecutar como root: sudo bash setup_servidor.sh"

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DEPLOY_DIR"
MDNS_HOSTNAME="$(hostname).local"

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Ingenio+ — Configuración del servidor v11"
echo "  Directorio: $DEPLOY_DIR"
echo "  mDNS hostname: $MDNS_HOSTNAME"
echo "══════════════════════════════════════════════════════"

section "1. Docker"
if ! command -v docker &>/dev/null; then
    warn "Instalando Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker && systemctl start docker
    log "Docker instalado"
else
    log "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
fi

if ! docker compose version &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq docker-compose-plugin
fi
log "Docker Compose: $(docker compose version --short)"

section "2. Red Docker 'apps'"
if docker network inspect apps &>/dev/null; then
    log "Red 'apps' ya existe"
else
    docker network create apps
    log "Red 'apps' creada"
fi

section "3. Permisos de directorios"
# EMQX — UID 1000
mkdir -p emqx/data emqx/log
chown -R 1000:1000 emqx/ && chmod -R 755 emqx/
log "emqx/ → UID 1000"

# OpenRemote PostgreSQL — UID 70 (openremote/postgresql usa 70, no 999)
mkdir -p openremote/data/postgresql openremote/data/manager
chown -R 70:70 openremote/data/postgresql
chown -R 1000:1000 openremote/data/manager
chmod -R 750 openremote/data/postgresql && chmod -R 755 openremote/data/manager
log "openremote/postgresql → UID 70"
log "openremote/manager → UID 1000"

# InfluxDB — UID 1000
mkdir -p influxdb/data influxdb/config
chown -R 1000:1000 influxdb/ && chmod -R 755 influxdb/
log "influxdb/ → UID 1000"

# Node-RED — UID 1000
mkdir -p nodered/data
chown -R 1000:1000 nodered/ && chmod -R 755 nodered/
log "nodered/ → UID 1000"

# Nginx — UID 101
mkdir -p nginx/html
chown -R 101:101 nginx/html && chmod -R 755 nginx/
log "nginx/html → UID 101"

# Caddy, Portainer, ChirpStack
mkdir -p caddy/data caddy/config portainer_data
mkdir -p chirpstack/data/{postgresql,redis}
chmod -R 755 caddy/ portainer_data/ chirpstack/
log "caddy/, portainer_data/, chirpstack/data/ OK"

# Grafana — UID 472
mkdir -p grafana/data
chown -R 472:472 grafana/data && chmod -R 755 grafana/
log "grafana/data → UID 472"

section "4. mDNS con avahi-daemon"
if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
    log "avahi-daemon ya activo"
else
    apt-get install -y -qq avahi-daemon avahi-utils 2>/dev/null || true
    systemctl enable avahi-daemon && systemctl start avahi-daemon
    log "avahi-daemon instalado y activo"
fi

# Actualizar hostname en keycloak.conf
mkdir -p keycloak
if [ -f keycloak/keycloak.conf ]; then
    sed -i "s|^hostname=.*|hostname=${MDNS_HOSTNAME}|" keycloak/keycloak.conf
    log "keycloak.conf hostname → ${MDNS_HOSTNAME}"
fi

# Actualizar OR_HOSTNAME en .env
if [ -f .env ]; then
    sed -i "s|^OR_HOSTNAME=.*|OR_HOSTNAME=${MDNS_HOSTNAME}|" .env
    log "OR_HOSTNAME → ${MDNS_HOSTNAME}"
fi

section "5. Archivo .env"
if [ ! -f .env ]; then
    [ -f .env.example ] && cp .env.example .env && warn ".env creado desde .env.example — completar valores" || err "No existe .env.example"
else
    log ".env ya existe"
fi
chmod 600 .env

section "6. Python y dependencias"
if command -v pip3 &>/dev/null; then
    pip3 install paho-mqtt requests python-dotenv -q --break-system-packages 2>/dev/null || \
    pip3 install paho-mqtt requests python-dotenv -q 2>/dev/null || true
    log "Dependencias Python instaladas"
else
    warn "pip3 no disponible — instalar: apt install python3-pip"
fi

section "7. Aliases bash"
ALIASES_FILE="/root/.bashrc"
if ! grep -q "alias ingenio=" "$ALIASES_FILE" 2>/dev/null; then
    cat >> "$ALIASES_FILE" << ALIASEOF

# ── Ingenio+ aliases ──────────────────────────────────────────────────────────
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
    log "Aliases agregados a $ALIASES_FILE"
else
    log "Aliases ya existen"
fi

section "8. Scripts ejecutables"
chmod +x scripts/*.sh 2>/dev/null && log "Scripts: +x"

echo ""
echo "══════════════════════════════════════════════════════"
log "Servidor configurado correctamente"
echo ""
echo "  Próximos pasos:"
echo ""
echo "  1. Completar variables:"
echo "     nano .env"
echo ""
echo "  2. Levantar el stack:"
echo "     source /root/.bashrc && ingenio up"
echo ""
echo "  3. Esperar 5 minutos y ejecutar:"
echo "     bash scripts/init_influxdb.sh"
echo ""
echo "  4. Iniciar WM1302 (si disponible):"
echo "     bash scripts/setup_wm1302.sh start"
echo ""
echo "  Accesos (mDNS):"
echo "    OpenRemote:  http://${MDNS_HOSTNAME}/manager/"
echo "    ChirpStack:  http://${MDNS_HOSTNAME}:8090"
echo "    Grafana:     http://${MDNS_HOSTNAME}:3000"
echo "    EMQX:        http://${MDNS_HOSTNAME}:18083"
echo "    Node-RED:    http://${MDNS_HOSTNAME}:1880"
echo "    Portal:      http://${MDNS_HOSTNAME}:8087"
echo "══════════════════════════════════════════════════════"
