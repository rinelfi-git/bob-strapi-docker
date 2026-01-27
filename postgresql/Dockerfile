# Image de base PostgreSQL 16 Alpine (légère ~80MB)
FROM postgres:16-alpine

# Installer musl-locales pour le support fr_FR.UTF-8
RUN apk add --no-cache \
    musl-locales \
    musl-locales-lang \
    icu-data-full

# Variables d'environnement pour les locales françaises
ENV LANG=fr_FR.UTF-8 \
    LC_ALL=fr_FR.UTF-8 \
    MUSL_LOCPATH=/usr/share/i18n/locales/musl

# Créer le répertoire de configuration
RUN mkdir -p /etc/postgresql \
    && chown postgres:postgres /etc/postgresql

# Copier les fichiers de configuration
COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY pg_hba.conf /etc/postgresql/pg_hba.conf
RUN chown postgres:postgres /etc/postgresql/*.conf

# Copier le script d'entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Exposer le port PostgreSQL
EXPOSE 5432

# Point d'entrée personnalisé
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
