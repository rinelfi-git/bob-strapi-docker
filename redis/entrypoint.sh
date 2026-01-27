#!/bin/sh
set -e

echo "Starting Redis with auto-configuration..."

# Générer le mot de passe Redis si non défini
if [ -z "$REDIS_PASSWORD" ]; then
  export REDIS_PASSWORD=$(openssl rand -base64 32)
  echo "Generated Redis password: $REDIS_PASSWORD"

  # Sauvegarder le mot de passe dans le volume de données
  echo "$REDIS_PASSWORD" > /data/redis_password.txt
  chmod 600 /data/redis_password.txt
fi

# Vérifier si le fichier .env de Strapi existe et le mettre à jour
STRAPI_ENV_FILE="/app/bob/.env"
if [ -f "$STRAPI_ENV_FILE" ]; then
  echo "Updating Strapi .env file with Redis configuration..."

  # Utiliser sed compatible POSIX/BusyBox (Alpine)
  sed -i'' "s/^REDIS_HOST=.*/REDIS_HOST=redis/" "$STRAPI_ENV_FILE"
  sed -i'' "s/^REDIS_PORT=.*/REDIS_PORT=6379/" "$STRAPI_ENV_FILE"
  sed -i'' "s/^REDIS_PASSWORD=.*/REDIS_PASSWORD=$REDIS_PASSWORD/" "$STRAPI_ENV_FILE"
  sed -i'' "s/^REDIS_DB=.*/REDIS_DB=0/" "$STRAPI_ENV_FILE"

  echo "Strapi .env file updated:"
  echo "   REDIS_HOST=redis"
  echo "   REDIS_PORT=6379"
  echo "   REDIS_PASSWORD=*** (hidden)"
  echo "   REDIS_DB=0"
else
  echo "Warning: Strapi .env file not found at $STRAPI_ENV_FILE"
  echo "   Redis will start but Strapi won't be able to connect without configuration"
fi

# Copier la configuration de base et ajouter le mot de passe
cp /usr/local/etc/redis/redis.conf /tmp/redis.conf
echo "requirepass $REDIS_PASSWORD" >> /tmp/redis.conf

echo "Starting Redis server..."
exec redis-server /tmp/redis.conf
