#!/bin/bash

# ============================================
# 3X-UI NEW Installation Script
# Author: @konspic
# Version: 3.0.0b
# ============================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Default values
DEFAULT_PANEL_PORT=2053
DEFAULT_SUB_PORT=2096
DEFAULT_DB_PASSWORD="change_this_password"
DEFAULT_NODE_PORT=8080
# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$SCRIPT_DIR"
NODE_DIR="$SCRIPT_DIR/node"
COMPOSE_FILE="docker-compose.yml"

# Print banner
print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║     ██████╗ ██╗  ██╗      ██╗   ██╗██╗    ███╗   ██╗███████╗██╗    ██╗  ║"
    echo "║     ╚════██╗╚██╗██╔╝      ██║   ██║██║    ████╗  ██║██╔════╝██║    ██║  ║"
    echo "║      █████╔╝ ╚███╔╝ █████╗██║   ██║██║    ██╔██╗ ██║█████╗  ██║ █╗ ██║  ║"
    echo "║      ╚═══██╗ ██╔██╗ ╚════╝██║   ██║██║    ██║╚██╗██║██╔══╝  ██║███╗██║  ║"
    echo "║     ██████╔╝██╔╝ ██╗      ╚██████╔╝██║    ██║ ╚████║███████╗╚███╔███╔╝  ║"
    echo "║     ╚═════╝ ╚═╝  ╚═╝       ╚═════╝ ╚═╝    ╚═╝  ╚═══╝╚══════╝ ╚══╝╚══╝   ║"
    echo "║                                                               ║"
    echo "║              Next Generation Panel Management                 ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Print colored message
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root!"
        echo -e "Please run: ${YELLOW}sudo bash install.sh${NC}"
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
    
    echo -e "  OS: ${CYAN}$OS${NC}"
    echo -e "  Package Manager: ${CYAN}$PACKAGE_MANAGER${NC}"
}

