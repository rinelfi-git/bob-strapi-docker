#!/bin/bash

# Configuration
SOURCE_SERVER="erijania@rinelfi.mg"
SOURCE_PATH="bob/strapi"
SOURCE_UPLOADS="$SOURCE_PATH/public/uploads"
SOURCE_DB="$SOURCE_PATH/.tmp/data.db"

LOCAL_PATH="/home/bob/app/strapi"
LOCAL_UPLOADS="$LOCAL_PATH/public/uploads"
LOCAL_DB="$LOCAL_PATH/.tmp/data.db"

# Génération du timestamp
TIMESTAMP=$(date +"%Y%m%d-%H%M")
ARCHIVE_NAME="uploads-${TIMESTAMP}.tar.gz"

echo "=== Import Strapi depuis rinelfi.mg - $TIMESTAMP ==="

# Étape 1: Compression du dossier uploads sur le serveur source
echo "[1/6] Compression du dossier uploads sur rinelfi.mg..."
ssh "$SOURCE_SERVER" "cd $SOURCE_PATH/public && tar -czvf /tmp/$ARCHIVE_NAME uploads"

if [ $? -ne 0 ]; then
    echo "❌ Erreur lors de la compression. Abandon."
    exit 1
fi

# Étape 2: Téléchargement de l'archive sur ce serveur
echo "[2/6] Téléchargement de l'archive uploads..."
scp "$SOURCE_SERVER:/tmp/$ARCHIVE_NAME" "/tmp/$ARCHIVE_NAME"

if [ $? -ne 0 ]; then
    echo "❌ Erreur lors du téléchargement de l'archive. Abandon."
    exit 1
fi

# Étape 3: Suppression de l'archive sur le serveur source
echo "[3/6] Suppression de l'archive sur rinelfi.mg..."
ssh "$SOURCE_SERVER" "rm -f /tmp/$ARCHIVE_NAME"

# Étape 4: Téléchargement de la base de données
echo "[4/6] Téléchargement de la base de données..."
scp "$SOURCE_SERVER:$SOURCE_DB" "/tmp/data-${TIMESTAMP}.db"

if [ $? -ne 0 ]; then
    echo "❌ Erreur lors du téléchargement de la base de données. Abandon."
    exit 1
fi

# Étape 5: Suppression des données locales et extraction
echo "[5/6] Remplacement du dossier uploads local..."
rm -rf "$LOCAL_UPLOADS"
mkdir -p "$LOCAL_PATH/public"
tar -xzvf "/tmp/$ARCHIVE_NAME" -C "$LOCAL_PATH/public"

if [ $? -ne 0 ]; then
    echo "❌ Erreur lors de l'extraction. Abandon."
    exit 1
fi

# Étape 6: Remplacement de la base de données
echo "[6/6] Remplacement de la base de données locale..."
mkdir -p "$LOCAL_PATH/.tmp"
rm -f "$LOCAL_DB"
mv "/tmp/data-${TIMESTAMP}.db" "$LOCAL_DB"

# Nettoyage
rm -f "/tmp/$ARCHIVE_NAME"

echo ""
echo "✅ === Import terminé avec succès ==="
echo "📁 Données importées dans $LOCAL_PATH :"
echo "  - public/uploads/"
echo "  - .tmp/data.db"
echo ""
echo "💡 Pour utiliser ces données avec Docker, assurez-vous que STRAPI_VOLUME dans .env pointe vers $LOCAL_PATH"
