#!/bin/bash

# =============================================================================
# Script de sauvegarde et restauration Strapi
#
# Usage:
#   ./strapi-data.sh                    # Export (crée une archive horodatée)
#   ./strapi-data.sh --restore FILE     # Import depuis une archive
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="strapi_backup_$TIMESTAMP"
TEMP_DIR="/tmp/$BACKUP_NAME"

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# EXPORT
# =============================================================================
do_export() {
    log_info "Démarrage de l'export Strapi..."

    cd "$SCRIPT_DIR"

    # Créer le répertoire temporaire
    mkdir -p "$TEMP_DIR"
    log_info "Répertoire temporaire: $TEMP_DIR"

    # 1. Export de la base de données Strapi
    log_info "Export de la base de données..."
    docker compose exec -T strapi yarn strapi export --exclude files --no-encrypt --file /tmp/database

    # Copier le fichier exporté depuis le container
    docker compose cp strapi:/tmp/database.tar.gz "$TEMP_DIR/database.tar.gz"
    log_success "Base de données exportée"

    # Nettoyer le fichier temporaire dans le container
    docker compose exec -T strapi rm -f /tmp/database.tar.gz

    # 2. Compression des uploads
    log_info "Compression des uploads..."

    # Vérifier si le dossier uploads existe dans le container
    if docker compose exec -T strapi test -d /app/bob/public/uploads; then
        docker compose exec -T strapi tar -czf /tmp/uploads.tar.gz -C /app/bob/public uploads
        docker compose cp strapi:/tmp/uploads.tar.gz "$TEMP_DIR/uploads.tar.gz"
        docker compose exec -T strapi rm -f /tmp/uploads.tar.gz
        log_success "Uploads compressés"
    else
        log_warning "Dossier uploads non trouvé, création d'une archive vide"
        mkdir -p "$TEMP_DIR/uploads"
        tar -czf "$TEMP_DIR/uploads.tar.gz" -C "$TEMP_DIR" uploads
        rm -rf "$TEMP_DIR/uploads"
    fi

    # 3. Créer l'archive finale horodatée
    log_info "Création de l'archive finale..."
    FINAL_ARCHIVE="$SCRIPT_DIR/${BACKUP_NAME}.tar.gz"
    tar -czf "$FINAL_ARCHIVE" -C "$TEMP_DIR" .

    # Nettoyer le répertoire temporaire
    rm -rf "$TEMP_DIR"

    log_success "Sauvegarde terminée: $FINAL_ARCHIVE"
    log_info "Taille: $(du -h "$FINAL_ARCHIVE" | cut -f1)"
}

# =============================================================================
# IMPORT / RESTORE
# =============================================================================
do_restore() {
    local ARCHIVE_FILE="$1"

    # Vérifier que le fichier existe
    if [ ! -f "$ARCHIVE_FILE" ]; then
        log_error "Fichier non trouvé: $ARCHIVE_FILE"
        exit 1
    fi

    log_info "Démarrage de la restauration depuis: $ARCHIVE_FILE"

    cd "$SCRIPT_DIR"

    # Créer le répertoire temporaire
    RESTORE_DIR="/tmp/strapi_restore_$$"
    mkdir -p "$RESTORE_DIR"
    log_info "Répertoire temporaire: $RESTORE_DIR"

    # 1. Décompresser l'archive principale
    log_info "Décompression de l'archive..."
    tar -xzf "$ARCHIVE_FILE" -C "$RESTORE_DIR"
    log_success "Archive décompressée"

    # 2. Restaurer les uploads
    log_info "Restauration des uploads..."

    if [ -f "$RESTORE_DIR/uploads.tar.gz" ]; then
        # Supprimer l'ancien dossier uploads dans le container
        log_info "Suppression de l'ancien dossier uploads..."
        docker compose exec -T strapi rm -rf /app/bob/public/uploads

        # Copier l'archive uploads dans le container
        docker compose cp "$RESTORE_DIR/uploads.tar.gz" strapi:/tmp/uploads.tar.gz

        # Décompresser dans le bon dossier
        docker compose exec -T strapi tar -xzf /tmp/uploads.tar.gz -C /app/bob/public

        # Nettoyer
        docker compose exec -T strapi rm -f /tmp/uploads.tar.gz

        log_success "Uploads restaurés"
    else
        log_warning "Fichier uploads.tar.gz non trouvé dans l'archive"
    fi

    # 3. Restaurer la base de données
    log_info "Restauration de la base de données..."

    if [ -f "$RESTORE_DIR/database.tar.gz" ]; then
        # Copier le fichier database dans le container
        docker compose cp "$RESTORE_DIR/database.tar.gz" strapi:/tmp/database.tar.gz

        # Importer la base de données
        docker compose exec -T strapi yarn strapi import --file /tmp/database.tar.gz --force

        # Nettoyer
        docker compose exec -T strapi rm -f /tmp/database.tar.gz

        log_success "Base de données restaurée"
    else
        log_error "Fichier database.tar.gz non trouvé dans l'archive"
        rm -rf "$RESTORE_DIR"
        exit 1
    fi

    # Nettoyer le répertoire temporaire
    rm -rf "$RESTORE_DIR"

    # Supprimer le fichier d'archive après import réussi
    log_info "Suppression du fichier d'archive..."
    rm -f "$ARCHIVE_FILE"
    log_success "Fichier d'archive supprimé: $ARCHIVE_FILE"

    log_success "Restauration terminée avec succès!"
    log_warning "Redémarrez Strapi pour appliquer les changements: docker compose restart strapi"
}

# =============================================================================
# MAIN
# =============================================================================
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  (aucune)              Créer une sauvegarde horodatée"
    echo "  --restore FILE        Restaurer depuis une archive"
    echo "  --help, -h            Afficher cette aide"
    echo ""
    echo "Exemples:"
    echo "  $0                                    # Export"
    echo "  $0 --restore strapi_backup_20240115_120000.tar.gz  # Import"
}

case "${1:-}" in
    --restore)
        if [ -z "${2:-}" ]; then
            log_error "Veuillez spécifier le fichier à restaurer"
            echo "Usage: $0 --restore FICHIER.tar.gz"
            exit 1
        fi
        do_restore "$2"
        ;;
    --help|-h)
        show_help
        ;;
    "")
        do_export
        ;;
    *)
        log_error "Option inconnue: $1"
        show_help
        exit 1
        ;;
esac