# Check system requirements
check_system() {
    print_info "Checking system requirements..."
    
    # Detect OS
    detect_os
    
    if [[ -z "$PACKAGE_MANAGER" ]]; then
        print_error "Could not detect package manager!"
        exit 1
    fi
    
    # Check architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" && "$ARCH" != "armv7l" ]]; then
        print_error "Unsupported architecture: $ARCH"
        exit 1
    fi
    echo -e "  Architecture: ${CYAN}$ARCH${NC}"
    
    print_success "System check passed!"
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
    
    # Set up repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# Install Docker - Fedora
install_docker_dnf() {
    # Remove old versions
    dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
    
    # Install prerequisites
    dnf install -y dnf-plugins-core
    
    # Add Docker repository
    dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    
    # Install Docker
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# Install Docker - CentOS/RHEL
install_docker_yum() {
    # Remove old versions
    yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
    
    # Install prerequisites
    yum install -y yum-utils
    
    # Add Docker repository
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    
    # Install Docker
    yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# Install Docker - Arch Linux
install_docker_pacman() {
    # Update system
    pacman -Syu --noconfirm
    
    # Install Docker
    pacman -S --noconfirm docker docker-compose
}

# Install Docker - Alpine
install_docker_apk() {
    # Update repositories
    apk update
    
    # Install Docker
    apk add docker docker-cli-compose
    
    # Add to boot
    rc-update add docker boot
}

# Install Docker - openSUSE
install_docker_zypper() {
    # Install Docker
    zypper install -y docker docker-compose
}

# Install Docker if not present
install_docker() {
    if command -v docker &> /dev/null; then
        print_success "Docker is already installed: $(docker --version)"
        return 0
    fi

    print_info "Installing Docker for $OS using $PACKAGE_MANAGER..."
    
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
            print_error "Unsupported package manager: $PACKAGE_MANAGER"
            print_info "Please install Docker manually: https://docs.docker.com/engine/install/"
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
        print_success "Docker installed successfully!"
    else
        print_error "Docker installation failed!"
        exit 1
    fi
}

# Install Docker Compose (standalone) if not present
install_docker_compose() {
    # Check for docker compose plugin
    if docker compose version &> /dev/null; then
        print_success "Docker Compose plugin is available: $(docker compose version)"
        return 0
    fi
    
    # Check for standalone docker-compose
    if command -v docker-compose &> /dev/null; then
        print_success "Docker Compose standalone is available: $(docker-compose --version)"
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
    
    print_info "Installing Docker Compose..."
    
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
            print_info "Installing Docker Compose standalone..."
            COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
            curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            ;;
    esac
    
    # Verify installation
    if docker compose version &> /dev/null || docker-compose --version &> /dev/null; then
        print_success "Docker Compose installed successfully!"
    else
        print_error "Docker Compose installation failed!"
        print_info "Please install manually: https://docs.docker.com/compose/install/"
        exit 1
    fi
}

# Generate random string
gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

# Generate random password
generate_password() {
    local length=${1:-24}
    tr -dc 'A-Za-z0-9!@#$%^&*()_+' < /dev/urandom | head -c "$length"
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
    ip=$(curl -6 -s ifconfig.me 2>/dev/null || curl -6 -s icanhazip.com 2>/dev/null || echo "")
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
        print_error "Invalid port number: $port (must be 1-65535)"
        return 1
    fi
    
    # Check if port is in use
    if is_port_in_use "$port"; then
        print_error "Port $port is already in use!"
        print_info "Please choose a different port or free this port first."
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
        read -p "Enter $service_name port [$default_port]: " port
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
    print_info "Installing acme.sh for SSL certificate management..."
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
        print_error "Failed to install acme.sh"
        return 1
    else
        print_success "acme.sh installed successfully"
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
    
    print_info "Setting up SSL certificate for domain: $domain"
    
    # Check if acme.sh is installed
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        install_acme
        if [ $? -ne 0 ]; then
            print_warning "Failed to install acme.sh, skipping SSL setup"
            return 1
        fi
    fi
    
    # Create certificate directory
    local acmeCertPath="/root/cert/${domain}"
    mkdir -p "$acmeCertPath"
    mkdir -p "$cert_dir"
    
    # Stop containers to free port 80
    print_info "Stopping containers temporarily to free port 80..."
    cd "$INSTALL_DIR" 2>/dev/null && docker compose down 2>/dev/null || true
    
    # Issue certificate
    print_info "Issuing SSL certificate for ${domain}..."
    print_warning "Note: Port 80 must be open and accessible from the internet"
    
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
    ~/.acme.sh/acme.sh --issue -d ${domain} --listen-v6 --standalone --httpport 80 --force
    
    if [ $? -ne 0 ]; then
        print_error "Failed to issue certificate for ${domain}"
        print_warning "Please ensure port 80 is open and domain points to this server"
        rm -rf ~/.acme.sh/${domain} 2>/dev/null
        rm -rf "$acmeCertPath" 2>/dev/null
        return 1
    fi
    
    # Install certificate to acme path
    ~/.acme.sh/acme.sh --installcert -d ${domain} \
        --key-file ${acmeCertPath}/privkey.pem \
        --fullchain-file ${acmeCertPath}/fullchain.pem \
        --reloadcmd "cp ${acmeCertPath}/privkey.pem ${cert_dir}/ && cp ${acmeCertPath}/fullchain.pem ${cert_dir}/ && cd ${INSTALL_DIR} && docker compose restart 3xui 2>/dev/null || true" >/dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        print_warning "Certificate install command had issues, checking files..."
    fi
    
    # Copy certificates to our cert directory
    if [[ -f "${acmeCertPath}/fullchain.pem" && -f "${acmeCertPath}/privkey.pem" ]]; then
        cp "${acmeCertPath}/fullchain.pem" "${cert_dir}/"
        cp "${acmeCertPath}/privkey.pem" "${cert_dir}/"
        chmod 600 "${cert_dir}/privkey.pem"
        chmod 644 "${cert_dir}/fullchain.pem"
        print_success "SSL certificate installed successfully!"
    else
        print_error "Certificate files not found"
        return 1
    fi
    
    # Enable auto-renew
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1
    
    print_success "Certificate valid for 90 days with auto-renewal enabled"
    return 0
}

# Setup Let's Encrypt IP certificate with shortlived profile (~6 days validity)
setup_ip_certificate() {
    local ipv4="$1"
    local ipv6="${2:-}"
    local cert_dir="$3"

    print_info "Setting up Let's Encrypt IP certificate (shortlived profile)..."
    print_warning "Note: IP certificates are valid for ~6 days and will auto-renew."

    # Check for acme.sh
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        install_acme
        if [ $? -ne 0 ]; then
            print_error "Failed to install acme.sh"
            return 1
        fi
    fi

    # Validate IP address
    if [[ -z "$ipv4" ]]; then
        print_error "IPv4 address is required"
        return 1
    fi

    if ! is_ipv4 "$ipv4"; then
        print_error "Invalid IPv4 address: $ipv4"
        return 1
    fi

    # Create certificate directories
    local acmeCertDir="/root/cert/ip"
    mkdir -p "$acmeCertDir"
    mkdir -p "$cert_dir"

    # Build domain arguments
    local domain_args="-d ${ipv4}"
    if [[ -n "$ipv6" ]] && is_ipv6 "$ipv6"; then
        domain_args="${domain_args} -d ${ipv6}"
        print_info "Including IPv6 address: ${ipv6}"
    fi

    # Stop containers to free port 80
    print_info "Stopping containers temporarily to free port 80..."
    cd "$INSTALL_DIR" 2>/dev/null && docker compose down 2>/dev/null || true

    # Choose port for HTTP-01 listener
    local WebPort=80
    
    # Ensure port 80 is available
    if is_port_in_use 80; then
        print_warning "Port 80 is in use, attempting to find process..."
        fuser -k 80/tcp 2>/dev/null || true
        sleep 2
    fi

    # Issue certificate with shortlived profile
    print_info "Issuing IP certificate for ${ipv4}..."
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
    
    ~/.acme.sh/acme.sh --issue \
        ${domain_args} \
        --standalone \
        --server letsencrypt \
        --certificate-profile shortlived \
        --days 6 \
        --httpport ${WebPort} \
        --force

    if [ $? -ne 0 ]; then
        print_error "Failed to issue IP certificate"
        print_warning "Please ensure port 80 is reachable from the internet"
        rm -rf ~/.acme.sh/${ipv4} 2>/dev/null
        [[ -n "$ipv6" ]] && rm -rf ~/.acme.sh/${ipv6} 2>/dev/null
        rm -rf ${acmeCertDir} 2>/dev/null
        return 1
    fi

    print_success "Certificate issued successfully, installing..."

    # Install certificate
    ~/.acme.sh/acme.sh --installcert -d ${ipv4} \
        --key-file "${acmeCertDir}/privkey.pem" \
        --fullchain-file "${acmeCertDir}/fullchain.pem" \
        --reloadcmd "cp ${acmeCertDir}/privkey.pem ${cert_dir}/ && cp ${acmeCertDir}/fullchain.pem ${cert_dir}/ && cd ${INSTALL_DIR} && docker compose restart 3xui 2>/dev/null || true" 2>&1 || true

    # Verify certificate files exist
    if [[ ! -f "${acmeCertDir}/fullchain.pem" || ! -f "${acmeCertDir}/privkey.pem" ]]; then
        print_error "Certificate files not found after installation"
        rm -rf ~/.acme.sh/${ipv4} 2>/dev/null
        [[ -n "$ipv6" ]] && rm -rf ~/.acme.sh/${ipv6} 2>/dev/null
        rm -rf ${acmeCertDir} 2>/dev/null
        return 1
    fi
    
    # Copy to our cert directory
    cp "${acmeCertDir}/fullchain.pem" "${cert_dir}/"
    cp "${acmeCertDir}/privkey.pem" "${cert_dir}/"
    chmod 600 "${cert_dir}/privkey.pem"
    chmod 644 "${cert_dir}/fullchain.pem"
    
    print_success "Certificate files installed successfully"

    # Enable auto-upgrade for acme.sh
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1

    print_success "IP certificate installed and configured successfully!"
    print_info "Certificate valid for ~6 days, auto-renews via acme.sh cron job."
    return 0
}

# Interactive SSL setup (domain or IP)
prompt_and_setup_ssl() {
    local cert_dir="$1"
    local server_ip="$2"

    echo ""
    echo -e "${CYAN}Choose SSL certificate setup method:${NC}"
    echo -e "${GREEN}1.${NC} Let's Encrypt for Domain (90-day validity, auto-renews)"
    echo -e "${GREEN}2.${NC} Let's Encrypt for IP Address (6-day validity, auto-renews)"
    echo -e "${GREEN}3.${NC} Skip SSL setup (configure later)"
    echo -e "${BLUE}Note:${NC} Both options require port 80 open for HTTP-01 challenge."
    echo ""
    read -rp "Choose an option [1-3, default: 2]: " ssl_choice
    ssl_choice="${ssl_choice:-2}"

    case "$ssl_choice" in
    1)
        # Let's Encrypt domain certificate
        print_info "Using Let's Encrypt for domain certificate..."
        
        local domain=""
        while true; do
            read -rp "Please enter your domain name: " domain
            domain="${domain// /}"
            
            if [[ -z "$domain" ]]; then
                print_error "Domain name cannot be empty. Please try again."
                continue
            fi
            
            if ! is_domain "$domain"; then
                print_error "Invalid domain format: ${domain}. Please enter a valid domain name."
                continue
            fi
            
            break
        done
        
        setup_ssl_certificate "$domain" "$cert_dir"
        if [ $? -eq 0 ]; then
            SSL_HOST="${domain}"
            CERT_TYPE="letsencrypt-domain"
            print_success "SSL certificate configured successfully with domain: ${domain}"
        else
            print_warning "SSL setup failed. You can configure it later from the menu."
            SSL_HOST="${server_ip}"
            CERT_TYPE="none"
        fi
        ;;
    2)
        # Let's Encrypt IP certificate
        print_info "Using Let's Encrypt for IP certificate (shortlived profile)..."
        
        # Ask for optional IPv6
        local ipv6_addr=""
        local detected_ipv6=$(get_server_ipv6)
        if [[ -n "$detected_ipv6" ]]; then
            echo -e "Detected IPv6: ${GREEN}$detected_ipv6${NC}"
            read -rp "Include this IPv6 address? [Y/n]: " include_ipv6
            if [[ "$include_ipv6" != "n" && "$include_ipv6" != "N" ]]; then
                ipv6_addr="$detected_ipv6"
            fi
        else
            read -rp "Enter IPv6 address to include (leave empty to skip): " ipv6_addr
            ipv6_addr="${ipv6_addr// /}"
        fi
        
        setup_ip_certificate "${server_ip}" "${ipv6_addr}" "$cert_dir"
        if [ $? -eq 0 ]; then
            SSL_HOST="${server_ip}"
            CERT_TYPE="letsencrypt-ip"
            print_success "Let's Encrypt IP certificate configured successfully"
        else
            print_warning "IP certificate setup failed. You can configure it later from the menu."
            SSL_HOST="${server_ip}"
            CERT_TYPE="none"
        fi
        ;;
    3)
        print_warning "Skipping SSL setup. Remember to configure SSL later!"
        SSL_HOST="${server_ip}"
        CERT_TYPE="none"
        ;;
    *)
        print_warning "Invalid option. Skipping SSL setup."
        SSL_HOST="${server_ip}"
        CERT_TYPE="none"
        ;;
    esac
}

