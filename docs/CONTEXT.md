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

---

## Tres planes de producto

### Plan 1 — Semilla (1-5 ha)
- **Hardware base:** WiFi Relay Module ESP32-WROOM-32E N4 (1-2 relés) + Wio-SX1262
- **Backend:** Todo embebido en el ESP32 — WebServer, motor reglas básico, portal cautivo
- **Dashboard:** HTML en PROGMEM servido por ESP32, acceso via WiFi local
- **Nodos campo:** XIAO ESP32-C3 + Wio-SX1262 (más económico)
- **Comunicación:** LoRa P2P 915MHz — nodo → receptor ESP32
- **Nube:** Opcional (Nube Ingenio+ por suscripción)
- **Firmware:** PlatformIO / Arduino ESP32 framework — carpeta `/plan1/`

### Plan 2 — Raíz (5-20 ha)
- **Hardware base:** Arduino UNO Q 4GB (Qualcomm QRB2210 + STM32U585) + Wio-SX1262
- **QRB2210:** Debian Linux + Docker — corre el stack de servicios
- **STM32U585:** Real-time MCU — receptor LoRa P2P + control relés RS485
- **Backend:** Docker 5 servicios — EMQX + InfluxDB + Node-RED + Home Assistant + Nginx
- **Dashboard:** HTML estático en Nginx, mismo diseño que Plan 3 pero JS diferente
- **Comunicación:** LoRa P2P 915MHz — nodo → STM32U585 → serial → QRB2210 → EMQX
- **Stack:** `/plan2/docker-compose.yml`

### Plan 3 — Cosecha (50+ ha)
- **Hardware base:** Mini PC Intel N2840 4GB RAM SSD 64GB + WM1302 USB LoRaWAN
- **OS:** Debian 13 x86_64 — hostname fijo: `ingenioplus`
- **Backend:** Docker 14 servicios — stack v12 completo
- **Dashboard:** HTML estático en Nginx:8087, conectado a OpenRemote + InfluxDB
- **Comunicación:** LoRaWAN 8 canales — nodo → WM1302 → ChirpStack → EMQX
- **Stack:** `/plan3/` (raíz actual del repo hasta reorganización)
- **Servidor actual:** IP 192.168.1.117

---

## Stack Plan 3 — v12 (14 servicios Docker)

```
EMQX 6.1.1              broker MQTT central — 1883/8083/18083
OpenRemote Manager      plataforma IoT: assets, reglas, actuadores — 8091
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
ChirpStack PostgreSQL   BD ChirpStack (requiere pg_trgm + hstore)
ChirpStack Redis        cache ChirpStack
```

### Accesos locales (mDNS)
```
http://ingenioplus.local/manager/  → OpenRemote (admin/linuxxl2)
http://ingenioplus.local:8087      → Portal cliente agricultor
http://ingenioplus.local:8090      → ChirpStack (admin/admin)
http://ingenioplus.local:3000      → Grafana
http://ingenioplus.local:18083     → EMQX dashboard
http://ingenioplus.local:1880      → Node-RED
http://ingenioplus.local:9000      → Portainer
```

### Deploy desde cero
```bash
git clone https://github.com/roserocarlos/ingenio /opt/ingenioplus
cd /opt/ingenioplus && sudo bash deploy.sh
```
Un solo comando — hostname fijo, Docker, permisos, stack completo, init.

---

## Arquitectura de datos

### Flujo LoRa P2P (Plan 1 y 2)
```
Sensor RS485/voltaje → Nodo XIAO ESP32-C3
  → LoRa P2P 915MHz
    → Receptor (ESP32 Plan1 / STM32U585 Plan2)
      → EMQX topic: ingenio/{finca_id}/{node_id}/up
        → OpenRemote MQTT Agent (Plan3) / directo (Plan2)
        → Node-RED → InfluxDB
```

