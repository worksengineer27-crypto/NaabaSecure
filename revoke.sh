#!/usr/bin/env bash
# Révocation immédiate d'un agent de la messagerie souveraine.
#
# Usage : ./revoke.sh <agent> [adresse-ip] [-y]
#   <agent>        nom de l'agent à révoquer (ex. agent2)
#   [adresse-ip]   facultatif : lue dans synapse-data/homeserver.yaml sinon
#   -y             ne pas demander de confirmation
# Le mot de passe de l'administrateur est demandé (ou variable ADMIN_PASSWORD).
#
# Effets (API d'administration de Synapse) :
#   - le compte est désactivé : connexion impossible ;
#   - tous les jetons d'accès sont invalidés et tous les appareils supprimés ;
#   - l'agent est retiré de tous ses salons : il ne reçoit plus de nouveaux
#     messages, et les clients restants renouvellent la clé du salon.
# Limite : l'agent conserve ce qu'il avait déjà reçu avant sa révocation.
set -euo pipefail
cd "$(dirname "$0")"

OUI=0
ARGS=()
for a in "$@"; do
  case "$a" in
    -y|--yes) OUI=1 ;;
    *) ARGS+=("$a") ;;
  esac
done
AGENT="${ARGS[0]:-}"
HOTE="${ARGS[1]:-}"

[ -n "$AGENT" ] || { echo "Usage : ./revoke.sh <agent> [adresse-ip] [-y]" >&2; exit 1; }
AGENT="${AGENT#@}"
AGENT="${AGENT%%:*}"
ADMIN="${ADMIN_USER:-admin}"
[ "$AGENT" != "$ADMIN" ] || { echo "Refus : le compte administrateur ne se révoque pas." >&2; exit 1; }
command -v curl >/dev/null || { echo "curl est requis" >&2; exit 1; }

# Nom du serveur : argument, sinon homeserver.yaml, sinon adresse de la machine
if [ -z "$HOTE" ] && [ -r synapse-data/homeserver.yaml ]; then
  HOTE=$(grep -m1 '^server_name:' synapse-data/homeserver.yaml | sed 's/^server_name: *//; s/"//g; s/ *$//' || true)
fi
[ -n "$HOTE" ] || HOTE=$(hostname -I | awk '{print $1}')
[ -n "$HOTE" ] || { echo "Adresse du serveur introuvable : ./revoke.sh $AGENT <adresse-ip>" >&2; exit 1; }

BASE="${BASE_URL:-https://$HOTE}"
MXID="@$AGENT:$HOTE"

# Mot de passe de l'administrateur
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
if [ -z "$ADMIN_PASSWORD" ]; then
  read -rsp "Mot de passe de l'administrateur ($ADMIN) : " ADMIN_PASSWORD
  echo
fi
PW_JSON=$(printf '%s' "$ADMIN_PASSWORD" | sed 's/\\/\\\\/g; s/"/\\"/g')

# 1. Connexion de l'administrateur
REP=$(curl -ksS -X POST "$BASE/_matrix/client/v3/login" \
  -H 'Content-Type: application/json' \
  -d "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"$ADMIN\"},\"password\":\"$PW_JSON\"}")
TOKEN=$(printf '%s' "$REP" | sed -n 's/.*"access_token" *: *"\([^"]*\)".*/\1/p')
if [ -z "$TOKEN" ]; then
  echo "Connexion de l'administrateur impossible : $REP" >&2
  exit 1
fi
# L'administrateur se déconnecte à la fin du script
trap 'curl -ksS -X POST "$BASE/_matrix/client/v3/logout" -H "Authorization: Bearer $TOKEN" -d "{}" >/dev/null 2>&1 || true' EXIT

api() { curl -ksS -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "$@"; }
total() { sed -n 's/.*"total" *: *\([0-9][0-9]*\).*/\1/p' | head -n1; }

# 2. État de l'agent avant la révocation
ETAT=$(api "$BASE/_synapse/admin/v2/users/$MXID")
if printf '%s' "$ETAT" | grep -q '"errcode"'; then
  echo "Agent introuvable : $MXID" >&2
  exit 1
fi
if printf '%s' "$ETAT" | grep -Eq '"deactivated" *: *true'; then
  echo "$MXID est déjà révoqué."
  exit 0
fi
AVANT_SALONS=$(api "$BASE/_synapse/admin/v1/users/$MXID/joined_rooms" | total)
AVANT_APPAREILS=$(api "$BASE/_synapse/admin/v2/users/$MXID/devices" | total)
echo "Avant : ${AVANT_APPAREILS:-?} appareil(s), ${AVANT_SALONS:-?} salon(s) pour $MXID"

# 3. Confirmation (la révocation est difficile à annuler)
if [ "$OUI" != 1 ]; then
  read -rp "Révoquer $MXID maintenant ? (o/N) " REPONSE
  case "$REPONSE" in o|O|oui|OUI) ;; *) echo "Annulé."; exit 0 ;; esac
fi

# 4. Révocation : désactivation du compte
REP=$(api -X POST "$BASE/_synapse/admin/v1/deactivate/$MXID" -d '{"erase": false}')
if printf '%s' "$REP" | grep -q '"errcode"'; then
  echo "Échec de la révocation : $REP" >&2
  exit 1
fi
echo "==> Compte désactivé : jetons invalidés, appareils supprimés."

# 5. Vérification (le retrait des salons se fait en arrière-plan)
SALONS=""
for i in $(seq 1 15); do
  SALONS=$(api "$BASE/_synapse/admin/v1/users/$MXID/joined_rooms" | total)
  [ "${SALONS:-1}" = "0" ] && break
  sleep 1
done
APPAREILS=$(api "$BASE/_synapse/admin/v2/users/$MXID/devices" | total)
api "$BASE/_synapse/admin/v2/users/$MXID" | grep -Eq '"deactivated" *: *true' && DESACTIVE=oui || DESACTIVE=non

echo ""
echo "Résultat pour $MXID"
echo "  Compte désactivé : $DESACTIVE"
echo "  Appareils        : ${APPAREILS:-?}"
echo "  Salons           : ${SALONS:-?}"
if [ "$DESACTIVE" = oui ] && [ "${APPAREILS:-1}" = "0" ] && [ "${SALONS:-1}" = "0" ]; then
  echo "Révocation effective : l'agent n'a plus accès à la messagerie."
else
  echo "Révocation incomplète : relancez la vérification ou consultez les journaux Synapse." >&2
  exit 1
fi
