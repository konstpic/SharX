#!/bin/bash

# ============================================
# SharX Скрипт установки (Русская версия)
# Author: @konspic
# Version: latest
# ============================================

set -e

# Colors for output
RED='\e[38;2;255;0;0m'
GREEN='\e[38;2;0;255;0m'
YELLOW='\033[1;33m'
SKYBLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\e[38;2;135;206;235m'
WHITE='\033[1;37m'
ORANGE='\e[38;2;255;100;0m'
LIME='\e[38;2;188;225;107m'
NC='\033[0m' # No Color

# Default values
DEFAULT_PANEL_PORT=2053
DEFAULT_SUB_PORT=2096
DEFAULT_DB_PASSWORD="change_this_password"
# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$SCRIPT_DIR"
COMPOSE_FILE="docker-compose.yml"

# UID:GID для PEM в INSTALL_DIR/cert — не оставляем файлы только root при sudo,
# плюс .sharx-cert-deploy-owner для cron acme.sh.
get_cert_deploy_owner() {
    if [[ -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" && "${SUDO_UID:-0}" != "0" ]]; then
        printf '%s:%s\n' "$SUDO_UID" "$SUDO_GID"
        return
    fi
    stat -c '%u:%g' "$INSTALL_DIR" 2>/dev/null || stat -f '%u:%g' "$INSTALL_DIR" 2>/dev/null || printf '0:0\n'
}

persist_cert_deploy_owner() {
    printf '%s\n' "$(get_cert_deploy_owner)" >"${INSTALL_DIR}/.sharx-cert-deploy-owner" 2>/dev/null || true
}

fix_cert_dir_ownership() {
    local dir="${1:?}"
    local owner
    owner="$(get_cert_deploy_owner)"
    persist_cert_deploy_owner
    [[ -d "$dir" ]] && chown "$owner" "$dir" 2>/dev/null || true
    if [[ -f "${dir}/privkey.pem" ]]; then
        chmod 600 "${dir}/privkey.pem" 2>/dev/null || true
        chown "$owner" "${dir}/privkey.pem" 2>/dev/null || true
    fi
    if [[ -f "${dir}/fullchain.pem" ]]; then
        chmod 644 "${dir}/fullchain.pem" 2>/dev/null || true
        chown "$owner" "${dir}/fullchain.pem" 2>/dev/null || true
    fi
    if [[ -f "${dir}/sub-privkey.pem" ]]; then
        chmod 600 "${dir}/sub-privkey.pem" 2>/dev/null || true
        chown "$owner" "${dir}/sub-privkey.pem" 2>/dev/null || true
    fi
    if [[ -f "${dir}/sub-fullchain.pem" ]]; then
        chmod 644 "${dir}/sub-fullchain.pem" 2>/dev/null || true
        chown "$owner" "${dir}/sub-fullchain.pem" 2>/dev/null || true
    fi
}

docker_compose_restart_sharx() {
    (
        cd "$INSTALL_DIR" || exit 0
        if docker compose version >/dev/null 2>&1; then
            docker compose -f "$COMPOSE_FILE" restart sharx
        elif command -v docker-compose >/dev/null 2>&1; then
            docker-compose -f "$COMPOSE_FILE" restart sharx
        fi
    ) 2>/dev/null || docker restart sharx_app 2>/dev/null || true
}

build_acme_reloadcmd() {
    local src="$1"
    local dst="$2"
    local idir="$INSTALL_DIR"
    local cf="$COMPOSE_FILE"
    echo "cp '${src}/privkey.pem' '${dst}/' && cp '${src}/fullchain.pem' '${dst}/' && chmod 600 '${dst}/privkey.pem' && chmod 644 '${dst}/fullchain.pem' && OWN=\$(cat '${idir}/.sharx-cert-deploy-owner' 2>/dev/null || stat -c '%u:%g' '${idir}' 2>/dev/null || stat -f '%u:%g' '${idir}' 2>/dev/null || echo 0:0) && chown \"\$OWN\" '${dst}/privkey.pem' '${dst}/fullchain.pem' 2>/dev/null || true && cd '${idir}' && ( docker compose -f '${cf}' restart sharx 2>/dev/null || docker-compose -f '${cf}' restart sharx 2>/dev/null || docker restart sharx_app 2>/dev/null || true )"
}

# Приоритет /root/.acme.sh (sudo + root cron), иначе $HOME.
acme_sh_bin() {
    if [[ -x "/root/.acme.sh/acme.sh" ]]; then
        printf '%s\n' "/root/.acme.sh/acme.sh"
        return 0
    fi
    if [[ -x "${HOME}/.acme.sh/acme.sh" ]]; then
        printf '%s\n' "${HOME}/.acme.sh/acme.sh"
        return 0
    fi
    printf '%s\n' "${HOME}/.acme.sh/acme.sh"
}

acme_sh_ready() {
    [[ -x "$(acme_sh_bin)" ]]
}

# ECDSA-серты в каталоге <имя>_ecc — для installcert и renew нужен --ecc
acme_subject_is_ecc() {
    local name="${1:?}"
    [[ -d "/root/.acme.sh/${name}_ecc" ]] || [[ -d "${HOME}/.acme.sh/${name}_ecc" ]]
}

acme_ecc_arg() {
    if acme_subject_is_ecc "$1"; then
        printf '%s' '--ecc'
    fi
}

acme_resolve_source_dir_for_subject() {
    local primary="$1"
    local h
    for h in "/root" "${HOME}"; do
        if [[ -d "${h}/.acme.sh/${primary}_ecc" ]]; then
            printf '%s\n' "${h}/.acme.sh/${primary}_ecc"
            return 0
        fi
        if [[ -d "${h}/.acme.sh/${primary}" ]]; then
            printf '%s\n' "${h}/.acme.sh/${primary}"
            return 0
        fi
    done
    return 1
}

acme_copy_from_store_to_pem_paths() {
    local primary="$1"
    local chain_pem="$2"
    local key_pem="$3"
    local src_dir
    if ! src_dir=$(acme_resolve_source_dir_for_subject "$primary"); then
        return 1
    fi
    if [[ ! -f "${src_dir}/fullchain.cer" ]] || [[ ! -f "${src_dir}/${primary}.key" ]]; then
        return 1
    fi
    cp "${src_dir}/fullchain.cer" "$chain_pem"
    cp "${src_dir}/${primary}.key" "$key_pem"
    chmod 644 "$chain_pem" 2>/dev/null || true
    chmod 600 "$key_pem" 2>/dev/null || true
    return 0
}

acme_rm_subject_dirs() {
    local primary="$1"
    local h
    for h in "/root" "${HOME}"; do
        rm -rf "${h}/.acme.sh/${primary}" "${h}/.acme.sh/${primary}_ecc" 2>/dev/null || true
    done
}

# Print banner
print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║     ███████╗██╗  ██╗ █████╗ ██████╗ ██╗  ██╗                  ║"
    echo "║     ██╔════╝██║  ██║██╔══██╗██╔══██╗╚██╗██╔╝                  ║"
    echo "║     ███████╗███████║███████║██████╔╝ ╚███╔╝                   ║"
    echo "║     ╚════██║██╔══██║██╔══██║██╔══██╗ ██╔██╗                   ║"
    echo "║     ███████║██║  ██║██║  ██║██║  ██║██╔╝ ██╗                  ║"
    echo "║     ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝                  ║"
    echo "║                                                               ║"
    echo "║         Управление панелью нового поколения                   ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Print colored message
print_info() { echo -e "${SKYBLUE}[ИНФО]${NC} $1"; }
print_success() { echo -e "${GREEN}[УСПЕХ]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ]${NC} $1"; }
print_error() { echo -e "${RED}[ОШИБКА]${NC} $1"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен быть запущен от имени root!"
        echo -e "Пожалуйста, запустите: ${YELLOW}sudo ./install_ru.sh${NC}"
        exit 1
    fi
}

# Detect OS and package manager
detect_os() {
    OS=""
    PACKAGE_MANAGER=""
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
    elif [[ -f /etc/redhat-release ]]; then
        OS="centos"
    elif [[ -f /etc/arch-release ]]; then
        OS="arch"
    elif [[ -f /etc/alpine-release ]]; then
        OS="alpine"
    fi
    
    # Detect package manager
    if command -v apt-get &> /dev/null; then
        PACKAGE_MANAGER="apt"
    elif command -v dnf &> /dev/null; then
        PACKAGE_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        PACKAGE_MANAGER="yum"
    elif command -v pacman &> /dev/null; then
        PACKAGE_MANAGER="pacman"
    elif command -v apk &> /dev/null; then
        PACKAGE_MANAGER="apk"
    elif command -v zypper &> /dev/null; then
        PACKAGE_MANAGER="zypper"
    fi
    
    echo -e "  ОС: ${CYAN}$OS${NC}"
    echo -e "  Менеджер пакетов: ${CYAN}$PACKAGE_MANAGER${NC}"
}

# Check system requirements
check_system() {
    print_info "Проверка системных требований..."
    
    # Detect OS
    detect_os
    
    if [[ -z "$PACKAGE_MANAGER" ]]; then
        print_error "Не удалось определить менеджер пакетов!"
        exit 1
    fi
    
    # Check architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" && "$ARCH" != "armv7l" ]]; then
        print_error "Неподдерживаемая архитектура: $ARCH"
        exit 1
    fi
    echo -e "  Архитектура: ${CYAN}$ARCH${NC}"
    
    print_success "Проверка системы пройдена!"
}

# Install Docker - Debian/Ubuntu
install_docker_apt() {
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Update and install prerequisites
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Set up reposiвry
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Enable BBR
    grep -qxF "net.core.default_qdisc=fq" /etc/sysctl.d/99-SharX-BBR.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.d/99-SharX-BBR.conf
    grep -qxF "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.d/99-SharX-BBR.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-SharX-BBR.conf
    sysctl -p
	
	# WAN-MASQ
	grep -qxF "net.ipv4.ip_forward=1" /etc/sysctl.d/99-SharX-ipv4fwd.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-SharX-ipv4fwd.conf
	sysctl -p
	sudo echo "#!/bin/sh -e" >> /etc/rc.local
	sudo echo "iptables -t nat -A POSTROUTING -o $(ip route show default | awk '{print $5}') -j MASQUERADE" >> /etc/rc.local
	sudo echo "exit 0" >> /etc/rc.local
	sudo chmod +x /etc/rc.local
	sudo systemctl enable rc-local
	sudo systemctl start rc-local
}

# Install Docker - Fedora
install_docker_dnf() {
    # Remove old versions
    dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
    
    # Install prerequisites
    dnf install -y dnf-plugins-core
    
    # Add Docker reposiвry
    sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
    
    # Install Docker
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Enable BBR
    grep -qxF "net.core.default_qdisc=fq" /etc/sysctl.d/99-SharX-BBR.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.d/99-SharX-BBR.conf
    grep -qxF "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.d/99-SharX-BBR.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-SharX-BBR.conf
    sysctl -p
	
	# WAN-MASQ
	grep -qxF "net.ipv4.ip_forward=1" /etc/sysctl.d/99-SharX-ipv4fwd.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-SharX-ipv4fwd.conf
	sudo echo "#!/bin/bash" >> /etc/rc.d/rc.local
	sudo echo "iptables -t nat -A POSTROUTING -o $(ip route show default | awk '{print $5}') -j MASQUERADE" >> /etc/rc.d/rc.local
	sudo echo "exit 0" >> /etc/rc.d/rc.local
	sudo ln -s /etc/rc.d/rc.local /etc/rc.local
	sudo chmod +x /etc/rc.d/rc.local
	sudo echo "[Unit]
Description=/etc/rc.d/rc.local Compatibility
ConditionFileIsExecutable=/etc/rc.d/rc.local
After=network-online.target

[Service]
Type=forking
ExecStart=/etc/rc.d/rc.local
TimeoutSec=0
RemainAfterExit=yes
GuessMainPID=no

[Install]
WantedBy=multi-user.target" >> /etc/systemd/system/rc-local.service
	sudo systemctl daemon-reload
	sudo systemctl enable --now rc-local
}

# Install Docker - Arch Linux
install_docker_pacman() {
    # Update system
    pacman -Syu --noconfirm
	echo -e "${GREEN}Обновление завершено. Требуется перезагрузка системы. Если перезгрузка уже производилась и скрипт установки запущен повторно ТО нажмите N${NC}"
	read -rp "Перезагрузить сейчас? [y/n]: " answer
     case "$answer" in
         [Yy]|[Дд])
             echo "Перезагрузка..."
             reboot
             ;;
         *)
             echo "${GREEN}Перезагрузка отменена. Продолжаем работу...${NC}"
             ;;
     esac
    
    # Install Docker
    pacman -S --noconfirm docker docker-compose

    # Enable BBR
    grep -qxF "net.core.default_qdisc=fq" /etc/sysctl.d/99-SharX-BBR.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.d/99-SharX-BBR.conf
    grep -qxF "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.d/99-SharX-BBR.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-SharX-BBR.conf
	
    # WAN-MASQ
    grep -qxF "net.ipv4.ip_forward=1" /etc/sysctl.d/99-SharX-ipv4fwd.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-SharX-ipv4fwd.conf
    sudo echo "#!/bin/bash" >> /etc/rc.local
    sudo echo "iptables -t nat -A POSTROUTING -o $(ip route show default | awk '{print $5}') -j MASQUERADE" >> /etc/rc.local
    sudo echo "exit 0" >> /etc/rc.local
    sudo chmod +x /etc/rc.local
    sudo echo "[Unit]
Description=/etc/rc.local Compatibility
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/rc.local
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target" >> /etc/systemd/system/rc-local.service
	sudo systemctl daemon-reload
	sudo systemctl enable --now rc-local
}

# Install Docker - Alpine
install_docker_apk() {
    # Update reposiвries
    apk update
    
    # Install Docker
    apk add docker docker-cli-compose
    
    # Add to boot
    rc-update add docker boot
	
	# Enable BBR
    grep -qxF "net.core.default_qdisc=fq" /etc/sysctl.d/99-SharX-BBR.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.d/99-SharX-BBR.conf
    grep -qxF "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.d/99-SharX-BBR.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-SharX-BBR.conf
    sysctl -p
	
	# Enable /dev/net/tun
	modprobe tun
	mkdir -p /dev/net
	[ ! -c /dev/net/tun ] && mknod /dev/net/tun c 10 200
	chmod 0666 /dev/net/tun
	echo "tun" >> /etc/modules

    # WAN-MASQ
    rc-update add local default
    echo "#!/bin/sh" >> /etc/local.d/nat-setup.start
    echo "iptables -t nat -A POSTROUTING -o $(ip route show default | awk '{print $5}') -j MASQUERADE" >> /etc/local.d/nat-setup.start
    chmod +x /etc/local.d/nat-setup.start
    grep -qxF "net.ipv4.ip_forward=1" /etc/sysctl.d/99-SharX-ipv4fwd.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-SharX-ipv4fwd.conf
	sysctl -p
}

# Install Docker - openSUSE
install_docker_zypper() {
    # Install Docker
    zypper install -y docker docker-compose
	
	# Enable BBR
    grep -qxF "net.core.default_qdisc=fq" /etc/sysctl.d/99-SharX-BBR.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.d/99-SharX-BBR.conf
    grep -qxF "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.d/99-SharX-BBR.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-SharX-BBR.conf
	
	# WAN-MASQ
	grep -qxF "net.ipv4.ip_forward=1" /etc/sysctl.d/99-SharX-ipv4fwd.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-SharX-ipv4fwd.conf
	sudo mkdir -p /usr/local/sbin
	echo -e "#!/bin/bash\niptables -t nat -A POSTROUTING -o $(ip route show default | awk '{print $5}') -j MASQUERADE" >> /usr/local/sbin/nat-awg.sh
	sudo chmod +x /usr/local/sbin/nat-awg.sh
	sudo echo -e "[Unit]\nDescription=Custom NAT Setup\nAfter=network-online.target\n\n[Service]\nType=oneshot\nExecStart=/usr/local/sbin/nat-awg.sh\nRemainAfterExit=yes\n\n[Install]\nWantedBy=multi-user.target" >> /etc/systemd/system/nat-awg.service
	sudo systemctl daemon-reload
	sudo systemctl enable --now nat-awg.service
}

# Install Docker if not present
install_docker() {
    if command -v docker &> /dev/null; then
        print_success "Docker уже установлен: $(docker --version)"
        return 0
    fi

    print_info "Установка Docker для $OS используя $PACKAGE_MANAGER..."
    
    case $PACKAGE_MANAGER in
        apt)
            install_docker_apt
            ;;
        dnf)
            install_docker_dnf
            ;;
        yum)
            install_docker_yum
            ;;
        pacman)
            install_docker_pacman
            ;;
        apk)
            install_docker_apk
            ;;
        zypper)
            install_docker_zypper
            ;;
        *)
            print_error "Неподдерживаемый менеджер пакетов: $PACKAGE_MANAGER"
            print_info "Пожалуйста, установите Docker вручную: https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac
    
    # Start and enable Docker
    if command -v systemctl &> /dev/null; then
        systemctl start docker
        systemctl enable docker
    elif command -v rc-service &> /dev/null; then
        rc-service docker start
    elif command -v service &> /dev/null; then
        service docker start
    fi
    
    # Verify installation
    if command -v docker &> /dev/null; then
        print_success "Docker успешно установлен!"
        print_success "BBR активирован..."
    else
        print_error "Ошибка установки Docker!"
        exit 1
    fi
}

