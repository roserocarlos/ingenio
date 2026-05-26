# Ingenio+ — Plataforma IoT Agrícola

> *Para que usted sepa qué pasa en su finca, así esté lejos de ella.*

Plataforma de monitoreo agrícola con LoRa 915MHz para fincas de papa, hortalizas y café
en Boyacá y Nariño, Colombia. Sin internet en el campo — radio LoRa y LoRaWAN.

---

## Deploy en un comando

```bash
git clone https://github.com/roserocarlos/ingenio /opt/ingenioplus
cd /opt/ingenioplus && sudo bash deploy.sh
```

Eso es todo. El script hace todo automáticamente:
- Configura hostname → `ingenioplus`
- Instala Docker y dependencias
- Levanta los 14 servicios
- Inicializa InfluxDB y Keycloak
- Configura mDNS → `ingenioplus.local`

Tiempo estimado: ~15 minutos (descarga de imágenes Docker).

---

## Accesos tras el deploy

| Servicio | URL |
|---|---|
| Portal cliente | http://ingenioplus.local:8087 |
| OpenRemote | http://ingenioplus.local/manager/ |
| ChirpStack | http://ingenioplus.local:8090 |
| Grafana | http://ingenioplus.local:3000 |
| EMQX | http://ingenioplus.local:18083 |
| Node-RED | http://ingenioplus.local:1880 |
| Portainer | http://ingenioplus.local:9000 |

Credenciales por defecto en `.env.example`.

> **Windows:** agregar `192.168.x.x ingenioplus.local` en
> `C:\Windows\System32\drivers\etc\hosts`

---

## Tres planes de producto

| Plan | Hardware base | Área |
|---|---|---|
| **Semilla** | WiFi Relay Module ESP32 + Wio-SX1262 | 1–5 ha |
| **Raíz** | Arduino UNO Q 4GB + STM32U585 + Wio-SX1262 | 5–20 ha |
| **Cosecha** | Mini PC N2840 + WM1302 USB LoRaWAN | 50+ ha |

Este repositorio contiene el stack del **Plan Cosecha**.

---

## Stack — 14 servicios Docker

| Servicio | Puerto | Rol |
|---|---|---|
| EMQX 6.1.1 | 1883 / 8083 / 18083 | Broker MQTT central |
| OpenRemote Manager | 8091 | Assets, reglas, actuadores |
| OpenRemote Keycloak | 8093 | Autenticación OAuth2 |
| OpenRemote PostgreSQL | — | BD OpenRemote |
| InfluxDB v2 | 8086 | Historial series temporales |
| Node-RED | 1880 | EMQX → InfluxDB |
| Grafana | 3000 | Dashboard admin |
| Nginx | 8087 | Portal cliente + proxy APIs |
| Caddy | 80 | Proxy unificado OpenRemote |
| Portainer | 9000 | Gestión Docker |
| ChirpStack v4.9.0 | 8090 | LNS LoRaWAN |
| ChirpStack Gateway Bridge | UDP:1700 | Semtech UDP → EMQX |
| ChirpStack PostgreSQL | — | BD ChirpStack |
| ChirpStack Redis | — | Cache ChirpStack |

---

## Gateway LoRaWAN WM1302 USB

```bash
# Compilar sx1302_hal (una vez por servidor)
cd ~ && git clone https://github.com/Lora-net/sx1302_hal && cd sx1302_hal
sed -i 's/TX_JIT_DELAY            40000/TX_JIT_DELAY            120000/' \
  packet_forwarder/src/jitqueue.c
make

# Iniciar
bash /opt/ingenioplus/scripts/setup_wm1302.sh start
# EUI del concentrador: 0016C001F11A7BD1
```

---

## Estructura del repositorio

```
ingenio/
├── deploy.sh                 # Deploy completo en un comando ← EMPEZAR AQUÍ
├── docker-compose.yml        # 14 servicios Docker
├── .env.example              # Variables por defecto
├── setup_servidor.sh         # Configuración del servidor (llamado por deploy.sh)
├── caddy/                    # Proxy unificado :80
├── chirpstack/               # ChirpStack v4 US915
├── keycloak/                 # Keycloak modo local
├── nginx/                    # Portal cliente + proxies API
├── scripts/
│   ├── init_influxdb.sh      # Inicialización (llamado por deploy.sh)
│   ├── setup_keycloak_uris.sh
│   ├── setup_wm1302.sh
│   └── simulador_sensor.py
├── dashboard/                # Frontend en desarrollo
├── firmware/                 # Firmware nodos PlatformIO
└── docs/                     # Documentación técnica
```

---

## Aliases en el servidor

```bash
ingenio up/down/ps    # gestionar stack
ingenio-or/emqx/nr/influx/chirp  # logs por servicio
ingenio-sim           # simulador sensores
cdingenia             # ir a /opt/ingenioplus
```

---

## Historial

| Versión | Cambios |
|---|---|
| v12 | Fix KC_HOSTNAME, ChirpStack 4.9.0, pg_trgm, proxy OR, Direct Access Grants, deploy.sh |
| v11 | ChirpStack integrado, portal conectado a APIs reales |
| v10 | OpenRemote login vía mDNS, Node-RED→InfluxDB verificado |

---

**Ingenio+** · Ipiales, Nariño · ingenio.plus.contacto@gmail.com
