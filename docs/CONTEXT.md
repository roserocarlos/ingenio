# CONTEXT.md — Ingenio+ · Contexto completo del proyecto

> Este archivo permite a cualquier asistente de IA entender el proyecto
> y continuar el desarrollo sin perder contexto.
> Mantenerlo actualizado en cada sesión importante.

---

## ¿Qué es Ingenio+?

Plataforma de monitoreo agrícola IoT para fincas de papa, hortalizas y café
en Boyacá y Nariño, Colombia. Permite al agricultor saber el estado de su finca
desde el celular, sin internet en el campo, usando radio LoRa 915MHz.

**Dominio:** ingenio.plus
**Ubicación:** Ipiales, Nariño, Colombia
**Estado:** En desarrollo activo — primer agricultor como objetivo inmediato
**Repo:** https://github.com/roserocarlos/ingenio (privado)

---

## Estructura del repositorio

```
ingenio/
├── cosecha/     Plan 3 — Mini PC N2840 + WM1302 (stack v12, 14 servicios)
├── raiz/        Plan 2 — Arduino UNO Q 4GB (stack ligero, en desarrollo)
├── semilla/     Plan 1 — ESP32 embebido (firmware PlatformIO, en desarrollo)
├── firmware/    Nodos y receptores LoRa (compartido entre planes)
└── docs/        Documentación técnica y de producto
```

---

## Tres planes de producto

### Plan 1 — Semilla (1-5 ha) · carpeta: `semilla/`
- **Hardware base:** WiFi Relay Module ESP32-WROOM-32E N4 (1-2 relés) + Wio-SX1262
- **Backend:** Todo embebido en el ESP32
- **Dashboard:** HTML en PROGMEM servido por WebServer ESP32
- **Nodos campo:** XIAO ESP32-C3 + Wio-SX1262
- **Comunicación:** LoRa P2P 915MHz
- **Firmware:** PlatformIO / Arduino ESP32 — `semilla/src/`

### Plan 2 — Raíz (5-20 ha) · carpeta: `raiz/`
- **Hardware base:** Arduino UNO Q 4GB (QRB2210 + STM32U585) + Wio-SX1262
- **QRB2210:** Debian Linux + Docker — corre el stack
- **STM32U585:** Real-time MCU — receptor LoRa P2P + control relés
- **Backend:** Docker 5 servicios — EMQX + InfluxDB + Node-RED + Home Assistant + Nginx
- **Comunicación:** LoRa P2P → STM32U585 → serial → QRB2210 → EMQX

### Plan 3 — Cosecha (50+ ha) · carpeta: `cosecha/`
- **Hardware base:** Mini PC Intel N2840 4GB RAM SSD 64GB + WM1302 USB LoRaWAN
- **OS:** Debian 13 x86_64 — hostname fijo: `ingenioplus`
- **Backend:** Docker 14 servicios — stack v12 completo
- **Comunicación:** LoRaWAN 8 canales — WM1302 → ChirpStack → EMQX
- **Servidor actual:** IP 192.168.1.117

---

## Stack Plan 3 — v12 (14 servicios Docker)

```
EMQX 6.1.1              broker MQTT — 1883/8083/18083
OpenRemote Manager      plataforma IoT — 8091
OpenRemote Keycloak     autenticación OAuth2 — 8093
OpenRemote PostgreSQL   BD OpenRemote (UID 70 crítico)
InfluxDB v2             historial series temporales — 8086
Node-RED                EMQX→InfluxDB + alertas — 1880
Grafana OSS             dashboard admin técnico — 3000
Nginx                   portal cliente + proxy APIs — 8087
Caddy                   proxy unificado :80
Portainer               gestión Docker — 9000
ChirpStack v4.9.0       LNS LoRaWAN — 8090
ChirpStack GW Bridge    Semtech UDP → EMQX — UDP:1700
ChirpStack PostgreSQL   BD ChirpStack (pg_trgm + hstore)
ChirpStack Redis        cache ChirpStack
```

### Accesos locales
```
http://ingenioplus.local/manager/  → OpenRemote (admin/linuxxl2)
http://ingenioplus.local:8087      → Portal cliente
http://ingenioplus.local:8090      → ChirpStack (admin/admin)
http://ingenioplus.local:3000      → Grafana
http://ingenioplus.local:18083     → EMQX
http://ingenioplus.local:1880      → Node-RED
http://ingenioplus.local:9000      → Portainer
```

### Deploy desde cero
```bash
git clone --no-checkout https://github.com/roserocarlos/ingenio /opt/ingenioplus
cd /opt/ingenioplus
git sparse-checkout init
git sparse-checkout set cosecha docs
git checkout main
cd cosecha && sudo bash deploy.sh
```

---

## Arquitectura de datos

