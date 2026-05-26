# Ingenio+ — Especificación técnica por plan

> Referencia de implementación: plataforma, función y estado por característica.
> Comparar con `producto_cliente.md` para alineación comercial/técnica.

---

## Arquitectura general

```
Plan 1 Semilla     Plan 2 Raíz          Plan 3 Cosecha
─────────────      ───────────────      ──────────────────────
ESP32 embebido     Arduino UNO Q 4GB    Mini PC N2840 + WM1302
                   QRB2210 + STM32U585
                   
WebServer local    Docker 5 servicios   Docker 14 servicios
HTML en PROGMEM    Portal HTML Nginx     Portal HTML Nginx
Sin historial      InfluxDB local       InfluxDB + OpenRemote
Reglas básicas     Node-RED + HA        Node-RED + OR WHEN-THEN
LoRa P2P receptor  LoRa P2P receptor    LoRaWAN 8ch WM1302
1-2 relés          8 relés STM32U585    Actuadores via OpenRemote
```

---

## Plan 1 — Semilla

**Hardware:** WiFi Relay Module ESP32-WROOM-32E N4 + Wio-SX1262
**Firmware:** PlatformIO / Arduino ESP32 framework
**Dashboard:** HTML embebido en PROGMEM, servido por WebServer ESP32

### Características implementadas

---

### 1.1 Dashboard local embebido

**Función cliente:** Ver estado de la finca desde el celular en red WiFi local

**Implementación:**
```
Plataforma: WebServer ESP32 (puerto 80)
Archivo:    ui.h — HTML/CSS/JS en PROGMEM (chunks de 512 bytes)
Datos:      GET /api/status → JSON con estados relés, entradas, sensores
Actualización: polling cada 2s desde el frontend
Acceso:     http://192.168.4.1 (modo AP) o IP local (modo STA)
```

**Estado:** ✅ Implementado en firmware v1.8

---

### 1.2 Control de relés (1-2 salidas)

**Función cliente:** Prender/apagar bomba desde el celular con temporizador

**Implementación:**
```
Plataforma: WebServer ESP32
Endpoint:   POST /api/output → { output: 0, state: true, duration: 1800 }
Endpoint:   POST /api/outputs → batch de múltiples salidas
Endpoint:   GET /api/alloff → apagar todas
Hardware:   Bus RS485 PCF8574 → relés físicos
Temporizador: outputTimer[] en loop() — apaga automáticamente
```

**Estado:** ✅ Implementado en firmware v1.8

---

### 1.3 Motor de reglas básico

**Función cliente:** Automatización simple: si humedad baja → activar bomba

**Implementación:**
```
Plataforma: rulesEngine (C++ embebido, archivo rules_engine.h)
Capacidad:  Reglas simples IF sensor > umbral THEN activar salida
Evaluación: cada RULE_EVAL_MS (5s) en loop() núcleo 1
Persistencia: Preferences ESP32 (NVS flash)
API:        GET/POST /api/rules — CRUD de reglas via JSON
Limitación: Sin historial, sin reglas temporales complejas
```

**Estado:** ✅ Implementado en firmware v1.8

---

### 1.4 Portal cautivo WiFi

**Función cliente:** Configuración inicial de red WiFi sin PC

**Implementación:**
```
Plataforma: captive_portal.h — DNSServer + WebServer rutas adicionales
Modo:       WiFi AP (SSID: Ingenio-XXXXXX, sin contraseña inicial)
Rutas:      /portal → formulario de configuración
            POST /api/wifi/connect → conectar a red del agricultor
Credenciales: guardadas en Preferences ESP32 (NVS)
Limitación: No usar DNSServer simultáneo con WiFi.begin() → crash AsyncUDP
Fix v1.8:   portalStop()/portalBegin() alrededor de WiFi.begin()
```

**Estado:** ✅ Implementado y estabilizado en firmware v1.8

---

### 1.5 Receptor LoRa P2P

**Función cliente:** Recibir datos de nodos de campo sin internet

**Implementación:**
```
Hardware:   Wio-SX1262 conectado al ESP32 via SPI
Librería:   RadioLib
Frecuencia: 915 MHz (Colombia)
Protocolo:  LoRa P2P (no LoRaWAN) — simétrico con nodos XIAO ESP32-C3
Payload:    JSON comprimido → { node_id, soil_moisture, temperature, battery }
Acción:     Actualiza estado interno → visible en /api/status
Nube:       Si WiFi conectado → publica en EMQX topic ingenio/{finca}/{node}/up
```