# Install Docker Compose (standalone) if not present
install_docker_compose() {
    # Check for docker compose plugin
    if docker compose version &> /dev/null; then
        print_success "Плагин Docker Compose доступен: $(docker compose version)"
        return 0
    fi
    
    # Check for standalone docker-compose
    if command -v docker-compose &> /dev/null; then
        print_success "Docker Compose standalone доступен: $(docker-compose --version)"
        # Create alias function for compatibility
        docker() {
            if [[ "$1" == "compose" ]]; then
                shift
                command docker-compose "$@"
            else
                command docker "$@"
            fi
        }
        return 0
    fi
    
    print_info "Установка Docker Compose..."
    
    case $PACKAGE_MANAGER in
        apt)
            apt-get update -y
            apt-get install -y docker-compose-plugin || apt-get install -y docker-compose
            ;;
        dnf)
            dnf install -y docker-compose-plugin || dnf install -y docker-compose
            ;;
        yum)
            yum install -y docker-compose-plugin || yum install -y docker-compose
            ;;
        pacman)
            # Already installed with docker
            pacman -S --noconfirm docker-compose 2>/dev/null || true
            ;;
        apk)
            # Already installed as docker-cli-compose
            apk add docker-cli-compose 2>/dev/null || apk add docker-compose
            ;;
        zypper)
            zypper install -y docker-compose-plugin || zypper install -y docker-compose
            ;;
        *)
            # Try to install standalone docker-compose
            print_info "Установка Docker Compose standalone..."
            COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
            curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            ;;
    esac
    
    # Verify installation
    if docker compose version &> /dev/null || docker-compose --version &> /dev/null; then
        print_success "Docker Compose успешно установлен!"
    else
        print_error "Ошибка установки Docker Compose!"
        print_info "Пожалуйста, установите вручную: https://docs.docker.com/compose/install/"
        exit 1
    fi
}

# Generate random string
gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

# Generate random password (safe for YAML and SQL - no special chars that need escaping)
generate_password() {
    local length=${1:-24}
    # Use only alphanumeric characters to avoid YAML/SQL escaping issues
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

# Escape string for SQL (single quotes)
escape_sql() {
    local str="$1"
    # Escape single quotes by doubling them
    echo "${str//\'/\'\'}"
}

# Escape string for YAML values
escape_yaml() {
    local str="$1"
    # If string contains special chars, quote it
    # Using grep to check for special characters
    if echo "$str" | grep -q '[:#"'"'"'\[\]{}|><!\&\*\?@`]'; then
        # Escape double quotes and wrap in double quotes
        str="${str//\\/\\\\}"
        str="${str//\"/\\\"}"
        echo "\"$str\""
    else
        echo "$str"
    fi
}

# Get server IPv4
get_server_ip() {
    local ip
    ip=$(curl -4 -s ifconfig.me 2>/dev/null || curl -4 -s icanhazip.com 2>/dev/null || curl -4 -s ipinfo.io/ip 2>/dev/null)
    echo "$ip"
}

# Get server IPv6
get_server_ipv6() {
    local ip
    ip=$(curl -6 -s --connect-timeout 3 -m 5 ifconfig.me 2>/dev/null || \
         curl -6 -s --connect-timeout 3 -m 5 icanhazip.com 2>/dev/null || \
         echo "")
    echo "$ip"
}

# Validate IPv4 address
is_ipv4() {
    local ip="$1"
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 0
    fi
    return 1
}

# Validate IPv6 address
is_ipv6() {
    local ip="$1"
    if [[ $ip =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]] || [[ $ip =~ ^::$ ]] || [[ $ip =~ : ]]; then
        return 0
    fi
    return 1
}

# Validate domain name
is_domain() {
    local domain="$1"
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

# Check if port is in use
is_port_in_use() {
    local port="$1"
    
    # Try different methods to check port
    if command -v ss &> /dev/null; then
        if ss -tuln 2>/dev/null | grep -q ":${port} "; then
            return 0
        fi
    elif command -v netstat &> /dev/null; then
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            return 0
        fi
    elif command -v lsof &> /dev/null; then
        if lsof -i :${port} 2>/dev/null | grep -q LISTEN; then
            return 0
        fi
    fi
    
    # Check Docker containers
    if docker ps --format '{{.Ports}}' 2>/dev/null | grep -q ":${port}->"; then
        return 0
    fi
    
    return 1
}

# Validate and check port availability
validate_port() {
    local port="$1"
    local service_name="${2:-service}"
    
    # Check if port is a valid number
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        print_error "Неверный номер порта: $port (должен быть 1-65535)"
        return 1
    fi
    
    # Check if port is in use
    if is_port_in_use "$port"; then
        print_error "Порт $port уже используется!"
        print_info "Пожалуйста, выберите другой порт или освободите этот порт."
        return 1
    fi
    
    return 0
}

# Prompt for port with validation
prompt_port() {
    local default_port="$1"
    local service_name="${2:-service}"
    local port
    
    while true; do
        read -p "Введите порт для $service_name [$default_port]: " port
        port=${port:-$default_port}
        
        if validate_port "$port" "$service_name"; then
            echo "$port"
            return 0
        fi
        
        read -p "Try again? [y/N]: " retry
        if [[ "$retry" != "y" && "$retry" != "Y" ]]; then
            return 1
        fi
    done
}

# Install acme.sh for SSL certificate management
install_acme() {
    print_info "Установка acme.sh для управления SSL сертификатами..."
    cd ~ || return 1
    
    # Install dependencies based on package manager
    case $PACKAGE_MANAGER in
        apt)
            apt-get update -y
            apt-get install -y curl socat cron
            ;;
        dnf)
            dnf install -y curl socat cronie
            ;;
        yum)
            yum install -y curl socat cronie
            ;;
        pacman)
            pacman -S --noconfirm curl socat cronie
            ;;
        apk)
            apk add curl socat
            ;;
        zypper)
            zypper install -y curl socat cron
            ;;
    esac
    
    curl -s https://get.acme.sh | sh >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        print_error "Ошибка установки acme.sh"
        return 1
    else
        print_success "acme.sh успешно установлен"
    fi
    
    # Enable cron for auto-renewal
    if command -v systemctl &> /dev/null; then
        systemctl enable cron 2>/dev/null || systemctl enable crond 2>/dev/null || systemctl enable cronie 2>/dev/null || true
        systemctl start cron 2>/dev/null || systemctl start crond 2>/dev/null || systemctl start cronie 2>/dev/null || true
    elif command -v rc-update &> /dev/null; then
        rc-update add crond default 2>/dev/null || true
        rc-service crond start 2>/dev/null || true
    fi
    
    return 0
}

# Setup SSL certificate for domain (90 days, auto-renewal)
setup_ssl_certificate() {
    local domain="$1"
    local cert_dir="$2"
    
    print_info "Настройка SSL сертификата для домена: $domain"
    
    # Check if acme.sh is installed
    if ! acme_sh_ready; then
        install_acme
        if [ $? -ne 0 ]; then
            print_warning "Ошибка установки acme.sh, пропуск настройки SSL"
            return 1
        fi
    fi
    
    local acme
    acme="$(acme_sh_bin)"

    # Create certificate directory
    local acmeCertPath="/root/cert/${domain}"
    mkdir -p "$acmeCertPath"
    mkdir -p "$cert_dir"
    persist_cert_deploy_owner
    
    # Stop containers to free port 80
    print_info "Временная остановка контейнероto для освобождения порта 80..."
    cd "$INSTALL_DIR" 2>/dev/null && docker compose down 2>/dev/null || true
    
    # Issue certificate
    print_info "Выпуск SSL сертификата для ${domain}..."
    print_warning "Примечание: Порт 80 должен быть открыт и доступен из интернета"
    
    "${acme}" --set-default-ca --server letsencrypt >/dev/null 2>&1
    "${acme}" --issue -d ${domain} --listen-v6 --standalone --httpport 80 --force
    
    if [ $? -ne 0 ]; then
        print_error "Ошибка выпуска сертификата для ${domain}"
        print_warning "Пожалуйста, убедитесь, что порт 80 открыт и домен указывает на этот сервер"
        acme_rm_subject_dirs "${domain}"
        rm -rf "$acmeCertPath" 2>/dev/null
        return 1
    fi
    
    # Install certificate to acme path
    local ecc_arg
    ecc_arg="$(acme_ecc_arg "${domain}")"
    "${acme}" --installcert -d ${domain} ${ecc_arg} \
        --key-file ${acmeCertPath}/privkey.pem \
        --fullchain-file ${acmeCertPath}/fullchain.pem \
        --reloadcmd "$(build_acme_reloadcmd "${acmeCertPath}" "${cert_dir}")" >/dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        print_warning "Команда установки сертификата имела проблемы, проверка файлов..."
    fi
    
    if [[ ! -f "${acmeCertPath}/fullchain.pem" || ! -f "${acmeCertPath}/privkey.pem" ]]; then
        print_warning "PEM не появились после installcert; копируем из хранилища acme.sh (ECDSA / --ecc)..."
        acme_copy_from_store_to_pem_paths "${domain}" "${acmeCertPath}/fullchain.pem" "${acmeCertPath}/privkey.pem" || true
    fi

    # Copy certificates to our cert directory
    if [[ -f "${acmeCertPath}/fullchain.pem" && -f "${acmeCertPath}/privkey.pem" ]]; then
        cp "${acmeCertPath}/fullchain.pem" "${cert_dir}/"
        cp "${acmeCertPath}/privkey.pem" "${cert_dir}/"
        chmod 600 "${cert_dir}/privkey.pem"
        chmod 644 "${cert_dir}/fullchain.pem"
        fix_cert_dir_ownership "$cert_dir"
        docker_compose_restart_sharx
        print_success "SSL сертификат успешно установлен!"
    else
        print_error "Файлы сертификата не найдены"
        return 1
    fi
    
    # Enable auto-renew
    "${acme}" --upgrade --auto-upgrade >/dev/null 2>&1
    
    print_success "Сертификат действителен 90 дней с автоматическим обновлением"
    return 0
}

# Setup Let's Encrypt IP certificate with shortlived profile (~6 days validity)
setup_ip_certificate() {
    local ipv4="$1"
    local ipv6="${2:-}"
    local cert_dir="$3"

    print_info "Настройка Let's Encrypt IP сертификата (краткосрочный профиль)..."
    print_warning "Примечание: IP сертификаты действительны ~6 дней и будут автоматически обновляться."

    # Check for acme.sh
    if ! acme_sh_ready; then
        install_acme
        if [ $? -ne 0 ]; then
            print_error "Ошибка установки acme.sh"
            return 1
        fi
    fi
    
    local acme
    acme="$(acme_sh_bin)"

    # Validate IP address
    if [[ -z "$ipv4" ]]; then
        print_error "Требуется IPv4 адрес"
        return 1
    fi

    if ! is_ipv4 "$ipv4"; then
        print_error "Неверный IPv4 адрес: $ipv4"
        return 1
    fi

    # Create certificate direcвries
    local acmeCertDir="/root/cert/ip"
    mkdir -p "$acmeCertDir"
    mkdir -p "$cert_dir"
    persist_cert_deploy_owner

    # Build domain arguments
    local domain_args="-d ${ipv4}"
    if [[ -n "$ipv6" ]] && is_ipv6 "$ipv6"; then
        domain_args="${domain_args} -d ${ipv6}"
        print_info "Включение IPv6 адреса: ${ipv6}"
    fi

    # Stop containers to free port 80
    print_info "Временная остановка контейнероto для освобождения порта 80..."
    cd "$INSTALL_DIR" 2>/dev/null && docker compose down 2>/dev/null || true

    # Choose port for HTTP-01 listener
    local WebPort=80
    
    # Ensure port 80 is available
    if is_port_in_use 80; then
        print_warning "Порт 80 используется, попытка найти процесс..."
        fuser -k 80/tcp 2>/dev/null || true
        sleep 2
    fi

    # Issue certificate with shortlived profile
    print_info "Выпуск IP сертификата для ${ipv4}..."
    "${acme}" --set-default-ca --server letsencrypt >/dev/null 2>&1
    
    "${acme}" --issue \
        ${domain_args} \
        --standalone \
        --server letsencrypt \
        --certificate-profile shortlived \
        --days 6 \
        --httpport ${WebPort} \
        --force

    if [ $? -ne 0 ]; then
        print_error "Ошибка выпуска IP сертификата"
        print_warning "Пожалуйста, убедитесь, что порт 80 доступен из интернета"
        acme_rm_subject_dirs "${ipv4}"
        [[ -n "$ipv6" ]] && acme_rm_subject_dirs "${ipv6}"
        rm -rf ${acmeCertDir} 2>/dev/null
        return 1
    fi

    print_success "Сертификат успешно выпущен, установка..."

    # Install certificate (ECDSA / Let's Encrypt IP — каталог *_ecc, нужен --ecc)
    local ecc_arg
    ecc_arg="$(acme_ecc_arg "${ipv4}")"
    "${acme}" --installcert -d ${ipv4} ${ecc_arg} \
        --key-file "${acmeCertDir}/privkey.pem" \
        --fullchain-file "${acmeCertDir}/fullchain.pem" \
        --reloadcmd "$(build_acme_reloadcmd "${acmeCertDir}" "${cert_dir}")" 2>&1 || true

    if [[ ! -f "${acmeCertDir}/fullchain.pem" || ! -f "${acmeCertDir}/privkey.pem" ]]; then
        print_warning "PEM не появились после installcert; копируем из хранилища acme.sh (ECDSA / --ecc)..."
        acme_copy_from_store_to_pem_paths "${ipv4}" "${acmeCertDir}/fullchain.pem" "${acmeCertDir}/privkey.pem" || true
    fi

    # Verify certificate files exist
    if [[ ! -f "${acmeCertDir}/fullchain.pem" || ! -f "${acmeCertDir}/privkey.pem" ]]; then
        print_error "Файлы сертификата не найдены после установки"
        acme_rm_subject_dirs "${ipv4}"
        [[ -n "$ipv6" ]] && acme_rm_subject_dirs "${ipv6}"
        rm -rf ${acmeCertDir} 2>/dev/null
        return 1
    fi
    
    # Copy to our cert directory
    cp "${acmeCertDir}/fullchain.pem" "${cert_dir}/"
    cp "${acmeCertDir}/privkey.pem" "${cert_dir}/"
    chmod 600 "${cert_dir}/privkey.pem"
    chmod 644 "${cert_dir}/fullchain.pem"
    fix_cert_dir_ownership "$cert_dir"
    docker_compose_restart_sharx
    
    print_success "Файлы сертификата успешно установлены"

    # Enable auto-upgrade for acme.sh
    "${acme}" --upgrade --auto-upgrade >/dev/null 2>&1

    print_success "IP сертификат успешно установлен и настроен!"
    print_info "Сертификат действителен ~6 дней, автоматически обновляется через cron задачу acme.sh."
    return 0
}

