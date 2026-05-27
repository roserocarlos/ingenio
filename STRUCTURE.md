# Estructura del repositorio Ingenio+

```
ingenio/
│
├── cosecha/                  Plan 3 — Mini PC N2840 + WM1302 USB (50+ ha)
│   ├── deploy.sh             Deploy completo en un comando
│   ├── docker-compose.yml    14 servicios Docker
│   ├── .env.example          Variables de entorno por defecto
│   ├── setup_servidor.sh     Configuración base servidor Debian
│   ├── caddy/
│   │   └── Caddyfile         Proxy reverso :80 → Keycloak / OpenRemote
│   ├── chirpstack/
│   │   └── configuration/
│   │       ├── chirpstack/chirpstack.toml          LNS LoRaWAN US915
│   │       ├── chirpstack-gateway-bridge/...toml   UDP:1700 → EMQX
│   │       └── postgresql/initdb/001-init.sql       pg_trgm + hstore
│   ├── grafana/provisioning/ Datasource InfluxDB pre-configurado
│   ├── keycloak/keycloak.conf Keycloak modo local sin TLS
│   ├── nginx/
│   │   ├── nginx.conf        Proxy /api/or/ /api/auth/ /api/historial
│   │   └── html/index.html   Portal cliente agricultor
│   ├── scripts/
│   │   ├── deploy.sh         Orquestador interno
│   │   ├── init_influxdb.sh  Token InfluxDB + Keycloak URIs
│   │   ├── setup_keycloak_uris.sh  OAuth2 + Direct Access Grants
│   │   ├── setup_wm1302.sh   Packet forwarder WM1302 USB LoRaWAN
│   │   └── simulador_sensor.py     Datos prueba EMQX (3 nodos f01)
│   └── dashboard/            Frontend Plan 3 — en desarrollo
│
├── raiz/                     Plan 2 — Arduino UNO Q 4GB (5-20 ha)
│   ├── deploy.sh             Deploy stack ligero — en desarrollo
│   ├── docker-compose.yml    5 servicios: EMQX+InfluxDB+Node-RED+HA+Nginx
│   ├── scripts/              Init y configuración Plan 2
│   └── dashboard/            Frontend Plan 2 — en desarrollo
│
├── semilla/                  Plan 1 — ESP32 embebido (1-5 ha)
│   ├── platformio.ini        Configuración PlatformIO
│   ├── src/                  Firmware ESP32
│   │   ├── main.cpp
│   │   ├── config.h
│   │   ├── rules_engine.h    Motor reglas básico
│   │   ├── captive_portal.h  Portal cautivo WiFi
│   │   └── ui.h              Dashboard HTML en PROGMEM
│   └── dashboard/            HTML embebido — mismo diseño, funciones básicas
│
├── firmware/                 Nodos y receptores LoRa
│   ├── nodo/                 Nodo de campo — plan se define al desplegar
│   │                         XIAO ESP32-C3 + Wio-SX1262, RadioLib
│   │                         LoRa P2P 915MHz, payload JSON
│   └── receptor/             Receptor varía por plan
│       ├── esp32/            WiFi Relay Module ESP32 — Plan 1
│       ├── stm32/            STM32U585 Arduino UNO Q — Plan 2
│       ├── esp32s3-xiao/     XIAO ESP32-S3 dedicado — Plan 3
│       └── techolite/        T-Echo Lite — candidato nodo Plan 2/3
│
└── docs/
    ├── CONTEXT.md            Contexto completo del proyecto para IA
    ├── STRUCTURE.md          Este archivo
    ├── producto_cliente.md   Características en lenguaje del agricultor
    └── producto_tecnico.md   Especificación técnica por plan y plataforma
```

---

## Flujo de trabajo

### Deploy Plan Cosecha (servidor nuevo)
```bash
git clone --no-checkout https://github.com/roserocarlos/ingenio /opt/ingenioplus
cd /opt/ingenioplus
git sparse-checkout init
git sparse-checkout set cosecha docs
git checkout main
cd cosecha && sudo bash deploy.sh
```

### Actualizar portal en servidor existente
```bash
cd /opt/ingenioplus && git pull && ingenio restart nginx
```

### Desarrollo local Windows + Docker Desktop
```bash
git clone https://github.com/roserocarlos/ingenio
cd ingenio/cosecha
docker network create apps
docker compose up -d
```

### Continuar con IA
Leer `docs/CONTEXT.md` — contiene todo el contexto del proyecto.
