#!/bin/bash
set -e

echo "🚀 Démarrage de PostgreSQL avec auto-configuration..."

# Vérifier que les variables d'environnement requises sont définies
if [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_PASSWORD" ] || [ -z "$POSTGRES_DB" ]; then
    echo "❌ Erreur: POSTGRES_USER, POSTGRES_PASSWORD et POSTGRES_DB doivent être définis"
    exit 1
fi

# Initialiser le cluster PostgreSQL si nécessaire
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "📦 Initialisation du cluster PostgreSQL..."

    # Initialiser le cluster avec l'encodage UTF-8
    /usr/lib/postgresql/16/bin/initdb \
        --username=postgres \
        --encoding=UTF8 \
        --locale=fr_FR.UTF-8 \
        --auth=scram-sha-256 \
        --pwfile=<(echo "postgres") \
        -D "$PGDATA"

    echo "✅ Cluster PostgreSQL initialisé"

    # Démarrer PostgreSQL temporairement pour créer l'utilisateur et la base
    echo "🔧 Démarrage temporaire pour configuration initiale..."
    /usr/lib/postgresql/16/bin/pg_ctl -D "$PGDATA" -o "-c listen_addresses=''" -w start

    # Créer l'utilisateur avec le mot de passe
    echo "👤 Création de l'utilisateur '$POSTGRES_USER'..."
    /usr/lib/postgresql/16/bin/psql -v ON_ERROR_STOP=1 --username postgres <<-EOSQL
        CREATE USER "$POSTGRES_USER" WITH PASSWORD '$POSTGRES_PASSWORD' CREATEDB;
EOSQL

    # Créer la base de données
    echo "🗄️  Création de la base de données '$POSTGRES_DB'..."
    /usr/lib/postgresql/16/bin/psql -v ON_ERROR_STOP=1 --username postgres <<-EOSQL
        CREATE DATABASE "$POSTGRES_DB" WITH OWNER "$POSTGRES_USER" ENCODING 'UTF8' LC_COLLATE 'fr_FR.UTF-8' LC_CTYPE 'fr_FR.UTF-8' TEMPLATE template0;
        GRANT ALL PRIVILEGES ON DATABASE "$POSTGRES_DB" TO "$POSTGRES_USER";
EOSQL

    # Arrêter PostgreSQL temporaire
    /usr/lib/postgresql/16/bin/pg_ctl -D "$PGDATA" -m fast -w stop

    echo "✅ Configuration initiale terminée"
    echo "   Utilisateur: $POSTGRES_USER"
    echo "   Base de données: $POSTGRES_DB"
else
    echo "📂 Cluster PostgreSQL existant détecté"
fi

echo "🚀 Démarrage du serveur PostgreSQL..."
exec /usr/lib/postgresql/16/bin/postgres -D "$PGDATA" -c config_file=/etc/postgresql/postgresql.conf