# Find certificates in standard Let's Encrypt locations
find_letsencrypt_certificates() {
    local domain_or_ip="$1"
    local found_certs=()
    
    # Check /etc/letsencrypt/live/ (standard certbot location)
    if [[ -d "/etc/letsencrypt/live" ]]; then
        # Check for exact domain match
        if [[ -f "/etc/letsencrypt/live/${domain_or_ip}/fullchain.pem" ]] && \
           [[ -f "/etc/letsencrypt/live/${domain_or_ip}/privkey.pem" ]]; then
            found_certs+=("/etc/letsencrypt/live/${domain_or_ip}")
        fi
        
        # Also list all available domains
        for cert_dir in /etc/letsencrypt/live/*/; do
            if [[ -d "$cert_dir" ]] && [[ -f "${cert_dir}fullchain.pem" ]] && [[ -f "${cert_dir}privkey.pem" ]]; then
                local cert_domain=$(basename "$cert_dir")
                # Skip if already added
                local already_added=false
                for existing in "${found_certs[@]}"; do
                    if [[ "$existing" == "/etc/letsencrypt/live/${cert_domain}" ]]; then
                        already_added=true
                        break
                    fi
                done
                if [[ "$already_added" == false ]]; then
                    found_certs+=("/etc/letsencrypt/live/${cert_domain}")
                fi
            fi
        done
    fi
    
    # Return found certificates (one per line)
    for cert_path in "${found_certs[@]}"; do
        echo "$cert_path"
    done
}

# Copy certificate from standard Let's Encrypt location
copy_letsencrypt_certificate() {
    local source_dir="$1"
    local target_dir="$2"
    
    if [[ ! -d "$source_dir" ]]; then
        print_error "Директория сертификата не найдена: $source_dir"
        return 1
    fi
    
    if [[ ! -f "${source_dir}/fullchain.pem" ]] || [[ ! -f "${source_dir}/privkey.pem" ]]; then
        print_error "Файлы сертификата не найдены in $source_dir"
        return 1
    fi
    
    # Verify certificate is valid (not expired)
    if command -v openssl &>/dev/null; then
        local expiry=$(openssl x509 -in "${source_dir}/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        if [[ -n "$expiry" ]]; then
            local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry" +%s 2>/dev/null)
            local now_epoch=$(date +%s)
            if [[ -n "$expiry_epoch" && "$expiry_epoch" -le "$now_epoch" ]]; then
                print_warning "Сертификат в $source_dir истек (истек: $expiry)"
                return 1
            fi
        fi
    fi
    
    # Copy certificates
    mkdir -p "$target_dir"
    cp "${source_dir}/fullchain.pem" "${target_dir}/"
    cp "${source_dir}/privkey.pem" "${target_dir}/"
    chmod 600 "${target_dir}/privkey.pem" 2>/dev/null
    chmod 644 "${target_dir}/fullchain.pem" 2>/dev/null
    fix_cert_dir_ownership "$target_dir"
    
    print_success "Сертификаты скопированы из $source_dir в $target_dir"
    return 0
}

# Interactive SSL setup (domain or IP)
prompt_and_setup_ssl() {
    local cert_dir="$1"
    local server_ip="$2"
    
    # First check for existing certificates
    echo ""
    print_info "Поиск существующих сертификатов..."
    
    # Check if we already have valid certificates in cert_dir
    if [[ -f "${cert_dir}/fullchain.pem" && -f "${cert_dir}/privkey.pem" ]]; then
        if check_existing_certificates "$server_ip" "$cert_dir" 2>/dev/null; then
            echo ""
            echo -e "${GREEN}Действительный сертификат уже существует в ${cert_dir}${NC}"
            read -p "Использовать существующий сертификат? [Y/n]: " use_existing
            if [[ "$use_existing" != "n" && "$use_existing" != "N" ]]; then
                SSL_HOST="${server_ip}"
                CERT_TYPE="letsencrypt-ip"
                print_success "Использование существующего сертификата"
                # Update SSL settings in database if panel is running (ignore errors)
                update_ssl_settings_in_db "/app/cert/fullchain.pem" "/app/cert/privkey.pem" || true
                return 0
            fi
        fi
    fi
    
    # Check for certificates in standard Let's Encrypt locations
    local letsencrypt_certs=()
    while IFS= read -r cert_path; do
        [[ -n "$cert_path" ]] && letsencrypt_certs+=("$cert_path")
    done < <(find_letsencrypt_certificates "$server_ip")
    
    if [[ ${#letsencrypt_certs[@]} -gt 0 ]]; then
        echo ""
        echo -e "${GREEN}Найдены Let's Encrypt сертификаты в стандартных местах:${NC}"
        local cert_index=1
        for cert_path in "${letsencrypt_certs[@]}"; do
            local cert_domain=$(basename "$cert_path")
            echo -e "  ${CYAN}${cert_index}.${NC} ${cert_path} (домен: ${GREEN}${cert_domain}${NC})"
            ((cert_index++))
        done
        echo ""
        read -p "Использовать один из этих сертификатов? [y/N]: " use_letsencrypt
        if [[ "$use_letsencrypt" == "y" || "$use_letsencrypt" == "Y" ]]; then
            if [[ ${#letsencrypt_certs[@]} -eq 1 ]]; then
                local selected_cert="${letsencrypt_certs[0]}"
            else
                read -p "Введите номер сертификата [1-${#letsencrypt_certs[@]}]: " cert_num
                if [[ "$cert_num" =~ ^[0-9]+$ ]] && [[ "$cert_num" -ge 1 ]] && [[ "$cert_num" -le ${#letsencrypt_certs[@]} ]]; then
                    local selected_cert="${letsencrypt_certs[$((cert_num-1))]}"
                else
                    print_error "Неверный выбор"
                    return 1
                fi
            fi
            
            if copy_letsencrypt_certificate "$selected_cert" "$cert_dir"; then
                local cert_domain=$(basename "$selected_cert")
                SSL_HOST="$cert_domain"
                # Determine if it's a domain or IP
                if is_ipv4 "$cert_domain" || is_ipv6 "$cert_domain"; then
                    CERT_TYPE="letsencrypt-ip"
                else
                    CERT_TYPE="letsencrypt-domain"
                fi
                print_success "Использование Let's Encrypt сертификата из $selected_cert"
                update_ssl_settings_in_db "/app/cert/fullchain.pem" "/app/cert/privkey.pem" || true
                return 0
            fi
        fi
    fi
    
    # Check acme.sh for existing certificates for this IP
    if [[ -d "/root/.acme.sh/${server_ip}_ecc" ]] || [[ -d "/root/.acme.sh/${server_ip}" ]] || \
       [[ -d "${HOME}/.acme.sh/${server_ip}_ecc" ]] || [[ -d "${HOME}/.acme.sh/${server_ip}" ]]; then
        if check_existing_certificates "$server_ip" "$cert_dir"; then
            echo ""
            echo -e "${GREEN}Найден существующий Let's Encrypt сертификат для ${server_ip}${NC}"
            read -p "Использовать существующий сертификат? [Y/n]: " use_existing
            if [[ "$use_existing" != "n" && "$use_existing" != "N" ]]; then
                SSL_HOST="${server_ip}"
                CERT_TYPE="letsencrypt-ip"
                print_success "Использование существующего сертификата"
                # Update SSL settings in database if panel is running (ignore errors)
                update_ssl_settings_in_db "/app/cert/fullchain.pem" "/app/cert/privkey.pem" || true
                return 0
            fi
        fi
    fi

    echo ""
    echo -e "${CYAN}Выберите метод настройки SSL сертификата:${NC}"
    echo -e "${GREEN}1.${NC} Let's Encrypt for Domain (90-day validity, auto-renews)"
    echo -e "${GREEN}2.${NC} Let's Encrypt for IP Address (6-day validity, auto-renews)"
    echo -e "${GREEN}3.${NC} Пропустить настройку SSL (настроить позже)"
    echo -e "${SKYBLUE}Примечание:${NC} Оба варианта требуют открытый порт 80 для HTTP-01 проверки."
    echo ""
    read -rp "Выберите опцию [1-3, по умолчанию: 2]: " ssl_choice
    ssl_choice="${ssl_choice:-2}"

    case "$ssl_choice" in
    1)
        # Let's Encrypt domain certificate
        print_info "Использование Let's Encrypt для сертификата домена..."
        
        local domain=""
        while true; do
            read -rp "Пожалуйста, введите имя вашего домена: " domain
            domain="${domain// /}"
            
            if [[ -z "$domain" ]]; then
                print_error "Имя домена не может быть пустым. Пожалуйста, попробуйте снова."
                continue
            fi
            
            if ! is_domain "$domain"; then
                print_error "Неверный формат домена: ${domain}. Пожалуйста, введите действительное имя домена."
                continue
            fi
            
            break
        done
        
        # Check for certificates in standard Let's Encrypt locations for this domain
        local letsencrypt_certs=()
        while IFS= read -r cert_path; do
            [[ -n "$cert_path" ]] && letsencrypt_certs+=("$cert_path")
        done < <(find_letsencrypt_certificates "$domain")
        
        if [[ ${#letsencrypt_certs[@]} -gt 0 ]]; then
            echo ""
            echo -e "${GREEN}Найдены сертификаты Let's Encrypt в стандартных местах для ${domain}:${NC}"
            local cert_index=1
            for cert_path in "${letsencrypt_certs[@]}"; do
                local cert_domain=$(basename "$cert_path")
                echo -e "  ${CYAN}${cert_index}.${NC} ${cert_path} (домен: ${GREEN}${cert_domain}${NC})"
                ((cert_index++))
            done
            echo ""
            read -p "Use one of these certificates? [Y/n]: " use_letsencrypt
            if [[ "$use_letsencrypt" != "n" && "$use_letsencrypt" != "N" ]]; then
                if [[ ${#letsencrypt_certs[@]} -eq 1 ]]; then
                    local selected_cert="${letsencrypt_certs[0]}"
                else
                    read -p "Введите номер сертификата [1-${#letsencrypt_certs[@]}]: " cert_num
                    if [[ "$cert_num" =~ ^[0-9]+$ ]] && [[ "$cert_num" -ge 1 ]] && [[ "$cert_num" -le ${#letsencrypt_certs[@]} ]]; then
                        local selected_cert="${letsencrypt_certs[$((cert_num-1))]}"
                    else
                        print_error "Неверный выбор"
                        continue
                    fi
                fi
                
                if copy_letsencrypt_certificate "$selected_cert" "$cert_dir"; then
                    SSL_HOST="${domain}"
                    CERT_TYPE="letsencrypt-domain"
                    print_success "Использование Let's Encrypt сертификата из $selected_cert"
                    update_ssl_settings_in_db "/app/cert/fullchain.pem" "/app/cert/privkey.pem" || true
                    return 0
                else
                    print_warning "Не удалось скопировать сертификат, продолжаем с генерацией нового сертификата..."
                fi
            fi
        fi
        
        # Check for existing domain certificate (acme.sh or local)
        if check_existing_certificates "$domain" "$cert_dir"; then
            echo ""
            echo -e "${GREEN}Найден существующий сертификат для ${domain}${NC}"
            read -p "Использовать существующий сертификат? [Y/n]: " use_existing
            if [[ "$use_existing" != "n" && "$use_existing" != "N" ]]; then
                SSL_HOST="${domain}"
                CERT_TYPE="letsencrypt-domain"
                print_success "Использование существующего сертификата для ${domain}"
                # Update SSL settings in database (ignore errors if DB not running)
                update_ssl_settings_in_db "/app/cert/fullchain.pem" "/app/cert/privkey.pem" || true
                return 0
            fi
        fi
        
        setup_ssl_certificate "$domain" "$cert_dir"
        if [ $? -eq 0 ]; then
            SSL_HOST="${domain}"
            CERT_TYPE="letsencrypt-domain"
            print_success "SSL сертификат успешно настроен для домена: ${domain}"
            # Update SSL settings in database (ignore errors if DB not running)
            update_ssl_settings_in_db "/app/cert/fullchain.pem" "/app/cert/privkey.pem" || true
        else
            print_warning "Ошибка настройки SSL. Вы можете настроить его позже из меню."
            SSL_HOST="${server_ip}"
            CERT_TYPE="none"
        fi
        ;;
    2)
        # Let's Encrypt IP certificate
        print_info "Использование Let's Encrypt для IP сертификата (краткосрочный профиль)..."
        
        # Ask for optional IPv6
        local ipv6_addr=""
        local detected_ipv6=$(get_server_ipv6)
        if [[ -n "$detected_ipv6" ]]; then
            echo -e "Обнаружен IPv6: ${GREEN}$detected_ipv6${NC}"
            read -rp "Включить этот IPv6 адрес? [Y/n]: " include_ipv6
            if [[ "$include_ipv6" != "n" && "$include_ipv6" != "N" ]]; then
                ipv6_addr="$detected_ipv6"
            fi
        else
            read -rp "Введите IPv6 адрес для включения (оставьте пустым для пропуска): " ipv6_addr
            ipv6_addr="${ipv6_addr// /}"
        fi
        
        setup_ip_certificate "${server_ip}" "${ipv6_addr}" "$cert_dir"
        if [ $? -eq 0 ]; then
            SSL_HOST="${server_ip}"
            CERT_TYPE="letsencrypt-ip"
            print_success "Let's Encrypt IP сертификат успешно настроен"
            # Update SSL settings in database (ignore errors if DB not running)
            update_ssl_settings_in_db "/app/cert/fullchain.pem" "/app/cert/privkey.pem" || true
        else
            print_warning "Ошибка настройки IP сертификата. Вы можете настроить его позже из меню."
            SSL_HOST="${server_ip}"
            CERT_TYPE="none"
        fi
        ;;
    3)
        print_warning "Пропуск настройки SSL. Не забудьте настроить SSL позже!"
        SSL_HOST="${server_ip}"
        CERT_TYPE="none"
        ;;
    *)
        print_warning "Неверная опция. Пропуск настройки SSL."
        SSL_HOST="${server_ip}"
        CERT_TYPE="none"
        ;;
    esac
}

# Read environment variable from docker-compose.yml
read_env_from_compose() {
    local var_name="$1"
    local compose_file="$INSTALL_DIR/$COMPOSE_FILE"
    
    if [[ ! -f "$compose_file" ]]; then
        return 1
    fi
    
    # Extract value from docker-compose.yml (handles both : and = formats)
    local value=$(grep -E "^\s+${var_name}:" "$compose_file" | sed -E "s/^\s+${var_name}:\s*(.+)$/\1/" | sed -E "s/^[\"']|[\"']$//g" | head -n 1)
    
    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    fi
    
    return 1
}

# Read all environment variables from docker-compose.yml
read_all_env_from_compose() {
    local compose_file="$INSTALL_DIR/$COMPOSE_FILE"
    
    if [[ ! -f "$compose_file" ]]; then
        return 1
    fi
    
    # Extract environment section
    local in_env=false
    local env_vars=""
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*environment: ]]; then
            in_env=true
            continue
        fi
        
        if [[ "$in_env" == true ]]; then
            # Stop at next top-level key
            if [[ "$line" =~ ^[[:space:]]*[a-zA-Z] ]] && [[ ! "$line" =~ ^[[:space:]]+# ]] && [[ ! "$line" =~ ^[[:space:]]+[A-Z_]+: ]]; then
                break
            fi
            
            # Extract env var (format: VAR_NAME: value or - VAR_NAME=value)
            if [[ "$line" =~ ^[[:space:]]+([A-Z_]+):[[:space:]]*(.+)$ ]]; then
                local var_name="${BASH_REMATCH[1]}"
                local var_value="${BASH_REMATCH[2]}"
                var_value=$(echo "$var_value" | sed -E "s/^[\"']|[\"']$//g")
                env_vars="${env_vars}${var_name}=${var_value}\n"
            fi
        fi
    done < "$compose_file"
    
    echo -e "$env_vars"
}

# Generate environment variables section for docker-compose.yml
generate_https_env() {
    local panel_port="$1"
    local sub_port="$2"
    local cert_dir="$INSTALL_DIR/cert"
    local env_section=""
    
    # Try to read existing env vars from docker-compose.yml
    local existing_env=""
    if [[ -f "$INSTALL_DIR/$COMPOSE_FILE" ]]; then
        existing_env=$(read_all_env_from_compose)
    fi
    
    # Extract existing values or use defaults
    # Use provided parameters as defaults, but prefer existing env values if they exist
    local web_port=$(echo -e "$existing_env" | grep "^XUI_WEB_PORT=" | cut -d'=' -f2)
    # If panel_port is provided and different from default, use it (allows override)
    if [[ -n "$panel_port" ]] && [[ "$panel_port" != "2053" ]]; then
        web_port=${web_port:-$panel_port}
    else
        web_port=${web_port:-$panel_port}
    fi
    
    local web_domain=$(echo -e "$existing_env" | grep "^XUI_WEB_DOMAIN=" | cut -d'=' -f2)
    local web_listen=$(echo -e "$existing_env" | grep "^XUI_WEB_LISTEN=" | cut -d'=' -f2)
    web_listen=${web_listen:-"0.0.0.0"}
    
    local web_base_path=$(echo -e "$existing_env" | grep "^XUI_WEB_BASE_PATH=" | cut -d'=' -f2)
    web_base_path=${web_base_path:-"/"}
    
    local web_cert_file=$(echo -e "$existing_env" | grep "^XUI_WEB_CERT_FILE=" | cut -d'=' -f2)
    local web_key_file=$(echo -e "$existing_env" | grep "^XUI_WEB_KEY_FILE=" | cut -d'=' -f2)
    
    local sub_port_env=$(echo -e "$existing_env" | grep "^XUI_SUB_PORT=" | cut -d'=' -f2)
    # If sub_port is provided and different from default, use it (allows override)
    if [[ -n "$sub_port" ]] && [[ "$sub_port" != "2096" ]]; then
        sub_port_env=${sub_port_env:-$sub_port}
    else
        sub_port_env=${sub_port_env:-$sub_port}
    fi
    
    local sub_path=$(echo -e "$existing_env" | grep "^XUI_SUB_PATH=" | cut -d'=' -f2)
    sub_path=${sub_path:-"/sub/"}
    
    local sub_domain=$(echo -e "$existing_env" | grep "^XUI_SUB_DOMAIN=" | cut -d'=' -f2)
    local sub_cert_file=$(echo -e "$existing_env" | grep "^XUI_SUB_CERT_FILE=" | cut -d'=' -f2)
    local sub_key_file=$(echo -e "$existing_env" | grep "^XUI_SUB_KEY_FILE=" | cut -d'=' -f2)
    
    # Web Panel settings
    # Always write port if it's different from default or explicitly set
    if [[ -n "$web_port" ]] && [[ "$web_port" != "2053" ]]; then
        env_section="${env_section}      XUI_WEB_PORT: $web_port\n"
    elif [[ -n "$panel_port" ]] && [[ "$panel_port" != "2053" ]]; then
        env_section="${env_section}      XUI_WEB_PORT: $panel_port\n"
    fi
    
    if [[ -n "$web_listen" ]] && [[ "$web_listen" != "0.0.0.0" ]]; then
        env_section="${env_section}      XUI_WEB_LISTEN: $web_listen\n"
    fi
    
    if [[ -n "$web_domain" ]]; then
        env_section="${env_section}      XUI_WEB_DOMAIN: $web_domain\n"
    elif load_config 2>/dev/null && [[ "$CERT_TYPE" == "letsencrypt-domain" && -n "$DOMAIN_OR_IP" ]]; then
        # Extract domain from DOMAIN_OR_IP
        local domain="${DOMAIN_OR_IP}"
        domain="${domain#https://}"
        domain="${domain#http://}"
        domain="${domain%%:*}"
        if [[ -n "$domain" ]] && ! is_ipv4 "$domain" && ! is_ipv6 "$domain"; then
            env_section="${env_section}      XUI_WEB_DOMAIN: $domain\n"
        fi
    fi
    
    if [[ -n "$web_base_path" ]] && [[ "$web_base_path" != "/" ]]; then
        env_section="${env_section}      XUI_WEB_BASE_PATH: $web_base_path\n"
    fi
    
    # Web Panel certificates
    if [[ -n "$web_cert_file" ]]; then
        env_section="${env_section}      XUI_WEB_CERT_FILE: $web_cert_file\n"
    elif [[ -f "$cert_dir/fullchain.pem" ]]; then
        env_section="${env_section}      XUI_WEB_CERT_FILE: /app/cert/fullchain.pem\n"
    fi
    
    if [[ -n "$web_key_file" ]]; then
        env_section="${env_section}      XUI_WEB_KEY_FILE: $web_key_file\n"
    elif [[ -f "$cert_dir/privkey.pem" ]]; then
        env_section="${env_section}      XUI_WEB_KEY_FILE: /app/cert/privkey.pem\n"
    fi
    
    # Subscription settings
    # Always write port if it's different from default or explicitly set
    if [[ -n "$sub_port_env" ]] && [[ "$sub_port_env" != "2096" ]]; then
        env_section="${env_section}      XUI_SUB_PORT: $sub_port_env\n"
    elif [[ -n "$sub_port" ]] && [[ "$sub_port" != "2096" ]]; then
        env_section="${env_section}      XUI_SUB_PORT: $sub_port\n"
    fi
    
    if [[ -n "$sub_path" ]] && [[ "$sub_path" != "/sub/" ]]; then
        env_section="${env_section}      XUI_SUB_PATH: $sub_path\n"
    fi
    
    if [[ -n "$sub_domain" ]]; then
        env_section="${env_section}      XUI_SUB_DOMAIN: $sub_domain\n"
    fi
    
    # Subscription certificates
    # Use sub-specific certificates if available, otherwise fallback to main certificates
    if [[ -n "$sub_cert_file" ]]; then
        env_section="${env_section}      XUI_SUB_CERT_FILE: $sub_cert_file\n"
    elif [[ -f "$cert_dir/sub-fullchain.pem" ]]; then
        env_section="${env_section}      XUI_SUB_CERT_FILE: /app/cert/sub-fullchain.pem\n"
    elif [[ -f "$cert_dir/fullchain.pem" ]]; then
        # Fallback to main certificate if sub-specific doesn't exist
        env_section="${env_section}      XUI_SUB_CERT_FILE: /app/cert/fullchain.pem\n"
    fi
    
    if [[ -n "$sub_key_file" ]]; then
        env_section="${env_section}      XUI_SUB_KEY_FILE: $sub_key_file\n"
    elif [[ -f "$cert_dir/sub-privkey.pem" ]]; then
        env_section="${env_section}      XUI_SUB_KEY_FILE: /app/cert/sub-privkey.pem\n"
    elif [[ -f "$cert_dir/privkey.pem" ]]; then
        # Fallback to main key if sub-specific doesn't exist
        env_section="${env_section}      XUI_SUB_KEY_FILE: /app/cert/privkey.pem\n"
    fi
    
    echo -e "$env_section"
}

# Create docker-compose.yml with host network
create_compose_host() {
    local panel_port="$1"
    local sub_port="$2"
    local db_password="$3"
    
    # Generate environment variables (Web Panel, Subscription, certificates)
    local env_vars=$(generate_https_env "$panel_port" "$sub_port")
    
    cat > "$INSTALL_DIR/$COMPOSE_FILE" << EOF
services:
  sharx:
    image: registry.konstpic.ru/sharx/sharx:latest
    container_name: sharx_app
    network_mode: host
    labels:
      com.centurylinklabs.watchtower.enable: "true"
    volumes:
      - \$PWD/cert/:/app/cert/
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    environment:
      # Xray settings
      XRAY_VMESS_AEAD_FORCED: "false"
      XUI_ENABLE_FAIL2BAN: "true"
      # XUI_LOG_LEVEL: "debug"
      
      # Web Panel настройки (только через env, не доступны в UI)
$(echo -e "$env_vars")
      
      # PostgreSQL settings
      XUI_DB_HOST: 127.0.0.1
      XUI_DB_PORT: 5432
      XUI_DB_USER: xui_user
      XUI_DB_PASSWORD: $db_password
      XUI_DB_NAME: xui_db
      XUI_DB_SSLMODE: disable
      XUI_DOCKER_UPDATER_URL: http://127.0.0.1:8081/v1/update
      XUI_DOCKER_UPDATER_TOKEN: \${WATCHTOWER_HTTP_API_TOKEN:-local-dev-insecure-watchtower-token}
    depends_on:
      postgres:
        condition: service_healthy
      watchtower:
        condition: service_started
    tty: true
    restart: unless-stopped

  watchtower:
    image: beatkind/watchtower:2.3.2
    container_name: sharx_watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command:
      - --http-api-update
    ports:
      - "127.0.0.1:8081:8080"
    environment:
      WATCHTOWER_HTTP_API_TOKEN: \${WATCHTOWER_HTTP_API_TOKEN:-local-dev-insecure-watchtower-token}
      WATCHTOWER_LABEL_ENABLE: "true"
      WATCHTOWER_CLEANUP: "true"
    labels:
      com.centurylinklabs.watchtower.enable: "false"
    networks:
      - xui_network

  postgres:
    image: registry.konstpic.ru/sharx/postgres:16-alpine
    container_name: sharx_postgres
    network_mode: host
    environment:
      POSTGRES_USER: xui_user
      POSTGRES_PASSWORD: $db_password
      POSTGRES_DB: xui_db
    volumes:
      - \$PWD/postgres_data:/var/lib/postgresql/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h 127.0.0.1 -p 5432 -U xui_user -d xui_db"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

networks:
  xui_network:
    driver: bridge
EOF
    
    print_success "Docker Compose file created with host network mode!"
}

# Create docker-compose.yml with bridge network (port mapping)
create_compose_bridge() {
    local panel_port="$1"
    local sub_port="$2"
    local db_password="$3"
    shift 3
    local additional_ports=("$@")
    
    # Build ports section
    # In bridge mode, we map external port to the same internal port (XUI_WEB_PORT/XUI_SUB_PORT)
    local ports_section="      - \"$panel_port:$panel_port\"   # Web UI\n      - \"$sub_port:$sub_port\"     # Subscriptions"
    
    for port in "${additional_ports[@]}"; do
        if [[ -n "$port" ]]; then
            ports_section="${ports_section}\n      - \"$port:$port\"   # Additional port"
        fi
    done
    
    # Generate environment variables (Web Panel, Subscription, certificates)
    local env_vars=$(generate_https_env "$panel_port" "$sub_port")
    
    cat > "$INSTALL_DIR/$COMPOSE_FILE" << EOF
services:
  sharx:
    image: registry.konstpic.ru/sharx/sharx:latest
    container_name: sharx_app
    labels:
      com.centurylinklabs.watchtower.enable: "true"
    ports:
$(echo -e "$ports_section")
    volumes:
      - \$PWD/cert/:/app/cert/
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    environment:
      # Xray settings
      XRAY_VMESS_AEAD_FORCED: "false"
      XUI_ENABLE_FAIL2BAN: "true"
      # XUI_LOG_LEVEL: "debug"
      
      # Web Panel настройки (только через env, не доступны в UI)
      # XUI_WEB_PORT: 2053
      # XUI_WEB_LISTEN: 0.0.0.0
      # XUI_WEB_DOMAIN: panel.example.com
      # XUI_WEB_BASE_PATH: /
      # XUI_WEB_CERT_FILE: /app/cert/fullchain.pem
      # XUI_WEB_KEY_FILE: /app/cert/privkey.pem
      
      # Subscription настройки (только через env, не доступны в UI)
      # XUI_SUB_PORT: 2096
      # XUI_SUB_PATH: /sub/
      # XUI_SUB_DOMAIN: sub.example.com
      # XUI_SUB_CERT_FILE: /app/cert/sub-fullchain.pem
      # XUI_SUB_KEY_FILE: /app/cert/sub-privkey.pem
$(echo -e "$env_vars")
      
      # PostgreSQL settings
      XUI_DB_HOST: postgres
      XUI_DB_PORT: 5432
      XUI_DB_USER: xui_user
      XUI_DB_PASSWORD: $db_password
      XUI_DB_NAME: xui_db
      XUI_DB_SSLMODE: disable
      XUI_DOCKER_UPDATER_URL: http://watchtower:8080/v1/update
      XUI_DOCKER_UPDATER_TOKEN: \${WATCHTOWER_HTTP_API_TOKEN:-local-dev-insecure-watchtower-token}
    depends_on:
      postgres:
        condition: service_healthy
      watchtower:
        condition: service_started
    networks:
      - xui_network
    tty: true
    restart: unless-stopped

  watchtower:
    image: beatkind/watchtower:2.3.2
    container_name: sharx_watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command:
      - --http-api-update
    environment:
      WATCHTOWER_HTTP_API_TOKEN: \${WATCHTOWER_HTTP_API_TOKEN:-local-dev-insecure-watchtower-token}
      WATCHTOWER_LABEL_ENABLE: "true"
      WATCHTOWER_CLEANUP: "true"
    labels:
      com.centurylinklabs.watchtower.enable: "false"
    networks:
      - xui_network

  postgres:
    image: registry.konstpic.ru/sharx/postgres:16-alpine
    container_name: sharx_postgres
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: xui_user
      POSTGRES_PASSWORD: $db_password
      POSTGRES_DB: xui_db
    volumes:
      - \$PWD/postgres_data:/var/lib/postgresql/data
    networks:
      - xui_network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h 127.0.0.1 -p 5432 -U xui_user -d xui_db"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

networks:
  xui_network:
    driver: bridge
EOF
    
    print_success "Docker Compose file created with bridge network mode!"
}

# WARP install
warp_install() {
    echo -e "\e[38;2;0;255;255m--- 1. Установка Cloudflare WARP ---\e[0m"
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
sudo apt update && sudo apt install cloudflare-warp -y

echo -e "\e[38;2;0;255;255m--- 2. Настройка WARP в режиме Proxy ---\e[0m"
warp-cli registration new
warp-cli mode proxy
warp-cli proxy port 4000
warp-cli connect

echo -e "\e[38;2;0;255;255m--- 3. Установка GOST (входной мост) ---\e[0m"
GOST_VERSION="3.0.0-rc10"
wget https://github.com/go-gost/gost/releases/download/v${GOST_VERSION}/gost_${GOST_VERSION}_linux_amd64.tar.gz
tar -xvzf gost_${GOST_VERSION}_linux_amd64.tar.gz
sudo mv gost /usr/bin/
rm gost_${GOST_VERSION}_linux_amd64.tar.gz README* LICENSE*

echo -e "\e[38;2;0;255;255m--- 4. Создание службы для автозапуска GOST ---\e[0m"
sudo tee /etc/systemd/system/gost.service > /dev/null <<EOF
[Unit]
Description=Gost Proxy Bridge
After=network.target warp-svc.service

[Service]
Type=simple
ExecStart=/usr/bin/gost -L PROXY_USER:PROXY_PASS@:PROXY_PORT -F socks5://127.0.0.1:4000
Restart=always

[Install]
WantedBy=multi-user.target
EOF

while true; do
	read -p "Укажите логин для внешнего прокси: " login
	if [ -z "$login" ]; then
		echo -e "\e[91mНе может быть пустым!\e[0m"
	continue
	fi
	break
done
sed -i 's/PROXY_USER/'$login'/g' /etc/systemd/system/gost.service
while true; do
        read -p "Укажите пароль для внешнего прокси: " password
	if [ -z "$password" ]; then
		echo -e "\e[91mНе может быть пустым!\e[0m"
	continue
	fi
	break
done
sed -i 's/PROXY_PASS/'$password'/g' /etc/systemd/system/gost.service
while true; do
	read -p "Укажите внешний порт прокси: " port
	if [ -z "$port" ]; then
		echo -e "\e[91mНе может быть пустым!\e[0m"
	continue
	fi
	break
done
sed -i 's/PROXY_PORT/'$port'/g' /etc/systemd/system/gost.service /etc/systemd/system/gost.service
sudo systemctl daemon-reload
sudo systemctl enable --now gost

echo -e "		\e[38;2;0;255;255m--- Успех! ---\e[0m"
sleep 5
clear
ss -tlnp | grep 4000
curl -x socks5h://127.0.0.1:4000 https://www.cloudflare.com/cdn-cgi/trace

    echo -e "\e[38;2;0;255;255m"
    echo "-----------------------------------------------------------------"
    echo "			ГОТОВО!"
    echo "	Ваш внешний прокси: SOCKS5 или HTTP"
    echo "	Адрес: $(curl -s -4 curl ident.me):${port}"
    echo "	Логин: ${login}"
    echo "	Пароль: ${password}"
    echo "	Ваш внутренний прокси SOCKS (без логина и пароля)"
    echo "	127.0.0.1:4000"
    echo "-----------------------------------------------------------------"
    echo -e "\e[0m"
}
# WARP uninstall
warp_uninstall() {
    systemctl daemon-reload
    systemctl disable gost.service
    systemctl stop gost.service
    rm /usr/bin/gost
    warp-cli registration delete
    warp-cli disconnect
    apt purge cloudflare-warp -y
    apt autoremove -y
}
# Disable ipv6
disable_ipv6() {
    grep -qxF "# Disable ipv6\nnet.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1\nnet.ipv6.conf.lo.disable_ipv6 = 1" /etc/sysctl.d/99-SharX-ipv6.conf || echo -e "# Disable ipv6\nnet.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1\nnet.ipv6.conf.lo.disable_ipv6 = 1" > /etc/sysctl.d/99-SharX-ipv6.conf
    sysctl -p
}

# Save configuration
save_config() {
    local panel_port="$1"
    local sub_port="$2"
    local db_password="$3"
    local network_mode="$4"
    local cert_type="$5"
    local domain_or_ip="$6"
    shift 6
    local additional_ports=("$@")
    
    cat > "$INSTALL_DIR/.3xui-config" << EOF
# SharX Configuration
# Generated: $(date)

PANEL_PORT=$panel_port
SUB_PORT=$sub_port
DB_PASSWORD=$db_password
NETWORK_MODE=$network_mode
CERT_TYPE=$cert_type
DOMAIN_OR_IP=$domain_or_ip
INSTALL_DIR=$INSTALL_DIR
ADDITIONAL_PORTS=($(IFS=' '; echo "${additional_ports[*]}"))
EOF
    
    chmod 600 "$INSTALL_DIR/.3xui-config"
}

# Load configuration
load_config() {
    if [[ -f "$INSTALL_DIR/.3xui-config" ]]; then
        source "$INSTALL_DIR/.3xui-config"
        # Initialize ADDITIONAL_PORTS if not set
        if [[ -z "${ADDITIONAL_PORTS[@]}" ]]; then
            ADDITIONAL_PORTS=()
        fi
        return 0
    fi
    return 1
}

# Start services
start_services() {
    print_info "Запуск сервисов SharX..."
    cd "$INSTALL_DIR"
    docker compose up -d
    
    # Wait for services to start
    sleep 5
    
    if docker compose ps | grep -q "Up"; then
        print_success "Services started successfully!"
    else
        print_error "Не удалось запустить сервисы. Проверьте логи: docker compose logs"
        exit 1
    fi
}

# Stop services
stop_services() {
    print_info "Остановка сервисов SharX..."
    cd "$INSTALL_DIR"
    docker compose down
    print_success "Services stopped!"
}

# Update services
update_services() {
    print_banner
    echo ""
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                  ⚠️  ВАЖНОЕ ПРЕДУПРЕЖДЕНИЕ ⚠️                ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${RED}Перед обновлением мы НАСТОЯТЕЛЬНО РЕКОМЕНДУЕМ создать резервную копию базы данных!${NC}"
    echo ""
    echo -e "${CYAN}Расположение базы данных:${NC} ${WHITE}$INSTALL_DIR/postgres_data${NC}"
    echo ""
    echo -e "${CYAN}Для создания резервной копии выполните:${NC}"
    echo -e "  ${YELLOW}docker exec -t \$(docker ps -qf name=postgres) pg_dump -U xui_user xui_db > backup_\$(date +%Y%m%d_%H%M%S).sql${NC}"
    echo ""
    echo -e "${CYAN}Или используйте встроенную функцию резервного копирования в панели: Настройки → Резервное копирование.${NC}"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    while true; do
        echo -e -n "${CYAN}Вы создали резервную копию базы данных? (да/нет): ${NC}"
        read -r backup_confirm
        case "$backup_confirm" in
            [Дд][Аа]|[Дд]|[Yy][Ee][Ss]|[Yy])
                break
                ;;
            [Нн][Ее][Тт]|[Нн]|[Nn][Oo]|[Nn])
                echo ""
                echo -e "${YELLOW}Вы хотите продолжить без резервной копии? (да/нет): ${NC}"
                read -r continue_confirm
                case "$continue_confirm" in
                    [Дд][Аа]|[Дд]|[Yy][Ee][Ss]|[Yy])
                        echo -e "${YELLOW}Продолжаем обновление без резервной копии...${NC}"
                        echo ""
                        break
                        ;;
                    [Нн][Ее][Тт]|[Нн]|[Nn][Oo]|[Nn]|*)
                        echo -e "${GREEN}Обновление отменено. Пожалуйста, сначала создайте резервную копию.${NC}"
                        return 1
                        ;;
                esac
                ;;
            *)
                echo -e "${RED}Пожалуйста, ответьте 'да' или 'нет'.${NC}"
                ;;
        esac
    done
    
    echo ""
    print_info "Обновление панели SharX..."
    cd "$INSTALL_DIR"
    
    print_info "Шаг 1/3: Загрузка новых образов (панель + watchtower)..."
    docker compose pull sharx watchtower
    
    print_info "Шаг 2/3: Остановка и удаление старых контейнеров..."
    docker compose stop sharx watchtower
    docker compose rm -f sharx watchtower
    
    print_info "Шаг 3/3: Запуск с новыми образами..."
    docker compose up -d sharx watchtower
    
    # Cleanup old images
    print_info "Очистка старых образов..."
    docker image prune -f
    
    print_success "Панель SharX успешно обновлена!"
    echo -e "${YELLOW}Примечание: База данных не была перезапущена.${NC}"
}

# Get webBasePath from database
get_webpath_from_db() {
    local db_host=""
    local db_port="5432"
    local db_user="xui_user"
    local db_password=""
    local db_name="xui_db"
    local webpath=""
    
    # Try to get database credentials from container environment
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^sharx_app$"; then
        local env_vars=$(docker inspect sharx_app --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null)
        if [[ -n "$env_vars" ]]; then
            db_host=$(echo "$env_vars" | grep "^XUI_DB_HOST=" | cut -d'=' -f2 | tr -d '\r\n')
            db_port=$(echo "$env_vars" | grep "^XUI_DB_PORT=" | cut -d'=' -f2 | tr -d '\r\n')
            db_user=$(echo "$env_vars" | grep "^XUI_DB_USER=" | cut -d'=' -f2 | tr -d '\r\n')
            db_password=$(echo "$env_vars" | grep "^XUI_DB_PASSWORD=" | cut -d'=' -f2 | tr -d '\r\n')
            db_name=$(echo "$env_vars" | grep "^XUI_DB_NAME=" | cut -d'=' -f2 | tr -d '\r\n')
        fi
    fi
    
    # Fallback to config file
    if [[ -z "$db_password" ]] && load_config 2>/dev/null; then
        db_password="$DB_PASSWORD"
        # Determine DB host based on network mode
        if [[ "$NETWORK_MODE" == "host" ]]; then
            db_host="127.0.0.1"
        else
            db_host="postgres"
        fi
    fi
    
    # If still no password, return empty
    if [[ -z "$db_password" ]]; then
        echo ""
        return 1
    fi
    
    # Set default values if not set
    db_host="${db_host:-127.0.0.1}"
    db_port="${db_port:-5432}"
    db_user="${db_user:-xui_user}"
    db_name="${db_name:-xui_db}"
    
    # Try to get webBasePath from database
    # First try via docker exec to postgres container
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^sharx_postgres$"; then
        # Use docker exec to connect to postgres container
        webpath=$(docker exec sharx_postgres psql -h 127.0.0.1 -p 5432 -U "$db_user" -d "$db_name" -t -c "SELECT value FROM settings WHERE key = 'webBasePath';" 2>/dev/null | tr -d ' \r\n')
    elif command -v psql &>/dev/null && [[ "$db_host" == "127.0.0.1" ]] || [[ "$db_host" == "localhost" ]]; then
        # Try direct psql connection (for host network mode)
        export PGPASSWORD="$db_password"
        webpath=$(psql -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_name" -t -c "SELECT value FROM settings WHERE key = 'webBasePath';" 2>/dev/null | tr -d ' \r\n')
        unset PGPASSWORD
    fi
    
    # Return webBasePath or empty string
    if [[ -n "$webpath" ]]; then
        echo "$webpath"
        return 0
    else
        echo ""
        return 1
    fi
}

# Update SSL settings in database
update_ssl_settings_in_db() {
    local cert_file="$1"
    local key_file="$2"
    local db_user="xui_user"
    local db_name="xui_db"
    
    # Check if postgres container is running
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^sharx_postgres$"; then
        # SSL settings will be passed via environment variables in docker-compose
        print_info "SSL settings will be applied via environment variables on panel start."
        return 0
    fi
    
    # Check if settings table exists and has data (panel needs to run first to create schema)
    local table_exists=$(docker exec sharx_postgres psql -h 127.0.0.1 -p 5432 -U "$db_user" -d "$db_name" -t -c \
        "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'settings');" 2>/dev/null | tr -d ' \r\n')
    
    if [[ "$table_exists" != "t" ]]; then
        # Settings table doesn't exist yet - panel hasn't started
        # SSL settings will be applied via environment variables
        print_info "SSL settings will be applied via environment variables on first panel start."
        return 0
    fi
    
    # Check if there are any settings records
    local settings_count=$(docker exec sharx_postgres psql -h 127.0.0.1 -p 5432 -U "$db_user" -d "$db_name" -t -c \
        "SELECT COUNT(*) FROM settings WHERE key IN ('webCertFile', 'webKeyFile');" 2>/dev/null | tr -d ' \r\n')
    
    if [[ "$settings_count" == "0" ]] || [[ -z "$settings_count" ]]; then
        # No settings yet - panel needs to start first to create default settings
        print_info "SSL settings will be applied via environment variables on first panel start."
        return 0
    fi
    
    # Escape values for SQL
    local cert_file_escaped=$(escape_sql "$cert_file")
    local key_file_escaped=$(escape_sql "$key_file")
    
    print_info "Updating SSL settings in database..."
    
    # Update webCertFile
    docker exec sharx_postgres psql -h 127.0.0.1 -p 5432 -U "$db_user" -d "$db_name" -c \
        "UPDATE settings SET value = '$cert_file_escaped' WHERE key = 'webCertFile';" 2>/dev/null
    
    # Update webKeyFile
    docker exec sharx_postgres psql -h 127.0.0.1 -p 5432 -U "$db_user" -d "$db_name" -c \
        "UPDATE settings SET value = '$key_file_escaped' WHERE key = 'webKeyFile';" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_success "SSL settings updated in database!"
        return 0
    else
        print_warning "Failed to update SSL settings in database. SSL will be applied via environment variables."
        return 0
    fi
}

# Check for existing Let's Encrypt certificates
check_existing_certificates() {
    local domain_or_ip="$1"
    local cert_dir="$2"
    
    # Standard acme.sh certificate locations
    local acme_cert_path=""
    local found_cert=false
    
    # Check in acme.sh folder for domain certificate
    if [[ -d "/root/.acme.sh/${domain_or_ip}_ecc" ]]; then
        acme_cert_path="/root/.acme.sh/${domain_or_ip}_ecc"
        if [[ -f "${acme_cert_path}/fullchain.cer" && -f "${acme_cert_path}/${domain_or_ip}.key" ]]; then
            found_cert=true
            print_info "Найден существующий ECC сертификат для ${domain_or_ip}"
        fi
    elif [[ -d "${HOME}/.acme.sh/${domain_or_ip}_ecc" ]]; then
        acme_cert_path="${HOME}/.acme.sh/${domain_or_ip}_ecc"
        if [[ -f "${acme_cert_path}/fullchain.cer" && -f "${acme_cert_path}/${domain_or_ip}.key" ]]; then
            found_cert=true
            print_info "Найден существующий ECC сертификат для ${domain_or_ip}"
        fi
    elif [[ -d "/root/.acme.sh/${domain_or_ip}" ]]; then
        acme_cert_path="/root/.acme.sh/${domain_or_ip}"
        if [[ -f "${acme_cert_path}/fullchain.cer" && -f "${acme_cert_path}/${domain_or_ip}.key" ]]; then
            found_cert=true
            print_info "Найден существующий RSA сертификат для ${domain_or_ip}"
        fi
    elif [[ -d "${HOME}/.acme.sh/${domain_or_ip}" ]]; then
        acme_cert_path="${HOME}/.acme.sh/${domain_or_ip}"
        if [[ -f "${acme_cert_path}/fullchain.cer" && -f "${acme_cert_path}/${domain_or_ip}.key" ]]; then
            found_cert=true
            print_info "Найден существующий RSA сертификат для ${domain_or_ip}"
        fi
    fi
    
    # Check in our local cert folder
    if [[ -f "${cert_dir}/fullchain.pem" && -f "${cert_dir}/privkey.pem" ]]; then
        # Verify certificate is valid (not expired)
        if command -v openssl &>/dev/null; then
            local expiry=$(openssl x509 -in "${cert_dir}/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
            if [[ -n "$expiry" ]]; then
                local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry" +%s 2>/dev/null)
                local now_epoch=$(date +%s)
                if [[ -n "$expiry_epoch" && "$expiry_epoch" -gt "$now_epoch" ]]; then
                    found_cert=true
                    print_info "Найден действительный сертификат в ${cert_dir} (истекает: $expiry)"
                else
                    print_warning "Сертификат to ${cert_dir} has expired"
                    found_cert=false
                fi
            fi
        else
            # Can't verify, assume it's valid
            found_cert=true
            print_info "Найден существующий сертификат в ${cert_dir}"
        fi
    fi
    
    # If found in acme.sh but not in local cert dir, copy it
    if [[ "$found_cert" == "true" && -n "$acme_cert_path" && ! -f "${cert_dir}/fullchain.pem" ]]; then
        print_info "Copying certificate from acme.sh to ${cert_dir}..."
        mkdir -p "$cert_dir"
        if [[ -f "${acme_cert_path}/fullchain.cer" ]]; then
            cp "${acme_cert_path}/fullchain.cer" "${cert_dir}/fullchain.pem"
        fi
        if [[ -f "${acme_cert_path}/${domain_or_ip}.key" ]]; then
            cp "${acme_cert_path}/${domain_or_ip}.key" "${cert_dir}/privkey.pem"
        fi
        chmod 600 "${cert_dir}/privkey.pem" 2>/dev/null
        chmod 644 "${cert_dir}/fullchain.pem" 2>/dev/null
        fix_cert_dir_ownership "$cert_dir"
    fi
    
    if [[ "$found_cert" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Get panel status for menu display
get_panel_status() {
    local panel_status=""
    local panel_port=""
    local panel_address=""
    local web_path=""
    local is_running=false
    
    # Check if container exists
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^sharx_app$"; then
        # Get actual container state
        local container_state=$(docker inspect --format='{{.State.Status}}' sharx_app 2>/dev/null)
        local container_restarting=$(docker inspect --format='{{.State.Restarting}}' sharx_app 2>/dev/null)
        local container_exit_code=$(docker inspect --format='{{.State.ExitCode}}' sharx_app 2>/dev/null)
        
        # Determine status based on actual state
        case "$container_state" in
            running)
                if [[ "$container_restarting" == "true" ]]; then
                    panel_status="${YELLOW}● Перезапускается${NC}"
                    is_running=false
                else
                    panel_status="${GREEN}● Запущена${NC}"
                    is_running=true
                fi
                ;;
            restarting)
                panel_status="${YELLOW}● Перезапускается${NC}"
                is_running=false
                ;;
            exited|stopped)
                if [[ "$container_exit_code" != "0" ]]; then
                    panel_status="${RED}● Ошибка (Код выхода: $container_exit_code)${NC}"
                else
                    panel_status="${RED}● Остановлена${NC}"
                fi
                is_running=false
                ;;
            *)
                panel_status="${RED}● $container_state${NC}"
                is_running=false
                ;;
        esac
        
        # Try to get environment variables from container (only if container is actually running)
        local env_vars=""
        if [[ "$is_running" == "true" ]] && docker inspect sharx_app &>/dev/null; then
            env_vars=$(docker inspect sharx_app --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null)
        fi
        
        # Extract port from environment or config
        local env_port=""
        if [[ -n "$env_vars" ]]; then
            env_port=$(echo "$env_vars" | grep "^XUI_WEB_PORT=" | cut -d'=' -f2 | tr -d '\r\n')
        fi
        
        # Extract domain from environment
        local env_domain=""
        if [[ -n "$env_vars" ]]; then
            env_domain=$(echo "$env_vars" | grep "^XUI_WEB_DOMAIN=" | cut -d'=' -f2 | tr -d '\r\n')
        fi
        
        # Check if SSL certificates are configured
        local has_cert=false
        if [[ -n "$env_vars" ]] && echo "$env_vars" | grep -q "^XUI_WEB_CERT_FILE="; then
            has_cert=true
        fi
        
        # Get webBasePath from database (only if running)
        if [[ "$is_running" == "true" ]]; then
            web_path=$(get_webpath_from_db)
        fi
        
        # Get port from environment, config, or default
        if [[ -n "$env_port" ]]; then
            panel_port="$env_port"
        elif load_config 2>/dev/null; then
            panel_port="$PANEL_PORT"
        else
            panel_port="2053"
        fi
        
        # Determine address and protocol
        local server_ip=$(get_server_ip)
        local protocol="http"
        
        if [[ "$has_cert" == "true" ]]; then
            protocol="https"
            if [[ -n "$env_domain" ]]; then
                panel_address="${protocol}://${env_domain}:${panel_port}"
            elif load_config 2>/dev/null && [[ "$CERT_TYPE" == "letsencrypt-domain" && -n "$DOMAIN_OR_IP" ]]; then
                panel_address="${protocol}://${DOMAIN_OR_IP}:${panel_port}"
            elif load_config 2>/dev/null && [[ "$CERT_TYPE" == "letsencrypt-ip" && -n "$DOMAIN_OR_IP" ]]; then
                panel_address="${protocol}://${DOMAIN_OR_IP}:${panel_port}"
            else
                panel_address="${protocol}://${server_ip}:${panel_port}"
            fi
        else
            if load_config 2>/dev/null && [[ -n "$DOMAIN_OR_IP" ]] && ! is_ipv4 "$DOMAIN_OR_IP" && ! is_ipv6 "$DOMAIN_OR_IP"; then
                panel_address="${protocol}://${DOMAIN_OR_IP}:${panel_port}"
            else
                panel_address="${protocol}://${server_ip}:${panel_port}"
            fi
        fi
        
        # Append WebPath to address if available
        if [[ -n "$web_path" ]] && [[ "$web_path" != "/" ]]; then
            # Remove leading slash if present and add to address
            local web_path_clean="${web_path#/}"
            panel_address="${panel_address}/${web_path_clean}"
        fi
    else
        # Container doesn't exist
        panel_status="${RED}● Не установлена${NC}"
        is_running=false
        # Try to get port from config
        if load_config 2>/dev/null; then
            panel_port="$PANEL_PORT"
            local server_ip=$(get_server_ip)
            panel_address="http://${server_ip}:${panel_port}"
        else
            panel_port="N/A"
            panel_address="N/A"
        fi
    fi
    
    echo "$panel_status|$panel_port|$panel_address|$web_path"
}

# Get database status for menu display
get_db_status() {
    local db_status=""
    local db_port="5432"
    local db_size=""
    
    # Check if container exists
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^sharx_postgres$"; then
        # Get actual container state
        local container_state=$(docker inspect --format='{{.State.Status}}' sharx_postgres 2>/dev/null)
        local container_restarting=$(docker inspect --format='{{.State.Restarting}}' sharx_postgres 2>/dev/null)
        local container_exit_code=$(docker inspect --format='{{.State.ExitCode}}' sharx_postgres 2>/dev/null)
        
        # Determine status based on actual state
        case "$container_state" in
            running)
                if [[ "$container_restarting" == "true" ]]; then
                    db_status="${YELLOW}● Перезапускается${NC}"
                else
                    db_status="${GREEN}● Запущена${NC}"
                    # Try to get database size if running
                    if docker exec sharx_postgres psql -h 127.0.0.1 -p 5432 -U xui_user -d xui_db -t -c "SELECT pg_size_pretty(pg_database_size('xui_db'));" 2>/dev/null | grep -q .; then
                        db_size=$(docker exec sharx_postgres psql -h 127.0.0.1 -p 5432 -U xui_user -d xui_db -t -c "SELECT pg_size_pretty(pg_database_size('xui_db'));" 2>/dev/null | tr -d ' \r\n')
                    fi
                fi
                ;;
            restarting)
                db_status="${YELLOW}● Перезапускается${NC}"
                ;;
            exited|stopped)
                if [[ "$container_exit_code" != "0" ]]; then
                    db_status="${RED}● Ошибка (Код выхода: $container_exit_code)${NC}"
                else
                    db_status="${RED}● Остановлена${NC}"
                fi
                ;;
            *)
                db_status="${RED}● $container_state${NC}"
                ;;
        esac
    else
        # Container doesn't exist
        db_status="${RED}● Не установлена${NC}"
    fi
    
    echo "$db_status|$db_port|$db_size"
}

# Database management functions
start_db() {
    if ! load_config; then
        print_error "Конфигурация не найдена. Пожалуйста, сначала выполните установку."
        return 1
    fi
    
    cd "$INSTALL_DIR"
    print_info "Запуск базы данных..."
    docker compose up -d postgres
    
    sleep 3
    if docker compose ps | grep -q "sharx_postgres.*Up"; then
        print_success "База данных успешно запущена!"
    else
        print_warning "База данных может еще запускаться. Проверьте: docker compose ps"
    fi
}

stop_db() {
    if ! load_config; then
        print_error "Конфигурация не найдена. Пожалуйста, сначала выполните установку."
        return 1
    fi
    
    cd "$INSTALL_DIR"
    print_info "Остановка базы данных..."
    docker compose stop postgres
    print_success "База данных остановлена!"
}

restart_db() {
    if ! load_config; then
        print_error "Конфигурация не найдена. Пожалуйста, сначала выполните установку."
        return 1
    fi
    
    cd "$INSTALL_DIR"
    print_info "Перезапуск базы данных..."
    docker compose restart postgres
    print_success "База данных перезапущена!"
}

backup_db() {
    if ! load_config; then
        print_error "Конфигурация не найдена. Пожалуйста, сначала выполните установку."
        return 1
    fi
    
    cd "$INSTALL_DIR"
    
    # Check if database is running
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^sharx_postgres$"; then
        print_error "База данных не запущена. Пожалуйста, сначала запустите её."
        return 1
    fi
    
    local backup_file="backup_$(date +%Y%m%d_%H%M%S).sql"
    local backup_path="$INSTALL_DIR/$backup_file"
    
    print_info "Создание резервной копии базы данных..."
    if docker compose exec -T postgres pg_dump -U xui_user xui_db > "$backup_path" 2>/dev/null; then
        local backup_size=$(du -h "$backup_path" | cut -f1)
        print_success "Резервная копия успешно создана!"
        echo -e "  Файл: ${CYAN}$backup_file${NC}"
        echo -e "  Размер: ${CYAN}$backup_size${NC}"
        echo -e "  Путь: ${CYAN}$backup_path${NC}"
    else
        print_error "Не удалось создать резервную копию!"
        return 1
    fi
}

restore_db() {
    if ! load_config; then
        print_error "Конфигурация не найдена. Пожалуйста, сначала выполните установку."
        return 1
    fi
    
    cd "$INSTALL_DIR"
    
    # Find backup files
    local backup_files=()
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            backup_files+=("$file")
        fi
    done < <(find "$INSTALL_DIR" -maxdepth 1 -name "backup_*.sql" -type f 2>/dev/null | sort -r)
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        print_error "Резервные копии не найдены в $INSTALL_DIR"
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}Доступные резервные копии:${NC}"
    for i in "${!backup_files[@]}"; do
        local file_name=$(basename "${backup_files[$i]}")
        local file_size=$(du -h "${backup_files[$i]}" | cut -f1)
        echo -e "  $((i+1))) ${CYAN}$file_name${NC} (${file_size})"
    done
    echo ""
    
    read -p "Выберите резервную копию для восстановления [1-${#backup_files[@]}]: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#backup_files[@]} ]]; then
        print_error "Неверный выбор!"
        return 1
    fi
    
    local selected_backup="${backup_files[$((choice-1))]}"
    
    echo ""
    echo -e "${YELLOW}⚠️  ПРЕДУПРЕЖДЕНИЕ: Это заменит все текущие данные базы данных!${NC}"
    read -p "Вы уверены, что хотите восстановить из $(basename "$selected_backup")? [y/N]: " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "Восстановление отменено."
        return 0
    fi
    
    # Check if database is running
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^sharx_postgres$"; then
        print_info "Запуск базы данных..."
        docker compose up -d postgres
        sleep 3
    fi
    
    print_info "Восстановление базы данных из резервной копии..."
    if docker compose exec -T postgres psql -U xui_user -d xui_db < "$selected_backup" 2>/dev/null; then
        print_success "База данных успешно восстановлена!"
        echo -e "${YELLOW}Возможно, потребуется перезапустить панель для применения изменений.${NC}"
    else
        print_error "Не удалось восстановить базу данных!"
        return 1
    fi
}

# Show instructions
show_instructions() {
    if ! load_config; then
        print_error "Конфигурация не найдена. Пожалуйста, сначала выполните установку."
        return 1
    fi
    
    print_banner
    echo ""
    echo -e "${WHITE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                        ИНСТРУКЦИИ                             ║${NC}"
    echo -e "${WHITE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Get current panel address
    local status_info=$(get_panel_status)
    local panel_address=$(echo "$status_info" | cut -d'|' -f3)
    local panel_port=$(echo "$status_info" | cut -d'|' -f2)
    
    # Get subscription port
    local sub_port_env=""
    if [[ -f "$INSTALL_DIR/$COMPOSE_FILE" ]]; then
        sub_port_env=$(read_env_from_compose "XUI_SUB_PORT" 2>/dev/null || echo "")
    fi
    local actual_sub_port=${sub_port_env:-$SUB_PORT}
    
    # Get subscription address
    local sub_address=""
    local sub_protocol="http"
    if [[ "$CERT_TYPE" != "none" ]]; then
        sub_protocol="https"
        local sub_domain_env=""
        if [[ -f "$INSTALL_DIR/$COMPOSE_FILE" ]]; then
            sub_domain_env=$(read_env_from_compose "XUI_SUB_DOMAIN" 2>/dev/null || echo "")
        fi
        if [[ -n "$sub_domain_env" ]]; then
            sub_address="${sub_protocol}://${sub_domain_env}:${actual_sub_port}"
        elif [[ "$CERT_TYPE" == "letsencrypt-domain" && -n "$DOMAIN_OR_IP" ]]; then
            sub_address="${sub_protocol}://${DOMAIN_OR_IP}:${actual_sub_port}"
        else
            local server_ip=$(get_server_ip)
            sub_address="${sub_protocol}://${server_ip}:${actual_sub_port}"
        fi
    else
        local server_ip=$(get_server_ip)
        sub_address="${sub_protocol}://${server_ip}:${actual_sub_port}"
    fi
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}Доступ к панели:${NC}"
    if [[ -n "$panel_address" ]] && [[ "$panel_address" != "N/A" ]]; then
        echo -e "  ${GREEN}${panel_address}${NC}"
    else
        local server_ip=$(get_server_ip)
        echo -e "  ${GREEN}http://${server_ip}:${panel_port}${NC}"
    fi
    echo ""
    echo -e "${WHITE}Сервис подписки:${NC}"
    echo -e "  ${GREEN}${sub_address}${NC}"
    echo ""
    echo -e "${WHITE}Учетные данные для входа:${NC}"
    echo -e "  Имя пользователя:  ${CYAN}admin${NC}"
    echo -e "  Пароль:            ${CYAN}admin${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  ВАЖНО: Пожалуйста, измените пароль после первого входа!${NC}"
    echo ""
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}Быстрый старт:${NC}"
    echo -e "  1. ${CYAN}Откройте панель${NC} используя адрес выше"
    echo -e "  2. ${CYAN}Войдите${NC} с учетными данными по умолчанию (admin/admin)"
    echo -e "  3. ${CYAN}Измените пароль${NC} немедленно в Настройки → Аккаунт"
    echo -e "  4. ${CYAN}Добавьте входящее подключение${NC} в разделе Входящие для начала использования сервиса"
    echo -e "  5. ${CYAN}Создайте пользователей${NC} и поделитесь ссылками на подписки"
    echo -e "  6. ${CYAN}Удалённые узлы${NC} (опционально): добавляйте и ведите в веб-панели (Ноды / География)."
    echo -e "     Образ воркера-узла на отдельном сервере: см. node/README.md в исходниках SharX."
    echo ""
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}Настройка файрвола:${NC}"
    echo -e "  Убедитесь, что эти порты открыты в вашем файрволе:"
    echo -e "    - ${CYAN}${panel_port}${NC} (Веб-интерфейс панели)"
    echo -e "    - ${CYAN}${actual_sub_port}${NC} (Сервис подписки)"
    if [[ "$CERT_TYPE" != "none" ]]; then
        echo -e "    - ${CYAN}80${NC} (HTTP, для обновления Let's Encrypt)"
    fi
    echo -e "    - ${CYAN}443${NC} (HTTPS, если планируете использовать для входящих подключений)"
    echo ""
    echo -e "  ${YELLOW}Пример команд UFW:${NC}"
    echo -e "    ${CYAN}ufw allow ${panel_port}/tcp${NC}"
    echo -e "    ${CYAN}ufw allow ${actual_sub_port}/tcp${NC}"
    if [[ "$CERT_TYPE" != "none" ]]; then
        echo -e "    ${CYAN}ufw allow 80/tcp${NC}"
    fi
    echo -e "    ${CYAN}ufw allow 443/tcp${NC}"
    echo ""
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}Резервное копирование и восстановление:${NC}"
    echo -e "  ${CYAN}Расположение базы данных:${NC} ${GREEN}\$PWD/postgres_data${NC}"
    echo ""
    echo -e "  ${CYAN}Создать резервную копию:${NC}"
    echo -e "    ${CYAN}cd $INSTALL_DIR${NC}"
    echo -e "    ${CYAN}docker compose exec postgres pg_dump -U xui_user xui_db > backup_\$(date +%Y%m%d_%H%M%S).sql${NC}"
    echo ""
    echo -e "  ${CYAN}Восстановить из резервной копии:${NC}"
    echo -e "    ${CYAN}docker compose exec -T postgres psql -U xui_user -d xui_db < backup.sql${NC}"
    echo ""
    echo -e "  ${CYAN}Восстановить пароль базы данных:${NC}"
    echo -e "    Пароль сохранен в: ${CYAN}$INSTALL_DIR/.3xui-config${NC}"
    echo -e "    Или проверьте docker-compose.yml: ${CYAN}XUI_DB_PASSWORD${NC}"
    echo ""
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}Мониторинг и логирование:${NC}"
    echo -e "  ${CYAN}Просмотр логов панели:${NC}"
    echo -e "    ${CYAN}docker compose logs -f sharx${NC}"
    echo ""
    echo -e "  ${CYAN}Просмотр логов базы данных:${NC}"
    echo -e "    ${CYAN}docker compose logs -f postgres${NC}"
    echo ""
    echo -e "  ${CYAN}Просмотр всех логов:${NC}"
    echo -e "    ${CYAN}docker compose logs -f${NC}"
    echo ""
    echo -e "  ${CYAN}Проверить статус сервисов:${NC}"
    echo -e "    ${CYAN}docker compose ps${NC}"
    echo ""
    echo -e "  ${CYAN}Проверить использование ресурсов:${NC}"
    echo -e "    ${CYAN}docker stats${NC}"
    echo ""
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}Расширенная настройка:${NC}"
    if [[ "$CERT_TYPE" != "none" ]]; then
        echo -e "  ${CYAN}Отдельный домен для подписки:${NC}"
        echo -e "    Отредактируйте ${CYAN}docker-compose.yml${NC} и установите:"
        echo -e "      ${CYAN}XUI_SUB_DOMAIN: sub.example.com${NC}"
        echo -e "      ${CYAN}XUI_SUB_CERT_FILE: /app/cert/sub-fullchain.pem${NC}"
        echo -e "      ${CYAN}XUI_SUB_KEY_FILE: /app/cert/sub-privkey.pem${NC}"
        echo -e "    Затем перезапустите: ${CYAN}docker compose restart sharx${NC}"
        echo ""
    fi
    echo -e "  ${CYAN}Изменить домен/порт панели:${NC}"
    echo -e "    Отредактируйте ${CYAN}docker-compose.yml${NC} переменные окружения:"
    echo -e "      ${CYAN}XUI_WEB_DOMAIN${NC}, ${CYAN}XUI_WEB_PORT${NC}, ${CYAN}XUI_WEB_LISTEN${NC}"
    echo -e "    Затем перезапустите: ${CYAN}docker compose restart sharx${NC}"
    echo ""
    echo -e "  ${CYAN}Изменить порт/путь подписки:${NC}"
    echo -e "    Отредактируйте ${CYAN}docker-compose.yml${NC} переменные окружения:"
    echo -e "      ${CYAN}XUI_SUB_PORT${NC}, ${CYAN}XUI_SUB_PATH${NC}, ${CYAN}XUI_SUB_DOMAIN${NC}"
    echo -e "    Затем перезапустите: ${CYAN}docker compose restart sharx${NC}"
    echo ""
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}Управление:${NC}"
    echo -e "  ${CYAN}./install_ru.sh${NC} - открыть меню управления"
    echo ""
    echo -e "  ${CYAN}Общие команды:${NC}"
    echo -e "    ${CYAN}docker compose restart sharx${NC} - перезапустить панель"
    echo -e "    ${CYAN}docker compose restart postgres${NC} - перезапустить базу данных"
    echo -e "    ${CYAN}docker compose down${NC} - остановить все сервисы"
    echo -e "    ${CYAN}docker compose up -d${NC} - запустить все сервисы"
    echo ""
}

# Show service status
show_status() {
    print_info "SharX Статус сервисов:"
    echo ""
    cd "$INSTALL_DIR"
    docker compose ps
    echo ""
    
    if load_config; then
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${WHITE}Конфигурация:${NC}"
        echo -e "  Порт панели:   ${GREEN}$PANEL_PORT${NC}"
        echo -e "  Порт подписки: ${GREEN}$SUB_PORT${NC}"
        echo -e "  Режим сети:    ${GREEN}$NETWORK_MODE${NC}"
        echo -e "  Сертификат:   ${GREEN}$CERT_TYPE${NC}"
        echo -e "  Домен/IP:     ${GREEN}$DOMAIN_OR_IP${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        local server_ip=$(get_server_ip)
        echo ""
        echo -e "${WHITE}Доступ к панели:${NC}"
        if [[ "$CERT_TYPE" == "letsencrypt-domain" ]]; then
            echo -e "  ${GREEN}https://$DOMAIN_OR_IP:$PANEL_PORT${NC}"
        elif [[ "$CERT_TYPE" == "letsencrypt-ip" ]]; then
            echo -e "  ${GREEN}https://$DOMAIN_OR_IP:$PANEL_PORT${NC}"
            echo -e "  ${YELLOW}(IP сертификат действителен ~6 дней, автопродление)${NC}"
        else
            echo -e "  ${GREEN}http://$server_ip:$PANEL_PORT${NC}"
            echo -e "  ${YELLOW}(SSL не настроен)${NC}"
        fi
        
        if [[ "$CERT_TYPE" != "none" ]]; then
            echo ""
            echo -e "${WHITE}SSL paths for panel settings:${NC}"
            echo -e "  Certificate:  ${CYAN}/app/cert/fullchain.pem${NC}"
            echo -e "  Private Key:  ${CYAN}/app/cert/privkey.pem${NC}"
        fi
    fi
}

# Show logs
show_logs() {
    cd "$INSTALL_DIR"
    echo -e "${CYAN}Select container:${NC}"
    echo "1) SharX Panel"
    echo "2) PostgreSQL"
    echo "3) All"
    echo ""
    read -p "Choice [1-3]: " log_choice
    
    case $log_choice in
        1) docker compose logs -f sharx ;;
        2) docker compose logs -f postgres ;;
        3) docker compose logs -f ;;
        *) docker compose logs -f ;;
    esac
}

# Change panel port
change_panel_port() {
    if ! load_config; then
        print_error "Конфигурация не найдена. Пожалуйста, сначала выполните установку."
        return 1
    fi
    
    local new_port=$(prompt_port "$PANEL_PORT" "Panel")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    print_info "Изменение порта панели на $new_port..."
    
    PANEL_PORT=$new_port
    
    # Recreate compose file
    if [[ "$NETWORK_MODE" == "host" ]]; then
        create_compose_host "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD"
    else
        # Load additional ports if they exist
        if [[ -n "${ADDITIONAL_PORTS[@]}" ]]; then
            create_compose_bridge "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "${ADDITIONAL_PORTS[@]}"
        else
            create_compose_bridge "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD"
        fi
    fi
    
    # Save config
    if [[ -n "${ADDITIONAL_PORTS[@]}" ]]; then
        save_config "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "$NETWORK_MODE" "$CERT_TYPE" "$DOMAIN_OR_IP" "${ADDITIONAL_PORTS[@]}"
    else
        save_config "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "$NETWORK_MODE" "$CERT_TYPE" "$DOMAIN_OR_IP"
    fi
    
    print_info "Перезапуск сервисов..."
    cd "$INSTALL_DIR"
    docker compose down
    docker compose up -d
    
    print_success "Порт панели изменен на $new_port!"
}

# Change subscription port
change_sub_port() {
    if ! load_config; then
        print_error "Конфигурация не найдена. Пожалуйста, сначала выполните установку."
        return 1
    fi
    
    local new_port=$(prompt_port "$SUB_PORT" "Subscription")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    print_info "Изменение порта подписки на $new_port..."
    
    SUB_PORT=$new_port
    
    # Recreate compose file
    if [[ "$NETWORK_MODE" == "host" ]]; then
        create_compose_host "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD"
    else
        # Load additional ports if they exist
        if [[ -n "${ADDITIONAL_PORTS[@]}" ]]; then
            create_compose_bridge "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "${ADDITIONAL_PORTS[@]}"
        else
            create_compose_bridge "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD"
        fi
    fi
    
    # Save config
    if [[ -n "${ADDITIONAL_PORTS[@]}" ]]; then
        save_config "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "$NETWORK_MODE" "$CERT_TYPE" "$DOMAIN_OR_IP" "${ADDITIONAL_PORTS[@]}"
    else
        save_config "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "$NETWORK_MODE" "$CERT_TYPE" "$DOMAIN_OR_IP"
    fi
    
    print_info "Перезапуск сервисов..."
    cd "$INSTALL_DIR"
    docker compose down
    docker compose up -d
    
    print_success "Порт подписки изменен на $new_port!"
}

# Change database password
change_db_password() {
    if ! load_config; then
        print_error "Конфигурация не найдена. Пожалуйста, сначала выполните установку."
        return 1
    fi
    
    echo -e "${YELLOW}ПРЕДУПРЕЖДЕНИЕ: Изменение пароля базы данных требует миграции данных!${NC}"
    read -p "Сгенерировать новый пароль? [y/N]: " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        return 0
    fi
    
    local new_password=$(generate_password 24)
    
    print_info "Новый пароль: $new_password"
    print_warning "Сохраните этот пароль! Он понадобится для восстановления."
    
    read -p "Продолжить с этим паролем? [y/N]: " confirm2
    
    if [[ "$confirm2" != "y" && "$confirm2" != "Y" ]]; then
        return 0
    fi
    
    print_info "Изменение пароля базы данных..."
    
    # Update compose file
    sed -i "s/XUI_DB_PASSWORD: .*/XUI_DB_PASSWORD: $new_password/" "$INSTALL_DIR/$COMPOSE_FILE"
    sed -i "s/POSTGRES_PASSWORD: .*/POSTGRES_PASSWORD: $new_password/" "$INSTALL_DIR/$COMPOSE_FILE"
    
    # Stop services and remove volume (only this project's volume)
    cd "$INSTALL_DIR"
    docker compose down -v
    
    DB_PASSWORD=$new_password
    save_config "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "$NETWORK_MODE" "$CERT_TYPE" "$DOMAIN_OR_IP"
    
    # Start services
    docker compose up -d
    
    print_success "Database password changed!"
    echo -e "${RED}WARNING: All previous data has been reset!${NC}"
}

