# Estructura del repositorio Ingenio+

```
ingenio/
│
├── deploy.sh                 Deployment completo Plan 3 en un comando
├── docker-compose.yml        14 servicios Docker — Plan 3 Cosecha
├── .env.example              Variables de entorno por defecto (sin secretos)
├── setup_servidor.sh         Configuración base del servidor Debian
│
├── caddy/
│   └── Caddyfile             Proxy reverso unificado puerto :80
│                             Enruta /auth → Keycloak, resto → OpenRemote
│
├── chirpstack/
│   └── configuration/
│       ├── chirpstack/
│       │   └── chirpstack.toml         LNS LoRaWAN US915, integración EMQX
│       ├── chirpstack-gateway-bridge/
│       │   └── chirpstack-gateway-bridge-us915.toml  UDP:1700 → EMQX
│       └── postgresql/initdb/
│           └── 001-init-chirpstack.sql BD + pg_trgm + hstore (crítico)
│
├── grafana/
│   └── provisioning/datasources/
│       └── datasources.yml   Datasource InfluxDB pre-configurado
│
├── keycloak/
│   └── keycloak.conf         Keycloak modo local sin TLS
│
├── nginx/
│   ├── nginx.conf            Proxy: /api/or/ /api/auth/ /api/historial
│   └── html/
│       └── index.html        Portal cliente agricultor Plan 3
│                             OpenRemote REST + InfluxDB + MQTT WebSocket
│
├── scripts/
│   ├── init_influxdb.sh      Token InfluxDB + Keycloak URIs automático
│   ├── setup_keycloak_uris.sh OAuth2 + Direct Access Grants portal
│   ├── setup_wm1302.sh       Packet forwarder WM1302 USB LoRaWAN
│   └── simulador_sensor.py   Datos de prueba EMQX (3 nodos finca f01)
│
├── plan1/                    Plan Semilla — ESP32 embebido (1-5 ha)
│                             WiFi Relay Module + Wio-SX1262
│                             WebServer local, reglas básicas, portal cautivo
│                             Firmware PlatformIO — en desarrollo
│
├── plan2/                    Plan Raíz — Arduino UNO Q 4GB (5-20 ha)
│                             QRB2210 (Debian+Docker) + STM32U585 (real-time)
│                             Docker 5 servicios: EMQX+InfluxDB+Node-RED+HA+Nginx
│                             En desarrollo
│
├── dashboard/                Frontend compartido — en desarrollo
│                             Mismo diseño visual para los 3 planes
│                             CSS/paleta compartida, JS diferente por plan
│
├── firmware/
│   ├── nodo/                 Nodo de campo — compartido los 3 planes
│   │                         XIAO ESP32-C3 + Wio-SX1262, RadioLib, LoRa P2P
│   │                         Payload JSON: soil_moisture, temperature, ph,
│   │                         battery, rssi, nitrogen, phosphorus, potassium
│   └── receptor/
│       ├── plan1-esp32/      Receptor integrado WiFi Relay Module ESP32
│       ├── plan2-stm32/      Receptor STM32U585 Arduino UNO Q
│       └── plan3-xiao/       Receptor XIAO ESP32-S3 dedicado
│
└── docs/
    ├── CONTEXT.md            Contexto completo del proyecto para IA
    ├── STRUCTURE.md          Este archivo
    ├── producto_cliente.md   Características en lenguaje del agricultor
    └── producto_tecnico.md   Especificación técnica por plan y plataforma
```

## Flujo de trabajo

### Nuevo servidor Plan 3
```bash
git clone https://github.com/roserocarlos/ingenio /opt/ingenioplus
cd /opt/ingenioplus && sudo bash deploy.sh
```

### Actualizar dashboard en servidor
```bash
cd /opt/ingenioplus && git pull && ingenio restart nginx
```

### Desarrollo local Windows + Docker Desktop
```bash
git clone https://github.com/roserocarlos/ingenio
cd ingenio
docker network create apps
docker compose up -d
```

### Continuar con IA
Leer `docs/CONTEXT.md` — contiene todo el contexto del proyecto.
