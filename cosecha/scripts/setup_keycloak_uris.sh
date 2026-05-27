#!/bin/bash
# =============================================================================
# Ingenio+ — Configurar redirect URIs de Keycloak
# Ejecutar UNA VEZ después de init_influxdb.sh
# Permite el login desde http://ingenioplus.local/manager/
#
# Uso: bash scripts/setup_keycloak_uris.sh
# =============================================================================
set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DEPLOY_DIR"
source .env

HOSTNAME="${OR_HOSTNAME:-ingenioplus.local}"
PASSWORD="${OR_ADMIN_PASSWORD:-linuxxl2}"
AUTH_URL="http://${HOSTNAME}/auth"

log "Configurando Keycloak redirect URIs para $HOSTNAME..."

# Esperar a que Keycloak esté disponible
log "Esperando Keycloak..."
timeout 60 bash -c "until curl -sf $AUTH_URL/realms/master >/dev/null 2>&1; do sleep 3; done" \
    || err "Keycloak no responde en $AUTH_URL"

# Obtener token admin
TOKEN=$(curl -sf -X POST "$AUTH_URL/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin&password=${PASSWORD}&grant_type=password&client_id=admin-cli" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null)

[ -z "$TOKEN" ] && err "No se pudo obtener token de Keycloak — verificar contraseña en .env"
log "Token Keycloak obtenido"

# Obtener ID del cliente openremote
CLIENT_ID=$(curl -sf "$AUTH_URL/admin/realms/master/clients" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c "
import sys,json
for c in json.load(sys.stdin):
    if c.get('clientId') == 'openremote':
        print(c['id'])
        break
" 2>/dev/null)

[ -z "$CLIENT_ID" ] && err "Cliente 'openremote' no encontrado en Keycloak"
log "Cliente openremote ID: $CLIENT_ID"

# Actualizar redirect URIs
curl -sf -X PUT "$AUTH_URL/admin/realms/master/clients/$CLIENT_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"redirectUris\": [
      \"http://${HOSTNAME}/*\",
      \"http://localhost/*\",
      \"http://127.0.0.1/*\"
    ],
    \"webOrigins\": [
      \"http://${HOSTNAME}\",
      \"http://localhost\",
      \"http://127.0.0.1\"
    ]
  }" && log "Redirect URIs configurados para $HOSTNAME" || err "Error actualizando URIs"

echo ""
echo "═══════════════════════════════════════════════════"
log "Keycloak configurado correctamente"
echo ""
echo "  Login disponible en:"
echo "    http://$HOSTNAME/manager/"
echo ""
echo "  Usuario: admin"
echo "  Password: $PASSWORD"
echo "═══════════════════════════════════════════════════"
