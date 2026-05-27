#!/bin/bash
# =============================================================================
# Ingenio+ — Deploy completo v12
# Un solo comando: sudo bash deploy.sh
#
# Probado en: Debian 13 x86_64 (OMW-N2C19 J1900 / Mini PC N2840)
# Tiempo estimado: ~15 min (descarga imágenes Docker)
#
# Uso:
#   git clone https://github.com/roserocarlos/ingenio /opt/ingenioplus
#   cd /opt/ingenioplus && sudo bash deploy.sh
# =============================================================================

set -e

# ── Colores ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ── Verificaciones iniciales ──────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && err "Ejecutar como root: sudo bash deploy.sh"
[[ ! -f docker-compose.yml ]] && err "Ejecutar desde el directorio del repo: cd /opt/ingenioplus"

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DEPLOY_DIR"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Ingenio+ — Deploy automático v12             ║${NC}"
echo -e "${GREEN}║         Plan Cosecha · Nariño, Colombia              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
section "1/9 · Hostname fijo → ingenioplus"
# ─────────────────────────────────────────────────────────────────────────────
if [ "$(hostname)" != "ingenioplus" ]; then
    hostnamectl set-hostname ingenioplus
    # Agregar al /etc/hosts si no existe
    grep -q "ingenioplus" /etc/hosts || echo "127.0.1.1 ingenioplus ingenioplus.local" >> /etc/hosts
    log "Hostname configurado: ingenioplus"
else
    log "Hostname ya es: ingenioplus"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "2/9 · Docker"
# ─────────────────────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    warn "Instalando Docker..."
    apt-get update -qq
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    log "Docker instalado: $(docker --version | cut -d' ' -f3 | tr -d ',')"
else
    log "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
fi

if ! docker compose version &>/dev/null; then
    apt-get install -y -qq docker-compose-plugin
fi
log "Docker Compose: $(docker compose version --short)"

# ─────────────────────────────────────────────────────────────────────────────
section "3/9 · Red Docker 'apps'"
# ─────────────────────────────────────────────────────────────────────────────
if docker network inspect apps &>/dev/null; then
    log "Red 'apps' ya existe"
else
    docker network create apps
    log "Red 'apps' creada"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "4/9 · Dependencias del sistema"
# ─────────────────────────────────────────────────────────────────────────────
apt-get install -y -qq avahi-daemon avahi-utils python3-pip 2>/dev/null || true
systemctl enable avahi-daemon
systemctl start avahi-daemon
# pip con --break-system-packages para Debian 13
pip3 install paho-mqtt requests -q --break-system-packages 2>/dev/null || \
pip3 install paho-mqtt requests -q 2>/dev/null || true
log "avahi-daemon activo → ingenioplus.local"
log "Dependencias Python instaladas"

# ─────────────────────────────────────────────────────────────────────────────
section "5/9 · Permisos de directorios"
# ─────────────────────────────────────────────────────────────────────────────
# EMQX — UID 1000
mkdir -p emqx/{data,log}
chown -R 1000:1000 emqx/
chmod -R 755 emqx/

# OpenRemote PostgreSQL — UID 70 (crítico — imagen openremote/postgresql)
mkdir -p openremote/data/postgresql openremote/data/manager
chown -R 70:70 openremote/data/postgresql
chown -R 1000:1000 openremote/data/manager
chmod -R 750 openremote/data/postgresql
chmod -R 755 openremote/data/manager

# InfluxDB — UID 1000
mkdir -p influxdb/{data,config}
chown -R 1000:1000 influxdb/
chmod -R 755 influxdb/

# Node-RED — UID 1000
mkdir -p nodered/data
chown -R 1000:1000 nodered/
chmod -R 755 nodered/

# Nginx — UID 101
mkdir -p nginx/html
chown -R 101:101 nginx/html
chmod -R 755 nginx/

# Grafana — UID 472
mkdir -p grafana/data
chown -R 472:472 grafana/data
chmod -R 755 grafana/

# Caddy, Portainer, ChirpStack
mkdir -p caddy/{data,config} portainer_data
mkdir -p chirpstack/data/{postgresql,redis}
chmod -R 755 caddy/ portainer_data/ chirpstack/

log "Permisos configurados (UID 70/101/472/1000)"

# ─────────────────────────────────────────────────────────────────────────────
section "6/9 · Variables de entorno"
# ─────────────────────────────────────────────────────────────────────────────
if [ ! -f .env ]; then
    cp .env.example .env
    log ".env creado desde .env.example"
else
    log ".env ya existe — manteniendo configuración actual"
fi
chmod 600 .env

# Forzar hostname correcto en .env
sed -i "s|^OR_HOSTNAME=.*|OR_HOSTNAME=ingenioplus.local|" .env
log "OR_HOSTNAME=ingenioplus.local en .env"

# ─────────────────────────────────────────────────────────────────────────────
section "7/9 · Keycloak y scripts"
# ─────────────────────────────────────────────────────────────────────────────
# keycloak.conf — hostname fijo
mkdir -p keycloak
sed -i "s|^hostname=.*|hostname=ingenioplus.local|" keycloak/keycloak.conf 2>/dev/null || true
log "keycloak.conf → ingenioplus.local"

# Scripts ejecutables
chmod +x scripts/*.sh 2>/dev/null || true

# Aliases bash
BASHRC="/root/.bashrc"
if ! grep -q "alias ingenio=" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << ALIASEOF

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
    log "Aliases agregados a $BASHRC"
fi
source "$BASHRC" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
section "8/9 · Levantando stack Docker"
# ─────────────────────────────────────────────────────────────────────────────
warn "Descargando imágenes Docker (~10 min en primera instalación)..."
docker compose -f docker-compose.yml up -d
log "Stack iniciado — $(docker compose -f docker-compose.yml ps --format '{{.Name}}' | wc -l) contenedores"

# ─────────────────────────────────────────────────────────────────────────────
section "9/9 · Inicializando servicios"
# ─────────────────────────────────────────────────────────────────────────────
warn "Esperando que OpenRemote y Keycloak arranquen (2 minutos)..."
for i in $(seq 1 24); do
    sleep 5
    echo -n "."
done
echo ""

warn "Inicializando InfluxDB y Keycloak..."
bash scripts/init_influxdb.sh

# ─────────────────────────────────────────────────────────────────────────────
# RESUMEN
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Ingenio+ — Deploy completado ✓              ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Portal:      http://ingenioplus.local:8087          ║${NC}"
echo -e "${GREEN}║  OpenRemote:  http://ingenioplus.local/manager/      ║${NC}"
echo -e "${GREEN}║  ChirpStack:  http://ingenioplus.local:8090          ║${NC}"
echo -e "${GREEN}║  Grafana:     http://ingenioplus.local:3000          ║${NC}"
echo -e "${GREEN}║  EMQX:        http://ingenioplus.local:18083         ║${NC}"
echo -e "${GREEN}║  Node-RED:    http://ingenioplus.local:1880          ║${NC}"
echo -e "${GREEN}║  Portainer:   http://ingenioplus.local:9000          ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Usuario: admin  |  Password: linuxxl2               ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  WM1302: bash scripts/setup_wm1302.sh start          ║${NC}"
echo -e "${GREEN}║  Simulador: source ~/.bashrc && ingenio-sim           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
