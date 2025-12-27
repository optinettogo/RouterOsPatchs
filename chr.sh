#!/bin/bash
set -e

# ---------------------------------------------------------
# 🎨 PERSONNALISATION OPTINET TOGO
# ---------------------------------------------------------
BANNER="
###########################################################
#          🚀 OPTINET TOGO - AUTO DEPLOYMENT             #
#            RouterOS Patched Infrastructure              #
###########################################################
"
echo "$BANNER"

_ask() {
	local _redo=0
	read resp
	case "$resp" in
	!)	echo "Type 'exit' to return to setup."; sh; _redo=1 ;;
	!*)	eval "${resp#?}"; _redo=1 ;;
	esac
	return $_redo
}

ask() {
	local _question="$1" _default="$2"
	while :; do
		printf %s "$_question "
		[ -z "$_default" ] || printf "[%s] " "$_default"
		_ask && : ${resp:=$_default} && break
	done
}

ask_until() { resp=; while [ -z "$resp" ] ; do ask "$1" "$2"; done; }
yesno() { case $1 in [Yy]) return 0;; esac; return 1; }
ask_yesno() { while true; do ask "$1" "$2"; case "$resp" in Y|y|N|n) break;; esac; done; yesno "$resp"; }

select_language() {
    while true; do
        echo "Select your language / Choisissez votre langue :"
        echo "1. English"
        echo "2. Français (Optinet Togo)"
        ask_until "Option :" "2"
        case $resp in
            1) MSG_ARCH="Arch:"; MSG_BOOTMODE="BootMode:"; MSG_STORAGE_DEVICE="Input storage device name:"; MSG_ADDRESS="Input IP:"; MSG_GATEWAY="Gateway:"; MSG_DNS="DNS:"; MSG_SELECT_VERSION="Select version:"; MSG_STABLE="stable (v7)"; MSG_TEST="testing (v7)"; MSG_PLEASE_CHOOSE="Choose [1-2]:"; MSG_SELECTED_VERSION="Selected:"; MSG_FILE_DOWNLOAD="Downloading:"; MSG_DOWNLOAD_ERROR="Error: wget/curl missing."; MSG_DOWNLOAD_FAILED="Error: Download failed!"; MSG_OPERATION_ABORTED="Aborted."; MSG_WARNING="Warn: Data on /dev/%s will be LOST!"; MSG_REBOOTING="Rebooting..."; MSG_ADMIN_PASSWORD="Admin password:"; MSG_AUTO_RUN_FILE_CREATED="Autorun created."; MSG_CONFIRM_CONTINUE="Continue? [y/n]" ;;
            2) MSG_ARCH="Architecture CPU :"; MSG_BOOTMODE="Mode de démarrage :"; MSG_STORAGE_DEVICE="Nom du disque cible (ex: sda) :"; MSG_ADDRESS="Adresse IP du serveur :"; MSG_GATEWAY="Passerelle (Gateway) :"; MSG_DNS="Serveur DNS :"; MSG_SELECT_VERSION="Sélectionnez la version Optinet :"; MSG_STABLE="Stable (v7 - Recommandé)"; MSG_TEST="Testing (v7)"; MSG_PLEASE_CHOOSE="Votre choix [1-2] :"; MSG_SELECTED_VERSION="Version sélectionnée :"; MSG_FILE_DOWNLOAD="Téléchargement de :"; MSG_DOWNLOAD_ERROR="Erreur : wget ou curl absent."; MSG_DOWNLOAD_FAILED="Erreur : Téléchargement échoué !"; MSG_OPERATION_ABORTED="Opération annulée."; MSG_WARNING="ATTENTION : Les données sur /dev/%s seront EFFACÉES !"; MSG_REBOOTING="Installation terminée, redémarrage..."; MSG_ADMIN_PASSWORD="Nouveau mot de passe admin :"; MSG_AUTO_RUN_FILE_CREATED="Fichier de configuration injecté."; MSG_CONFIRM_CONTINUE="Voulez-vous continuer ? [y/n]" ;;
            *) echo "Option invalide !"; continue ;;
        esac
        break
    done
}

show_system_info() {
    ARCH=$(uname -m); BOOT_MODE=$( [ -d "/sys/firmware/efi" ] && echo "UEFI" || echo "BIOS" )
    echo "$MSG_ARCH $ARCH"; echo "$MSG_BOOTMODE $BOOT_MODE"
}

confirm_storge() {
    STORAGE=$(lsblk -d -n -o NAME,TYPE | awk '$2=="disk"{print $1; exit}') || STORAGE="sda"
    ask_until "$MSG_STORAGE_DEVICE" "$STORAGE"; STORAGE=$resp
}

