# Ingenio+ — Plan Raíz (Arduino UNO Q)

Stack para fincas 5-20 ha. Basado en la arquitectura validada [MING Stack](https://github.com/roserocarlos/Ming), adaptado para producción de campo.

## Diferencias vs MING original

| MING (educativo) | Plan Raíz (producción) |
|---|---|
| Mosquitto anónimo | Mosquitto con usuario/password |
| Credenciales hardcodeadas | Todo en `.env` |
| `ming_*` nombres | `ingenio_*` nombres |
| bucket `gas_data` | bucket `sensores` (consistente con Plan Cosecha) |
| Sin Nginx | Nginx + dashboard v3 + proxy InfluxDB |
| Sin Home Assistant | HA integrado, modo host |
| Token/secret regenerable | Fijos vía `.env` (sin bug flows_cred.json) |

## Hardware

Arduino UNO Q 4GB — QRB2210 (Debian+Docker) + STM32U585 (tiempo real, recibe LoRa P2P)

## Deploy

```bash
git clone https://github.com/roserocarlos/ingenio
cd ingenio/raiz
bash deploy.sh
```

## Accesos

| Servicio | URL | Notas |
|---|---|---|
| Portal cliente | http://localhost:8087 | Dashboard agricultor |
| Node-RED | http://localhost:1880 | Flujos EMQX→InfluxDB |
| InfluxDB | http://localhost:8086 | admin / ver .env |
| Grafana | http://localhost:3000 | Solo panel técnico |
| Home Assistant | http://localhost:8123 | Automatizaciones offline |
| MQTT | mqtt://localhost:1883 | Usuario/password en .env |

## Configurar Node-RED (primera vez)

Igual que Plan Cosecha — importar flujo desde `scripts/nodered_flows.json`, configurar credenciales MQTT (usuario/password del `.env`) y token InfluxDB en el nodo `influxdb out`.

## Configurar Grafana (opcional, solo admin)

1. Connections → Data sources → InfluxDB
2. URL: `http://ingenio_influxdb:8086`, Org: `agrosensor`, Token: ver `.env`, Bucket: `sensores`

## Topics MQTT (mismo esquema que Plan Cosecha)

```
ingenio/{finca_id}/{node_id}/up      ← datos sensor
ingenio/{finca_id}/{node_id}/cmd     ← comando actuador
ingenio/{finca_id}/{node_id}/ack     ← confirmación actuador
ingenio/{finca_id}/alertas           ← alertas automáticas
```

## Notas

- Sin OpenRemote — el dashboard lee directo de Mosquitto WS (puerto 9001) e InfluxDB
- Home Assistant corre en `network_mode: host` para discovery mDNS/SSDP en la red de la finca
- El dashboard es el mismo `index.html` v3 del Plan Cosecha — solo cambia el backend de datos
