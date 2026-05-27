#!/bin/bash
# =============================================================================
# Ingenio+ — Inicialización post-arranque v11
# Ejecutar UNA VEZ después de: ingenio up && sleep 300
#
# Hace en secuencia:
#   1. Obtiene token InfluxDB → guarda en .env
#   2. Inyecta token en nginx.conf
#   3. Reinicia Node-RED y Nginx
#   4. Configura redirect URIs de Keycloak (crítico para login)
# =============================================================================

set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

cd /opt/ingenioplus
[ -f .env ] || err "No existe .env — ejecutar: cp .env.example .env"
source .env

# ── 1. Esperar InfluxDB ───────────────────────────────────────────────────────
log "Verificando InfluxDB..."
timeout 60 bash -c 'until docker exec influxdb influx ping 2>/dev/null; do sleep 3; done' \
    || err "InfluxDB no respondió en 60s"
log "InfluxDB listo"

# ── 2. Obtener token ─────────────────────────────────────────────────────────
log "Obteniendo token InfluxDB..."
TOKEN=$(docker exec influxdb influx auth list \
    --org "${INFLUXDB_ORG}" --json 2>/dev/null | \
    python3 -c "import sys,json; a=json.load(sys.stdin); print(a[0]['token'])" 2>/dev/null || true)

if [ -z "$TOKEN" ]; then
    warn "Creando token nuevo..."
    TOKEN=$(docker exec influxdb influx auth create \
        --org "${INFLUXDB_ORG}" --all-access \
        --description "Ingenio+ admin" --json 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
fi

[ -z "$TOKEN" ] && err "No se pudo obtener el token de InfluxDB"
log "Token obtenido: ${TOKEN:0:20}..."

# ── 3. Guardar en .env ────────────────────────────────────────────────────────
if grep -q "^INFLUXDB_TOKEN=" .env; then
    sed -i "s|^INFLUXDB_TOKEN=.*|INFLUXDB_TOKEN=${TOKEN}|" .env
else
    echo "INFLUXDB_TOKEN=${TOKEN}" >> .env
fi
log "Token guardado en .env"

# ── 4. Inyectar en nginx.conf ─────────────────────────────────────────────────
sed -i "s|INFLUXDB_TOKEN_PLACEHOLDER|${TOKEN}|g" nginx/nginx.conf
log "Token inyectado en nginx.conf"

# ── 5. Reiniciar servicios ────────────────────────────────────────────────────
docker compose restart nodered nginx
log "Node-RED y Nginx reiniciados"

# ── 6. Configurar Keycloak redirect URIs ─────────────────────────────────────
log "Configurando Keycloak redirect URIs..."
sleep 10
bash scripts/setup_keycloak_uris.sh || warn "Keycloak URIs fallaron — ejecutar manualmente: bash scripts/setup_keycloak_uris.sh"

log "══════════════════════════════════════"
log "Inicialización completa"
log ""
log "Accesos:"
log "  OpenRemote: http://$(hostname).local/manager/"
log "  ChirpStack: http://$(hostname).local:8090"
log "  Grafana:    http://$(hostname).local:3000"
log "  EMQX:       http://$(hostname).local:18083"
log "  Node-RED:   http://$(hostname).local:1880"
log "  Portal:     http://$(hostname).local:8087"
log ""
log "Simulador: ingenio-sim"
log "WM1302:    bash scripts/setup_wm1302.sh start"
log "══════════════════════════════════════"
