#!/usr/bin/env bash
# ============================================================
# C-OS Installer — cos-install.sh
# Arch Linux tabanli C-OS kurulum betigi
# ============================================================

set -euo pipefail

# --- Renkler ---
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'
DIM='\033[2m'; NC='\033[0m'

# --- Repo ---
REPO_RAW="https://raw.githubusercontent.com/canacikbas2010-blip/c-os-repo/main"
REPO_API="https://api.github.com/repos/canacikbas2010-blip/c-os-repo/contents"

# ============================================================
# BANNER
# ============================================================
show_banner() {
    clear
    echo -e "${CYAN}"
    echo '  ________________________________________________'
    echo ' /                                                \'
    echo ' |   ____    _____   ______                       |'
    echo ' |  / ___|  / _ \  / _____/                      |'
    echo ' | | |  _  | | | | | |___                        |'
    echo ' | | | |_| | | | | \___ \                        |'
    echo ' | | |___  | |_| |  ___) |                       |'
    echo ' |  \____|  \_____/ /______/                      |'
    echo ' |                                                 |'
    echo ' |         C-OS Kurulum Sihirbazi                 |'
    echo ' =================================================='
    echo -e "${NC}"
    echo -e "  ${DIM}Arch Linux tabanli C-OS Kurulum Sihirbazi${NC}"
    echo
}

# ============================================================
# YARDIMCI FONKSIYONLAR
# ============================================================
info()    { echo -e "  ${CYAN}[*]${NC} $*"; }
success() { echo -e "  ${GREEN}[+]${NC} $*"; }
warn()    { echo -e "  ${YELLOW}[!]${NC} $*"; }
error()   { echo -e "  ${RED}[-]${NC} $*"; exit 1; }
step()    { echo; echo -e "${BOLD}${BLUE}===> $*${NC}"; echo; }

confirm() {
    local msg="$1"
    echo -ne "  ${YELLOW}[?]${NC} ${msg} [e/H]: "
    read -r ans
    [[ "$ans" =~ ^[Ee] ]]
}

pause() {
    echo
    echo -ne "  ${DIM}Devam etmek icin Enter'a bas...${NC}"
    read -r
}

# ============================================================
# ON KONTROL
# ============================================================
pre_check() {
    step "Sistem Kontrolu"
    [[ $EUID -ne 0 ]] && error "Bu script root olarak calistirilmalidir."

    if ! ping -c1 -W3 archlinux.org &>/dev/null; then
        error "Internet baglantisi yok. Kurulum icin ag gereklidir."
    fi
    success "Internet baglantisi mevcut."

    # BOOT_MODE tespiti — host uzerinde yapilir, chroot'a aktarilir
    if [[ -d /sys/firmware/efi ]]; then
        BOOT_MODE="UEFI"
    else
        BOOT_MODE="BIOS"
    fi
    success "Onyukleme modu: ${BOLD}${BOOT_MODE}${NC}"
}