# Renew certificate
renew_certificate() {
    if ! load_config; then
        print_error "Конфигурация не найдена. Пожалуйста, сначала выполните установку."
        return 1
    fi
    
    local cert_dir="$INSTALL_DIR/cert"
    
    # Check if acme.sh is installed
    if ! acme_sh_ready; then
        print_error "acme.sh is not installed. Cannot renew certificate."
        return 1
    fi
    
    local acme
    acme="$(acme_sh_bin)"
    local ecc_arg
    ecc_arg="$(acme_ecc_arg "$DOMAIN_OR_IP")"
    
    print_info "Renewing certificate via acme.sh..."
    
    if [[ "$CERT_TYPE" == "letsencrypt-domain" ]]; then
        # Renew domain certificate
        print_info "Renewing Let's Encrypt certificate for домен: $DOMAIN_OR_IP"
        
        # Stop containers to free port 80
        cd "$INSTALL_DIR"
        docker compose down 2>/dev/null || true
        
        "${acme}" --renew -d "$DOMAIN_OR_IP" --force ${ecc_arg}
        
        if [ $? -eq 0 ]; then
            # Copy renewed certificates
            local acmeCertPath="/root/cert/${DOMAIN_OR_IP}"
            if [[ ! -f "${acmeCertPath}/fullchain.pem" || ! -f "${acmeCertPath}/privkey.pem" ]]; then
                acme_copy_from_store_to_pem_paths "${DOMAIN_OR_IP}" "${acmeCertPath}/fullchain.pem" "${acmeCertPath}/privkey.pem" || true
            fi
            if [[ -f "${acmeCertPath}/fullchain.pem" && -f "${acmeCertPath}/privkey.pem" ]]; then
                cp "${acmeCertPath}/fullchain.pem" "${cert_dir}/"
                cp "${acmeCertPath}/privkey.pem" "${cert_dir}/"
                chmod 600 "${cert_dir}/privkey.pem"
                chmod 644 "${cert_dir}/fullchain.pem"
                fix_cert_dir_ownership "$cert_dir"
                print_success "Domain certificate renewed successfully!"
            fi
        else
            print_error "Failed to renew domain certificate"
        fi
        
    elif [[ "$CERT_TYPE" == "letsencrypt-ip" ]]; then
        # Renew IP certificate
        print_info "Renewing Let's Encrypt certificate for IP: $DOMAIN_OR_IP"
        
        # Stop containers to free port 80
        cd "$INSTALL_DIR"
        docker compose down 2>/dev/null || true
        
        "${acme}" --renew -d "$DOMAIN_OR_IP" --force ${ecc_arg}
        
        if [ $? -eq 0 ]; then
            # Copy renewed certificates
            local acmeCertDir="/root/cert/ip"
            if [[ ! -f "${acmeCertDir}/fullchain.pem" || ! -f "${acmeCertDir}/privkey.pem" ]]; then
                acme_copy_from_store_to_pem_paths "${DOMAIN_OR_IP}" "${acmeCertDir}/fullchain.pem" "${acmeCertDir}/privkey.pem" || true
            fi
            if [[ -f "${acmeCertDir}/fullchain.pem" && -f "${acmeCertDir}/privkey.pem" ]]; then
                cp "${acmeCertDir}/fullchain.pem" "${cert_dir}/"
                cp "${acmeCertDir}/privkey.pem" "${cert_dir}/"
                chmod 600 "${cert_dir}/privkey.pem"
                chmod 644 "${cert_dir}/fullchain.pem"
                fix_cert_dir_ownership "$cert_dir"
                print_success "IP certificate renewed successfully!"
            fi
        else
            print_error "Failed to renew IP certificate"
        fi
        
    else
        print_warning "No valid certificate type found. Running new SSL setup..."
        local server_ip=$(get_server_ip)
        prompt_and_setup_ssl "$cert_dir" "$server_ip"
        
        # Update config with new cert type
        save_config "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "$NETWORK_MODE" "$CERT_TYPE" "$SSL_HOST"
        DOMAIN_OR_IP="$SSL_HOST"
    fi
    
    # Bring stack back and reload panel TLS
    cd "$INSTALL_DIR"
    docker compose up -d
    docker_compose_restart_sharx
    
    print_success "Certificate operation completed!"
}

