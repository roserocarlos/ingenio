#!/bin/bash
# =============================================================================
# Ingenio+ — Plan Raíz · Deploy en un comando
# Arduino UNO Q 4GB (Debian + Docker, arquitectura ARM64)
#
# Uso:
#   git clone https://github.com/roserocarlos/ingenio
#   cd ingenio/raiz && bash deploy.sh
#
# Este script resuelve automáticamente:
#   - Particiones eMMC pequeñas (mueve Docker a partición con más espacio)
#   - Acceso por nombre local (mDNS/Avahi) — sin necesidad de recordar IP
#   - Verifica salud de Mosquitto tras el arranque
# =============================================================================

set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}━━ $1 ━━${NC}"; }

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DEPLOY_DIR"
HOME_DIR="$(eval echo ~$(whoami))"
HOSTNAME_LOCAL="$(hostname).local"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Ingenio+ — Plan Raíz · Arduino UNO Q            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"

# ── 1. Verificar Docker ───────────────────────────────────────────────────────
section "1/8 · Docker"
command -v docker &>/dev/null || err "Docker no instalado — viene preinstalado en Arduino UNO Q OS"
log "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"

# ── 2. Verificar espacio en disco — mover Docker si la raíz está casi llena ──
section "2/8 · Verificando espacio en disco"
ROOT_USE=$(df / --output=pcent | tail -1 | tr -d ' %')
ROOT_AVAIL_MB=$(df / --output=avail -BM | tail -1 | tr -d 'M ')

if [ "$ROOT_USE" -ge 85 ] || [ "$ROOT_AVAIL_MB" -lt 2000 ]; then
    warn "Partición raíz al ${ROOT_USE}% (${ROOT_AVAIL_MB}MB libres) — buscando partición con más espacio"

    # Buscar la partición montada con más espacio libre, excluyendo /, /boot, tmpfs
    BEST_MOUNT=$(df --output=avail,target -BM 2>/dev/null | tail -n +2 | \
        grep -vE "tmpfs|/boot|^.*\s/$" | sort -rn | head -1 | awk '{print $2}')
    BEST_AVAIL=$(df --output=avail -BM "$BEST_MOUNT" 2>/dev/null | tail -1 | tr -d 'M ')

    if [ -n "$BEST_MOUNT" ] && [ "$BEST_AVAIL" -gt "$ROOT_AVAIL_MB" ]; then
        DOCKER_DATA_DIR="${BEST_MOUNT}/docker-data"
        log "Partición con más espacio: $BEST_MOUNT (${BEST_AVAIL}MB libres)"
        warn "Moviendo Docker data-root a $DOCKER_DATA_DIR"

        sudo systemctl stop docker 2>/dev/null || true
        command -v rsync &>/dev/null || sudo apt-get install -y rsync
        sudo mkdir -p "$DOCKER_DATA_DIR"

        if [ -d /var/lib/docker ] && [ "$(sudo du -s /var/lib/docker 2>/dev/null | cut -f1)" -gt 0 ]; then
            sudo rsync -a /var/lib/docker/ "$DOCKER_DATA_DIR/"
        fi

        # Combinar con daemon.json existente si lo hay, preservando otras claves
        sudo mkdir -p /etc/docker
        if [ -f /etc/docker/daemon.json ]; then
            sudo python3 -c "
import json
path='/etc/docker/daemon.json'
try:
    with open(path) as f: cfg = json.load(f)
except Exception:
    cfg = {}
cfg['data-root'] = '$DOCKER_DATA_DIR'
with open(path,'w') as f: json.dump(cfg, f, indent=2)
"
        else
            echo "{\"data-root\": \"$DOCKER_DATA_DIR\"}" | sudo tee /etc/docker/daemon.json >/dev/null
        fi

        sudo systemctl start docker
        sleep 3
        log "Docker reconfigurado — Root Dir: $(docker info 2>/dev/null | grep 'Root Dir' | awk '{print $3}')"

        # Limpiar datos viejos solo si la copia fue exitosa
        NEW_SIZE=$(sudo du -s "$DOCKER_DATA_DIR" 2>/dev/null | cut -f1)
        if [ -n "$NEW_SIZE" ] && [ "$NEW_SIZE" -gt 0 ]; then
            sudo rm -rf /var/lib/docker
            log "Datos antiguos de Docker liberados en /"
        fi
    else
        warn "No se encontró partición con más espacio — continuando en ubicación por defecto"
    fi
else
    log "Espacio en disco OK (${ROOT_USE}% usado, ${ROOT_AVAIL_MB}MB libres)"
fi

# ── 3. .env ───────────────────────────────────────────────────────────────────
section "3/8 · Variables de entorno"
if [ ! -f .env ]; then
    cp .env.example .env
    log ".env creado desde .env.example"
else
    log ".env ya existe"
fi
chmod 600 .env
source .env

