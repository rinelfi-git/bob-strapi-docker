#!/bin/sh

# Desactiver Yarn PnP pour compatibilite Docker
export YARN_NODE_LINKER=node-modules

# Installer les dependances si node_modules n'existe pas ou si package.json a change
if [ ! -d "node_modules" ] || [ "package.json" -nt "node_modules" ]; then
    echo "Installing dependencies..."
    yarn install
fi

# Lancer le serveur de dev sur toutes les interfaces
exec yarn dev --hostname 0.0.0.0
