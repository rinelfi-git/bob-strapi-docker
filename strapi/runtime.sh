#!/bin/sh
set -e

echo "🚀 Starting Strapi runtime..."
echo "   NODE_ENV: ${NODE_ENV:-production}"

# Naviguer vers le répertoire de l'application
cd /app/bob

echo "📦 Installing dependencies with yarn..."
yarn install

# Vérifier l'environnement
if [ "$NODE_ENV" = "development" ]; then
  # En dev: générer les types puis lancer develop
  echo "🔄 Generating TypeScript types..."
  yarn strapi ts:generate-types
  echo "🔧 Mode DEVELOPMENT - Starting with yarn develop..."
  exec yarn develop
else
  # En prod: build, générer les types, puis start
  echo "🔨 Mode PRODUCTION - Building Strapi..."
  yarn build
  echo "🔄 Generating TypeScript types..."
  # Timeout car ts:generate-types reste bloqué (connexions Redis/APNs/Firebase ouvertes)
  timeout 30 yarn strapi ts:generate-types || echo "⚠️ Typegen terminé (timeout normal)"
  echo "▶️  Starting Strapi..."
  exec yarn start
fi
