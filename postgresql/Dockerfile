# Image de base Debian Bookworm Slim
FROM debian:bookworm-slim

# Variables d'environnement pour PostgreSQL
ENV PGDATA=/var/lib/postgresql/data \
    LANG=fr_FR.UTF-8 \
    LC_ALL=fr_FR.UTF-8

# Installation de PostgreSQL 16 et des dépendances
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg2 \
    curl \
    ca-certificates \
    locales \
    gosu \
    && echo "fr_FR.UTF-8 UTF-8" >> /etc/locale.gen \
    && locale-gen \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    postgresql-16 \
    && rm -rf /var/lib/apt/lists/*

# Créer les répertoires nécessaires
RUN mkdir -p /var/lib/postgresql/data \
    && mkdir -p /var/run/postgresql \
    && mkdir -p /etc/postgresql \
    && chown -R postgres:postgres /var/lib/postgresql \
    && chown -R postgres:postgres /var/run/postgresql \
    && chown -R postgres:postgres /etc/postgresql \
    && chmod 700 /var/lib/postgresql/data

# Copier les fichiers de configuration
COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY pg_hba.conf /etc/postgresql/pg_hba.conf
RUN chown postgres:postgres /etc/postgresql/*.conf

# Copier le script d'entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Exposer le port PostgreSQL
EXPOSE 5432

# Démarrer en root pour fixer les permissions, puis passer à postgres
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