# Generate HTTPS environment variables if certificates exist
generate_https_env() {
    local panel_port="$1"
    local cert_dir="$INSTALL_DIR/cert"
    local https_env=""
    
    # Check if certificate files exist
    if [[ -f "$cert_dir/fullchain.pem" && -f "$cert_dir/privkey.pem" ]]; then
        https_env="      XUI_WEB_CERT_FILE: /app/cert/fullchain.pem\n      XUI_WEB_KEY_FILE: /app/cert/privkey.pem\n"
        
        # Add domain if available (from config or detect from certificate)
        local domain=""
        if load_config 2>/dev/null; then
            if [[ "$CERT_TYPE" == "letsencrypt-domain" && -n "$DOMAIN_OR_IP" ]]; then
                # Remove https://, http:// and port if present
                domain="${DOMAIN_OR_IP}"
                domain="${domain#https://}"
                domain="${domain#http://}"
                domain="${domain%%:*}"
                # Check if it's a domain (not IP address)
                if [[ -n "$domain" ]] && ! is_ipv4 "$domain" && ! is_ipv6 "$domain"; then
                    https_env="${https_env}      XUI_WEB_DOMAIN: $domain\n"
                fi
            fi
        else
            # Try to extract domain from certificate if config not available
            if command -v openssl &>/dev/null && [[ -f "$cert_dir/fullchain.pem" ]]; then
                # Extract domain from certificate (more compatible approach)
                local cert_domain=$(openssl x509 -in "$cert_dir/fullchain.pem" -noout -text 2>/dev/null | grep -A 1 "Subject Alternative Name" | grep "DNS:" | sed 's/.*DNS:\([^, ]*\).*/\1/' | head -n 1)
                # If no SAN, try to get from Subject CN
                if [[ -z "$cert_domain" ]]; then
                    cert_domain=$(openssl x509 -in "$cert_dir/fullchain.pem" -noout -subject 2>/dev/null | sed -n 's/.*CN=\([^, ]*\).*/\1/p' | head -n 1)
                fi
                if [[ -n "$cert_domain" ]] && ! is_ipv4 "$cert_domain" && ! is_ipv6 "$cert_domain"; then
                    https_env="${https_env}      XUI_WEB_DOMAIN: $cert_domain\n"
                fi
            fi
        fi
        
        # Add port only if it differs from default (2053)
        if [[ "$panel_port" != "2053" ]]; then
            https_env="${https_env}      XUI_WEB_PORT: $panel_port\n"
        fi
    fi
    
    echo -e "$https_env"
}

# Create docker-compose.yml with host network
create_compose_host() {
    local panel_port="$1"
    local sub_port="$2"
    local db_password="$3"
    
    # Generate HTTPS environment variables if certificates exist
    local https_env=$(generate_https_env "$panel_port")
    
    cat > "$INSTALL_DIR/$COMPOSE_FILE" << EOF
services:
  3xui:
    image: registry.konstpic.ru/3x-ui/3xui:3.0.0b
    container_name: 3xui_app
    network_mode: host
    volumes:
      - \$PWD/cert/:/app/cert/
    environment:
      # Xray settings
      XRAY_VMESS_AEAD_FORCED: "false"
      XUI_ENABLE_FAIL2BAN: "true"
$(echo -e "$https_env")
      # Panel ports (for host mode, change in panel settings)
      # Web UI: $panel_port
      # Subscriptions: $sub_port
      
      # PostgreSQL settings
      XUI_DB_HOST: 127.0.0.1
      XUI_DB_PORT: 5432
      XUI_DB_USER: xui_user
      XUI_DB_PASSWORD: $db_password
      XUI_DB_NAME: xui_db
      XUI_DB_SSLMODE: disable
    depends_on:
      postgres:
        condition: service_healthy
    tty: true
    restart: unless-stopped

  postgres:
    image: registry.konstpic.ru/3x-ui/postgres:16-alpine
    container_name: 3xui_postgres
    network_mode: host
    environment:
      POSTGRES_USER: xui_user
      POSTGRES_PASSWORD: $db_password
      POSTGRES_DB: xui_db
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h 127.0.0.1 -p 5432 -U xui_user -d xui_db"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

volumes:
  postgres_data:
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
    local ports_section="      - \"$panel_port:2053\"   # Web UI\n      - \"$sub_port:2096\"     # Subscriptions"
    
    for port in "${additional_ports[@]}"; do
        if [[ -n "$port" ]]; then
            ports_section="${ports_section}\n      - \"$port:$port\"   # Additional port"
        fi
    done
    
    # Generate HTTPS environment variables if certificates exist
    local https_env=$(generate_https_env "$panel_port")
    
    cat > "$INSTALL_DIR/$COMPOSE_FILE" << EOF
services:
  3xui:
    image: registry.konstpic.ru/3x-ui/3xui:3.0.0b
    container_name: 3xui_app
    ports:
$(echo -e "$ports_section")
    volumes:
      - \$PWD/cert/:/app/cert/
    environment:
      # Xray settings
      XRAY_VMESS_AEAD_FORCED: "false"
      XUI_ENABLE_FAIL2BAN: "true"
$(echo -e "$https_env")
      # PostgreSQL settings
      XUI_DB_HOST: postgres
      XUI_DB_PORT: 5432
      XUI_DB_USER: xui_user
      XUI_DB_PASSWORD: $db_password
      XUI_DB_NAME: xui_db
      XUI_DB_SSLMODE: disable
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - xui_network
    tty: true
    restart: unless-stopped

  postgres:
    image: registry.konstpic.ru/3x-ui/postgres:16-alpine
    container_name: 3xui_postgres
    environment:
      POSTGRES_USER: xui_user
      POSTGRES_PASSWORD: $db_password
      POSTGRES_DB: xui_db
    volumes:
      - postgres_data:/var/lib/postgresql/data
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

volumes:
  postgres_data:
EOF
    
    print_success "Docker Compose file created with bridge network mode!"
}

# ============================================
# NODE FUNCTIONS
# ============================================

# Create node docker-compose.yml with host network
create_node_compose_host() {
    local node_port="$1"
    
    cat > "$NODE_DIR/$COMPOSE_FILE" << EOF
services:
  node:
    image: registry.konstpic.ru/3x-ui/node:3.0.0b
    container_name: 3x-ui-node
    network_mode: host
    restart: unless-stopped
    volumes:
      - \$PWD/bin/config.json:/app/bin/config.json
      - \$PWD/bin/node-config.json:/app/bin/node-config.json
      - \$PWD/logs:/app/logs
      - \$PWD/cert:/app/cert
    environment:
      - NODE_TLS_CERT_FILE=/app/cert/fullchain.pem
      - NODE_TLS_KEY_FILE=/app/cert/privkey.pem
EOF
    
    print_success "Node Docker Compose file created with host network mode!"
}

# Create node docker-compose.yml with bridge network (port mapping)
create_node_compose_bridge() {
    local node_port="$1"
    shift
    local xray_ports=("$@")
    
    # Build ports section
    local ports_section="      - \"$node_port:8080\"  # API port (connect to panel)"
    
    for port in "${xray_ports[@]}"; do
        if [[ -n "$port" ]]; then
            ports_section="${ports_section}\n      - \"$port:$port\"  # Xray inbound port"
        fi
    done
    
    cat > "$NODE_DIR/$COMPOSE_FILE" << EOF
services:
  node:
    image: registry.konstpic.ru/3x-ui/node:3.0.0b
    container_name: 3x-ui-node
    restart: unless-stopped
    ports:
$(echo -e "$ports_section")
    volumes:
      - \$PWD/bin/config.json:/app/bin/config.json
      - \$PWD/bin/node-config.json:/app/bin/node-config.json
      - \$PWD/logs:/app/logs
      - \$PWD/cert:/app/cert
    environment:
      - NODE_TLS_CERT_FILE=/app/cert/fullchain.pem
      - NODE_TLS_KEY_FILE=/app/cert/privkey.pem
    networks:
      - node_network

networks:
  node_network:
    driver: bridge
EOF
    
    print_success "Node Docker Compose file created with bridge network mode!"
}

# Save node configuration
save_node_config() {
    local node_port="$1"
    local network_mode="$2"
    local cert_type="$3"
    local domain_or_ip="$4"
    shift 4
    local xray_ports=("$@")
    
    cat > "$NODE_DIR/.node-config" << EOF
# 3X-UI Node Configuration
# Generated: $(date)

NODE_PORT=$node_port
NETWORK_MODE=$network_mode
CERT_TYPE=$cert_type
DOMAIN_OR_IP=$domain_or_ip
NODE_DIR=$NODE_DIR
XRAY_PORTS=($(IFS=' '; echo "${xray_ports[*]}"))
EOF
    
    chmod 600 "$NODE_DIR/.node-config"
}

