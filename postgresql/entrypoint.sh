#!/bin/bash
set -e

echo "🚀 Démarrage de PostgreSQL avec auto-configuration..."

# Vérifier que les variables d'environnement requises sont définies
if [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_PASSWORD" ] || [ -z "$POSTGRES_DB" ]; then
    echo "❌ Erreur: POSTGRES_USER, POSTGRES_PASSWORD et POSTGRES_DB doivent être définis"
    exit 1
fi

# Fixer les permissions du répertoire de données
echo "🔧 Configuration des permissions..."
chown -R postgres:postgres "$PGDATA"
chmod 700 "$PGDATA"
chown -R postgres:postgres /var/run/postgresql

# Initialiser le cluster PostgreSQL si nécessaire
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "📦 Initialisation du cluster PostgreSQL..."

    # Créer un fichier temporaire pour le mot de passe superuser
    PWFILE=$(mktemp)
    echo "postgres" > "$PWFILE"
    chown postgres:postgres "$PWFILE"
    chmod 600 "$PWFILE"

    # Initialiser le cluster en tant que postgres
    su postgres -c "/usr/lib/postgresql/16/bin/initdb \
        --username=postgres \
        --encoding=UTF8 \
        --locale=fr_FR.UTF-8 \
        --auth=scram-sha-256 \
        --pwfile=$PWFILE \
        -D $PGDATA"

    # Supprimer le fichier temporaire
    rm -f "$PWFILE"

    echo "✅ Cluster PostgreSQL initialisé"

    # Démarrer PostgreSQL temporairement pour créer l'utilisateur et la base
    echo "🔧 Démarrage temporaire pour configuration initiale..."
    su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D $PGDATA -o \"-c listen_addresses=''\" -w start"

    # Créer l'utilisateur avec le mot de passe
    echo "👤 Création de l'utilisateur '$POSTGRES_USER'..."
    su postgres -c "/usr/lib/postgresql/16/bin/psql -v ON_ERROR_STOP=1 --username postgres -c \"CREATE USER \\\"$POSTGRES_USER\\\" WITH PASSWORD '$POSTGRES_PASSWORD' CREATEDB;\""

    # Créer la base de données
    echo "🗄️  Création de la base de données '$POSTGRES_DB'..."
    su postgres -c "/usr/lib/postgresql/16/bin/psql -v ON_ERROR_STOP=1 --username postgres -c \"CREATE DATABASE \\\"$POSTGRES_DB\\\" WITH OWNER \\\"$POSTGRES_USER\\\" ENCODING 'UTF8' LC_COLLATE 'fr_FR.UTF-8' LC_CTYPE 'fr_FR.UTF-8' TEMPLATE template0;\""
    su postgres -c "/usr/lib/postgresql/16/bin/psql -v ON_ERROR_STOP=1 --username postgres -c \"GRANT ALL PRIVILEGES ON DATABASE \\\"$POSTGRES_DB\\\" TO \\\"$POSTGRES_USER\\\";\""

    # Arrêter PostgreSQL temporaire
    su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D $PGDATA -m fast -w stop"

    echo "✅ Configuration initiale terminée"
    echo "   Utilisateur: $POSTGRES_USER"
    echo "   Base de données: $POSTGRES_DB"
else
    echo "📂 Cluster PostgreSQL existant détecté"
fi

echo "🚀 Démarrage du serveur PostgreSQL..."
exec su postgres -c "/usr/lib/postgresql/16/bin/postgres -D $PGDATA -c config_file=/etc/postgresql/postgresql.conf"