# Setup new certificate (from menu)
setup_new_certificate() {
    if ! load_config; then
        print_error "Конфигурация не найдена. Пожалуйста, сначала выполните установку."
        return 1
    fi
    
    local cert_dir="$INSTALL_DIR/cert"
    local server_ip=$(get_server_ip)
    
    echo ""
    echo -e "${YELLOW}Current certificate type: ${CERT_TYPE}${NC}"
    echo -e "${YELLOW}Current domain/IP: ${DOMAIN_OR_IP}${NC}"
    echo ""
    
    # Run interactive SSL setup
    prompt_and_setup_ssl "$cert_dir" "$server_ip"
    
    # Update config with new cert type
    if [[ -n "${ADDITIONAL_PORTS[@]}" ]]; then
        save_config "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "$NETWORK_MODE" "$CERT_TYPE" "$SSL_HOST" "${ADDITIONAL_PORTS[@]}"
    else
        save_config "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "$NETWORK_MODE" "$CERT_TYPE" "$SSL_HOST"
    fi
    
    # Restart services
    cd "$INSTALL_DIR"
    docker compose up -d
    docker_compose_restart_sharx
    
    print_success "Certificate setup completed!"
    echo -e "New certificate type: ${GREEN}$CERT_TYPE${NC}"
    echo -e "Domain/IP: ${GREEN}$SSL_HOST${NC}"
}

