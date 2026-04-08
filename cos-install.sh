#!/usr/bin/env bash
# ============================================================
#  C-OS Installer  —  cos-install.sh
#  Arch Linux tabanlı C-OS kurulum betiği
# ============================================================

# --- Renkler ---
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'
DIM='\033[2m'; NC='\033[0m'

# --- Repo ---
REPO_RAW="https://raw.githubusercontent.com/canacikbas2010-blip/c-os-repo/main"

# ============================================================
#  BANNER
# ============================================================
show_banner() {
    clear
    echo -e "${CYAN}"
    echo '                                      ________________________________________________'
    echo '                                     /                                                \'
    echo '                                     |         ____           _____    ______         |'
    echo '                                     |        / ___|         /  _  \  /  ___/         |'
    echo '                                     |       | |      _____  | | | |  | |___          |'
    echo '                                     |       | |     |_____| | | | |  \___  \         |'
    echo '                                     |       | |___          | |_| |   ___)  |        |'
    echo '                                     |        \____|         \_____/ /_____ /         |'
    echo '                                     |                                                |'
    echo '                                     |                    Welcome!                    |'
    echo '                                     =================================================='
    echo -e "${NC}"
    echo -e "${DIM}                              Arch Linux tabanlı C-OS Kurulum Sihirbazı${NC}"
    echo
}

