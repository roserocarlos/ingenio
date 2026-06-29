#!/bin/bash
# =============================================================================
# Ingenio+ — Plan Raíz · Deploy en un comando
# Arduino UNO Q 4GB (Debian + Docker, arquitectura ARM64)
#
# Uso:
#   git clone https://github.com/roserocarlos/ingenio
#   cd ingenio/raiz && bash deploy.sh
# =============================================================================

set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}━━ $1 ━━${NC}"; }

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DEPLOY_DIR"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Ingenio+ — Plan Raíz · Arduino UNO Q            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"

# ── 1. Verificar Docker ───────────────────────────────────────────────────────
section "1/6 · Docker"
command -v docker &>/dev/null || err "Docker no instalado — viene preinstalado en Arduino UNO Q OS"
log "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"

# ── 2. .env ───────────────────────────────────────────────────────────────────
section "2/6 · Variables de entorno"
if [ ! -f .env ]; then
    cp .env.example .env
    log ".env creado desde .env.example"
else
    log ".env ya existe"
fi
chmod 600 .env
source .env

# ── 3. Usuario Mosquitto ──────────────────────────────────────────────────────
section "3/6 · Autenticación Mosquitto"
mkdir -p mosquitto/config
if [ ! -f mosquitto/config/passwd ]; then
    docker run --rm -v "$(pwd)/mosquitto/config:/mosquitto/config" eclipse-mosquitto:2.0 \
        mosquitto_passwd -b -c /mosquitto/config/passwd "$MQTT_USER" "$MQTT_PASSWORD"
    log "Usuario MQTT '$MQTT_USER' creado"
else
    log "passwd ya existe"
fi

# ── 4. Inyectar token InfluxDB en nginx.conf ──────────────────────────────────
section "4/6 · Configurando proxy Nginx"
sed -i "s|INFLUXDB_TOKEN_PLACEHOLDER|${INFLUXDB_TOKEN}|g" nginx/nginx.conf
log "Token InfluxDB inyectado en nginx.conf"

# ── 5. Levantar stack ─────────────────────────────────────────────────────────
section "5/6 · Levantando stack (ARM64 — primera descarga puede tardar)"
docker compose up -d
log "Stack iniciado"

# ── 6. Resumen ─────────────────────────────────────────────────────────────────
section "6/6 · Listo"
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Ingenio+ Plan Raíz — Deploy completado       ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Portal:        http://localhost:8087                ║${NC}"
echo -e "${GREEN}║  Node-RED:      http://localhost:1880                 ║${NC}"
echo -e "${GREEN}║  InfluxDB:      http://localhost:8086                 ║${NC}"
echo -e "${GREEN}║  Grafana:       http://localhost:3000                 ║${NC}"
echo -e "${GREEN}║  Home Assistant: http://localhost:8123                ║${NC}"
echo -e "${GREEN}║  MQTT:          mqtt://localhost:1883                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
warn "Configurar datasource InfluxDB en Grafana manualmente (ver README)"