# Uninstall
uninstall() {
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                  ПРЕДУПРЕЖДЕНИЕ: УДАЛЕНИЕ                     ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Это приведет к:"
    echo "  - Остановке и удалению всех контейнеров"
    echo "  - Удалению Docker volumes (ВСЕ ДАННЫЕ БУДУТ ПОТЕРЯНЫ)"
    echo "  - Удалению файлов конфигурации"
    echo ""
    read -p "Вы уверены, что хотите удалить? [y/N]: " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        return 0
    fi
    
    read -p "Введите 'DELETE' для подтверждения: " confirm2
    
    if [[ "$confirm2" != "DELETE" ]]; then
        print_info "Удаление отменено."
        return 0
    fi
    
    print_info "Удаление панели SharX..."
    
    # Stop and remove panel containers and volumes
    cd "$INSTALL_DIR" 2>/dev/null || true
    docker compose down -v 2>/dev/null || true
    
    # Remove panel config file
    rm -f "$INSTALL_DIR/.3xui-config" 2>/dev/null || true
    
    # Remove acme.sh certificates (optional)
    read -p "Удалить сертификаты acme.sh? [y/N]: " remove_acme
    if [[ "$remove_acme" == "y" || "$remove_acme" == "Y" ]]; then
        rm -rf /root/cert 2>/dev/null || true
        rm -rf /root/.acme.sh "${HOME}/.acme.sh" 2>/dev/null || true
        print_info "Сертификаты acme.sh удалены"
    fi
    
    # Remove local certificates (optional)
    read -p "Удалить локальные сертификаты из папок cert/? [y/N]: " remove_local_cert
    if [[ "$remove_local_cert" == "y" || "$remove_local_cert" == "Y" ]]; then
        rm -f "$INSTALL_DIR/cert/"*.pem 2>/dev/null || true
        print_info "Локальные сертификаты удалены"
    fi
    
    print_success "SharX успешно удален!"
    echo ""
    echo -e "${YELLOW}Примечание: Файлы скриптов и директории сохранены.${NC}"
    echo -e "${YELLOW}Вы можете переустановить в любое время, запустив: ./install_ru.sh${NC}"
}