# Load node configuration
load_node_config() {
    if [[ -f "$NODE_DIR/.node-config" ]]; then
        source "$NODE_DIR/.node-config"
        # Initialize XRAY_PORTS if not set
        if [[ -z "${XRAY_PORTS[@]}" ]]; then
            XRAY_PORTS=()
        fi
        return 0
    fi
    return 1
}

# Start node services
start_node_services() {
    print_info "Starting Node services..."
    cd "$NODE_DIR"
    docker compose up -d
    
    # Wait for services to start
    sleep 3
    
    if docker compose ps | grep -q "Up"; then
        print_success "Node started successfully!"
    else
        print_error "Failed to start node. Check logs with: docker compose logs"
        return 1
    fi
}

# Stop node services
stop_node_services() {
    print_info "Stopping Node services..."
    cd "$NODE_DIR"
    docker compose down
    print_success "Node stopped!"
}

# Update node
update_node() {
    print_info "Updating Node..."
    cd "$NODE_DIR"
    
    print_info "Step 1/3: Pulling new node image..."
    docker compose pull node
    
    print_info "Step 2/3: Stopping and removing old container..."
    docker compose stop node
    docker compose rm -f node
    
    print_info "Step 3/3: Starting node with new image..."
    docker compose up -d node
    
    # Cleanup old images
    print_info "Cleaning up old images..."
    docker image prune -f
    
    print_success "Node updated successfully!"
}

# Show node status
show_node_status() {
    print_info "Node Service Status:"
    echo ""
    cd "$NODE_DIR"
    docker compose ps
    echo ""
    
    if load_node_config; then
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${WHITE}Configuration:${NC}"
        echo -e "  Node Port:     ${GREEN}$NODE_PORT${NC}"
        echo -e "  Network Mode:  ${GREEN}$NETWORK_MODE${NC}"
        echo -e "  Certificate:   ${GREEN}$CERT_TYPE${NC}"
        echo -e "  Domain/IP:     ${GREEN}$DOMAIN_OR_IP${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        if [[ "$CERT_TYPE" != "none" ]]; then
            echo ""
            echo -e "${WHITE}SSL paths for node:${NC}"
            echo -e "  Certificate:  ${CYAN}/app/cert/fullchain.pem${NC}"
            echo -e "  Private Key:  ${CYAN}/app/cert/privkey.pem${NC}"
        fi
    fi
}

# Node installation wizard
install_node_wizard() {
    print_banner
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}          3X-UI Node Installation Wizard${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    check_root
    check_system
    
    # Step 1: Install Docker
    echo ""
    echo -e "${PURPLE}[Step 1/4]${NC} Docker Installation"
    install_docker
    install_docker_compose
    
    # Step 2: Network mode
    echo ""
    echo -e "${PURPLE}[Step 2/4]${NC} Network Configuration"
    echo -e "${CYAN}Choose network mode:${NC}"
    echo "1) Host network (recommended for nodes)"
    echo "   - Direct access to all ports"
    echo "   - Better performance"
    echo ""
    echo "2) Bridge network with port mapping"
    echo "   - Isolated container"
    echo "   - Need to expose inbound ports manually"
    echo ""
    read -p "Select [1-2, default: 1]: " network_choice
    network_choice=${network_choice:-1}
    
    local network_mode="host"
    if [[ "$network_choice" == "2" ]]; then
        network_mode="bridge"
    fi
    
    # Step 3: Port configuration (only for bridge mode)
    local node_port=$DEFAULT_NODE_PORT
    local xray_ports=()
    
    if [[ "$network_mode" == "bridge" ]]; then
        echo ""
        echo -e "${PURPLE}[Step 3/4]${NC} Port Configuration"
        
        # Validate and get API port
        node_port=$(prompt_port "$DEFAULT_NODE_PORT" "Node API")
        if [[ $? -ne 0 ]]; then
            print_error "Port configuration failed"
            exit 1
        fi
        
        # Ask for Xray ports
        echo ""
        echo -e "${CYAN}Add Xray inbound ports?${NC}"
        echo -e "${YELLOW}These ports will be used for Xray traffic (e.g., 443, 8443, 2053)${NC}"
        read -p "Add Xray ports? [y/N]: " add_xray
        
        if [[ "$add_xray" == "y" || "$add_xray" == "Y" ]]; then
            while true; do
                echo ""
                read -p "Enter Xray port (or 'done' to finish): " xray_port
                
                if [[ "$xray_port" == "done" || "$xray_port" == "" ]]; then
                    break
                fi
                
                if validate_port "$xray_port" "Xray"; then
                    xray_ports+=("$xray_port")
                    echo -e "${GREEN}Port $xray_port added${NC}"
                else
                    read -p "Skip this port? [y/N]: " skip
                    if [[ "$skip" != "y" && "$skip" != "Y" ]]; then
                        continue
                    fi
                fi
            done
        fi
    else
        echo ""
        echo -e "${PURPLE}[Step 3/4]${NC} Port Configuration"
        echo -e "${YELLOW}Using host network - node will listen on port 8080 by default${NC}"
        node_port=8080
    fi
    
    # Step 4: SSL Certificate
    echo ""
    echo -e "${PURPLE}[Step 4/4]${NC} SSL Certificate Configuration"
    local server_ip=$(get_server_ip)
    echo -e "Your server IP: ${GREEN}$server_ip${NC}"
    
    local detected_ipv6=$(get_server_ipv6)
    if [[ -n "$detected_ipv6" ]]; then
        echo -e "Your server IPv6: ${GREEN}$detected_ipv6${NC}"
    fi
    
    # Create node directory structure
    mkdir -p "$NODE_DIR/cert"
    mkdir -p "$NODE_DIR/bin"
    mkdir -p "$NODE_DIR/logs"
    
    # Create default config files if not exist
    if [[ ! -f "$NODE_DIR/bin/config.json" ]]; then
        cat > "$NODE_DIR/bin/config.json" << 'NODECONFIG'
{
    "log": {
      "access": "none",
      "dnsLog": false,
      "error": "",
      "loglevel": "warning",
      "maskAddress": ""
    },
    "api": {
      "tag": "api",
      "services": [
        "HandlerService",
        "LoggerService",
        "StatsService"
      ]
    },
    "inbounds": [
      {
        "tag": "api",
        "listen": "127.0.0.1",
        "port": 62789,
        "protocol": "tunnel",
        "settings": {
          "address": "127.0.0.1"
        }
      }
    ],
    "outbounds": [
      {
        "tag": "direct",
        "protocol": "freedom",
        "settings": {
          "domainStrategy": "AsIs",
          "redirect": "",
          "noises": []
        }
      },
      {
        "tag": "blocked",
        "protocol": "blackhole",
        "settings": {}
      }
    ],
    "policy": {
      "levels": {
        "0": {
          "statsUserDownlink": true,
          "statsUserUplink": true
        }
      },
      "system": {
        "statsInboundDownlink": true,
        "statsInboundUplink": true,
        "statsOutboundDownlink": false,
        "statsOutboundUplink": false
      }
    },
    "routing": {
      "domainStrategy": "AsIs",
      "rules": [
        {
          "type": "field",
          "inboundTag": [
            "api"
          ],
          "outboundTag": "api"
        },
        {
          "type": "field",
          "outboundTag": "blocked",
          "ip": [
            "geoip:private"
          ]
        },
        {
          "type": "field",
          "outboundTag": "blocked",
          "protocol": [
            "bittorrent"
          ]
        }
      ]
    },
    "stats": {},
    "metrics": {
      "tag": "metrics_out",
      "listen": "127.0.0.1:11111"
    }
  }
NODECONFIG
    fi
    
    if [[ ! -f "$NODE_DIR/bin/node-config.json" ]]; then
        echo '{}' > "$NODE_DIR/bin/node-config.json"
    fi
    
    # Initialize SSL variables
    SSL_HOST="$server_ip"
    CERT_TYPE="none"
    
    # Interactive SSL setup (reuse existing function but with NODE_DIR)
    local original_install_dir="$INSTALL_DIR"
    INSTALL_DIR="$NODE_DIR"
    prompt_and_setup_ssl "$NODE_DIR/cert" "$server_ip"
    INSTALL_DIR="$original_install_dir"
    
    local cert_type="$CERT_TYPE"
    local domain_or_ip="$SSL_HOST"
    
    # Create docker-compose
    echo ""
    print_info "Creating Docker Compose configuration..."
    
    if [[ "$network_mode" == "host" ]]; then
        create_node_compose_host "$node_port"
    else
        create_node_compose_bridge "$node_port" "${xray_ports[@]}"
    fi
    
    # Save configuration
    save_node_config "$node_port" "$network_mode" "$cert_type" "$domain_or_ip" "${xray_ports[@]}"
    
    # Start services
    start_node_services
    
    # Final summary
    print_banner
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║            Node Installation Completed Successfully!         ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}Node is now running!${NC}"
    echo -e "  API Port: ${GREEN}$node_port${NC}"
    echo -e "  Network:  ${GREEN}$network_mode${NC}"
    echo ""
    
    if [[ "$cert_type" != "none" ]]; then
        echo -e "${GREEN}✓ SSL certificate issued and saved to node/cert/ folder${NC}"
        if [[ "$cert_type" == "letsencrypt-ip" ]]; then
            echo -e "${YELLOW}  (IP certificate valid ~6 days, auto-renews via acme.sh)${NC}"
        elif [[ "$cert_type" == "letsencrypt-domain" ]]; then
            echo -e "${YELLOW}  (domain certificate valid 90 days, auto-renews via acme.sh)${NC}"
        fi
        echo ""
    fi
    
    echo -e "${WHITE}To connect this node to the panel:${NC}"
    echo -e "  1. Open panel web interface"
    echo -e "  2. Go to Node Management"
    echo -e "  3. Add new node with address: ${CYAN}$server_ip:$node_port${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}Management:${NC}"
    echo -e "  ${CYAN}bash install.sh${NC} - open management menu"
    echo ""
}