### Topics EMQX
```
ingenio/{finca_id}/{node_id}/up   ← datos sensor uplink
ingenio/{finca_id}/{node_id}/cmd  ← comando actuador downlink
ingenio/{finca_id}/{node_id}/ack  ← confirmación actuador
ingenio/{finca_id}/alertas        ← alertas Node-RED → dashboard
ingenio/{finca_id}/{node_id}/rec  ← recomendación de riego
```

### Payload sensor (JSON)
```json
{
  "finca_id": "f01", "node_id": "s001", "ts": 1234567890,
  "soil_moisture": 68.5, "temperature": 22.4, "ph": 6.8,
  "nitrogen": 142.0, "phosphorus": 45.0, "potassium": 89.0,
  "battery": 87.0, "rssi": -72
}
```

### Flujo Node-RED verificado (EMQX → InfluxDB)
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

---

## Dashboard — estado actual (Plan 3)

### Funciona hoy
- Mapa Leaflet con nodos ONLINE/DEGRADED/OFFLINE
- KPIs tiempo real via MQTT WebSocket ws://host:8083/mqtt
- Historial 24h desde InfluxDB via proxy /api/historial
- Recomendación desde atributo OpenRemote
- Autenticación Keycloak con Direct Access Grants

### Pendiente (en orden)
```
Sesión 1 — JS puro:
  ⬜ Índice salud 0-100 (humedad 50% + batería 30% + RSSI 20%)
  ⬜ Tendencia ↑↓ (query InfluxDB últimas 3h)
  ⬜ Batería en días estimados

Sesión 2 — Node-RED + dashboard:
  ⬜ ¿Regar hoy? (Node-RED → topic rec → dashboard)
  ⬜ Alertas automáticas (humedad, batería, offline)
  ⬜ Comparación con ayer

Sesión 3 — Control:
  ⬜ Botón actuador (PUT OpenRemote + ACK MQTT)
  ⬜ Reglas WHEN-THEN OpenRemote

Sesión 4 — Escala:
  ⬜ Alertas WhatsApp (Twilio + Node-RED)
  ⬜ Multi-finca (realms OpenRemote)
```

---

## Firmware — estado

```
nodo/           XIAO ESP32-C3 + Wio-SX1262 — pendiente desarrollo
receptor/esp32  WiFi Relay Module — firmware v1.8 base listo
receptor/stm32  STM32U585 Arduino UNO Q — pendiente
receptor/xiao   XIAO ESP32-S3 — pendiente
receptor/techolite T-Echo Lite — candidato nodo Plan 2/3
```

---

## Fixes críticos (NO olvidar en nuevas instalaciones)

```
1. KC_HOSTNAME no puede coexistir con KC_HOSTNAME_URL
   → Solo usar KC_HOSTNAME_URL en docker-compose.yml

2. ChirpStack v4 requiere pg_trgm + hstore antes de arrancar
   → Incluido en cosecha/chirpstack/configuration/postgresql/initdb/

3. Usar chirpstack/chirpstack:4.9.0 no :4 (latest rompe migraciones)

4. OpenRemote PostgreSQL usa UID 70 (no 999 ni 1000)
   → chown -R 70:70 openremote/data/postgresql

5. Nginx proxy OpenRemote debe reescribir header Origin
   → proxy_set_header Origin http://ingenioplus.local

6. Keycloak Direct Access Grants deshabilitado por defecto
   → setup_keycloak_uris.sh lo habilita automáticamente

7. Node-RED payload ya viene parseado — NO usar JSON.parse()

8. InfluxDB node-red-contrib-influxdb v2:
   → msg.payload = [{ fields }, { tags }]
   → msg.measurement = 'sensor_data'
   → Time Precision: Milliseconds

9. pip3 en Debian 13: pip3 install X --break-system-packages
```

---

## Credenciales por defecto

```
OR_HOSTNAME=ingenioplus.local
OR_ADMIN_PASSWORD=linuxxl2
EMQX_DASHBOARD_USER=ingenio / PASSWORD=linuxxl2
INFLUXDB_ADMIN_USER=ingenio / PASSWORD=linuxxl2
INFLUXDB_ORG=agrosensor / BUCKET=sensores
ChirpStack: admin / admin
Token InfluxDB: generado por init_influxdb.sh
```

---

## Contexto de negocio

- **Desarrollador:** Carlos Rosero — Ipiales, Nariño, Colombia
- **Segmento:** Agricultores papa, hortalizas, café — fincas 1-50+ ha
- **Ventaja competitiva:** Offline-first + precio accesible + lenguaje agricultor
- **Modelo negocio:** Pago único hardware + instalación + suscripción Nube Ingenio+
- **Competidores Colombia:** Agrometer, Libelium, Precisagro

---

*Actualizado: Mayo 2026 — Stack v12 — Plan 3 en producción*
*Próximo hito: primer agricultor viendo su finca con datos reales*
