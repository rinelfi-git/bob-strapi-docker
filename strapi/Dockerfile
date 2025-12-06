# Utiliser Node 20 LTS comme image de base
FROM node:20-alpine

# Installer msmtp (alternative légère à sendmail pour Alpine)
# et créer un lien symbolique pour la compatibilité avec Strapi
RUN apk add --no-cache msmtp && \
    ln -sf /usr/bin/msmtp /usr/sbin/sendmail

# Définir le répertoire de travail
WORKDIR /app/bob

# Copier le script runtime dans /opt
COPY runtime.sh /opt/runtime.sh
RUN chmod +x /opt/runtime.sh

# Exposer le port 1337 (port par défaut de Strapi)
EXPOSE 1337

# Point d'entrée : exécuter le script runtime
ENTRYPOINT ["/opt/runtime.sh"]
