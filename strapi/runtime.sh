#!/bin/sh
set -e

echo "🚀 Starting Strapi runtime..."
echo "   NODE_ENV: ${NODE_ENV:-production}"

# Naviguer vers le répertoire de l'application
cd /app/bob

echo "📦 Installing dependencies with pnpm..."
# --frozen-lockfile: utilise le lockfile existant (plus rapide, reproductible)
# Fallback sur pnpm install normal si pas de lockfile
pnpm install --frozen-lockfile 2>/dev/null || pnpm install

# Supprimer les types générés pour forcer la régénération
# (évite les conflits de cache ou types obsolètes)
echo "🗑️  Cleaning generated types..."
rm -rf types/generated

# Vérifier l'environnement
if [ "$NODE_ENV" = "development" ]; then
  # En dev: Strapi develop régénère automatiquement les types
  echo "🔧 Mode DEVELOPMENT - Starting with pnpm develop..."
  echo "   (Types will be auto-generated on startup)"
  exec pnpm develop
else
  # En prod: générer les types, puis build, puis start
  echo "🔄 Generating TypeScript types..."
  # Timeout de 120s pour la génération des types (peut prendre du temps)
  timeout 30 pnpm strapi ts:generate-types --silent || echo "⚠️  Types generation timed out, continuing..."
  echo "🔨 Mode PRODUCTION - Building Strapi..."
  pnpm build
  echo "▶️  Starting Strapi..."
  exec pnpm start
fi