**Estado:** ⬜ Pendiente implementar (firmware nodo en desarrollo)

---

### Lo que el Plan 1 NO implementa deliberadamente

```
❌ Historial de datos — sin InfluxDB, sin almacenamiento
❌ Alertas remotas — sin conexión permanente a internet
❌ Control >2 relés complejos — heap ESP32 limitado
❌ Motor de reglas temporales avanzadas — memoria insuficiente
❌ Dashboard con gráficas históricas — sin datos históricos
```

**Argumento de venta hacia Plan 2:**
El agricultor que quiere historial, automatizaciones avanzadas
y múltiples sensores necesita el salto de hardware del Plan Raíz.

---

## Plan 2 — Raíz

**Hardware:** Arduino UNO Q 4GB (QRB2210 + STM32U585) + Wio-SX1262
**OS:** Debian Linux (QRB2210) + Zephyr/Arduino (STM32U585)
**Stack:** Docker Compose — 5 servicios
**Dashboard:** HTML estático servido por Nginx, mismo diseño que Plan 3

### Stack Docker Plan 2

```yaml
# docker-compose.raiz.yml
services:
  emqx:          broker MQTT central — puerto 1883/8083/18083
  influxdb:      historial series temporales — puerto 8086
  nodered:       transformación EMQX→InfluxDB + reglas — puerto 1880
  homeassistant: automatizaciones offline — puerto 8123
  nginx:         portal cliente + proxy APIs — puerto 8087
```

**RAM estimada en reposo:** ~1.8GB de 4GB disponibles ✅

---

### 2.1 Dashboard con historial

**Función cliente:** Ver estado + gráfica últimas 24h + comparación con ayer

**Implementación:**
```
Plataforma: Nginx (porta 8087) — sirve index.html estático
Datos tiempo real: MQTT WebSocket → ws://localhost:8083/mqtt
                   Suscribe a topics ingenio/#
Datos históricos:  Fetch POST /api/historial (proxy Nginx → InfluxDB)
                   Query Flux: range(-24h), aggregateWindow(1h)
Datos ayer:        Segunda query Flux: range(-25h, -23h) → mean()
Autenticación:     Sin OAuth — red local privada del agricultor
Frontend:          Chart.js para gráficas, Leaflet para mapa
```

**Estado:** ⬜ Pendiente — mismo HTML que Plan 3 con config.js diferente

---

### 2.2 "¿Necesita regar hoy?" — Motor de recomendación

**Función cliente:** Respuesta directa Sí/No con acción concreta

**Implementación:**
```
Plataforma: Node-RED (flujo de evaluación)
Lógica:
  Nodo function evalúa payload entrante de EMQX:
  SI soil_moisture < 30 por 2 lecturas → publicar recomendación URGENTE
  SI soil_moisture < 45 → publicar recomendación HOY
  SI tendencia_caida > 5%/hora → calcular tiempo estimado
  SI soil_moisture > 70 → publicar NO REGAR

Topic salida: ingenio/{finca}/{node}/rec
  Payload: { recommendation: "...", urgency: "high|medium|low" }

Dashboard suscribe al topic rec via MQTT WebSocket
Renderiza texto en panel de detalle del nodo
```

**Estado:** ⬜ Pendiente — flujo Node-RED + suscripción en dashboard

---

### 2.3 Índice de salud por nodo

**Función cliente:** Número 0-100 + semáforo verde/amarillo/rojo

**Implementación:**
```
Plataforma: JavaScript frontend (cálculo en el navegador)
Fórmula:
  hum_score  = normalizar soil_moisture en rango óptimo 40-70%
  bat_score  = battery / 100
  rssi_score = normalizar rssi entre -60 (100%) y -110 (0%)
  health     = (hum_score*0.5) + (bat_score*0.3) + (rssi_score*0.2)

Escala:
  80-100 → verde  → "Su finca está bien"
  50-79  → amarillo → "Hay algo que revisar"
  0-49   → rojo   → "Necesita actuar hoy"

Actualización: cada mensaje MQTT recibido
```

**Estado:** ⬜ Pendiente — función JS puro, sin dependencias nuevas

