#!/bin/sh
set -e

echo "🚀 Starting Strapi runtime..."
echo "   NODE_ENV: ${NODE_ENV:-production}"

# Naviguer vers le répertoire de l'application
cd /app/bob

# Configurer pnpm pour autoriser les scripts de build (modules natifs)
echo "📝 Configuring pnpm to allow build scripts..."
cat > .npmrc << 'EOF'
# Autoriser tous les scripts de build (nécessaire pour better-sqlite3, mediasoup, sharp, etc.)
ignore-scripts=false
side-effects-cache=true
EOF

# Nettoyer node_modules si les modules natifs ne sont pas compilés
if [ ! -f "node_modules/.pnpm/better-sqlite3@*/node_modules/better-sqlite3/build/Release/better_sqlite3.node" ]; then
  echo "🧹 Cleaning node_modules to rebuild native modules..."
  rm -rf node_modules
fi

echo "📦 Installing dependencies with pnpm..."
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
  # En prod: build puis start
  echo "🔨 Mode PRODUCTION - Building Strapi..."
  pnpm build
  echo "▶️  Starting Strapi..."
  exec pnpm start
fi
