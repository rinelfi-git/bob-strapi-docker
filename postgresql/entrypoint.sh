#!/bin/sh
set -e

echo "Demarrage de PostgreSQL avec auto-configuration..."

# Vérifier que les variables d'environnement requises sont définies
if [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_PASSWORD" ] || [ -z "$POSTGRES_DB" ]; then
    echo "Erreur: POSTGRES_USER, POSTGRES_PASSWORD et POSTGRES_DB doivent etre definis"
    exit 1
fi

# PGDATA est défini par l'image postgres:16-alpine (/var/lib/postgresql/data)
PGDATA="${PGDATA:-/var/lib/postgresql/data}"
export PGDATA

# Fixer les permissions du répertoire de données
echo "Configuration des permissions..."
chown -R postgres:postgres "$PGDATA"
chmod 700 "$PGDATA"
chown -R postgres:postgres /var/run/postgresql 2>/dev/null || true

# Initialiser le cluster PostgreSQL si nécessaire
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "Initialisation du cluster PostgreSQL..."

    # Initialiser le cluster avec auth=trust pour permettre la configuration initiale
    su-exec postgres initdb \
        --username=postgres \
        --encoding=UTF8 \
        --locale=fr_FR.UTF-8 \
        --auth=trust \
        -D "$PGDATA"

    echo "Cluster PostgreSQL initialise"

    # Démarrer PostgreSQL temporairement pour créer l'utilisateur et la base
    echo "Demarrage temporaire pour configuration initiale..."
    su-exec postgres pg_ctl -D "$PGDATA" -o "-c listen_addresses=''" -w start

    # Créer l'utilisateur avec le mot de passe
    echo "Creation de l'utilisateur '$POSTGRES_USER'..."
    su-exec postgres psql -v ON_ERROR_STOP=1 --username postgres -c "CREATE USER \"$POSTGRES_USER\" WITH PASSWORD '$POSTGRES_PASSWORD' CREATEDB;"

    # Créer la base de données
    echo "Creation de la base de donnees '$POSTGRES_DB'..."
    su-exec postgres psql -v ON_ERROR_STOP=1 --username postgres -c "CREATE DATABASE \"$POSTGRES_DB\" WITH OWNER \"$POSTGRES_USER\" ENCODING 'UTF8' LC_COLLATE 'fr_FR.UTF-8' LC_CTYPE 'fr_FR.UTF-8' TEMPLATE template0;"
    su-exec postgres psql -v ON_ERROR_STOP=1 --username postgres -c "GRANT ALL PRIVILEGES ON DATABASE \"$POSTGRES_DB\" TO \"$POSTGRES_USER\";"

    # Arrêter PostgreSQL temporaire
    su-exec postgres pg_ctl -D "$PGDATA" -m fast -w stop

    # Copier la configuration sécurisée (scram-sha-256)
    echo "Application de la configuration securisee..."
    cp /etc/postgresql/pg_hba.conf "$PGDATA/pg_hba.conf"
    chown postgres:postgres "$PGDATA/pg_hba.conf"

    echo "Configuration initiale terminee"
    echo "   Utilisateur: $POSTGRES_USER"
    echo "   Base de donnees: $POSTGRES_DB"
else
    echo "Cluster PostgreSQL existant detecte"
fi

echo "Demarrage du serveur PostgreSQL..."
exec su-exec postgres postgres -D "$PGDATA" -c config_file=/etc/postgresql/postgresql.conf
