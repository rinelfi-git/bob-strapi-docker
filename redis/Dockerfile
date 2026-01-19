# Utiliser Redis 7 Bookworm slim comme image de base
FROM redis:7-bookworm

# Installer openssl pour générer le mot de passe
RUN apt-get update && apt-get install -y --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/*

# Créer le répertoire de configuration
RUN mkdir -p /usr/local/etc/redis

# Copier le fichier de configuration Redis
COPY redis.conf /usr/local/etc/redis/redis.conf

# Copier le script d'entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Exposer le port Redis (interne au réseau Docker uniquement)
EXPOSE 6379

# Point d'entrée personnalisé
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