confirm_address() {
    ETH=$(ip route show default | grep '^default' | awk '{print $5}')
    ADDRESS=$(ip addr show $ETH | grep global | awk '{print $2}' | head -n 1)
    GATEWAY=$(ip route list | grep default | awk '{print $3}')
    DNS=$(grep '^nameserver' /etc/resolv.conf | awk '{print $2}' | head -n 1)
    [ -z "$DNS" ] && DNS="1.1.1.1"
    ask_until "$MSG_ADDRESS" "$ADDRESS"; ADDRESS=$resp
    ask_until "$MSG_GATEWAY" "$GATEWAY"; GATEWAY=$resp
    ask_until "$MSG_DNS" "$DNS"; DNS=$resp
}

http_get() {
    local url=$1; local dest=$2
    if command -v curl >/dev/null 2>&1; then
        [ -z "$dest" ] && curl -Ls "$url" || curl -L -# -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        [ -z "$dest" ] && wget -qO- "$url" || wget --no-check-certificate -O "$dest" "$url"
    else echo "$MSG_DOWNLOAD_ERROR"; exit 1; fi
}

select_version() {
    while true; do
        echo "$MSG_SELECT_VERSION"
        echo "1. $MSG_STABLE"
        echo "2. $MSG_TEST"
        read -p "$MSG_PLEASE_CHOOSE " version_choice
        case $version_choice in
            1) VERSION=$(http_get "https://patch.optinettogo.com/routeros/NEWESTa7.stable" | cut -d' ' -f1); V7=1 ;;
            2) VERSION=$(http_get "https://patch.optinettogo.com/routeros/NEWESTa7.testing" | cut -d' ' -f1); V7=1 ;;
            *) echo "Option invalide !"; continue ;;
        esac
        echo "$MSG_SELECTED_VERSION $VERSION"; break
    done
}

download_image(){
    # Nettoyage de la version (on enlève le 'v' pour correspondre au lien manuel du Boss)
    VERSION_CLEAN=$(echo $VERSION | sed 's/^v//')
    
    case $ARCH in
        x86_64)
            if [[ $BOOT_MODE == "BIOS" ]]; then
                IMG_NAME="install-image-$VERSION_CLEAN.img.zip"
            else
                IMG_NAME="chr-$VERSION_CLEAN.img.zip"
            fi ;;
        aarch64)
            IMG_NAME="chr-$VERSION_CLEAN-arm64.img.zip" ;;
        *) echo "Arch non supportée"; exit 1 ;;
    esac

    # FIX CRITIQUE : Utilisation de VERSION_CLEAN pour le dossier aussi !
    IMG_URL="https://patch.optinettogo.com/routeros/$VERSION_CLEAN/$IMG_NAME"
    echo "$MSG_FILE_DOWNLOAD $IMG_URL"
    
    if ! http_get "$IMG_URL" "/tmp/chr.img.zip"; then
        echo "$MSG_DOWNLOAD_FAILED"; exit 1
    fi

    unzip -qo /tmp/chr.img.zip -d /tmp
    mv /tmp/*.img /tmp/chr.img
}

create_autorun() {
    if LOOP=$(losetup -Pf --show /tmp/chr.img 2>/dev/null); then
        sleep 1; MNT=/tmp/chr; mkdir -p $MNT
        if mount "${LOOP}p2" "$MNT" 2>/dev/null; then
            confirm_address
            RANDOM_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12)
            ask_until "$MSG_ADMIN_PASSWORD" "$RANDOM_PASS"; FINAL_PASS=$resp
            mkdir -p "$MNT/rw"
            cat <<EOF > "$MNT/rw/autorun.scr"
/user set admin password="$FINAL_PASS"
/ip dns set servers=$DNS
/ip address add address=$ADDRESS interface=ether1
/ip route add gateway=$GATEWAY
EOF
            echo "$MSG_AUTO_RUN_FILE_CREATED"; umount $MNT; losetup -d "$LOOP"
        else losetup -d "$LOOP"; echo "Erreur de montage partition."; fi
    fi
}

write_and_reboot() {
	confirm_storge
    printf "$MSG_WARNING\n" "$STORAGE"
    ask_yesno "$MSG_CONFIRM_CONTINUE"
    if [ $? -ne 0 ]; then exit 1; fi
    dd if=/tmp/chr.img of=/dev/$STORAGE bs=4M conv=fsync
    echo "$MSG_REBOOTING"
    reboot -f
}

select_language; show_system_info; select_version; download_image; create_autorun; write_and_reboot