# Reset panel to default settings (clear database)
reset_panel() {
    if ! load_config; then
        print_error "Конфигурация не найдена. Пожалуйста, сначала выполните установку."
        return 1
    fi
    
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║        ПРЕДУПРЕЖДЕНИЕ: СБРОС ПАНЕЛИ К НАСТРОЙКАМ ПО УМОЛЧАНИЮ ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Это приведет к:"
    echo "  - Остановке всех контейнеров"
    echo "  - Удалению Docker volumes (ВСЕ ДАННЫЕ БУДУТ ПОТЕРЯНЫ)"
    echo "  - Перезапуску сервисов с новой базой данных"
    echo ""
    read -p "Вы уверены? [y/N]: " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        return 0
    fi
    
    read -p "Введите 'RESET' для подтверждения: " confirm2
    
    if [[ "$confirm2" != "RESET" ]]; then
        print_info "Сброс отменен."
        return 0
    fi
    
    print_info "Сброс панели к настройкам по умолчанию..."
    
    cd "$INSTALL_DIR"
    
    # Stop and remove volumes
    docker compose down -v
    
    # Recreate compose file
    if [[ "$NETWORK_MODE" == "host" ]]; then
        create_compose_host "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD"
    else
        # Load additional ports if they exist
        if [[ -n "${ADDITIONAL_PORTS[@]}" ]]; then
            create_compose_bridge "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "${ADDITIONAL_PORTS[@]}"
        else
            create_compose_bridge "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD"
        fi
    fi
    
    # Start services
    docker compose up -d
    
    print_success "Панель сброшена к настройкам по умолчанию!"
    echo -e "${YELLOW}All data has been cleared. Please reconfigure the panel.${NC}"
}

# Add port to panel
add_panel_port() {
    if ! load_config; then
        print_error "Конфигурация не найдена. Пожалуйста, сначала выполните установку."
        return 1
    fi
    
    if [[ "$NETWORK_MODE" != "bridge" ]]; then
        print_error "Управление портами доступно только в режиме мостовой сети!"
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}Добавить порт к панели${NC}"
    
    local new_port=$(prompt_port "" "Panel")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Check if port already exists
    if [[ " ${ADDITIONAL_PORTS[@]} " =~ " ${new_port} " ]]; then
        print_error "Порт $new_port уже настроен!"
        return 1
    fi
    
    # Add port to array
    ADDITIONAL_PORTS+=("$new_port")
    
    # Recreate compose file
    create_compose_bridge "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "${ADDITIONAL_PORTS[@]}"
    
    # Save config
    save_config "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "$NETWORK_MODE" "$CERT_TYPE" "$DOMAIN_OR_IP" "${ADDITIONAL_PORTS[@]}"
    
    # Restart services
    cd "$INSTALL_DIR"
    docker compose down
    docker compose up -d
    
    print_success "Порт $new_port добавлен и панель перезапущена!"
}