### Flujo LoRaWAN (Plan 3)
```
Nodo LoRaWAN → WM1302 USB → lora_pkt_fwd (host) → UDP:1700
  → ChirpStack Gateway Bridge → EMQX (us915_0/gateway/{EUI}/event/up)
    → ChirpStack → EMQX (chirpstack/application/{id}/device/{eui}/event/up)
      → Node-RED → InfluxDB + OpenRemote
```

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
  "finca_id": "f01",
  "node_id": "s001",
  "ts": 1234567890,
  "soil_moisture": 68.5,
  "temperature": 22.4,
  "ph": 6.8,
  "nitrogen": 142.0,
  "phosphorus": 45.0,
  "potassium": 89.0,
  "battery": 87.0,
  "rssi": -72
}
```

---

## Dashboard — estado y pendientes

### Lo que funciona hoy (Plan 3)
- Mapa Leaflet con nodos coloreados ONLINE/DEGRADED/OFFLINE
- KPIs: humedad, temperatura, pH, batería en tiempo real via MQTT WebSocket
- Panel detalle con gráfica historial 24h desde InfluxDB
- Recomendación desde atributo OpenRemote
- Proxy Nginx resuelve CORS: /api/or/ → OpenRemote, /api/auth/ → Keycloak
- Autenticación Keycloak con Direct Access Grants habilitado

### Pendiente implementar (en orden de prioridad)

**Sesión 1 — JS puro, sin dependencias nuevas:**
- Índice de salud 0-100 (humedad 50% + batería 30% + RSSI 20%)
- Tendencia ↑↓ por KPI (query InfluxDB últimas 3h)
- Batería en días estimados (consumo diario de últimos 7 días)

**Sesión 2 — Node-RED + dashboard:**
- "¿Necesita regar hoy?" (flujo Node-RED → topic rec → dashboard)
- Alertas automáticas (humedad baja, batería crítica, nodo offline)
- Comparación con ayer (segunda query InfluxDB)

**Sesión 3 — Control:**
- Botón actuador (PUT OpenRemote REST + ACK MQTT WebSocket)
- Reglas WHEN-THEN en OpenRemote

**Sesión 4 — Escala:**
- Alertas WhatsApp (Node-RED + Twilio API)
- Multi-finca (realms OpenRemote)
- Panel Grafana admin técnico

---

## Firmware — estado

### Nodo de campo (compartido Plan 1, 2 y 3)
- Hardware: XIAO ESP32-C3 + Wio-SX1262
- Librería: RadioLib
- Frecuencia: 915 MHz LoRa P2P
- Payload: JSON con datos del sensor
- **Estado: pendiente desarrollo**
- Carpeta: `/firmware/nodo/`

### Receptor Plan 1
- Hardware: WiFi Relay Module ESP32 (receptor integrado)
- Firmware v1.8 estable: WebServer + reglas + portal cautivo
- Fix crítico: portalStop()/portalBegin() alrededor de WiFi.begin()
- Fix crítico: inputTask en FreeRTOS núcleo 0
- **Estado: firmware base listo, pendiente integración LoRa**
- Carpeta: `/plan1/`

### Receptor Plan 2
- Hardware: STM32U585 del Arduino UNO Q
- Recibe LoRa P2P → serial interno → QRB2210 → EMQX
- **Estado: pendiente desarrollo**
- Carpeta: `/firmware/receptor/plan2-stm32/`

### Receptor Plan 3
- Hardware: XIAO ESP32-S3 + Wio-SX1262 (receptor dedicado)
- O directamente: nodos LoRaWAN → WM1302 USB
- **Estado: WM1302 compilado y funcionando, nodos LoRaWAN pendiente**
- EUI gateway: 0016C001F11A7BD1

---

## Fixes críticos conocidos (NO olvidar en nuevas instalaciones)

```
1. KC_HOSTNAME NO puede coexistir con KC_HOSTNAME_URL en Keycloak
   → Solo usar KC_HOSTNAME_URL en docker-compose.yml

2. ChirpStack v4 requiere extensiones PostgreSQL antes de arrancar
   → CREATE EXTENSION pg_trgm; CREATE EXTENSION hstore;
   → Ya incluido en 001-init-chirpstack.sql

3. ChirpStack imagen usar 4.9.0 no :4 (latest rompe migraciones)
   → image: chirpstack/chirpstack:4.9.0

4. OpenRemote PostgreSQL usa UID 70 (no 999 ni 1000)
   → chown -R 70:70 openremote/data/postgresql