# ============================================================
#  YARDIMCI FONKSİYONLAR
# ============================================================
info()    { echo -e "  ${CYAN}[•]${NC} $*"; }
success() { echo -e "  ${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "  ${YELLOW}[!]${NC} $*"; }
error()   { echo -e "  ${RED}[✗]${NC} $*"; exit 1; }
step()    { echo; echo -e "${BOLD}${BLUE}══► $*${NC}"; echo; }

confirm() {
    local msg="$1"
    echo -ne "  ${YELLOW}[?]${NC} ${msg} [e/H]: "
    read -r ans
    [[ "$ans" =~ ^[Ee]$ ]]
}

pause() {
    echo
    echo -ne "  ${DIM}Devam etmek için Enter'a bas...${NC}"
    read -r
}

# ============================================================
#  ÖN KONTROL
# ============================================================
pre_check() {
    step "Sistem Kontrolü"

    [[ $EUID -ne 0 ]] && error "Bu script root olarak çalıştırılmalıdır."

    if ! ping -c1 -W3 archlinux.org &>/dev/null; then
        error "İnternet bağlantısı yok. Kurulum için ağ gereklidir."
    fi
    success "İnternet bağlantısı mevcut."

    if [[ -d /sys/firmware/efi ]]; then
        BOOT_MODE="UEFI"
    else
        BOOT_MODE="BIOS"
    fi
    success "Önyükleme modu: ${BOLD}${BOOT_MODE}${NC}"
}

# ============================================================
#  DİSK SEÇİMİ  (ok tuşu navigasyonu)
# ============================================================
select_disk() {
    step "Disk Seçimi"

    mapfile -t DISKS < <(lsblk -dno NAME,SIZE,TYPE | awk '$3=="disk"{print "/dev/"$1" ("$2")"}')

    if [[ ${#DISKS[@]} -eq 0 ]]; then
        error "Hiç disk bulunamadı."
    fi

    echo -e "  ${BOLD}Kurulacak diski seç:${NC}"
    echo -e "  ${DIM}↑↓ ok tuşları ile gezin, Enter ile seç${NC}"
    echo

    local selected=0
    local key

    # İmleç gizle
    tput civis

    while true; do
        # Listeyi yeniden çiz
        local draw_start=$(( $(tput lines) / 2 - ${#DISKS[@]} ))
        tput cup $draw_start 0 2>/dev/null || true

        for i in "${!DISKS[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e "  ${CYAN}${BOLD}▶  ${DISKS[$i]}${NC}"
            else
                echo -e "     ${DIM}${DISKS[$i]}${NC}"
            fi
        done

        # Tuş oku
        IFS= read -rsn1 key
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key2
            key="$key$key2"
        fi

        case "$key" in
            $'\x1b[A') (( selected > 0 )) && (( selected-- )) ;;
            $'\x1b[B') (( selected < ${#DISKS[@]}-1 )) && (( selected++ )) ;;
            '') break ;;
        esac
    done

    # İmleci geri getir
    tput cnorm

    TARGET_DISK=$(echo "${DISKS[$selected]}" | awk '{print $1}')
    echo
    success "Seçilen disk: ${BOLD}${TARGET_DISK}${NC}"

    echo
    warn "${RED}${BOLD}DİKKAT:${NC} ${TARGET_DISK} üzerindeki TÜM VERİ SİLİNECEK!"
    confirm "Devam etmek istiyor musun?" || { info "Kurulum iptal edildi."; exit 0; }
}

# ============================================================
#  ROOT ŞİFRESİ
# ============================================================
set_root_password() {
    step "Root Şifresi"

    while true; do
        echo -ne "  ${CYAN}[•]${NC} Root şifresi gir: "
        read -rs ROOT_PASS; echo
        [[ -z "$ROOT_PASS" ]] && { warn "Şifre boş olamaz."; continue; }

        echo -ne "  ${CYAN}[•]${NC} Root şifresini tekrar gir: "
        read -rs ROOT_PASS2; echo

        if [[ "$ROOT_PASS" == "$ROOT_PASS2" ]]; then
            success "Root şifresi ayarlandı."
            break
        else
            warn "Şifreler eşleşmedi, tekrar dene."
        fi
    done
}

# ============================================================
#  KULLANICI OLUŞTURMA
# ============================================================
create_user() {
    step "Kullanıcı Oluşturma"

    echo -ne "  ${CYAN}[•]${NC} Kullanıcı adı gir: "
    read -r USERNAME
    [[ -z "$USERNAME" ]] && error "Kullanıcı adı boş olamaz."

    while true; do
        echo -ne "  ${CYAN}[•]${NC} ${USERNAME} için şifre gir: "
        read -rs USER_PASS; echo
        [[ -z "$USER_PASS" ]] && { warn "Şifre boş olamaz."; continue; }

        echo -ne "  ${CYAN}[•]${NC} Şifreyi tekrar gir: "
        read -rs USER_PASS2; echo

        if [[ "$USER_PASS" == "$USER_PASS2" ]]; then
            success "Kullanıcı '${BOLD}${USERNAME}${NC}' ayarlandı."
            break
        else
            warn "Şifreler eşleşmedi, tekrar dene."
        fi
    done
}

# ============================================================
#  HOSTNAME & LOCALE
# ============================================================
set_system_info() {
    step "Sistem Bilgileri"

    echo -ne "  ${CYAN}[•]${NC} Hostname gir [c-os]: "
    read -r HOSTNAME
    HOSTNAME="${HOSTNAME:-c-os}"
    success "Hostname: ${BOLD}${HOSTNAME}${NC}"

    echo -e "  ${CYAN}[•]${NC} Zaman dilimi seçenekleri:"
    select TIMEZONE in "Europe/Istanbul" "UTC" "Europe/London" "America/New_York" "Özel..."; do
        case $TIMEZONE in
            "Özel...")
                echo -ne "  Zaman dilimi gir (ör: Europe/Paris): "
                read -r TIMEZONE
                ;;
        esac
        [[ -n "$TIMEZONE" ]] && break
    done
    success "Zaman dilimi: ${BOLD}${TIMEZONE}${NC}"
}

# ============================================================
#  ÖZet EKRANI
# ============================================================
show_summary() {
    step "Kurulum Özeti"
    echo -e "  ${BOLD}Disk        :${NC} ${TARGET_DISK}"
    echo -e "  ${BOLD}Boot modu   :${NC} ${BOOT_MODE}"
    echo -e "  ${BOLD}Hostname    :${NC} ${HOSTNAME}"
    echo -e "  ${BOLD}Kullanıcı   :${NC} ${USERNAME}"
    echo -e "  ${BOLD}Zaman dilimi:${NC} ${TIMEZONE}"
    echo
    confirm "Kurulumu başlat?" || { info "İptal edildi."; exit 0; }
}

# ============================================================
#  DİSK BÖLÜMLENDİRME
# ============================================================
partition_disk() {
    step "Disk Bölümlendirme"
    info "${TARGET_DISK} bölümlendiriliyor..."

    # Eski imzaları sil
    wipefs -af "${TARGET_DISK}" &>/dev/null
    sgdisk --zap-all "${TARGET_DISK}" &>/dev/null

    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        # GPT: EFI (512M) + swap (2G) + root (kalan)
        parted -s "${TARGET_DISK}" \
            mklabel gpt \
            mkpart EFI  fat32  1MiB   513MiB \
            set 1 esp on \
            mkpart SWAP linux-swap 513MiB 2561MiB \
            mkpart ROOT ext4  2561MiB 100%

        EFI_PART="${TARGET_DISK}1"
        SWAP_PART="${TARGET_DISK}2"
        ROOT_PART="${TARGET_DISK}3"

        mkfs.fat -F32 -n EFI   "${EFI_PART}"  &>/dev/null
        mkswap   -L   SWAP     "${SWAP_PART}" &>/dev/null
        mkfs.ext4 -L  C_OS     "${ROOT_PART}" -F &>/dev/null

        swapon "${SWAP_PART}"
        mount  "${ROOT_PART}" /mnt
        mkdir -p /mnt/boot/efi
        mount "${EFI_PART}" /mnt/boot/efi
    else
        # MBR: boot (512M) + swap (2G) + root (kalan)
        parted -s "${TARGET_DISK}" \
            mklabel msdos \
            mkpart primary ext4       1MiB   513MiB \
            set 1 boot on \
            mkpart primary linux-swap 513MiB 2561MiB \
            mkpart primary ext4       2561MiB 100%

        BOOT_PART="${TARGET_DISK}1"
        SWAP_PART="${TARGET_DISK}2"
        ROOT_PART="${TARGET_DISK}3"

        mkfs.ext4  -L BOOT "${BOOT_PART}" -F &>/dev/null
        mkswap     -L SWAP "${SWAP_PART}"    &>/dev/null
        mkfs.ext4  -L C_OS "${ROOT_PART}" -F &>/dev/null

        swapon "${SWAP_PART}"
        mount  "${ROOT_PART}" /mnt
        mkdir -p /mnt/boot
        mount "${BOOT_PART}" /mnt/boot
    fi

    success "Disk bölümlendirildi ve bağlandı."
}

# ============================================================
#  TEMEL SİSTEM KURULUMU
# ============================================================
install_base() {
    step "Temel Sistem Kurulumu"
    info "pacstrap çalışıyor, bu biraz sürebilir..."

    pacstrap -K /mnt \
        base base-devel linux linux-firmware \
        networkmanager grub efibootmgr os-prober \
        sudo nano git curl wget htop \
        pipewire pipewire-pulse pipewire-alsa wireplumber \
        xdg-user-dirs xdg-utils \
        noto-fonts noto-fonts-emoji ttf-liberation \
        bash-completion \
        2>&1 | while IFS= read -r line; do
            echo -ne "  ${DIM}${line:0:70}${NC}\r"
        done

    echo
    success "Temel paketler kuruldu."

    genfstab -L /mnt >> /mnt/etc/fstab
    success "fstab oluşturuldu."
}

# ============================================================
#  CHROOTa BETIK YAZAR VE ÇALIŞTIRIR
# ============================================================
configure_system() {
    step "Sistem Yapılandırması"

    # chroot betiği yaz
    cat > /mnt/root/cos-chroot.sh << CHROOT_EOF
#!/bin/bash
set -e

# Locale
sed -i 's/#tr_TR.UTF-8/tr_TR.UTF-8/' /etc/locale.gen
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=tr_TR.UTF-8" > /etc/locale.conf
echo "KEYMAP=trq"       > /etc/vconsole.conf

# Hostname
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# Zaman
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

# NetworkManager
systemctl enable NetworkManager

# Root şifresi
echo "root:${ROOT_PASS}" | chpasswd

# Kullanıcı
useradd -m -G wheel,audio,video,storage,optical -s /bin/bash "${USERNAME}"
echo "${USERNAME}:${USER_PASS}" | chpasswd

# sudo wheel
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# initramfs
mkinitcpio -P

# GRUB
if [[ -d /sys/firmware/efi ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi \
                 --bootloader-id="C-OS" --recheck
else
    grub-install --target=i386-pc ${TARGET_DISK} --recheck
fi

# GRUB tema & başlık
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/'                 /etc/default/grub
sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="C-OS"/'    /etc/default/grub
sed -i 's/^#GRUB_DISABLE_OS_PROBER/GRUB_DISABLE_OS_PROBER/' /etc/default/grub || true

grub-mkconfig -o /boot/grub/grub.cfg

echo "CHROOT_DONE"
CHROOT_EOF

    chmod +x /mnt/root/cos-chroot.sh

    # TARGET_DISK'i chroot içine ilet
    export TARGET_DISK
    arch-chroot /mnt /bin/bash -c "
        export TARGET_DISK='${TARGET_DISK}'
        /root/cos-chroot.sh
    " | while IFS= read -r line; do
        [[ "$line" == "CHROOT_DONE" ]] && success "Sistem yapılandırması tamamlandı." && continue
        echo -e "  ${DIM}${line}${NC}"
    done

    rm -f /mnt/root/cos-chroot.sh
}

# ============================================================
#  C-OS REPO — İCONLAR & WALLPAPERLAR
# ============================================================
install_cos_assets() {
    step "C-OS Repo Varlıkları (İkonlar & Duvar Kağıtları)"

    REPO_RAW="https://raw.githubusercontent.com/canacikbas2010-blip/c-os-repo/main"

    # Hedef dizinler
    ICON_DIR="/mnt/usr/share/icons/c-os"
    WALL_DIR="/mnt/usr/share/backgrounds/c-os"
    mkdir -p "${ICON_DIR}" "${WALL_DIR}"

    # --- İkonları indir ---
    info "İkonlar indiriliyor..."

    # Repo'daki ikonların listesini API ile çek
    ICON_JSON=$(curl -sf \
        "https://api.github.com/repos/canacikbas2010-blip/c-os-repo/contents/icons" \
        2>/dev/null)

    if [[ -n "$ICON_JSON" ]]; then
        # API çalıştıysa parse et
        mapfile -t ICON_URLS < <(echo "$ICON_JSON" | \
            grep '"download_url"' | \
            sed 's/.*"download_url": "\(.*\)".*/\1/')

        for url in "${ICON_URLS[@]}"; do
            fname=$(basename "$url")
            if curl -sf "$url" -o "${ICON_DIR}/${fname}" 2>/dev/null; then
                info "  → ${fname}"
            fi
        done
        success "İkonlar indirildi: ${ICON_DIR}"
    else
        # API çalışmadıysa bilinen isimlerle dene
        warn "GitHub API yanıt vermedi, bilinen ikon isimleri deneniyor..."
        for icon in c-os.png c-update.png c-os-logo.svg c-os-icon.png; do
            if curl -sf "${REPO_RAW}/icons/${icon}" \
                    -o "${ICON_DIR}/${icon}" 2>/dev/null; then
                success "  → ${icon}"
            fi
        done
    fi

    # --- Duvar kağıtlarını indir ---
    info "Duvar kağıtları indiriliyor..."

    WALL_JSON=$(curl -sf \
        "https://api.github.com/repos/canacikbas2010-blip/c-os-repo/contents/wallpapers" \
        2>/dev/null)

    if [[ -n "$WALL_JSON" ]]; then
        mapfile -t WALL_URLS < <(echo "$WALL_JSON" | \
            grep '"download_url"' | \
            sed 's/.*"download_url": "\(.*\)".*/\1/')

        for url in "${WALL_URLS[@]}"; do
            fname=$(basename "$url")
            if curl -sf "$url" -o "${WALL_DIR}/${fname}" 2>/dev/null; then
                info "  → ${fname}"
            fi
        done
        success "Duvar kağıtları indirildi: ${WALL_DIR}"
    else
        warn "GitHub API yanıt vermedi, bilinen isimler deneniyor..."
        for wall in c-os-wallpaper.jpg c-os-wallpaper.png c-os-dark.jpg c-os-dark.png; do
            if curl -sf "${REPO_RAW}/wallpapers/${wall}" \
                    -o "${WALL_DIR}/${wall}" 2>/dev/null; then
                success "  → ${wall}"
            fi
        done
    fi

    # --- Varsayılan duvar kağıdı & ikon teması ayarla ---
    # (KDE ve Hyprland için)

    # KDE — Plasma default wallpaper
    KDE_WALL_CONF="/mnt/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc"
    mkdir -p "$(dirname "$KDE_WALL_CONF")"
    # Bu dosya masaüstü oturumunda oluşturulur;
    # SDDM'e fallback resim olarak birini bırakıyoruz
    FIRST_WALL=$(ls "${WALL_DIR}"/*.{jpg,png} 2>/dev/null | head -1)
    if [[ -n "$FIRST_WALL" ]]; then
        mkdir -p /mnt/etc/skel/.config
        cat > /mnt/etc/skel/.config/cos-wallpaper << EOF
${FIRST_WALL##/mnt}
EOF
        success "Varsayılan duvar kağıdı ayarlandı: $(basename "$FIRST_WALL")"
    fi

    # Hyprland — hyprpaper.conf
    mkdir -p /mnt/etc/skel/.config/hypr
    if [[ -n "$FIRST_WALL" ]]; then
        cat > /mnt/etc/skel/.config/hypr/hyprpaper.conf << EOF
preload = ${FIRST_WALL##/mnt}
wallpaper = ,${FIRST_WALL##/mnt}
splash = false
EOF
        success "hyprpaper.conf oluşturuldu."
    fi

    # İkon teması — GTK & Qt
    mkdir -p /mnt/etc/skel/.config
    cat > /mnt/etc/skel/.config/gtk-3.0/settings.ini << EOF
[Settings]
gtk-icon-theme-name=c-os
gtk-cursor-theme-name=Adwaita
EOF
}

# ============================================================
#  C-UPDATE İKON DESTEĞİ
# ============================================================
install_c_update_icon() {
    info "C-Update ikonu kuruluyor..."

    CUPD_SIZES="16x16 22x22 32x32 48x48 64x64 128x128 256x256"
    for sz in $CUPD_SIZES; do
        TARGET="/mnt/usr/share/icons/hicolor/${sz}/apps"
        mkdir -p "$TARGET"
        if curl -sf "${REPO_RAW}/icons/c-update/c-update-${sz}.png" \
                -o "${TARGET}/c-update.png" 2>/dev/null; then
            info "  → c-update ${sz}"
        elif curl -sf "${REPO_RAW}/icons/c-update.png" \
                -o "${TARGET}/c-update.png" 2>/dev/null; then
            info "  → c-update.png (tek boyut)"
            break
        fi
    done

    # SVG varsa
    SVG_DIR="/mnt/usr/share/icons/hicolor/scalable/apps"
    mkdir -p "$SVG_DIR"
    curl -sf "${REPO_RAW}/icons/c-update.svg" \
         -o "${SVG_DIR}/c-update.svg" 2>/dev/null && \
        success "c-update.svg kuruldu."
}

# ============================================================
#  SON DOKUNUŞLAR
# ============================================================
finalize() {
    step "Son Dokunuşlar"

    # motd
    cat > /mnt/etc/motd << 'MOTD'

                                      ________________________________________________
                                     /                                                \
                                     |         ____           _____    ______         |
                                     |        / ___|         /  _  \  /  ___/         |
                                     |       | |      _____  | | | |  | |___          |
                                     |       | |     |_____| | | | |  \___  \         |
                                     |       | |___          | |_| |   ___)  |        |
                                     |        \____|         \_____/ /_____ /         |
                                     |                                                |
                                     |            C-OS'e Hoş Geldiniz!               |
                                     ==================================================

MOTD

    # os-release
    cat > /mnt/etc/os-release << EOF
NAME="C-OS"
PRETTY_NAME="C-OS"
ID=c-os
ID_LIKE=arch
ANSI_COLOR="0;36"
HOME_URL="https://github.com/canacikbas2010-blip/c-os-repo"
BUILD_ID=$(date +%Y%m%d)
EOF

    # xdg-user-dirs (her kullanıcı için)
    arch-chroot /mnt xdg-user-dirs-update &>/dev/null || true

    # umount
    sync
    umount -R /mnt

    success "Disk bağlantıları kesildi."
}

# ============================================================
#  TAMAMLANDI EKRANI
# ============================================================
show_done() {
    clear
    show_banner
    echo -e "  ${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "  ${GREEN}${BOLD}║         C-OS BAŞARIYLA KURULDU!  🎉              ║${NC}"
    echo -e "  ${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "  ${BOLD}Kullanıcı adı :${NC} ${USERNAME}"
    echo -e "  ${BOLD}Hostname      :${NC} ${HOSTNAME}"
    echo -e "  ${BOLD}Boot modu     :${NC} ${BOOT_MODE}"
    echo
    echo -e "  ${DIM}Sistemi yeniden başlatabilirsin.${NC}"
    echo -e "  ${DIM}Live ortamdan çıkmak için: ${CYAN}reboot${NC}"
    echo
}

# ============================================================
#  ANA AKIŞ
# ============================================================
main() {
    show_banner
    pre_check
    select_disk
    set_root_password
    create_user
    set_system_info
    show_summary
    partition_disk
    install_base
    configure_system
    install_cos_assets
    install_c_update_icon
    finalize
    show_done
}

main "$@"