---

### 2.4 Tendencia ↑↓ por KPI

**Función cliente:** Flecha que muestra si el suelo está mejorando o empeorando

**Implementación:**
```
Plataforma: InfluxDB query + JavaScript frontend
Query Flux:
  from(bucket:"sensores")
  |> range(start:-3h)
  |> filter(fn:(r) => r.node_id == "{id}" and r._field == "soil_moisture")
  |> first() → valor hace 3h
  + last()   → valor actual
  diferencia = actual - hace3h

Renderizado:
  diferencia > +2%  → flecha ↑ verde
  diferencia < -2%  → flecha ↓ roja
  entre -2% y +2%   → punto → estable

Implementación: query al abrir detalle del nodo, icono junto al KPI
```

**Estado:** ⬜ Pendiente — query InfluxDB + icono en dpBody

---

### 2.5 Alertas automáticas

**Función cliente:** Avisos con causa y acción recomendada

**Implementación:**
```
Plataforma: Node-RED (flujo watchdog + evaluación)
Flujos:

  A. Humedad baja:
     Trigger: soil_moisture < 30 en 2 lecturas consecutivas
     Publica: ingenio/{finca}/alertas
     Payload: { type:"LOW_MOISTURE", node:"s001", value:28,
                msg:"Humedad baja en Lote Norte — regar 30 min hoy" }

  B. Batería crítica:
     Trigger: battery < 20
     Payload: { type:"LOW_BATTERY", node:"s001", value:18,
                msg:"Batería crítica en s001 — revisar panel solar" }

  C. Nodo offline:
     Trigger: timestamp watchdog — sin mensaje > 60 min
     Payload: { type:"NODE_OFFLINE", node:"s001", elapsed:75,
                msg:"s001 sin señal 75 min — verificar alimentación" }

  D. Suelo saturado:
     Trigger: soil_moisture > 85
     Payload: { type:"SATURATED", node:"s001", value:88,
                msg:"Suelo saturado — suspender riego" }

Dashboard: suscribe a ingenio/{finca}/alertas via MQTT WS
           renderiza en panel alertas con color por severidad
```

**Estado:** ⬜ Pendiente — flujos Node-RED + suscripción dashboard

---

### 2.6 Control de actuadores

**Función cliente:** Botón de riego con confirmación y temporizador regresivo

**Implementación:**
```
Plataforma: MQTT → Node-RED → STM32U585 → relé físico
Flujo:
  Dashboard → MQTT publish ingenio/{finca}/{node}/cmd
  Payload: { action:"OPEN", duration_min:30, ts:1234567890 }

  Node-RED recibe CMD → reenvía a STM32U585 via serial USB interno
  STM32U585 activa relé → responde ACK

  ACK topic: ingenio/{finca}/{node}/ack
  Payload:   { status:"CONFIRMED", action:"OPEN", ts:1234567890 }

Estados UI:
  IDLE      → botón "Activar riego" verde
  PENDING   → "Enviando..." amarillo spinner (timeout 30s)
  CONFIRMED → "Riego activo — 28 min restantes" contador regresivo
  ERROR     → "Sin respuesta" rojo, permitir reintento

STM32U585: firmware Arduino/Zephyr — recibe serial, activa GPIO relé
```

**Estado:** ⬜ Pendiente — botón dashboard + flujo Node-RED + firmware STM32

---

### 2.7 Automatizaciones offline — Home Assistant

**Función cliente:** El sistema actúa solo aunque no haya internet

**Implementación:**
```
Plataforma: Home Assistant Docker (puerto 8123)
            Integración MQTT → suscribe a EMQX local
Automatización ejemplo:
  trigger:   MQTT topic ingenio/f01/s001/up, soil_moisture < 30
  condition: time between 06:00 and 20:00
  action:    MQTT publish ingenio/f01/s001/cmd
             { action:"OPEN", duration_min:45 }

Ventaja vs Plan 1: reglas temporales, condiciones complejas,
                   historial de ejecuciones, UI web de configuración
Ventaja vs Plan 3: sin OpenRemote overhead — más liviano para ARM

Configuración: /opt/homeassistant/config/automations.yaml
               editable desde UI http://localhost:8123
```

**Estado:** ⬜ Pendiente — imagen Docker HA + integración MQTT + automatización base

