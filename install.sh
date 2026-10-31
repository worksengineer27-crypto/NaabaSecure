#!/usr/bin/env bash
# Installation de la messagerie souveraine en une seule commande.
# Usage : ./install.sh [adresse-ip]     Réinitialisation complète : ./install.sh --reset
set -euo pipefail
cd "$(dirname "$0")"
trap 'echo "ERREUR ligne $LINENO : installation interrompue" >&2' ERR

RESET=0
if [ "${1:-}" = "--reset" ]; then RESET=1; shift; fi
HOTE="${1:-$(hostname -I | awk '{print $1}')}"
[ -n "$HOTE" ] || { echo "Adresse IP introuvable : ./install.sh <adresse-ip>" >&2; exit 1; }
command -v docker >/dev/null || { echo "Docker est requis" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl est requis" >&2; exit 1; }
docker compose version >/dev/null

if [ "$RESET" = 1 ]; then
  echo "==> Réinitialisation : suppression des données"
  docker compose down 2>/dev/null || true
  sudo rm -rf pgdata synapse-data caddy-data .env
fi

echo "==> Adresse du serveur : $HOTE"

# 1. Secret de la base de données (généré une fois, jamais publié)
if [ ! -f .env ]; then
  PGPW=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
  printf 'POSTGRES_PASSWORD=%s\n' "$PGPW" > .env
  chmod 600 .env
fi
PGPW=$(grep '^POSTGRES_PASSWORD=' .env | cut -d= -f2)

# 2. Configuration de Synapse : générée puis durcie, une seule fois
mkdir -p synapse-data
if [ ! -f synapse-data/homeserver.yaml ]; then
  echo "==> Génération de la configuration de Synapse"
  docker run --rm -v "$(pwd)/synapse-data:/data" \
    -e SYNAPSE_SERVER_NAME="$HOTE" -e SYNAPSE_REPORT_STATS=no \
    ghcr.io/element-hq/synapse:latest generate
  echo "==> Durcissement : PostgreSQL, inscriptions fermées, fédération coupée, expiration"
  docker run --rm -i -v "$(pwd)/synapse-data:/data" -e PGPW="$PGPW" \
    --entrypoint python ghcr.io/element-hq/synapse:latest - << 'PY'
import os, re
p = "/data/homeserver.yaml"
s = open(p).read()
db = ("database:\n  name: psycopg2\n  args:\n    user: synapse\n"
      "    password: \"%s\"\n    database: synapse\n    host: db\n"
      "    cp_min: 5\n    cp_max: 10\n") % os.environ["PGPW"]
s, n = re.subn(r"(?m)^database:\n(?:[ \t]+.*\n)+", db, s, count=1)
assert n == 1, "bloc database introuvable"
s = re.sub(r"(?m)^trusted_key_servers:\n(?:[ \t]+.*\n)+", "trusted_key_servers: []\n", s, count=1)
s += """
enable_registration: false
federation_domain_whitelist: []
max_upload_size: 50M

retention:
  enabled: true
  allowed_lifetime_min: 1m
  allowed_lifetime_max: 30d
  purge_jobs:
    - longest_max_lifetime: 1d
      interval: 1m
    - shortest_max_lifetime: 1d
      interval: 1h
"""
open(p, "w").write(s)
print("homeserver.yaml durci")
PY
fi

# 3. Caddy (point d'entrée HTTPS) et Element Web
cat > Caddyfile << EOF
{
    default_sni $HOTE
}

$HOTE {
    tls internal

    handle /_matrix/* {
        reverse_proxy synapse:8008
    }

    handle /_synapse/* {
        reverse_proxy synapse:8008
    }

    handle {
        reverse_proxy element:80
    }
}
EOF

cat > element-config.json << EOF
{
  "default_server_config": {
    "m.homeserver": { "base_url": "https://$HOTE", "server_name": "$HOTE" }
  },
  "disable_custom_urls": true,
  "disable_guests": true
}
EOF

# 4. Démarrage et attente de Synapse
echo "==> Démarrage des services"
docker compose up -d
echo "==> Attente de Synapse (3 minutes au maximum)"
for i in $(seq 1 90); do
  if curl -ksf "https://$HOTE/_matrix/client/versions" >/dev/null; then break; fi
  if [ "$i" = 90 ]; then
    echo "Synapse ne répond pas : docker compose logs synapse --tail 30" >&2
    exit 1
  fi
  sleep 2
done

# 5. Comptes de démonstration (fictifs)
echo "==> Comptes de démonstration"
creer() {
  if docker compose exec -T synapse register_new_matrix_user -u "$1" -p "$2" "$3" \
       -c /data/homeserver.yaml http://localhost:8008 >/dev/null 2>&1; then
    echo "    créé : $1"
  else
    echo "    déjà présent ou erreur : $1"
  fi
}
creer agent1 "Demo-Agent1-2026" --no-admin
creer agent2 "Demo-Agent2-2026" --no-admin
creer agent3 "Demo-Agent3-2026" --no-admin
creer admin  "Demo-Admin-2026"  --admin

echo ""
echo "Installation terminée."
echo "  Adresse : https://$HOTE   (accepter l'avertissement du certificat)"
echo "  Comptes : agent1, agent2, agent3 (utilisateurs), admin (administrateur)"
echo "  Mots de passe de démonstration : voir README.md"
