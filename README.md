# Ingenio+ — Stack IoT Agrícola v11

Plataforma de monitoreo agrícola con LoRa P2P 915 MHz + LoRaWAN (WM1302).
Nariño, Colombia · Plan Cosecha (Mini PC N2840 + WM1302 USB)

## Arquitectura

```
WM1302 USB → lora_pkt_fwd → UDP:1700
  → chirpstack-gateway-bridge → EMQX (us915_0/gateway/...)
    → ChirpStack → EMQX (chirpstack/application/.../event/up)
      → Node-RED → InfluxDB + OpenRemote

Receptor XIAO ESP32-S3 → LoRa P2P → EMQX (ingenio/f01/s001/up)
  → OpenRemote MQTT Agent + Node-RED → InfluxDB
```

## Accesos locales (mDNS)

| Servicio | URL |
|---|---|
| OpenRemote Manager | http://ingenioplus.local/manager/ |
| ChirpStack | http://ingenioplus.local:8090 |
| Grafana | http://ingenioplus.local:3000 |
| EMQX Dashboard | http://ingenioplus.local:18083 |
| Node-RED | http://ingenioplus.local:1880 |
| InfluxDB | http://ingenioplus.local:8086 |
| Portal cliente | http://ingenioplus.local:8087 |
| Portainer | http://ingenioplus.local:9000 |

## Instalación desde cero

```bash
cd /opt && tar -xzf ingenioplus_stack_v11.tar.gz && cd ingenioplus
sudo bash setup_servidor.sh
source /root/.bashrc
ingenio up
sleep 300 && bash scripts/init_influxdb.sh
```

## WM1302 USB (LoRaWAN Gateway)

```bash
# Compilar sx1302_hal (una vez)
cd ~ && git clone https://github.com/Lora-net/sx1302_hal && cd sx1302_hal
sed -i 's/TX_JIT_DELAY            40000/TX_JIT_DELAY            120000/' packet_forwarder/src/jitqueue.c
make

# Iniciar packet forwarder
bash /opt/ingenioplus/scripts/setup_wm1302.sh start

# Registrar gateway en ChirpStack UI
# http://ingenioplus.local:8090
# EUI: 0016C001F11A7BD1
```

## Aliases disponibles

```bash
ingenio up/down/ps    # gestionar stack
ingenio-or            # logs OpenRemote
ingenio-emqx          # logs EMQX
ingenio-nr            # logs Node-RED
ingenio-influx        # logs InfluxDB
ingenio-chirp         # logs ChirpStack
ingenio-sim           # simulador sensores
cdingenia             # ir a /opt/ingenioplus
```

## Flujo de datos Node-RED verificado

**Función EMQX → InfluxDB:**
```javascript
const parts = msg.topic.split('/');
const finca_id = parts[1], node_id = parts[2], tipo = parts[3];
if (tipo !== 'up') return null;
const payload = msg.payload;
const ts = payload.ts ? payload.ts * 1000 : Date.now();
msg.payload = [
  { soil_moisture: payload.soil_moisture||0, temperature: payload.temperature||0,
    ph: payload.ph||0, nitrogen: payload.nitrogen||0, phosphorus: payload.phosphorus||0,
    potassium: payload.potassium||0, battery: payload.battery||0, rssi: payload.rssi||0,
    time: ts },
  { finca_id, node_id }
];
msg.measurement = 'sensor_data';
return msg;
```

## Credenciales por defecto

Ver archivo `.env` en el servidor.