# ── 4. Usuario Mosquitto ──────────────────────────────────────────────────────
section "4/8 · Autenticación Mosquitto"
mkdir -p mosquitto/config
if [ ! -f mosquitto/config/passwd ]; then
    docker run --rm -v "$(pwd)/mosquitto/config:/mosquitto/config" eclipse-mosquitto:2.0 \
        mosquitto_passwd -b -c /mosquitto/config/passwd "$MQTT_USER" "$MQTT_PASSWORD"
    log "Usuario MQTT '$MQTT_USER' creado"
else
    log "passwd ya existe"
fi
# Mosquitto corre como uid 1883 dentro del contenedor — el archivo debe ser legible
sudo chmod 644 mosquitto/config/passwd 2>/dev/null || chmod 644 mosquitto/config/passwd

# ── 5. Inyectar token InfluxDB en nginx.conf ──────────────────────────────────
section "5/8 · Configurando proxy Nginx"
if grep -q "INFLUXDB_TOKEN_PLACEHOLDER" nginx/nginx.conf 2>/dev/null; then
    sed -i "s|INFLUXDB_TOKEN_PLACEHOLDER|${INFLUXDB_TOKEN}|g" nginx/nginx.conf
    log "Token InfluxDB inyectado en nginx.conf"
else
    log "nginx.conf ya configurado"
fi

# ── 6. mDNS — acceso por nombre local (sin recordar IP) ───────────────────────
section "6/8 · Configurando acceso por nombre (mDNS)"
if ! command -v avahi-daemon &>/dev/null; then
    warn "Instalando Avahi..."
    sudo apt-get update -qq
    sudo apt-get install -y avahi-daemon avahi-utils
fi

# Restringir a la interfaz WiFi si existe (evita conflictos con docker0/veth)
WIFI_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -E "^wlan" | head -1)
if [ -n "$WIFI_IF" ] && ! grep -q "allow-interfaces" /etc/avahi/avahi-daemon.conf 2>/dev/null; then
    sudo sed -i "/\[server\]/a allow-interfaces=${WIFI_IF}" /etc/avahi/avahi-daemon.conf
    log "Avahi restringido a interfaz $WIFI_IF"
fi

# Servicio mDNS del portal Ingenio+
sudo mkdir -p /etc/avahi/services
sudo tee /etc/avahi/services/ingenioplus.service >/dev/null << EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>Ingenio+ Raíz</name>
  <service>
    <type>_http._tcp</type>
    <port>8087</port>
    <txt-record>version=1.0</txt-record>
  </service>
</service-group>
EOF

sudo systemctl enable avahi-daemon --now 2>/dev/null
sudo systemctl restart avahi-daemon
log "Portal accesible como: ${HOSTNAME_LOCAL}:8087"

# ── 7. Levantar stack ─────────────────────────────────────────────────────────
section "7/8 · Levantando stack (ARM64 — primera descarga puede tardar)"
docker compose up -d
log "Stack iniciado"

# ── 8. Verificación de salud — Mosquitto suele fallar si passwd no es legible ─
section "8/8 · Verificando servicios"
sleep 8
MOSQ_STATUS=$(docker inspect -f '{{.State.Status}}' ingenio_mosquitto 2>/dev/null || echo "unknown")
if [ "$MOSQ_STATUS" != "running" ]; then
    warn "Mosquitto no está 'running' (estado: $MOSQ_STATUS) — reintentando con permisos corregidos"
    sudo chmod 644 mosquitto/config/passwd 2>/dev/null
    docker compose restart mosquitto
    sleep 5
fi
MOSQ_STATUS=$(docker inspect -f '{{.State.Status}}' ingenio_mosquitto 2>/dev/null || echo "unknown")
if [ "$MOSQ_STATUS" = "running" ]; then
    log "Mosquitto: running"
else
    warn "Mosquitto sigue con problemas — revisar: docker logs ingenio_mosquitto"
fi

# ── Resumen ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Ingenio+ Plan Raíz — Deploy completado       ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
printf "${GREEN}║  Portal:        http://%-30s║${NC}\n" "${HOSTNAME_LOCAL}:8087"
printf "${GREEN}║  Node-RED:      http://%-30s║${NC}\n" "${HOSTNAME_LOCAL}:1880"
printf "${GREEN}║  InfluxDB:      http://%-30s║${NC}\n" "${HOSTNAME_LOCAL}:8086"
printf "${GREEN}║  Grafana:       http://%-30s║${NC}\n" "${HOSTNAME_LOCAL}:3000"
printf "${GREEN}║  Home Assistant: http://%-29s║${NC}\n" "${HOSTNAME_LOCAL}:8123"
echo -e "${GREEN}║  MQTT:          mqtt://localhost:1883                ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
warn "Si el nombre .local no resuelve en Windows, agregar manualmente a"
warn "C:\\Windows\\System32\\drivers\\etc\\hosts:  <IP>  ${HOSTNAME_LOCAL}"
warn "Configurar datasource InfluxDB en Grafana manualmente (ver README)"