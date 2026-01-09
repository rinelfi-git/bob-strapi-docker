# Utiliser Node 22 LTS sur Debian Bookworm Slim (meilleure compatibilité réseau)
FROM node:22-bookworm-slim

# Installer msmtp (alternative légère à sendmail)
# ca-certificates pour les connexions TLS (APNs, etc.)
# build-essential et python3 pour compiler better-sqlite3 et autres modules natifs
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        msmtp \
        ca-certificates \
        curl \
        iputils-ping \
        build-essential \
        python3 \
        && \
    update-ca-certificates && \
    ln -sf /usr/bin/msmtp /usr/sbin/sendmail && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Définir le répertoire de travail
WORKDIR /app/bob

# Copier le script runtime dans /opt
COPY runtime.sh /opt/runtime.sh
RUN chmod +x /opt/runtime.sh

# Exposer le port 1337 (port par défaut de Strapi)
EXPOSE 1337

# Point d'entrée : exécuter le script runtime
ENTRYPOINT ["/opt/runtime.sh"]