# Renew node certificate
renew_node_certificate() {
    if ! load_node_config; then
        print_error "Node configuration not found. Please install node first."
        return 1
    fi
    
    local cert_dir="$NODE_DIR/cert"
    
    # Check if acme.sh is installed
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        print_error "acme.sh is not installed. Cannot renew certificate."
        return 1
    fi
    
    print_info "Renewing node certificate via acme.sh..."
    
    # Stop node to free port 80
    cd "$NODE_DIR"
    docker compose down 2>/dev/null || true
    
    if [[ "$CERT_TYPE" == "letsencrypt-domain" ]]; then
        ~/.acme.sh/acme.sh --renew -d "$DOMAIN_OR_IP" --force
        local acmeCertPath="/root/cert/${DOMAIN_OR_IP}"
    else
        ~/.acme.sh/acme.sh --renew -d "$DOMAIN_OR_IP" --force
        local acmeCertPath="/root/cert/ip"
    fi
    
    # Copy renewed certificates
    if [[ -f "${acmeCertPath}/fullchain.pem" && -f "${acmeCertPath}/privkey.pem" ]]; then
        cp "${acmeCertPath}/fullchain.pem" "${cert_dir}/"
        cp "${acmeCertPath}/privkey.pem" "${cert_dir}/"
        chmod 600 "${cert_dir}/privkey.pem"
        chmod 644 "${cert_dir}/fullchain.pem"
        print_success "Node certificate renewed successfully!"
    else
        print_error "Certificate files not found"
    fi
    
    # Restart node
    docker compose up -d
}

# Reset node (clear node-config.json)
reset_node() {
    if ! load_node_config; then
        print_error "Node configuration not found. Please install node first."
        return 1
    fi
    
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                  WARNING: RESET NODE                          ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This will:"
    echo "  - Clear node-config.json (reset node to default state)"
    echo "  - Reset config.json to default configuration"
    echo "  - Stop and start node container"
    echo "  - Node will need to be re-registered with panel"
    echo ""
    read -p "Are you sure? [y/N]: " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        return 0
    fi
    
    print_info "Resetting node..."
    
    # Clear node-config.json
    echo '{}' > "$NODE_DIR/bin/node-config.json"
    
    # Reset config.json to default
    cat > "$NODE_DIR/bin/config.json" << 'NODECONFIG'
{
    "log": {
      "access": "none",
      "dnsLog": false,
      "error": "",
      "loglevel": "warning",
      "maskAddress": ""
    },
    "api": {
      "tag": "api",
      "services": [
        "HandlerService",
        "LoggerService",
        "StatsService"
      ]
    },
    "inbounds": [
      {
        "tag": "api",
        "listen": "127.0.0.1",
        "port": 62789,
        "protocol": "tunnel",
        "settings": {
          "address": "127.0.0.1"
        }
      }
    ],
    "outbounds": [
      {
        "tag": "direct",
        "protocol": "freedom",
        "settings": {
          "domainStrategy": "AsIs",
          "redirect": "",
          "noises": []
        }
      },
      {
        "tag": "blocked",
        "protocol": "blackhole",
        "settings": {}
      }
    ],
    "policy": {
      "levels": {
        "0": {
          "statsUserDownlink": true,
          "statsUserUplink": true
        }
      },
      "system": {
        "statsInboundDownlink": true,
        "statsInboundUplink": true,
        "statsOutboundDownlink": false,
        "statsOutboundUplink": false
      }
    },
    "routing": {
      "domainStrategy": "AsIs",
      "rules": [
        {
          "type": "field",
          "inboundTag": [
            "api"
          ],
          "outboundTag": "api"
        },
        {
          "type": "field",
          "outboundTag": "blocked",
          "ip": [
            "geoip:private"
          ]
        },
        {
          "type": "field",
          "outboundTag": "blocked",
          "protocol": [
            "bittorrent"
          ]
        }
      ]
    },
    "stats": {},
    "metrics": {
      "tag": "metrics_out",
      "listen": "127.0.0.1:11111"
    }
  }
NODECONFIG
    
    # Stop and start node (instead of restart)
    cd "$NODE_DIR"
    docker compose stop node
    docker compose start node
    
    print_success "Node reset successfully! Node needs to be re-registered with panel."
}

# Add port to node
add_node_port() {
    if ! load_node_config; then
        print_error "Node configuration not found. Please install node first."
        return 1
    fi
    
    if [[ "$NETWORK_MODE" != "bridge" ]]; then
        print_error "Port management is only available in bridge network mode!"
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}Add Xray port to node${NC}"
    
    local new_port=$(prompt_port "" "Xray")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Check if port already exists
    if [[ " ${XRAY_PORTS[@]} " =~ " ${new_port} " ]]; then
        print_error "Port $new_port is already configured!"
        return 1
    fi
    
    # Add port to array
    XRAY_PORTS+=("$new_port")
    
    # Recreate compose file
    if [[ "$NETWORK_MODE" == "bridge" ]]; then
        create_node_compose_bridge "$NODE_PORT" "${XRAY_PORTS[@]}"
    fi
    
    # Save config
    save_node_config "$NODE_PORT" "$NETWORK_MODE" "$CERT_TYPE" "$DOMAIN_OR_IP" "${XRAY_PORTS[@]}"
    
    # Restart node
    cd "$NODE_DIR"
    docker compose down
    docker compose up -d
    
    print_success "Port $new_port added and node restarted!"
}

