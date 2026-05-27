# Ingenio+ — Plataforma IoT Agrícola

> *Para que usted sepa qué pasa en su finca, así esté lejos de ella.*

Plataforma de monitoreo agrícola con LoRa 915MHz para fincas de papa, hortalizas
y café en Boyacá y Nariño, Colombia. Sin internet en el campo.

---

## Tres planes de producto

| Plan | Carpeta | Hardware | Área |
|---|---|---|---|
| **Cosecha** | `cosecha/` | Mini PC N2840 + WM1302 USB | 50+ ha |
| **Raíz** | `raiz/` | Arduino UNO Q 4GB | 5–20 ha |
| **Semilla** | `semilla/` | WiFi Relay Module ESP32 | 1–5 ha |

---

## Deploy Plan Cosecha (Plan 3)

```bash
# Clonar solo lo necesario
git clone --no-checkout https://github.com/roserocarlos/ingenio /opt/ingenioplus
cd /opt/ingenioplus
git sparse-checkout init
git sparse-checkout set cosecha docs
git checkout main

# Desplegar
cd cosecha && sudo bash deploy.sh
```

O clonar todo si hay buena conexión:
```bash
git clone https://github.com/roserocarlos/ingenio /opt/ingenioplus
cd /opt/ingenioplus/cosecha && sudo bash deploy.sh
```

### Accesos tras el deploy

| Servicio | URL |
|---|---|
| Portal cliente | http://ingenioplus.local:8087 |
| OpenRemote | http://ingenioplus.local/manager/ |
| ChirpStack | http://ingenioplus.local:8090 |
| Grafana | http://ingenioplus.local:3000 |
| EMQX | http://ingenioplus.local:18083 |
| Node-RED | http://ingenioplus.local:1880 |
| Portainer | http://ingenioplus.local:9000 |

Credenciales por defecto en `cosecha/.env.example`.

---

## Deploy Plan Raíz (Plan 2) — en desarrollo

```bash
git clone --no-checkout https://github.com/roserocarlos/ingenio
cd ingenio
git sparse-checkout init
git sparse-checkout set raiz docs
git checkout main
cd raiz && sudo bash deploy.sh
```

---

## Deploy Plan Semilla (Plan 1) — en desarrollo

```bash
git clone --no-checkout https://github.com/roserocarlos/ingenio
cd ingenio
git sparse-checkout init
git sparse-checkout set semilla docs
git checkout main
# Abrir semilla/ en PlatformIO y flashear al ESP32
```

---

## Estructura del repositorio

```
ingenio/
├── cosecha/      Plan 3 — stack completo 14 servicios Docker
├── raiz/         Plan 2 — stack ligero 5 servicios Docker
├── semilla/      Plan 1 — firmware ESP32 embebido
├── firmware/     Nodos y receptores LoRa (compartido)
└── docs/         Documentación técnica y de producto
```

Ver `STRUCTURE.md` para detalle completo de carpetas.
Ver `docs/CONTEXT.md` para contexto completo del proyecto.

---

## Gateway LoRaWAN WM1302 USB (Plan Cosecha)

```bash
# Compilar sx1302_hal (una vez por servidor)
cd ~ && git clone https://github.com/Lora-net/sx1302_hal && cd sx1302_hal
sed -i 's/TX_JIT_DELAY            40000/TX_JIT_DELAY            120000/' \
  packet_forwarder/src/jitqueue.c
make

# Iniciar
bash /opt/ingenioplus/cosecha/scripts/setup_wm1302.sh start
# EUI: 0016C001F11A7BD1
```

---

**Ingenio+** · Ipiales, Nariño, Colombia · ingenio.plus.contacto@gmail.com
