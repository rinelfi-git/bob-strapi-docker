# Utiliser Node 22 LTS sur Debian Bookworm (inclut build tools)
FROM node:22-bookworm

# Installer msmtp (alternative légère à sendmail)
RUN apt-get update && \
    apt-get install -y --no-install-recommends msmtp && \
    ln -sf /usr/bin/msmtp /usr/sbin/sendmail && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Activer yarn via corepack
RUN corepack enable && corepack prepare yarn@stable --activate

# Définir le répertoire de travail
WORKDIR /app/bob

# Copier le script runtime dans /opt
COPY runtime.sh /opt/runtime.sh
RUN chmod +x /opt/runtime.sh

# Exposer le port 1337 (port par défaut de Strapi)
EXPOSE 1337

# Point d'entrée : exécuter le script runtime
ENTRYPOINT ["/opt/runtime.sh"]