# Remove port from node
remove_node_port() {
    if ! load_node_config; then
        print_error "Node configuration not found. Please install node first."
        return 1
    fi
    
    if [[ "$NETWORK_MODE" != "bridge" ]]; then
        print_error "Port management is only available in bridge network mode!"
        return 1
    fi
    
    if [[ ${#XRAY_PORTS[@]} -eq 0 ]]; then
        print_error "No Xray ports configured!"
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}Remove Xray port from node${NC}"
    echo ""
    echo "Current Xray ports:"
    for i in "${!XRAY_PORTS[@]}"; do
        echo "  $((i+1))) ${XRAY_PORTS[$i]}"
    done
    echo ""
    
    read -p "Enter port number to remove: " port_to_remove
    
    # Find and remove port
    local new_ports=()
    local found=0
    for port in "${XRAY_PORTS[@]}"; do
        if [[ "$port" != "$port_to_remove" ]]; then
            new_ports+=("$port")
        else
            found=1
        fi
    done
    
    if [[ $found -eq 0 ]]; then
        print_error "Port $port_to_remove not found!"
        return 1
    fi
    
    XRAY_PORTS=("${new_ports[@]}")
    
    # Recreate compose file
    create_node_compose_bridge "$NODE_PORT" "${XRAY_PORTS[@]}"
    
    # Save config
    save_node_config "$NODE_PORT" "$NETWORK_MODE" "$CERT_TYPE" "$DOMAIN_OR_IP" "${XRAY_PORTS[@]}"
    
    # Restart node
    cd "$NODE_DIR"
    docker compose down
    docker compose up -d
    
    print_success "Port $port_to_remove removed and node restarted!"
}

# ============================================
# END NODE FUNCTIONS
# ============================================

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
# 3X-UI Configuration
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
    print_info "Starting 3X-UI services..."
    cd "$INSTALL_DIR"
    docker compose up -d
    
    # Wait for services to start
    sleep 5
    
    if docker compose ps | grep -q "Up"; then
        print_success "Services started successfully!"
    else
        print_error "Failed to start services. Check logs with: docker compose logs"
        exit 1
    fi
}

# Stop services
stop_services() {
    print_info "Stopping 3X-UI services..."
    cd "$INSTALL_DIR"
    docker compose down
    print_success "Services stopped!"
}

# Update services
update_services() {
    print_info "Updating 3X-UI Panel..."
    cd "$INSTALL_DIR"
    
    print_info "Step 1/3: Pulling new panel image..."
    docker compose pull 3xui
    
    print_info "Step 2/3: Stopping and removing old container..."
    docker compose stop 3xui
    docker compose rm -f 3xui
    
    print_info "Step 3/3: Starting panel with new image..."
    docker compose up -d 3xui
    
    # Cleanup old images
    print_info "Cleaning up old images..."
    docker image prune -f
    
    print_success "3X-UI Panel updated successfully!"
    echo -e "${YELLOW}Note: Database was not restarted.${NC}"
}

# Show service status
show_status() {
    print_info "3X-UI Service Status:"
    echo ""
    cd "$INSTALL_DIR"
    docker compose ps
    echo ""
    
    if load_config; then
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${WHITE}Configuration:${NC}"
        echo -e "  Panel Port:    ${GREEN}$PANEL_PORT${NC}"
        echo -e "  Sub Port:      ${GREEN}$SUB_PORT${NC}"
        echo -e "  Network Mode:  ${GREEN}$NETWORK_MODE${NC}"
        echo -e "  Certificate:   ${GREEN}$CERT_TYPE${NC}"
        echo -e "  Domain/IP:     ${GREEN}$DOMAIN_OR_IP${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        local server_ip=$(get_server_ip)
        echo ""
        echo -e "${WHITE}Access Panel:${NC}"
        if [[ "$CERT_TYPE" == "letsencrypt-domain" ]]; then
            echo -e "  ${GREEN}https://$DOMAIN_OR_IP:$PANEL_PORT${NC}"
        elif [[ "$CERT_TYPE" == "letsencrypt-ip" ]]; then
            echo -e "  ${GREEN}https://$DOMAIN_OR_IP:$PANEL_PORT${NC}"
            echo -e "  ${YELLOW}(IP certificate valid ~6 days, auto-renews)${NC}"
        else
            echo -e "  ${GREEN}http://$server_ip:$PANEL_PORT${NC}"
            echo -e "  ${YELLOW}(No SSL configured)${NC}"
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
    echo "1) 3X-UI Panel"
    echo "2) PostgreSQL"
    echo "3) All"
    echo ""
    read -p "Choice [1-3]: " log_choice
    
    case $log_choice in
        1) docker compose logs -f 3xui ;;
        2) docker compose logs -f postgres ;;
        3) docker compose logs -f ;;
        *) docker compose logs -f ;;
    esac
}

# Change panel port
change_panel_port() {
    if ! load_config; then
        print_error "Configuration not found. Please run installation first."
        return 1
    fi
    
    local new_port=$(prompt_port "$PANEL_PORT" "Panel")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    print_info "Changing panel port to $new_port..."
    
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
    
    print_info "Restarting services..."
    cd "$INSTALL_DIR"
    docker compose down
    docker compose up -d
    
    print_success "Panel port changed to $new_port!"
}

# Change subscription port
change_sub_port() {
    if ! load_config; then
        print_error "Configuration not found. Please run installation first."
        return 1
    fi
    
    local new_port=$(prompt_port "$SUB_PORT" "Subscription")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    print_info "Changing subscription port to $new_port..."
    
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
    
    print_info "Restarting services..."
    cd "$INSTALL_DIR"
    docker compose down
    docker compose up -d
    
    print_success "Subscription port changed to $new_port!"
}

# Change database password
change_db_password() {
    if ! load_config; then
        print_error "Configuration not found. Please run installation first."
        return 1
    fi
    
    echo -e "${YELLOW}WARNING: Changing database password requires data migration!${NC}"
    read -p "Generate new password? [y/N]: " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        return 0
    fi
    
    local new_password=$(generate_password 24)
    
    print_info "New password: $new_password"
    print_warning "Save this password! It will be needed for recovery."
    
    read -p "Continue with this password? [y/N]: " confirm2
    
    if [[ "$confirm2" != "y" && "$confirm2" != "Y" ]]; then
        return 0
    fi
    
    print_info "Changing database password..."
    
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
        print_error "Configuration not found. Please run installation first."
        return 1
    fi
    
    local cert_dir="$INSTALL_DIR/cert"
    
    # Check if acme.sh is installed
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        print_error "acme.sh is not installed. Cannot renew certificate."
        return 1
    fi
    
    print_info "Renewing certificate via acme.sh..."
    
    if [[ "$CERT_TYPE" == "letsencrypt-domain" ]]; then
        # Renew domain certificate
        print_info "Renewing Let's Encrypt certificate for domain: $DOMAIN_OR_IP"
        
        # Stop containers to free port 80
        cd "$INSTALL_DIR"
        docker compose down 2>/dev/null || true
        
        ~/.acme.sh/acme.sh --renew -d "$DOMAIN_OR_IP" --force
        
        if [ $? -eq 0 ]; then
            # Copy renewed certificates
            local acmeCertPath="/root/cert/${DOMAIN_OR_IP}"
            if [[ -f "${acmeCertPath}/fullchain.pem" && -f "${acmeCertPath}/privkey.pem" ]]; then
                cp "${acmeCertPath}/fullchain.pem" "${cert_dir}/"
                cp "${acmeCertPath}/privkey.pem" "${cert_dir}/"
                chmod 600 "${cert_dir}/privkey.pem"
                chmod 644 "${cert_dir}/fullchain.pem"
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
        
        ~/.acme.sh/acme.sh --renew -d "$DOMAIN_OR_IP" --force
        
        if [ $? -eq 0 ]; then
            # Copy renewed certificates
            local acmeCertDir="/root/cert/ip"
            if [[ -f "${acmeCertDir}/fullchain.pem" && -f "${acmeCertDir}/privkey.pem" ]]; then
                cp "${acmeCertDir}/fullchain.pem" "${cert_dir}/"
                cp "${acmeCertDir}/privkey.pem" "${cert_dir}/"
                chmod 600 "${cert_dir}/privkey.pem"
                chmod 644 "${cert_dir}/fullchain.pem"
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
    
    # Restart services
    cd "$INSTALL_DIR"
    docker compose up -d
    
    print_success "Certificate operation completed!"
}