---

### Lo que el Plan 2 NO implementa deliberadamente

```
❌ LoRaWAN multi-canal — solo LoRa P2P, un canal
   → Plan 3: WM1302 USB, 8 canales, 50+ nodos simultáneos

❌ OpenRemote — overhead innecesario para ARM A53
   → Plan 3: assets, reglas WHEN-THEN, multi-tenant, API completa

❌ ChirpStack — sin LNS, sin OTAA/ABP
   → Plan 3: red LoRaWAN privada certificable

❌ Multi-finca desde un servidor
   → Plan 3: múltiples realms OpenRemote en N2840

❌ Puertos RS232/RS485 industriales nativos
   → Plan 3: Mini PC N2840 con puertos físicos incluidos

❌ Historial para certificaciones de exportación
   → Plan 3: SSD 64GB + OpenRemote + InfluxDB largo plazo

❌ Alertas WhatsApp
   → Plan 3 + Nube Ingenio+: Twilio API desde Node-RED
```

---

## Plan 3 — Cosecha

**Hardware:** Mini PC N2840 4GB RAM SSD 64GB + WM1302 USB LoRaWAN
**OS:** Debian 13 x86_64
**Stack:** Docker Compose v12 — 14 servicios
**Dashboard:** HTML estático servido por Nginx:8087

### Stack Docker Plan 3 (v12)

```
emqx                  → broker MQTT central
openremote-manager    → plataforma IoT: assets, reglas, actuadores
openremote-keycloak   → autenticación OAuth2
openremote-postgres   → BD OpenRemote (UID 70)
influxdb              → historial series temporales
nodered               → EMQX→InfluxDB + alertas + WhatsApp
grafana               → dashboard admin técnico
nginx                 → portal cliente + proxy APIs
caddy                 → proxy unificado :80
portainer             → gestión Docker visual
chirpstack            → LNS LoRaWAN v4.9.0
chirpstack-gateway-bridge → Semtech UDP → EMQX
chirpstack-postgres   → BD ChirpStack (pg_trgm + hstore)
chirpstack-redis      → cache ChirpStack
```

---

### 3.1 Dashboard completo — Plan 3

**Función cliente:** Vista completa con todos los indicadores avanzados

**Implementación:**
```
Plataforma: Nginx:8087 → sirve index.html
Autenticación: Keycloak OAuth2 via proxy /api/auth/
               Direct Access Grants habilitado (setup_keycloak_uris.sh)
Datos assets:  POST /api/or/api/{realm}/asset/query → OpenRemote REST API
               proxy Nginx reescribe Origin → openremote-manager:8080
Datos tiempo real: MQTT WebSocket ws://host:8083/mqtt → EMQX
Datos históricos:  POST /api/historial → InfluxDB Flux API
                   proxy Nginx inyecta token Authorization

Estado actual: ✅ Conectado a OpenRemote — muestra assets reales
               ✅ MQTT WebSocket activo
               ✅ InfluxDB historial funcional
               ⬜ Pendiente: índice salud, tendencia, alertas automáticas
```

---

### 3.2 Recomendación de riego — Plan 3

**Función cliente:** "¿Necesita regar hoy?" visible en panel de detalle

**Implementación:**
```
Plataforma: OpenRemote WHEN-THEN Rules (UI en /manager/)
Regla:
  WHEN: atributo soilMoisture del asset < 30
  THEN: escribir atributo recommendation =
        "💧 Humedad baja ({valor}%) — regar 30 min hoy antes del mediodía"

  WHEN: soilMoisture > 70
  THEN: recommendation = "🌊 Suelo saturado — suspender riego"

  WHEN: soilMoisture between 45 and 70
  THEN: recommendation = "✅ Condiciones normales"

Dashboard: lee atributo recommendation del asset via OpenRemote REST
           renderiza en dp-rec-txt del panel de detalle

Complemento Node-RED: publica también en topic ingenio/{finca}/rec
                      para actualizaciones en tiempo real via MQTT WS
```

**Estado:** ⬜ Pendiente — reglas WHEN-THEN en OpenRemote + lógica dashboard

---

### 3.3 Índice de salud — Plan 3

**Función cliente:** Número 0-100 + semáforo por zona/finca

