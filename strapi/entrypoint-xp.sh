#!/bin/sh
set -e

if [ ! -f node_modules/.yarn-state.yml ]; then
  echo "[XP] node_modules manquant, lancement de yarn install..."
  yarn install
fi

exec "$@"