# Setup new certificate (from menu)
setup_new_certificate() {
    if ! load_config; then
        print_error "Configuration not found. Please run installation first."
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
    
    print_success "Certificate setup completed!"
    echo -e "New certificate type: ${GREEN}$CERT_TYPE${NC}"
    echo -e "Domain/IP: ${GREEN}$SSL_HOST${NC}"
}

# Uninstall
uninstall() {
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                     WARNING: UNINSTALL                        ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This will:"
    echo "  - Stop and remove all containers"
    echo "  - Remove Docker volumes (ALL DATA WILL BE LOST)"
    echo "  - Remove configuration files"
    echo ""
    read -p "Are you sure you want to uninstall? [y/N]: " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        return 0
    fi
    
    read -p "Type 'DELETE' to confirm: " confirm2
    
    if [[ "$confirm2" != "DELETE" ]]; then
        print_info "Uninstall cancelled."
        return 0
    fi
    
    print_info "Uninstalling 3X-UI Panel..."
    
    # Stop and remove panel containers and volumes
    cd "$INSTALL_DIR" 2>/dev/null || true
    docker compose down -v 2>/dev/null || true
    
    # Remove panel config file
    rm -f "$INSTALL_DIR/.3xui-config" 2>/dev/null || true
    
    # Ask about node uninstall
    if [[ -f "$NODE_DIR/.node-config" ]]; then
        read -p "Also uninstall Node? [y/N]: " remove_node
        if [[ "$remove_node" == "y" || "$remove_node" == "Y" ]]; then
            print_info "Uninstalling Node..."
            cd "$NODE_DIR" 2>/dev/null || true
            docker compose down 2>/dev/null || true
            rm -f "$NODE_DIR/.node-config" 2>/dev/null || true
            print_success "Node uninstalled!"
        fi
    fi
    
    # Remove acme.sh certificates (optional)
    read -p "Remove acme.sh certificates? [y/N]: " remove_acme
    if [[ "$remove_acme" == "y" || "$remove_acme" == "Y" ]]; then
        rm -rf /root/cert 2>/dev/null || true
        rm -rf ~/.acme.sh 2>/dev/null || true
        print_info "acme.sh certificates removed"
    fi
    
    # Remove local certificates (optional)
    read -p "Remove local certificates from cert/ folders? [y/N]: " remove_local_cert
    if [[ "$remove_local_cert" == "y" || "$remove_local_cert" == "Y" ]]; then
        rm -f "$INSTALL_DIR/cert/"*.pem 2>/dev/null || true
        rm -f "$NODE_DIR/cert/"*.pem 2>/dev/null || true
        print_info "Local certificates removed"
    fi
    
    print_success "3X-UI uninstalled successfully!"
    echo ""
    echo -e "${YELLOW}Note: Script files and directories are preserved.${NC}"
    echo -e "${YELLOW}You can reinstall anytime by running: bash install.sh${NC}"
}

# Reset panel to default settings (clear database)
reset_panel() {
    if ! load_config; then
        print_error "Configuration not found. Please run installation first."
        return 1
    fi
    
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║              WARNING: RESET PANEL TO DEFAULTS                 ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This will:"
    echo "  - Stop all containers"
    echo "  - Remove Docker volumes (ALL DATA WILL BE LOST)"
    echo "  - Restart services with fresh database"
    echo ""
    read -p "Are you sure? [y/N]: " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        return 0
    fi
    
    read -p "Type 'RESET' to confirm: " confirm2
    
    if [[ "$confirm2" != "RESET" ]]; then
        print_info "Reset cancelled."
        return 0
    fi
    
    print_info "Resetting panel to default settings..."
    
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
    
    print_success "Panel reset to default settings!"
    echo -e "${YELLOW}All data has been cleared. Please reconfigure the panel.${NC}"
}

# Add port to panel
add_panel_port() {
    if ! load_config; then
        print_error "Configuration not found. Please run installation first."
        return 1
    fi
    
    if [[ "$NETWORK_MODE" != "bridge" ]]; then
        print_error "Port management is only available in bridge network mode!"
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}Add port to panel${NC}"
    
    local new_port=$(prompt_port "" "Panel")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Check if port already exists
    if [[ " ${ADDITIONAL_PORTS[@]} " =~ " ${new_port} " ]]; then
        print_error "Port $new_port is already configured!"
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
    
    print_success "Port $new_port added and panel restarted!"
}

# Remove port from panel
remove_panel_port() {
    if ! load_config; then
        print_error "Configuration not found. Please run installation first."
        return 1
    fi
    
    if [[ "$NETWORK_MODE" != "bridge" ]]; then
        print_error "Port management is only available in bridge network mode!"
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
    
    read -p "Enter port number to remove: " port_to_remove
    
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
        print_error "Port $port_to_remove not found!"
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
    
    print_success "Port $port_to_remove removed and panel restarted!"
}