# ============================================================
# DISK SECIMI (ok tusu navigasyonu)
# ============================================================
select_disk() {
    step "Disk Secimi"

    mapfile -t DISKS < <(lsblk -dno NAME,SIZE,TYPE | awk '$3=="disk"{print "/dev/"$1" ("$2")"}')
    [[ ${#DISKS[@]} -eq 0 ]] && error "Hic disk bulunamadi."

    echo -e "  ${BOLD}Kurulacak diski sec:${NC}"
    echo -e "  ${DIM}Yukari/asagi ok tuslari ile gezin, Enter ile sec${NC}"
    echo

    local selected=0
    local key
    tput civis  # imleci gizle

    while true; do
        tput cup 0 0 2>/dev/null || true
        for i in "${!DISKS[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e "  ${CYAN}${BOLD}> ${DISKS[$i]}${NC}     "
            else
                echo -e "    ${DIM}${DISKS[$i]}${NC}     "
            fi
        done

        IFS= read -rsn1 key
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key2
            key="${key}${key2}"
        fi

        case "$key" in
            $'\x1b[A') (( selected > 0 )) && (( selected-- )) ;;
            $'\x1b[B') (( selected < ${#DISKS[@]}-1 )) && (( selected++ )) ;;
            '') break ;;
        esac
    done

    tput cnorm  # imleci geri getir

    TARGET_DISK=$(echo "${DISKS[$selected]}" | awk '{print $1}')
    echo
    success "Secilen disk: ${BOLD}${TARGET_DISK}${NC}"
    echo
    warn "${RED}${BOLD}DIKKAT:${NC} ${TARGET_DISK} uzerindeki TUM VERI SILINECEK!"
    echo

    # --- Cift onay ---
    confirm "Bu islemi geri alamazsin. Yine de devam etmek istiyor musun?" \
        || { info "Kurulum iptal edildi."; exit 0; }

    echo -ne "  ${RED}[!]${NC} Onaylamak icin disk adini yaz (${TARGET_DISK}): "
    read -r disk_confirm
    if [[ "$disk_confirm" != "$TARGET_DISK" ]]; then
        info "Disk adi eslesmiyor. Kurulum iptal edildi."
        exit 0
    fi
    success "Disk secimi onaylandi."
}

# ============================================================
# ROOT SIFRESI
# ============================================================
set_root_password() {
    step "Root Sifresi"
    while true; do
        echo -ne "  ${CYAN}[*]${NC} Root sifresi gir: "
        read -rs ROOT_PASS; echo
        [[ -z "$ROOT_PASS" ]] && { warn "Sifre bos olamaz."; continue; }
        echo -ne "  ${CYAN}[*]${NC} Root sifresini tekrar gir: "
        read -rs ROOT_PASS2; echo
        if [[ "$ROOT_PASS" == "$ROOT_PASS2" ]]; then
            success "Root sifresi ayarlandi."
            break
        else
            warn "Sifreler eslesmedi, tekrar dene."
        fi
    done
}

# ============================================================
# KULLANICI OLUSTURMA
# ============================================================
create_user() {
    step "Kullanici Olusturma"
    echo -ne "  ${CYAN}[*]${NC} Kullanici adi gir: "
    read -r USERNAME
    [[ -z "$USERNAME" ]] && error "Kullanici adi bos olamaz."

    while true; do
        echo -ne "  ${CYAN}[*]${NC} ${USERNAME} icin sifre gir: "
        read -rs USER_PASS; echo
        [[ -z "$USER_PASS" ]] && { warn "Sifre bos olamaz."; continue; }
        echo -ne "  ${CYAN}[*]${NC} Sifreyi tekrar gir: "
        read -rs USER_PASS2; echo
        if [[ "$USER_PASS" == "$USER_PASS2" ]]; then
            success "Kullanici '${BOLD}${USERNAME}${NC}' ayarlandi."
            break
        else
            warn "Sifreler eslesmedi, tekrar dene."
        fi
    done
}

# ============================================================
# HOSTNAME & LOCALE
# ============================================================
set_system_info() {
    step "Sistem Bilgileri"

    echo -ne "  ${CYAN}[*]${NC} Hostname gir [c-os]: "
    read -r HOSTNAME
    HOSTNAME="${HOSTNAME:-c-os}"
    success "Hostname: ${BOLD}${HOSTNAME}${NC}"

    echo -e "  ${CYAN}[*]${NC} Zaman dilimi secenekleri:"
    select TIMEZONE in "Europe/Istanbul" "UTC" "Europe/London" "America/New_York" "Ozel..."; do
        case $TIMEZONE in
            "Ozel...")
                echo -ne "  Zaman dilimi gir (or: Europe/Paris): "
                read -r TIMEZONE
                ;;
        esac
        [[ -n "$TIMEZONE" ]] && break
    done
    success "Zaman dilimi: ${BOLD}${TIMEZONE}${NC}"
}

# ============================================================
# OZET EKRANI
# ============================================================
show_summary() {
    step "Kurulum Ozeti"
    echo -e "  ${BOLD}Disk:${NC}          ${TARGET_DISK}"
    echo -e "  ${BOLD}Boot modu:${NC}     ${BOOT_MODE}"
    echo -e "  ${BOLD}Hostname:${NC}      ${HOSTNAME}"
    echo -e "  ${BOLD}Kullanici:${NC}     ${USERNAME}"
    echo -e "  ${BOLD}Zaman dilimi:${NC}  ${TIMEZONE}"
    echo
    confirm "Kurulumu baslat?" || { info "Iptal edildi."; exit 0; }
}

# ============================================================
# DISK BOLÜMLENDIRME
# ============================================================
partition_disk() {
    step "Disk Bolümlendirme"
    info "${TARGET_DISK} bolümlendiriliyor..."

    wipefs -af "${TARGET_DISK}"  &>/dev/null
    sgdisk --zap-all "${TARGET_DISK}" &>/dev/null

    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        parted -s "${TARGET_DISK}" \
            mklabel gpt \
            mkpart EFI fat32 1MiB 513MiB \
            set 1 esp on \
            mkpart SWAP linux-swap 513MiB 2561MiB \
            mkpart ROOT ext4 2561MiB 100%

        EFI_PART="${TARGET_DISK}1"
        SWAP_PART="${TARGET_DISK}2"
        ROOT_PART="${TARGET_DISK}3"

        mkfs.fat -F32 -n EFI  "${EFI_PART}"  &>/dev/null
        mkswap   -L SWAP       "${SWAP_PART}" &>/dev/null
        mkfs.ext4 -L C_OS -F  "${ROOT_PART}" &>/dev/null

        swapon "${SWAP_PART}"
        mount  "${ROOT_PART}" /mnt
        mkdir -p /mnt/boot/efi
        mount "${EFI_PART}" /mnt/boot/efi
    else
        parted -s "${TARGET_DISK}" \
            mklabel msdos \
            mkpart primary ext4 1MiB 513MiB \
            set 1 boot on \
            mkpart primary linux-swap 513MiB 2561MiB \
            mkpart primary ext4 2561MiB 100%

        BOOT_PART="${TARGET_DISK}1"
        SWAP_PART="${TARGET_DISK}2"
        ROOT_PART="${TARGET_DISK}3"

        mkfs.ext4 -L BOOT -F  "${BOOT_PART}" &>/dev/null
        mkswap    -L SWAP     "${SWAP_PART}"  &>/dev/null
        mkfs.ext4 -L C_OS -F  "${ROOT_PART}" &>/dev/null

        swapon "${SWAP_PART}"
        mount  "${ROOT_PART}" /mnt
        mkdir -p /mnt/boot
        mount "${BOOT_PART}" /mnt/boot
    fi

    success "Disk bolumlendirildi ve baglandi."
}

# ============================================================
# TEMEL SISTEM KURULUMU
# ============================================================
install_base() {
    step "Temel Sistem Kurulumu"
    info "pacstrap calisiyor, bu biraz surebilir..."

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
    success "fstab olusturuldu."
}

# ============================================================
# CHROOT BETIGI YAZAR VE CALISTIRIR
#
# Guvenlik notu: Sifreler gecici, izinleri kisitlanmis bir
# dosya uzerinden chpasswd'a pipe edilir; process listesinde
# gorunmez, log'a dusmez.
# ============================================================
configure_system() {
    step "Sistem Yapilandirmasi"

    # --- Gecici sifre dosyasi (sadece root okuyabilir) ---
    local pass_file
    pass_file=$(mktemp /mnt/root/.cospw.XXXXXX)
    chmod 600 "$pass_file"
    printf 'root:%s\n%s:%s\n' "$ROOT_PASS" "$USERNAME" "$USER_PASS" > "$pass_file"

    # BOOT_MODE ve TARGET_DISK chroot'a env degiskeni olarak aktarilir;
    # chroot icinde /sys/firmware/efi kontrolu YAPILMAZ — host tespiti
    # gecerlidir. Bu sayede VM/fiziksel fark sorun olusturmaz.
    cat > /mnt/root/cos-chroot.sh << CHROOT_EOF
#!/bin/bash
set -e

BOOT_MODE="${BOOT_MODE}"
TARGET_DISK="${TARGET_DISK}"
HOSTNAME="${HOSTNAME}"
USERNAME="${USERNAME}"
TIMEZONE="${TIMEZONE}"
PASS_FILE="/root/.cospw.XXXXXX_placeholder"

# Locale
sed -i 's/#tr_TR.UTF-8/tr_TR.UTF-8/' /etc/locale.gen
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=tr_TR.UTF-8" > /etc/locale.conf
echo "KEYMAP=trq"        > /etc/vconsole.conf

# Hostname
echo "\${HOSTNAME}" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   \${HOSTNAME}.localdomain \${HOSTNAME}
EOF

# Zaman
ln -sf "/usr/share/zoneinfo/\${TIMEZONE}" /etc/localtime
hwclock --systohc

# NetworkManager
systemctl enable NetworkManager

# Sifreler — pass_file'dan oku, hic bir arguman aciga cikmaz
chpasswd < "\${PASS_FILE}"
shred -u "\${PASS_FILE}" 2>/dev/null || rm -f "\${PASS_FILE}"

# Kullanici
useradd -m -G wheel,audio,video,storage,optical -s /bin/bash "\${USERNAME}"

# sudo — wheel grubu
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# initramfs
mkinitcpio -P

# GRUB — BOOT_MODE degiskenine gore; /sys kontrolu yok
if [[ "\${BOOT_MODE}" == "UEFI" ]]; then
    grub-install --target=x86_64-efi \
        --efi-directory=/boot/efi \
        --bootloader-id="C-OS" \
        --recheck
else
    grub-install --target=i386-pc "\${TARGET_DISK}" --recheck
fi

sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/'              /etc/default/grub
sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="C-OS"/' /etc/default/grub
sed -i 's/^#GRUB_DISABLE_OS_PROBER/GRUB_DISABLE_OS_PROBER/' /etc/default/grub || true
grub-mkconfig -o /boot/grub/grub.cfg

echo "CHROOT_DONE"
CHROOT_EOF

    # pass_file yolunu chroot betigine gercek degerle yaz
    sed -i "s|/root/.cospw.XXXXXX_placeholder|${pass_file##/mnt}|" /mnt/root/cos-chroot.sh
    chmod 700 /mnt/root/cos-chroot.sh

    arch-chroot /mnt /bin/bash /root/cos-chroot.sh \
        | while IFS= read -r line; do
            [[ "$line" == "CHROOT_DONE" ]] \
                && success "Sistem yapilandirmasi tamamlandi." \
                && continue
            echo -e "  ${DIM}${line}${NC}"
        done

    rm -f /mnt/root/cos-chroot.sh
    # pass_file chroot icinde shred'lendi; dis tarafta artik kalmadigindan emin ol
    rm -f "$pass_file" 2>/dev/null || true
}

# ============================================================
# GITHUB'DAN DOSYA INDIRME YARDIMCISI
# Rate limit veya hata durumunda yeniden dener (3 deneme).
# ============================================================
safe_curl() {
    # Kullanim: safe_curl <url> <hedef_dosya>
    local url="$1" dest="$2"
    local attempts=3 delay=4

    for (( i=1; i<=attempts; i++ )); do
        if curl -fsSL --max-time 20 --retry 2 "$url" -o "$dest" 2>/dev/null; then
            return 0
        fi
        warn "Indirme basarisiz (deneme ${i}/${attempts}): $(basename "$dest")"
        sleep "$delay"
    done
    return 1
}

# ============================================================
# C-OS REPO VARLIKLARI
# ============================================================
install_cos_assets() {
    step "C-OS Repo Varliklari (Ikonlar & Duvar Kagitlari)"

    local ICON_DIR="/mnt/usr/share/icons/c-os"
    local WALL_DIR="/mnt/usr/share/backgrounds/c-os"
    mkdir -p "${ICON_DIR}" "${WALL_DIR}"

    # --------------- IKONLAR ---------------
    info "Ikonlar indiriliyor..."
    local ICON_JSON
    ICON_JSON=$(curl -fsSL --max-time 15 "${REPO_API}/icons" 2>/dev/null || true)

    if [[ -n "$ICON_JSON" ]] && echo "$ICON_JSON" | grep -q '"download_url"'; then
        mapfile -t ICON_URLS < <(
            echo "$ICON_JSON" \
            | grep '"download_url"' \
            | sed 's/.*"download_url": "\(.*\)".*/\1/'
        )
        local ok=0
        for url in "${ICON_URLS[@]}"; do
            local fname
            fname=$(basename "$url")
            if safe_curl "$url" "${ICON_DIR}/${fname}"; then
                info "  -> ${fname}"
                (( ok++ )) || true
            fi
        done
        success "${ok} ikon indirildi: ${ICON_DIR}"
    else
        warn "GitHub API yanit vermedi veya rate limit. Bilinen isimler deneniyor..."
        for icon in c-os.png c-update.png c-os-logo.svg c-os-icon.png; do
            if safe_curl "${REPO_RAW}/icons/${icon}" "${ICON_DIR}/${icon}"; then
                success "  -> ${icon}"
            else
                warn "  -> ${icon} indirilemedi, atlaniyor."
            fi
        done
    fi

    # --------------- DUVAR KAGITLARI ---------------
    info "Duvar kagitlari indiriliyor..."
    local WALL_JSON
    WALL_JSON=$(curl -fsSL --max-time 15 "${REPO_API}/wallpapers" 2>/dev/null || true)

    if [[ -n "$WALL_JSON" ]] && echo "$WALL_JSON" | grep -q '"download_url"'; then
        mapfile -t WALL_URLS < <(
            echo "$WALL_JSON" \
            | grep '"download_url"' \
            | sed 's/.*"download_url": "\(.*\)".*/\1/'
        )
        local ok=0
        for url in "${WALL_URLS[@]}"; do
            local fname
            fname=$(basename "$url")
            if safe_curl "$url" "${WALL_DIR}/${fname}"; then
                info "  -> ${fname}"
                (( ok++ )) || true
            fi
        done
        success "${ok} duvar kagidi indirildi: ${WALL_DIR}"
    else
        warn "GitHub API yanit vermedi. Bilinen isimler deneniyor..."
        for wall in c-os-wallpaper.jpg c-os-wallpaper.png c-os-dark.jpg c-os-dark.png; do
            if safe_curl "${REPO_RAW}/wallpapers/${wall}" "${WALL_DIR}/${wall}"; then
                success "  -> ${wall}"
            else
                warn "  -> ${wall} indirilemedi, atlaniyor."
            fi
        done
    fi

    # --------------- VARSAYILAN DUVAR KAGIDI ---------------
    local FIRST_WALL
    FIRST_WALL=$(ls "${WALL_DIR}"/*.{jpg,png} 2>/dev/null | head -1 || true)

    mkdir -p /mnt/etc/skel/.config
    mkdir -p /mnt/etc/skel/.config/hypr

    if [[ -n "$FIRST_WALL" ]]; then
        echo "${FIRST_WALL##/mnt}" > /mnt/etc/skel/.config/cos-wallpaper
        success "Varsayilan duvar kagidi: $(basename "$FIRST_WALL")"

        cat > /mnt/etc/skel/.config/hypr/hyprpaper.conf << EOF
preload = ${FIRST_WALL##/mnt}
wallpaper = ,${FIRST_WALL##/mnt}
splash = false
EOF
        success "hyprpaper.conf olusturuldu."
    else
        warn "Hic duvar kagidi indirilemedi; hyprpaper.conf olusturulmadi."
    fi

    # --------------- GTK IKON TEMASI ---------------
    mkdir -p /mnt/etc/skel/.config/gtk-3.0
    cat > /mnt/etc/skel/.config/gtk-3.0/settings.ini << EOF
[Settings]
gtk-icon-theme-name=c-os
gtk-cursor-theme-name=Adwaita
EOF
}

# ============================================================
# C-UPDATE IKON DESTEGI
# ============================================================
install_c_update_icon() {
    info "C-Update ikonu kuruluyor..."

    local CUPD_SIZES="16x16 22x22 32x32 48x48 64x64 128x128 256x256"
    local installed=0

    for sz in $CUPD_SIZES; do
        local TARGET="/mnt/usr/share/icons/hicolor/${sz}/apps"
        mkdir -p "$TARGET"
        if safe_curl "${REPO_RAW}/icons/c-update/${sz}/c-update.png" "${TARGET}/c-update.png"; then
            info "  -> c-update ${sz}"
            (( installed++ )) || true
        elif [[ $installed -eq 0 ]]; then
            # Tek-boyutlu fallback: sadece ilk basarili indirimde dene
            if safe_curl "${REPO_RAW}/icons/c-update.png" "${TARGET}/c-update.png"; then
                info "  -> c-update.png (tek boyut fallback)"
                installed=1
                break
            fi
        fi
    done

    # SVG
    local SVG_DIR="/mnt/usr/share/icons/hicolor/scalable/apps"
    mkdir -p "$SVG_DIR"
    if safe_curl "${REPO_RAW}/icons/c-update.svg" "${SVG_DIR}/c-update.svg"; then
        success "c-update.svg kuruldu."
    fi
}

# ============================================================
# SON DOKUNUSLAR
# ============================================================
finalize() {
    step "Son Dokunuslar"

    cat > /mnt/etc/motd << 'MOTD'
  ________________________________________________
 /                                                \
 |   ____   _____     ______                       |
 |  / ___| /  _  \   / _____/                      |
 | | |  _  | | | |   | |___                        |
 | | | |_| | | | |   \___ \                        |
 | | |___  | |_| |    ___) |                       |
 |  \____| \_____/  /_____/                        |
 |                                                 |
 |         C-OS'e Hos Geldiniz!                    |
 ==================================================
MOTD

    cat > /mnt/etc/os-release << EOF
NAME="C-OS"
PRETTY_NAME="C-OS"
ID=c-os
ID_LIKE=arch
ANSI_COLOR="0;36"
HOME_URL="https://github.com/canacikbas2010-blip/c-os-repo"
BUILD_ID=$(date +%Y%m%d)
EOF

    arch-chroot /mnt xdg-user-dirs-update &>/dev/null || true

    sync
    umount -R /mnt
    success "Disk baglantilari kesildi."
}

# ============================================================
# TAMAMLANDI EKRANI
# ============================================================
show_done() {
    clear
    show_banner
    echo -e "  ${GREEN}${BOLD}+--------------------------------------------------+${NC}"
    echo -e "  ${GREEN}${BOLD}|   C-OS BASARIYLA KURULDU!                        |${NC}"
    echo -e "  ${GREEN}${BOLD}+--------------------------------------------------+${NC}"
    echo
    echo -e "  ${BOLD}Kullanici adi:${NC}  ${USERNAME}"
    echo -e "  ${BOLD}Hostname:${NC}       ${HOSTNAME}"
    echo -e "  ${BOLD}Boot modu:${NC}      ${BOOT_MODE}"
    echo
    echo -e "  ${DIM}Sistemi yeniden baslatabilirsin.${NC}"
    echo -e "  ${DIM}Live ortamdan cikmak icin: ${CYAN}reboot${NC}"
    echo
}

# ============================================================
# ANA AKIS
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