**Implementación:**
```
Plataforma: JavaScript frontend (mismo cálculo que Plan 2)
Diferencia Plan 3: datos vienen de OpenRemote REST API
                   múltiples assets por realm = índice por finca completa

Índice finca = promedio health_score de todos los assets del realm
Renderizado: círculo grande en topbar con color semáforo
             número por asset en sensor-card de la lista lateral
```

**Estado:** ⬜ Pendiente — función JS + renderizado en topbar y lista

---

### 3.4 Alertas automáticas — Plan 3

**Función cliente:** Avisos con causa y acción — en portal y WhatsApp

**Implementación:**
```
Plataforma A — OpenRemote WHEN-THEN:
  Reglas de alerta → escriben atributo alarmStatus del asset
  Dashboard lee alarmStatus y renderiza en panel alertas

Plataforma B — Node-RED (complementario):
  Flujo watchdog: detecta nodo offline (sin mensaje > 60 min)
  Flujo humedad:  evalúa soil_moisture en topic EMQX entrante
  Publica alertas en topic ingenio/{finca}/alertas
  Dashboard suscribe via MQTT WebSocket

WhatsApp (Nube Ingenio+):
  Node-RED nodo HTTP request → POST api.twilio.com/Messages
  Headers: Authorization Basic {TWILIO_SID}:{TWILIO_TOKEN}
  Body: To=whatsapp:+57{numero}, From=whatsapp:{TWILIO_FROM},
        Body={mensaje_alerta}
  Config: variables TWILIO_SID, TWILIO_TOKEN, TWILIO_FROM en .env
  Número agricultor: atributo phoneNumber del asset en OpenRemote
```

**Estado:** ⬜ Pendiente — reglas OR + flujos Node-RED + Twilio (Nube)

---

### 3.5 Control de actuadores — Plan 3

**Función cliente:** Botón de riego con confirmación desde el dashboard

**Implementación:**
```
Plataforma: OpenRemote REST API + MQTT
Flujo:
  Dashboard → PUT /api/or/api/{realm}/asset/{id}/attribute/pumpControl/value
  Body: { value: { action:"OPEN", duration_min:30 } }

  OpenRemote MQTT Agent → publica en topic ingenio/{finca}/{node}/cmd
  Nodo recibe CMD → activa relé → responde ACK en /ack topic
  OpenRemote actualiza atributo pumpStatus → dashboard lo refleja

Estados UI: idénticos a Plan 2
Timeout ACK: 30s → mostrar error

Alternativa directa (sin OpenRemote intermediario):
  Dashboard → MQTT publish directo via WebSocket
  Topic: ingenio/{finca}/{node}/cmd
  Más rápido pero sin trazabilidad en OpenRemote
```

**Estado:** ⬜ Pendiente — botón dashboard + PUT OpenRemote + escuchar ACK

---

### 3.6 Gateway LoRaWAN — WM1302 USB

**Función cliente:** Red LoRaWAN profesional para múltiples nodos

**Implementación:**
```
Hardware: Seeed WM1302 USB, EUI: 0016C001F11A7BD1, /dev/ttyACM0
HAL:      sx1302_hal v2.1.0 compilado en host
          Fix: TX_JIT_DELAY 40000 → 120000 (jitqueue.c)
Config:   global_conf.json.sx1250.US915.USB
          gateway_ID: 0016C001F11A7BD1
          server: localhost:1700

Flujo datos:
  Nodos LoRaWAN → WM1302 → lora_pkt_fwd (host) → UDP:1700
  → chirpstack-gateway-bridge (Docker) → EMQX
  Topics EMQX: us915_0/gateway/{EUI}/event/{type}
  → ChirpStack → procesa → publica en EMQX
  Topics: chirpstack/application/{id}/device/{eui}/event/up
  → Node-RED → InfluxDB + OpenRemote

Iniciar: bash scripts/setup_wm1302.sh start
Systemd: bash scripts/setup_wm1302.sh install (arranque automático)
```

**Estado:** ✅ Hardware detectado, sx1302_hal compilado
            ⬜ Pendiente: registrar gateway en ChirpStack UI

---

### 3.7 Grafana — Panel admin técnico

**Función:** Solo para el técnico/administrador, no para el agricultor

