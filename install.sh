#!/bin/bash
set -e

echo "=== Messagerie souveraine — installation ==="

if [ ! -f .env ]; then
    echo "Erreur : fichier .env manquant."
    echo "Créez-le avec : echo 'POSTGRES_PASSWORD=votre_mot_de_passe' > .env"
    exit 1
fi

echo "Démarrage des conteneurs (Caddy, PostgreSQL, Synapse, Element)..."
docker compose up -d

echo "En attente du démarrage de Synapse (30 secondes)..."
sleep 30

echo ""
echo "État des services :"
docker compose ps

IP=$(hostname -I | awk '{print $1}')

echo ""
echo "=== Installation terminée ==="
echo "Accédez à la messagerie via : https://${IP}"
echo "(acceptez l'avertissement de certificat auto-signé au premier accès)"
echo ""
echo "Note : si l'adresse IP de cette machine change, mettez à jour"
echo "Caddyfile et element-config.json avec la nouvelle adresse,"
echo "puis relancez : docker compose restart caddy element"
