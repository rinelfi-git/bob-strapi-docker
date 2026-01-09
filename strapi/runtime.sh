#!/bin/sh
set -e

echo "🚀 Starting Strapi runtime..."
echo "   NODE_ENV: ${NODE_ENV:-production}"

# Naviguer vers le répertoire de l'application
cd /app/bob

echo "📦 Installing dependencies with pnpm..."
# Importer yarn.lock si pnpm-lock.yaml n'existe pas
if [ ! -f pnpm-lock.yaml ] && [ -f yarn.lock ]; then
  echo "   Importing yarn.lock to pnpm-lock.yaml..."
  pnpm import
fi
pnpm install

# Vérifier l'environnement
if [ "$NODE_ENV" = "development" ]; then
  # En dev: générer les types puis lancer develop
  echo "🔧 Mode DEVELOPMENT - Starting with pnpm develop..."
  exec pnpm develop
else
  # En prod: build puis start
  echo "🔨 Mode PRODUCTION - Building Strapi..."
  pnpm build
  echo "▶️  Starting Strapi..."
  exec pnpm start
fi