5. Nginx proxy OpenRemote debe reescribir el header Origin
   → proxy_set_header Origin http://ingenioplus.local;

6. Keycloak Direct Access Grants deshabilitado por defecto
   → setup_keycloak_uris.sh lo habilita automáticamente

7. Node-RED payload ya viene parseado como objeto
   → NO usar JSON.parse(msg.payload) — falla con [object Object]

8. InfluxDB node-red-contrib-influxdb formato v2:
   → msg.payload = [{ fields... }, { tags... }]
   → msg.measurement = 'sensor_data'
   → Time Precision: Milliseconds

9. pip3 en Debian 13 requiere --break-system-packages
   → pip3 install paho-mqtt --break-system-packages
```

---

## Estructura del repositorio

```
roserocarlos/ingenio (privado)
│
├── deploy.sh                    ← Plan 3: deploy en un comando
├── docker-compose.yml           ← Plan 3: 14 servicios
├── .env.example                 ← credenciales por defecto
├── setup_servidor.sh            ← configuración servidor Debian
├── caddy/Caddyfile              ← proxy :80
├── chirpstack/configuration/    ← ChirpStack v4 US915
├── keycloak/keycloak.conf       ← modo local sin TLS
├── nginx/nginx.conf             ← proxy APIs + portal
├── nginx/html/index.html        ← portal cliente Plan 3
├── grafana/provisioning/        ← datasources Grafana
├── scripts/
│   ├── deploy.sh                ← orquestador principal
│   ├── init_influxdb.sh         ← token + Keycloak URIs
│   ├── setup_keycloak_uris.sh   ← Direct Access Grants
│   ├── setup_wm1302.sh          ← packet forwarder WM1302
│   └── simulador_sensor.py      ← datos de prueba EMQX
│
├── plan2/                       ← Plan Raíz (en desarrollo)
├── plan1/                       ← Plan Semilla (en desarrollo)
├── firmware/                    ← nodos y receptores LoRa
│
└── docs/
    ├── CONTEXT.md               ← este archivo
    ├── producto_cliente.md      ← características para el agricultor
    └── producto_tecnico.md      ← especificación técnica por plan
```

---

## Tecnologías y versiones clave

```
Docker:           29.4.3
Docker Compose:   5.1.3
Debian:           13 (Trixie) x86_64
EMQX:             6.1.1
OpenRemote:       latest (Manager + Keycloak 23.0.7)
InfluxDB:         2.x
ChirpStack:       4.9.0
Node-RED:         latest
Grafana:          latest
Caddy:            2
node-red-contrib-influxdb: 2.x (versión 2.0 en configuración)
sx1302_hal:       2.1.0 (TX_JIT_DELAY: 120000)
PlatformIO:       Arduino ESP32 framework
RadioLib:         última estable
```

---

## Credenciales por defecto (.env.example)

```
OR_HOSTNAME=ingenioplus.local
OR_ADMIN_PASSWORD=linuxxl2
EMQX_DASHBOARD_USER=ingenio
EMQX_DASHBOARD_PASSWORD=linuxxl2
INFLUXDB_ADMIN_USER=ingenio
INFLUXDB_ADMIN_PASSWORD=linuxxl2
INFLUXDB_ORG=agrosensor
INFLUXDB_BUCKET=sensores
NODE_RED_CREDENTIAL_SECRET=ingenio
```
Token InfluxDB: generado automáticamente por init_influxdb.sh

---

## Contacto y contexto de negocio

- **Desarrollador:** Carlos Rosero — Ipiales, Nariño, Colombia
- **Segmento:** Agricultores de papa, hortalizas y café, fincas 1-50+ ha
- **Competidores Colombia:** Agrometer (palma, Casanare), Libelium, Precisagro
- **Ventaja competitiva:** Offline-first + precio accesible + lenguaje del agricultor
- **Modelo negocio:** Pago único hardware + instalación, suscripción opcional Nube Ingenio+
- **GitHub:** https://github.com/roserocarlos/ingenio (privado)

---

*Actualizado: Mayo 2026 — Stack v12 — Plan 3 en producción*
*Próximo hito: primer agricultor viendo su finca con datos reales*
