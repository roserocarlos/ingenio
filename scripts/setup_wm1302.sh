#!/bin/bash
# =============================================================================
# Ingenio+ — Configurar y lanzar WM1302 USB packet forwarder
# Ejecutar en el HOST (no en Docker) porque necesita acceso a /dev/ttyACM0
#
# Prerequisitos:
#   - sx1302_hal compilado en ~/sx1302_hal
#   - WM1302 USB conectado en /dev/ttyACM0
#   - ChirpStack Gateway Bridge corriendo en Docker (puerto 1700)
#
# Uso: bash scripts/setup_wm1302.sh [start|stop|status]
# =============================================================================

set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

HAL_DIR="$HOME/sx1302_hal"
PKT_FWD="$HAL_DIR/packet_forwarder"
CONFIG="global_conf.json.sx1250.US915.USB"
PID_FILE="/tmp/lora_pkt_fwd.pid"
LOG_FILE="/tmp/lora_pkt_fwd.log"

# EUI real del concentrador WM1302
GATEWAY_EUI="0016C001F11A7BD1"

check_hardware() {
    if [ ! -e /dev/ttyACM0 ]; then
        err "WM1302 no detectado en /dev/ttyACM0 — verificar conexión USB"
    fi
    log "WM1302 detectado en /dev/ttyACM0"
}

check_hal() {
    if [ ! -f "$PKT_FWD/lora_pkt_fwd" ]; then
        err "sx1302_hal no compilado — ejecutar primero: cd ~/sx1302_hal && make"
    fi
    log "sx1302_hal OK: $PKT_FWD/lora_pkt_fwd"
}

configure() {
    cd "$PKT_FWD"

    log "Configurando global_conf.json para WM1302 US915..."

    python3 -c "
import json, sys

with open('$CONFIG') as f:
    conf = json.load(f)

# Corregir gateway_ID con EUI real del WM1302
conf['gateway_conf']['gateway_ID'] = '$GATEWAY_EUI'

# Puerto 1700 — ChirpStack Gateway Bridge en Docker
conf['gateway_conf']['server_address'] = 'localhost'
conf['gateway_conf']['serv_port_up']   = 1700
conf['gateway_conf']['serv_port_down'] = 1700

# Puerto USB correcto
conf['SX130x_conf']['com_path'] = '/dev/ttyACM0'

with open('$CONFIG', 'w') as f:
    json.dump(conf, f, indent=4)

print('Configuración actualizada')
print(f'  gateway_ID:     $GATEWAY_EUI')
print(f'  server:         localhost:1700')
print(f'  com_path:       /dev/ttyACM0')
"
    log "global_conf.json configurado"
}

start() {
    check_hardware
    check_hal
    configure

    if [ -f "$PID_FILE" ] && kill -0 "$(cat $PID_FILE)" 2>/dev/null; then
        warn "El packet forwarder ya está corriendo (PID: $(cat $PID_FILE))"
        return
    fi

    cd "$PKT_FWD"
    log "Iniciando lora_pkt_fwd..."
    sudo nohup ./lora_pkt_fwd -c "$CONFIG" > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    sleep 3

    if kill -0 "$(cat $PID_FILE)" 2>/dev/null; then
        log "Packet forwarder iniciado (PID: $(cat $PID_FILE))"
        log "Logs: tail -f $LOG_FILE"
        log "EUI del gateway: $GATEWAY_EUI"
        echo ""
        echo "  Próximo paso: registrar el gateway en ChirpStack"
        echo "    http://ingenioplus.local:8090"
        echo "    EUI: $GATEWAY_EUI"
    else
        err "El packet forwarder falló — ver: cat $LOG_FILE"
    fi
}

stop() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            sudo kill "$PID"
            rm -f "$PID_FILE"
            log "Packet forwarder detenido"
        else
            warn "El proceso no estaba corriendo"
            rm -f "$PID_FILE"
        fi
    else
        warn "No hay PID guardado"
    fi
}

status() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat $PID_FILE)" 2>/dev/null; then
        log "Packet forwarder CORRIENDO (PID: $(cat $PID_FILE))"
        echo ""
        tail -5 "$LOG_FILE" 2>/dev/null || true
    else
        warn "Packet forwarder DETENIDO"
    fi

    echo ""
    log "Estado ChirpStack Gateway Bridge:"
    docker logs chirpstack-gateway-bridge --tail=5 2>/dev/null || warn "Contenedor no disponible"
}

install_service() {
    cat > /etc/systemd/system/ingenio-lora.service << EOF
[Unit]
Description=Ingenio+ LoRa Packet Forwarder WM1302
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$PKT_FWD
ExecStart=$PKT_FWD/lora_pkt_fwd -c $CONFIG
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable ingenio-lora
    log "Servicio systemd instalado: ingenio-lora"
    log "Para iniciar: systemctl start ingenio-lora"
}

case "${1:-start}" in
    start)   start ;;
    stop)    stop ;;
    status)  status ;;
    install) install_service ;;
    *)
        echo "Uso: bash scripts/setup_wm1302.sh [start|stop|status|install]"
        echo "  start   — configura y lanza el packet forwarder"
        echo "  stop    — detiene el packet forwarder"
        echo "  status  — ver estado y últimos logs"
        echo "  install — instalar como servicio systemd (arranque automático)"
        ;;
esac
