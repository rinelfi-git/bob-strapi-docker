#!/bin/sh
set -e

echo "🚀 Starting Strapi runtime..."

# Naviguer vers le répertoire de l'application
cd /app/bob

echo "📦 Installing dependencies with yarn..."
yarn install

echo "🔨 Building Strapi..."
yarn build

echo "▶️  Starting Strapi..."
exec yarn start
