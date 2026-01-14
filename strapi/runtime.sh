#!/bin/sh
set -e

echo "🚀 Starting Strapi runtime..."
echo "   NODE_ENV: ${NODE_ENV:-production}"

# Naviguer vers le répertoire de l'application
cd /app/bob
rm -rf /app/bob/dist

echo "📦 Installing dependencies with yarn..."
yarn install

# Vérifier l'environnement
if [ "$NODE_ENV" = "development" ]; then
  # En dev: générer les types puis lancer develop
  echo "🔧 Mode DEVELOPMENT - Starting with yarn develop..."
  exec yarn develop
else
  # En prod: build puis start
  echo "🔨 Mode PRODUCTION - Building Strapi..."
  yarn build
  echo "▶️  Starting Strapi..."
  exec yarn start
fi
