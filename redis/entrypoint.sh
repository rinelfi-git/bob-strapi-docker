#!/bin/sh
set -e

echo "Starting Redis..."

# Le mot de passe doit etre fourni via la variable d'environnement REDIS_PASSWORD
if [ -z "$REDIS_PASSWORD" ]; then
  echo "ERROR: REDIS_PASSWORD environment variable is not set."
  echo "Please set it in docker/.env"
  exit 1
fi

# Sauvegarder le mot de passe pour le healthcheck
echo "$REDIS_PASSWORD" > /data/redis_password.txt
chmod 600 /data/redis_password.txt

# Construire la config avec le mot de passe
cp /usr/local/etc/redis/redis.conf /tmp/redis.conf
echo "requirepass $REDIS_PASSWORD" >> /tmp/redis.conf

echo "Starting Redis server..."
exec redis-server /tmp/redis.conf
