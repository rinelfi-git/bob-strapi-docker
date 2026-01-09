#!/bin/sh
set -e

echo "🚀 Starting Strapi runtime..."
echo "   NODE_ENV: ${NODE_ENV:-production}"

# Naviguer vers le répertoire de l'application
cd /app/bob

echo "📦 Installing dependencies with yarn..."
yarn install

# Générer les types TypeScript (nécessaire pour la compilation)
echo "🔄 Generating TypeScript types..."
yarn strapi ts:generate-types

# Vérifier l'environnement
if [ "$NODE_ENV" = "development" ]; then
  echo "🔧 Mode DEVELOPMENT - Starting with yarn develop..."
  exec yarn develop
else
  echo "🔨 Mode PRODUCTION - Building Strapi..."
  yarn build
  echo "▶️  Starting Strapi..."
  exec yarn start
fi