**Implementación:**
```
Plataforma: Grafana OSS (puerto 3000)
Datasource: InfluxDB v2 — org:agrosensor, bucket:sensores
            Token: desde .env INFLUXDB_TOKEN
Plugin:     yesoreyeram-infinity-datasource (OpenRemote REST)

Dashboards a crear:
  - Estado de todos los nodos (tabla con últimos valores)
  - Señal LoRa por nodo (RSSI histórico)
  - Consumo de batería por nodo
  - Uptime de servicios Docker
  - Volumen de mensajes MQTT por hora

Acceso: http://ingenioplus.local:3000
        Solo en red local — no expuesto al agricultor
```

**Estado:** ⬜ Pendiente — crear datasources y dashboards admin

---

## Tabla de implementación — estado actual

| Característica | Plan 1 | Plan 2 | Plan 3 | Plataforma Plan 2 | Plataforma Plan 3 |
|---|:---:|:---:|:---:|---|---|
| Dashboard local | ✅ | ⬜ | ✅ | Nginx + HTML | Nginx + HTML |
| Control relés | ✅ | ⬜ | ⬜ | MQTT → STM32U585 | OpenRemote REST |
| Motor reglas básico | ✅ | ⬜ | ⬜ | Node-RED + HA | OR WHEN-THEN |
| Portal cautivo WiFi | ✅ | — | — | — | — |
| Receptor LoRa P2P | ⬜ | ⬜ | — | STM32U585 + RadioLib | — |
| Gateway LoRaWAN | — | — | ✅* | — | WM1302 + ChirpStack |
| Historial 24h | — | ⬜ | ✅ | InfluxDB + Chart.js | InfluxDB + Chart.js |
| ¿Regar hoy? | — | ⬜ | ⬜ | Node-RED | OR WHEN-THEN |
| Índice salud 0-100 | — | ⬜ | ⬜ | JS frontend | JS frontend |
| Tendencia ↑↓ | — | ⬜ | ⬜ | InfluxDB + JS | InfluxDB + JS |
| Alertas automáticas | — | ⬜ | ⬜ | Node-RED | Node-RED + OR |
| Control actuador UI | — | ⬜ | ⬜ | MQTT WebSocket | OpenRemote REST |
| Automatización offline | — | ⬜ | — | Home Assistant | — |
| Comparación con ayer | — | ⬜ | ⬜ | InfluxDB + JS | InfluxDB + JS |
| Batería en días | — | ⬜ | ⬜ | JS frontend | JS frontend |
| Alertas WhatsApp | — | — | ⬜ | — | Node-RED + Twilio |
| Multi-finca | — | — | ⬜ | — | OpenRemote realms |
| Panel admin Grafana | — | — | ⬜ | — | Grafana + InfluxDB |

✅ Implementado  ⬜ Pendiente  — No aplica para este plan
*Hardware listo, pendiente registro en ChirpStack UI

---

## Orden de desarrollo recomendado

### Sesión 1 — Impacto alto, esfuerzo bajo (JS frontend puro)
```
1. Índice de salud 0-100 — función JS, sin dependencias nuevas
2. Tendencia ↑↓ — query InfluxDB ya configurado + icono
3. Batería en días — cálculo JS + query historial 7 días
```

### Sesión 2 — Lógica de negocio (Node-RED + dashboard)
```
4. ¿Regar hoy? — flujo Node-RED + texto en dashboard
5. Alertas automáticas — flujos Node-RED + suscripción MQTT WS
6. Comparación con ayer — segunda query InfluxDB
```

### Sesión 3 — Control y acción
```
7. Botón control actuador — PUT OpenRemote + ACK MQTT
8. Reglas WHEN-THEN en OpenRemote — humedad + batería + offline
```

### Sesión 4 — Escala y nube
```
9.  Alertas WhatsApp — Twilio + Node-RED (Nube Ingenio+)
10. Multi-finca — realms OpenRemote + selector en dashboard
11. Panel Grafana admin — datasources + dashboards técnicos
```

### Paralelo — Hardware
```
Firmware nodo Plan 1: XIAO ESP32-C3 + sensor voltaje + LoRa P2P
Firmware STM32U585:   receptor LoRa + control relay + serial QRB2210
Stack Plan 2:         docker-compose.raiz.yml para Arduino UNO Q
```

---

*Ingenio+  ·  Especificación técnica v1  ·  Stack v12*
*Comparar con docs/producto_cliente.md para alineación comercial*