# Full installation wizard
install_wizard() {
    print_banner
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}          3X-UI NEW Installation Wizard${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    check_root
    check_system
    
    # Step 1: Install Docker
    echo ""
    echo -e "${PURPLE}[Step 1/6]${NC} Docker Installation"
    install_docker
    install_docker_compose
    
    # Step 2: Network mode
    echo ""
    echo -e "${PURPLE}[Step 2/6]${NC} Network Configuration"
    echo -e "${CYAN}Choose network mode:${NC}"
    echo "1) Host network (recommended for advanced users)"
    echo "   - Direct access to all ports"
    echo "   - Better performance"
    echo "   - Requires manual port configuration in panel"
    echo ""
    echo "2) Bridge network with port mapping (recommended)"
    echo "   - Isolated containers"
    echo "   - Easy port management"
    echo "   - Need to expose inbound ports manually"
    echo ""
    read -p "Select [1-2, default: 2]: " network_choice
    network_choice=${network_choice:-2}
    
    local network_mode="bridge"
    if [[ "$network_choice" == "1" ]]; then
        network_mode="host"
    fi
    
    # Step 3: Port configuration
    echo ""
    echo -e "${PURPLE}[Step 3/6]${NC} Port Configuration"
    read -p "Panel port [$DEFAULT_PANEL_PORT]: " panel_port
    panel_port=${panel_port:-$DEFAULT_PANEL_PORT}
    
    read -p "Subscription port [$DEFAULT_SUB_PORT]: " sub_port
    sub_port=${sub_port:-$DEFAULT_SUB_PORT}
    
    # Validate ports
    if ! [[ "$panel_port" =~ ^[0-9]+$ ]] || [ "$panel_port" -lt 1 ] || [ "$panel_port" -gt 65535 ]; then
        print_error "Invalid panel port!"
        exit 1
    fi
    if ! [[ "$sub_port" =~ ^[0-9]+$ ]] || [ "$sub_port" -lt 1 ] || [ "$sub_port" -gt 65535 ]; then
        print_error "Invalid subscription port!"
        exit 1
    fi
    
    # Step 4: Database password
    echo ""
    echo -e "${PURPLE}[Step 4/6]${NC} Database Configuration"
    echo -e "${CYAN}Database password options:${NC}"
    echo "1) Generate secure random password (recommended)"
    echo "2) Enter custom password"
    echo ""
    read -p "Select [1-2, default: 1]: " pwd_choice
    pwd_choice=${pwd_choice:-1}
    
    local db_password
    if [[ "$pwd_choice" == "2" ]]; then
        read -sp "Enter database password: " db_password
        echo ""
        if [[ ${#db_password} -lt 8 ]]; then
            print_warning "Password is too short. Generating secure password instead."
            db_password=$(generate_password 24)
        fi
    else
        db_password=$(generate_password 24)
    fi
    
    echo -e "${GREEN}Database password: $db_password${NC}"
    echo -e "${YELLOW}Please save this password!${NC}"
    echo ""
    
    # Step 5: SSL Certificate
    echo ""
    echo -e "${PURPLE}[Step 5/6]${NC} SSL Certificate Configuration"
    local server_ip=$(get_server_ip)
    echo -e "Your server IPv4: ${GREEN}$server_ip${NC}"
    
    local detected_ipv6=$(get_server_ipv6)
    if [[ -n "$detected_ipv6" ]]; then
        echo -e "Your server IPv6: ${GREEN}$detected_ipv6${NC}"
    fi
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR/cert"
    
    # Initialize SSL variables
    SSL_HOST="$server_ip"
    CERT_TYPE="none"
    
    # Interactive SSL setup
    prompt_and_setup_ssl "$INSTALL_DIR/cert" "$server_ip"
    
    local cert_type="$CERT_TYPE"
    local domain_or_ip="$SSL_HOST"
    
    # Step 6: Create and start services
    echo ""
    echo -e "${PURPLE}[Step 6/6]${NC} Creating and Starting Services"
    
    if [[ "$network_mode" == "host" ]]; then
        create_compose_host "$panel_port" "$sub_port" "$db_password"
    else
        create_compose_bridge "$panel_port" "$sub_port" "$db_password"
    fi
    
    # Save configuration (no additional ports on initial install)
    save_config "$panel_port" "$sub_port" "$db_password" "$network_mode" "$cert_type" "$domain_or_ip"
    
    # Start services
    start_services
    
    # Final summary
    print_banner
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Installation Completed Successfully!            ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}Your panel is now available at:${NC}"
    echo -e "  ${GREEN}http://$server_ip:$panel_port${NC}"
    echo ""
    echo -e "${WHITE}Login credentials:${NC}"
    echo -e "  Username:  ${CYAN}admin${NC}"
    echo -e "  Password:  ${CYAN}admin${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Please change your password after first login!${NC}"
    echo ""
    
    if [[ "$cert_type" != "none" ]]; then
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${GREEN}✓ SSL certificate issued and saved to cert/ folder${NC}"
        if [[ "$cert_type" == "letsencrypt-ip" ]]; then
            echo -e "${YELLOW}  (IP certificate valid ~6 days, auto-renews via acme.sh)${NC}"
        elif [[ "$cert_type" == "letsencrypt-domain" ]]; then
            echo -e "${YELLOW}  (domain certificate valid 90 days, auto-renews via acme.sh)${NC}"
        fi
        echo ""
        echo -e "${WHITE}To enable HTTPS, add certificate paths in web panel settings:${NC}"
        echo -e "  Certificate:  ${CYAN}/app/cert/fullchain.pem${NC}"
        echo -e "  Private Key:  ${CYAN}/app/cert/privkey.pem${NC}"
        echo ""
        echo -e "${WHITE}After configuration, panel will be available at:${NC}"
        if [[ "$cert_type" == "letsencrypt-domain" ]]; then
            echo -e "  ${GREEN}https://$domain_or_ip:$panel_port${NC}"
        else
            echo -e "  ${GREEN}https://$server_ip:$panel_port${NC}"
        fi
        echo ""
    fi
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}Database password:${NC} ${CYAN}$db_password${NC}"
    echo -e "${YELLOW}(save it in a secure place)${NC}"
    echo ""
    echo -e "${WHITE}Management:${NC}"
    echo -e "  ${CYAN}bash install.sh${NC} - open management menu"
    echo ""
}

# Main menu
main_menu() {
    while true; do
        print_banner
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${WHITE}                    Management Menu${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "  ${WHITE}── Panel ──${NC}"
        echo -e "  ${GREEN}1)${NC}  Install Panel"
        echo -e "  ${GREEN}2)${NC}  Update Panel"
        echo -e "  ${GREEN}3)${NC}  Start Panel"
        echo -e "  ${GREEN}4)${NC}  Stop Panel"
        echo -e "  ${GREEN}5)${NC}  Restart Panel"
        echo -e "  ${GREEN}6)${NC}  Panel Status"
        echo -e "  ${GREEN}7)${NC}  Panel Logs"
        echo ""
        echo -e "  ${WHITE}── Panel Settings ──${NC}"
        echo -e "  ${YELLOW}8)${NC}  Change Panel Port"
        echo -e "  ${YELLOW}9)${NC}  Change Subscription Port"
        echo -e "  ${YELLOW}10)${NC} Change Database Password"
        echo -e "  ${YELLOW}11)${NC} Renew Panel Certificate"
        echo -e "  ${YELLOW}12)${NC} Setup New Panel Certificate"
        echo -e "  ${YELLOW}13)${NC} Add Panel Port"
        echo -e "  ${YELLOW}14)${NC} Remove Panel Port"
        echo -e "  ${YELLOW}15)${NC} Reset Panel to Defaults"
        echo ""
        echo -e "  ${WHITE}── Node ──${NC}"
        echo -e "  ${BLUE}20)${NC} Install Node"
        echo -e "  ${BLUE}21)${NC} Update Node"
        echo -e "  ${BLUE}22)${NC} Start Node"
        echo -e "  ${BLUE}23)${NC} Stop Node"
        echo -e "  ${BLUE}24)${NC} Restart Node"
        echo -e "  ${BLUE}25)${NC} Node Status"
        echo -e "  ${BLUE}26)${NC} Node Logs"
        echo -e "  ${BLUE}27)${NC} Renew Node Certificate"
        echo -e "  ${BLUE}28)${NC} Add Node Port"
        echo -e "  ${BLUE}29)${NC} Remove Node Port"
        echo -e "  ${BLUE}30)${NC} Reset Node"
        echo ""
        echo -e "  ${RED}99)${NC} Uninstall Panel"
        echo -e "  ${WHITE}0)${NC}  Exit"
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        read -p "Select option: " choice
        
        case $choice in
            # Panel options
            1) install_wizard ;;
            2) update_services ;;
            3) start_services ;;
            4) stop_services ;;
            5) 
                cd "$INSTALL_DIR"
                docker compose restart
                print_success "Panel restarted!"
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
            
            # Node options
            20) install_node_wizard ;;
            21) update_node ;;
            22) start_node_services ;;
            23) stop_node_services ;;
            24) 
                cd "$NODE_DIR"
                docker compose restart
                print_success "Node restarted!"
                ;;
            25) show_node_status ;;
            26) 
                cd "$NODE_DIR"
                docker compose logs -f
                ;;
            27) renew_node_certificate ;;
            28) add_node_port ;;
            29) remove_node_port ;;
            30) reset_node ;;
            
            # Other
            99) uninstall ;;
            0) 
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                print_error "Invalid option!"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Script entry point
main() {
    # Check if config exists (already installed)
    if [[ -f "$INSTALL_DIR/.3xui-config" ]] || [[ -f "$NODE_DIR/.node-config" ]]; then
        main_menu
    else
        # First run - check for arguments
        case "${1:-}" in
            install|--install|-i)
                check_root
                install_wizard
                ;;
            node|--node|-n)
                check_root
                install_node_wizard
                ;;
            menu|--menu|-m)
                check_root
                main_menu
                ;;
            *)
                # Interactive selection for first run
                print_banner
                echo ""
                echo -e "${CYAN}Welcome to 3X-UI NEW Installer!${NC}"
                echo ""
                echo -e "${WHITE}What would you like to install?${NC}"
                echo ""
                echo -e "  ${GREEN}1)${NC} Install Panel (with database)"
                echo -e "  ${BLUE}2)${NC} Install Node (standalone)"
                echo -e "  ${YELLOW}3)${NC} Open Menu"
                echo -e "  ${WHITE}0)${NC} Exit"
                echo ""
                read -p "Select option: " first_choice
                
                case $first_choice in
                    1)
                        check_root
                        install_wizard
                        ;;
                    2)
                        check_root
                        install_node_wizard
                        ;;
                    3)
                        check_root
                        main_menu
                        ;;
                    0|*)
                        echo -e "${GREEN}Goodbye!${NC}"
                        exit 0
                        ;;
                esac
                ;;
        esac
    fi
}

# Run main
main "$@"