# Remove port from panel
remove_panel_port() {
    if ! load_config; then
        print_error "Конфигурация не найдена. Пожалуйста, сначала выполните установку."
        return 1
    fi
    
    if [[ "$NETWORK_MODE" != "bridge" ]]; then
        print_error "Управление портами доступно только в режиме мостовой сети!"
        return 1
    fi
    
    if [[ ${#ADDITIONAL_PORTS[@]} -eq 0 ]]; then
        print_error "No additional ports configured!"
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}Remove port from panel${NC}"
    echo ""
    echo "Current additional ports:"
    for i in "${!ADDITIONAL_PORTS[@]}"; do
        echo "  $((i+1))) ${ADDITIONAL_PORTS[$i]}"
    done
    echo ""
    
    read -p "Введите номер порта для удаления: " port_to_remove
    
    # Find and remove port
    local new_ports=()
    local found=0
    for port in "${ADDITIONAL_PORTS[@]}"; do
        if [[ "$port" != "$port_to_remove" ]]; then
            new_ports+=("$port")
        else
            found=1
        fi
    done
    
    if [[ $found -eq 0 ]]; then
        print_error "Порт $port_to_remove не найден!"
        return 1
    fi
    
    ADDITIONAL_PORTS=("${new_ports[@]}")
    
    # Recreate compose file
    create_compose_bridge "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "${ADDITIONAL_PORTS[@]}"
    
    # Save config
    save_config "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "$NETWORK_MODE" "$CERT_TYPE" "$DOMAIN_OR_IP" "${ADDITIONAL_PORTS[@]}"
    
    # Restart services
    cd "$INSTALL_DIR"
    docker compose down
    docker compose up -d
    
    print_success "Порт $port_to_remove удален и панель перезапущена!"
}

# Full installation wizard
install_wizard() {
    print_banner
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}          SharX Мастер установки${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    check_root
    check_system
    
    # Step 1: Install Docker
    echo ""
    echo -e "${PURPLE}[Шаг 1/7]${NC} Установка Docker"
    install_docker
    install_docker_compose
    
#    # Step 2: Network mode
#    echo ""
#    echo -e "${PURPLE}[Шаг 2/7]${NC} Настройка сети"
#    echo -e "${CYAN}Выберите режим сети:${NC}"
#    echo "1) Сеть хоста (рекомендуется для опытных пользователей)"
#    echo "   - Прямой доступ ко всем портам"
#    echo "   - Лучшая производительность"
#    echo "   - Требует ручной настройки портов в панели"
#    echo ""
#    echo "2) Мостовая сеть с пробросом портов (рекомендуется)"
#    echo "   - Изолированные контейнеры"
#    echo "   - Удобное управление портами"
#    echo "   - Нужно вручную открывать входящие порты"
#    echo ""
#    read -p "Выберите [1-2, по умолчанию: 2]: " network_choice
#    network_choice=${network_choice:-2}
    
    local network_mode="host"
#    if [[ "$network_choice" == "1" ]]; then
#        network_mode="host"
#    fi
    
    # Step 2: Port configuration
    echo ""
    echo -e "${PURPLE}[Шаг 3/7]${NC} Настройка портов"
    read -p "Порт панели [$DEFAULT_PANEL_PORT]: " panel_port
    panel_port=${panel_port:-$DEFAULT_PANEL_PORT}
    
    read -p "Порт подписки [$DEFAULT_SUB_PORT]: " sub_port
    sub_port=${sub_port:-$DEFAULT_SUB_PORT}
    
    # Validate ports
    if ! [[ "$panel_port" =~ ^[0-9]+$ ]] || [ "$panel_port" -lt 1 ] || [ "$panel_port" -gt 65535 ]; then
        print_error "Неверный порт панели!"
        exit 1
    fi
    if ! [[ "$sub_port" =~ ^[0-9]+$ ]] || [ "$sub_port" -lt 1 ] || [ "$sub_port" -gt 65535 ]; then
        print_error "Неверный порт подписки!"
        exit 1
    fi
    
    # Step 4: Database password
    echo ""
    echo -e "${PURPLE}[Шаг 4/7]${NC} Настройка базы данных"
    echo -e "${CYAN}Опции пароля базы данных:${NC}"
    echo "1) Сгенерировать безопасный случайный пароль (рекомендуется)"
    echo "2) Ввести свой пароль"
    echo ""
    read -p "Выберите [1-2, по умолчанию: 1]: " pwd_choice
    pwd_choice=${pwd_choice:-1}
    
    local db_password
    if [[ "$pwd_choice" == "2" ]]; then
        read -sp "Введите пароль базы данных: " db_password
        echo ""
        if [[ ${#db_password} -lt 8 ]]; then
            print_warning "Пароль слишком короткий. Генерируется безопасный пароль."
            db_password=$(generate_password 24)
        fi
    else
        db_password=$(generate_password 24)
    fi
    
    echo -e "${GREEN}Пароль базы данных: $db_password${NC}"
    echo -e "${YELLOW}Пожалуйста, сохраните этот пароль!${NC}"
    echo ""
    
    # Step 5: Create Docker Compose and start database first
    echo ""
    echo -e "${PURPLE}[Шаг 5/7]${NC} Создание Docker Compose и запуск базы данных"
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR/cert"
    fix_cert_dir_ownership "$INSTALL_DIR/cert"
    
    if [[ "$network_mode" == "host" ]]; then
        create_compose_host "$panel_port" "$sub_port" "$db_password"
    else
        create_compose_bridge "$panel_port" "$sub_port" "$db_password"
    fi
    
    # Start only PostgreSQL first and wait for it to be ready
    print_info "Запуск базы данных PostgreSQL..."
    cd "$INSTALL_DIR"
    docker compose up -d postgres
    
    # Wait for PostgreSQL to be healthy
    print_info "Ожидание готовности PostgreSQL..."
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if docker compose exec -T postgres pg_isready -h 127.0.0.1 -p 5432 -U xui_user -d xui_db &>/dev/null; then
            print_success "PostgreSQL is ready!"
            break
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 2
    done
    echo ""
    
    if [ $attempt -ge $max_attempts ]; then
        print_warning "PostgreSQL может быть не полностью готов, но продолжаем..."
    fi
    
    # Step 6: SSL Certificate
    echo ""
    echo -e "${PURPLE}[Шаг 6/7]${NC} Настройка SSL сертификата"
    local server_ip=$(get_server_ip)
    echo -e "IPv4 вашего сервера: ${GREEN}$server_ip${NC}"
    
    local detected_ipv6=$(get_server_ipv6)
    if [[ -n "$detected_ipv6" ]]; then
        echo -e "IPv6 вашего сервера: ${GREEN}$detected_ipv6${NC}"
    fi
    
    # Initialize SSL variables
    SSL_HOST="$server_ip"
    CERT_TYPE="none"
    
    # Interactive SSL setup (database is now running, can update settings)
    prompt_and_setup_ssl "$INSTALL_DIR/cert" "$server_ip"
    
    local cert_type="$CERT_TYPE"
    local domain_or_ip="$SSL_HOST"
    
    # Save configuration
    save_config "$panel_port" "$sub_port" "$db_password" "$network_mode" "$cert_type" "$domain_or_ip"
    
    # Step 7: Start panel
    echo ""
    echo -e "${PURPLE}[Шаг 7/7]${NC} Запуск панели"
    
    # Regenerate docker-compose with SSL environment variables now that we have certs
    if [[ "$network_mode" == "host" ]]; then
        create_compose_host "$panel_port" "$sub_port" "$db_password"
    else
        create_compose_bridge "$panel_port" "$sub_port" "$db_password"
    fi
    
    # Start the panel
    print_info "Запуск панели SharX..."
    docker compose up -d sharx
    
    # Wait for panel to start
    sleep 5
    
    if docker compose ps | grep -q "sharx_app.*Up"; then
        print_success "Панель успешно запущена!"
    else
        print_warning "Панель может еще запускаться. Проверьте: docker compose ps"
    fi
    
    # Final summary
    print_banner
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Установка успешно завершена!                     ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}Учетные данные для входа:${NC}"
    echo -e "  Имя пользователя:  ${CYAN}admin${NC}"
    echo -e "  Пароль:            ${CYAN}admin${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  ВАЖНО: Пожалуйста, смените пароль после первого входа!${NC}"
    echo ""
    
    # Get subscription info from env or use defaults
    local sub_port_env=""
    local sub_domain_env=""
    if [[ -f "$INSTALL_DIR/$COMPOSE_FILE" ]]; then
        sub_port_env=$(read_env_from_compose "XUI_SUB_PORT" 2>/dev/null || echo "")
        sub_domain_env=$(read_env_from_compose "XUI_SUB_DOMAIN" 2>/dev/null || echo "")
    fi
    local actual_sub_port=${sub_port_env:-$sub_port}
    
    # Determine panel and subscription addresses
    local panel_address=""
    local sub_address=""
    local panel_protocol="http"
    local sub_protocol="http"
    
    if [[ "$cert_type" != "none" ]]; then
        panel_protocol="https"
        sub_protocol="https"
        
        # Determine panel domain/IP
        local panel_domain=""
        if [[ -f "$INSTALL_DIR/$COMPOSE_FILE" ]]; then
            panel_domain=$(read_env_from_compose "XUI_WEB_DOMAIN" 2>/dev/null || echo "")
        fi
        
        if [[ -n "$panel_domain" ]]; then
            panel_address="${panel_protocol}://${panel_domain}:${panel_port}"
        elif [[ "$cert_type" == "letsencrypt-domain" ]]; then
            panel_address="${panel_protocol}://${domain_or_ip}:${panel_port}"
        else
            panel_address="${panel_protocol}://${server_ip}:${panel_port}"
        fi
        
        # Determine subscription domain/IP
        if [[ -n "$sub_domain_env" ]]; then
            sub_address="${sub_protocol}://${sub_domain_env}:${actual_sub_port}"
        elif [[ -n "$panel_domain" ]]; then
            sub_address="${sub_protocol}://${panel_domain}:${actual_sub_port}"
        elif [[ "$cert_type" == "letsencrypt-domain" ]]; then
            sub_address="${sub_protocol}://${domain_or_ip}:${actual_sub_port}"
        else
            sub_address="${sub_protocol}://${server_ip}:${actual_sub_port}"
        fi
        
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${GREEN}✓ SSL certificate configured${NC}"
        if [[ "$cert_type" == "letsencrypt-ip" ]]; then
            echo -e "${YELLOW}  (IP сертификат действителен ~6 дней, автоматически обновляется через acme.sh)${NC}"
        elif [[ "$cert_type" == "letsencrypt-domain" ]]; then
            echo -e "${YELLOW}  (Доменный сертификат действителен 90 дней, автоматически обновляется через acme.sh)${NC}"
        fi
        echo ""
        echo -e "${WHITE}Панель доступна по адресу:${NC}"
        echo -e "  ${GREEN}${panel_address}${NC}"
        echo ""
        echo -e "${WHITE}Сервис подписки доступен по адресу:${NC}"
        echo -e "  ${GREEN}${sub_address}${NC}"
        echo ""
    else
        panel_address="${panel_protocol}://${server_ip}:${panel_port}"
        sub_address="${sub_protocol}://${server_ip}:${actual_sub_port}"
        
        echo -e "${WHITE}Панель доступна по адресу:${NC}"
        echo -e "  ${GREEN}${panel_address}${NC}"
        echo ""
        echo -e "${WHITE}Сервис подписки доступен по адресу:${NC}"
        echo -e "  ${GREEN}${sub_address}${NC}"
        echo ""
        echo -e "${YELLOW}Примечание: SSL сертификат не настроен. Вы можете настроить его позже из меню.${NC}"
        echo ""
    fi
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}Пароль базы данных:${NC} ${CYAN}$db_password${NC}"
    echo -e "${YELLOW}(сохраните его в безопасном месте)${NC}"
    echo ""
    
    # Check if panel is accessible
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    print_info "Проверка доступности панели..."
    sleep 2
    
    local panel_accessible=false
    if command -v curl &>/dev/null; then
        if curl -s -k --connect-timeout 5 "${panel_address}" &>/dev/null; then
            panel_accessible=true
        fi
    elif command -v wget &>/dev/null; then
        if wget -q --spider --timeout=5 --no-check-certificate "${panel_address}" 2>/dev/null; then
            panel_accessible=true
        fi
    fi
    
    if [[ "$panel_accessible" == "true" ]]; then
        echo -e "${GREEN}✓ Панель доступна${NC}"
    else
        echo -e "${YELLOW}⚠ Панель может еще запускаться. Пожалуйста, подождите несколько мгновений и попробуйте получить доступ.${NC}"
    fi
    echo ""
    
    # Show service status
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}Статус сервисов:${NC}"
    cd "$INSTALL_DIR"
    if docker compose ps &>/dev/null; then
        docker compose ps 2>/dev/null
    else
        docker-compose ps 2>/dev/null
    fi
    echo ""
    
    # Check for updates
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    print_info "Проверка обновлений панели..."
    local current_image=$(docker compose config 2>/dev/null | grep -E "^\s+image:" | head -n 1 | sed -E 's/^\s+image:\s*(.+)$/\1/' | tr -d '"' | tr -d "'")
    if [[ -n "$current_image" ]]; then
        # Try to pull latest image info (without actually pulling)
        docker manifest inspect "$current_image" &>/dev/null
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}✓ Образ панели доступен${NC}"
            echo -e "${CYAN}  Для проверки обновлений запустите: ${YELLOW}./install_ru.sh${NC} → ${YELLOW}2) Обновить панель${NC}"
        else
            echo -e "${YELLOW}⚠ Не удалось проверить обновления (проблема с сетью или приватный реестр)${NC}"
        fi
    fi
    echo ""
    
    echo ""
	echo -e "${CYAN}Для подробных инструкций выберите опцию 23) Инструкции из меню.${NC}"
	echo -e "${GREEN}Установка завершена!${NC}"
	. /etc/os-release && case "$ID" in fedora|alpine|arch) echo -e "${GREEN}Для Fedora/Alpine/Arch требуется перезагрузка! Перезагрузка через 5...${NC}" && sleep 5 && reboot ;; ubuntu|debian) systemctl restart rc-local.service ;; esac
}

# Main menu
main_menu() {
    while true; do
        print_banner
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${WHITE}                    Меню управления${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        # Display panel status
        if [[ -f "$INSTALL_DIR/.3xui-config" ]] || docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^sharx_app$"; then
            local status_info=$(get_panel_status)
            local panel_status=$(echo "$status_info" | cut -d'|' -f1)
            local panel_port=$(echo "$status_info" | cut -d'|' -f2)
            local panel_address=$(echo "$status_info" | cut -d'|' -f3)
            local web_path=$(echo "$status_info" | cut -d'|' -f4)
            
            echo -e "  ${WHITE}── Статус панели ──${NC}"
            echo -e "  Статус:  $(echo -e "$panel_status")"
            echo -e "  Порт:    ${CYAN}$panel_port${NC}"
            if [[ -n "$web_path" ]] && [[ "$web_path" != "/" ]]; then
                echo -e "  Веб-путь: ${CYAN}/$web_path${NC}"
            fi
            echo -e "  Адрес: ${CYAN}$panel_address${NC}"
            echo ""
        fi
        
        # Display database status
        if [[ -f "$INSTALL_DIR/.3xui-config" ]] || docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^sharx_postgres$"; then
            local db_status_info=$(get_db_status)
            local db_status=$(echo "$db_status_info" | cut -d'|' -f1)
            local db_port=$(echo "$db_status_info" | cut -d'|' -f2)
            local db_size=$(echo "$db_status_info" | cut -d'|' -f3)
            
            echo -e "  ${WHITE}── Статус базы данных ──${NC}"
            echo -e "  Статус:  $(echo -e "$db_status")"
            echo -e "  Порт:    ${CYAN}$db_port${NC}"
            if [[ -n "$db_size" ]]; then
                echo -e "  Размер:  ${CYAN}$db_size${NC}"
            fi
            echo ""
        fi
        
        echo -e "  ${WHITE}── Панель ──${NC}"
        echo -e "  ${GREEN}1)${NC}  Установить панель"
        echo -e "  ${GREEN}2)${NC}  Обновить панель"
        echo -e "  ${GREEN}3)${NC}  Запустить панель"
        echo -e "  ${GREEN}4)${NC}  Остановить панель"
        echo -e "  ${GREEN}5)${NC}  Перезапустить панель"
        echo -e "  ${GREEN}6)${NC}  Статус панели"
        echo -e "  ${GREEN}7)${NC}  Логи панели"
        echo ""
        echo -e "  ${WHITE}── Настройки панели ──${NC}"
        echo -e "  ${YELLOW}8)${NC}  Изменить порт панели"
        echo -e "  ${YELLOW}9)${NC}  Изменить порт подписки"
        echo -e "  ${YELLOW}10)${NC} Изменить пароль базы данных"
        echo -e "  ${YELLOW}11)${NC} Обновить сертификат панели"
        echo -e "  ${YELLOW}12)${NC} Настроить новый сертификат панели"
        echo -e "  ${YELLOW}13)${NC} Добавить порт панели"
        echo -e "  ${YELLOW}14)${NC} Удалить порт панели"
        echo -e "  ${YELLOW}15)${NC} Сбросить панель к настройкам по умолчанию"
        echo ""
        echo -e "  ${WHITE}── База данных ──${NC}"
        echo -e "  ${ORANGE}17)${NC} Запустить базу данных"
        echo -e "  ${ORANGE}18)${NC} Остановить базу данных"
        echo -e "  ${ORANGE}19)${NC} Перезапустить базу данных"
        echo -e "  ${ORANGE}20)${NC} Статус базы данных"
        echo -e "  ${ORANGE}21)${NC} Создать резервную копию"
        echo -e "  ${ORANGE}22)${NC} Восстановить из резервной копии"
        echo ""
        echo -e "  ${WHITE}── Информация ──${NC}"
        echo -e "  ${CYAN}23)${NC} Инструкции"
        echo ""
        echo -e "  ${WHITE}── Дополнительно ──${NC}"
        echo -e "  ${CYAN}50)${NC} Установить WARP"
		echo -e "  ${CYAN}51)${NC} Отключение ipv6"
        echo -e "  ${RED}98)${NC} Удалить WARP"
        echo -e "  ${RED}99)${NC} Удалить панель"
        echo -e "  ${WHITE}0)${NC}  Выход"
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        read -p "Выберите опцию: " choice
        
        case $choice in
            # Panel options
            1) install_wizard ;;
            2) update_services ;;
            3) start_services ;;
            4) stop_services ;;
            5) 
                cd "$INSTALL_DIR"
                docker compose restart
                print_success "Панель перезапущена!"
                ;;
            6) show_status ;;
            7) show_logs ;;
            8) change_panel_port ;;
            9) change_sub_port ;;
            10) change_db_password ;;
            11) renew_certificate ;;
            12) setup_new_certificate ;;
            13) add_panel_port ;;
            14) remove_panel_port ;;
            15) reset_panel ;;
            
            # Database options
            17) start_db ;;
            18) stop_db ;;
            19) restart_db ;;
            20) 
                local db_status_info=$(get_db_status)
                local db_status=$(echo "$db_status_info" | cut -d'|' -f1)
                local db_port=$(echo "$db_status_info" | cut -d'|' -f2)
                local db_size=$(echo "$db_status_info" | cut -d'|' -f3)
                
                print_banner
                echo ""
                echo -e "${WHITE}Статус базы данных:${NC}"
                echo -e "  Статус:  $(echo -e "$db_status")"
                echo -e "  Порт:    ${CYAN}$db_port${NC}"
                if [[ -n "$db_size" ]]; then
                    echo -e "  Размер:  ${CYAN}$db_size${NC}"
                fi
                echo ""
                cd "$INSTALL_DIR"
                docker compose ps postgres
                ;;
            21) backup_db ;;
            22) restore_db ;;
            
            # Information
            23) show_instructions ;;
            
            # Other
            50) warp_install ;;
			51) disable_ipv6 ;;
            98) warp_uninstall ;;
            99) uninstall ;;
            0) 
                echo -e "${GREEN}До свидания!${NC}"
                exit 0
                ;;
            *)
                print_error "Неверная опция!"
                ;;
        esac
        
        echo ""
        read -p "Нажмите Enter для продолжения..."
    done
}

# Script entry point
main() {
    # Check if config exists (already installed)
    if [[ -f "$INSTALL_DIR/.3xui-config" ]]; then
        main_menu
    else
        # First run - check for arguments
        case "${1:-}" in
            install|--install|-i)
                check_root
                install_wizard
                ;;
            menu|--menu|-m)
                check_root
                main_menu
                ;;
            *)
                # Interactive selection for first run
                print_banner
                echo ""
                echo -e "${CYAN}Добро пожаловать в установщик SharX!${NC}"
                echo ""
                echo -e "${WHITE}Что вы хотите сделать?${NC}"
                echo ""
                echo -e "  ${GREEN}1)${NC} Установить панель (с базой данных)"
                echo -e "  ${YELLOW}2)${NC} Открыть меню"
                echo -e "  ${WHITE}0)${NC} Выход"
                echo ""
                read -p "Выберите опцию: " first_choice
                
                case $first_choice in
                    1)
                        check_root
                        install_wizard
                        ;;
                    2)
                        check_root
                        main_menu
                        ;;
                    0|*)
                        echo -e "${GREEN}До свидания!${NC}"
                        exit 0
                        ;;
                esac
                ;;
        esac
    fi
}

# Run main
main "$@"
