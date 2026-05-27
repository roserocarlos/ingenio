#!/usr/bin/env python3
# =============================================================================
# Ingenio+ — Simulador de sensores
# Publica datos de prueba en EMQX para los 3 nodos de la finca f01
# Uso: python3 scripts/simulador_sensor.py
# =============================================================================
import paho.mqtt.client as mqtt
import json, time, random, math

BROKER = "localhost"
PORT   = 1883
FINCAS = [
    {"finca": "f01", "nodos": ["s001", "s002", "s003"]},
]

client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
client.connect(BROKER, PORT)
client.loop_start()

print("Simulador Ingenio+ iniciado — Ctrl+C para detener")
print(f"Broker: {BROKER}:{PORT}")
print("─" * 50)

t = 0
while True:
    for finca in FINCAS:
        for nodo in finca["nodos"]:
            payload = {
                "finca_id":      finca["finca"],
                "node_id":       nodo,
                "ts":            int(time.time()),
                "soil_moisture": round(45 + 25 * math.sin(t / 10 + random.uniform(-0.5, 0.5)), 1),
                "temperature":   round(20 + 5  * math.sin(t / 15) + random.uniform(-1, 1), 1),
                "ph":            round(6.5 + 0.5 * math.sin(t / 20) + random.uniform(-0.1, 0.1), 2),
                "nitrogen":      round(140 + 20 * random.random(), 1),
                "phosphorus":    round(45  + 10 * random.random(), 1),
                "potassium":     round(85  + 15 * random.random(), 1),
                "battery":       round(80  + 10 * random.random(), 1),
                "rssi":          round(-75  - 20 * random.random(), 0),
            }
            topic = f"ingenio/{finca['finca']}/{nodo}/up"
            client.publish(topic, json.dumps(payload))
            print(f"  [{nodo}] {topic} → hum={payload['soil_moisture']}% temp={payload['temperature']}°C bat={payload['battery']}%")
    t += 1
    print(f"  ─ ciclo {t} completado ─")
    time.sleep(30)
