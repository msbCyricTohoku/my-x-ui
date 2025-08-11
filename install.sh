#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# ====== customize these if you ever move repos ======
GITHUB_OWNER="msbCyricTohoku"
GITHUB_REPO="my-x-ui"
FALLBACK_TAG="v1.0.0"   # used only if GitHub API "latest" check fails
# ====================================================

cur_dir=$(pwd)

# check root
if [[ $EUID -ne 0 ]]; then
  echo -e "${red}Error:${plain} must run this script as root!\n"
  exit 1
fi

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif grep -Eqi "debian" /etc/issue 2>/dev/null; then
    release="debian"
elif grep -Eqi "ubuntu" /etc/issue 2>/dev/null; then
    release="ubuntu"
elif grep -Eqi "centos|red hat|redhat" /etc/issue 2>/dev/null; then
    release="centos"
elif grep -Eqi "debian" /proc/version 2>/dev/null; then
    release="debian"
elif grep -Eqi "ubuntu" /proc/version 2>/dev/null; then
    release="ubuntu"
elif grep -Eqi "centos|red hat|redhat" /proc/version 2>/dev/null; then
    release="centos"
else
    echo -e "${red}System version not detected, please contact script author!${plain}\n"
    exit 1
fi

arch=$(arch)
if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="amd64"
    echo -e "${red}Failed to detect architecture, using default: ${arch}${plain}"
fi
echo "Architecture: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ]; then
    echo "This software does not support 32-bit systems (x86); please use a 64-bit system (x86_64). If this detection is wrong, contact the author"
    exit 1
fi

os_version=""
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}Please use CentOS 7 or higher!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Please use Ubuntu 16 or higher!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Please use Debian 8 or higher!${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install -y wget curl tar
    else
        apt update -y && apt install -y wget curl tar
    fi
}

#This function will be called when user installed x-ui out of security
config_after_install() {
    echo -e "${yellow}For security, change the port and account password after installation/update${plain}"
    read -p "Continue? [y/n]: " config_confirm
    if [[ x"${config_confirm}" == x"y" || x"${config_confirm}" == x"Y" ]]; then
        read -p "Please set your account name: " config_account
        echo -e "${yellow}Your account name will be set to: ${config_account}${plain}"
        read -p "Please set your account password: " config_password
        echo -e "${yellow}Your account password will be set to: ${config_password}${plain}"
        read -p "Please set the panel access port: " config_port
        echo -e "${yellow}Your panel access port will be set to: ${config_port}${plain}"
        echo -e "${yellow}Confirming settings${plain}"
        /usr/local/x-ui/x-ui setting -username "${config_account}" -password "${config_password}"
        echo -e "${yellow}Account and password set${plain}"
        /usr/local/x-ui/x-ui setting -port "${config_port}"
        echo -e "${yellow}Panel port set${plain}"
    else
        echo -e "${red}Cancelled, all settings remain default, please modify promptly${plain}"
    fi
}

install_x_ui() {
    systemctl stop x-ui 2>/dev/null
    cd /usr/local/ || exit 1

    # If no arg OR arg is empty -> use latest from your releases
    if [[ $# -eq 0 || -z "${1:-}" ]]; then
        api_url="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest"
        last_version=$(curl -Ls "${api_url}" | grep -m1 '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ -z "$last_version" ]]; then
            echo -e "${yellow}Warning:${plain} Failed to check latest release from your repo (rate limit or network?)."
            echo -e "Falling back to ${green}${FALLBACK_TAG}${plain}"
            last_version="${FALLBACK_TAG}"
        fi
        echo -e "Detected latest ${GITHUB_OWNER}/${GITHUB_REPO} version: ${green}${last_version}${plain}, starting installation"
    else
        last_version="$1"
        echo -e "Starting installation of ${GITHUB_REPO} ${green}${last_version}${plain}"
    fi

    asset_url="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"

    wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz "${asset_url}"
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Failed to download ${GITHUB_REPO} ${last_version} for arch ${arch}.${plain}"
        echo -e "URL tried: ${asset_url}"
        exit 1
    fi

    # Clean old dir, unpack
    if [[ -e /usr/local/x-ui/ ]]; then
        rm -rf /usr/local/x-ui/
    fi

    tar zxvf x-ui-linux-${arch}.tar.gz
    rm -f x-ui-linux-${arch}.tar.gz
    cd x-ui || { echo -e "${red}Unpack failed (x-ui dir missing)${plain}"; exit 1; }

    # Ensure binaries/scripts are executable
    chmod +x x-ui || true
    if [[ -f "bin/xray-linux-${arch}" ]]; then
        chmod +x "bin/xray-linux-${arch}"
    fi

    # Install service
    cp -f x-ui.service /etc/systemd/system/

    # Pull the helper script from YOUR fork
    wget --no-check-certificate -O /usr/bin/x-ui "https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/main/x-ui.sh"
    chmod +x /usr/bin/x-ui

    # If bundled, ensure it's executable
    if [[ -f /usr/local/x-ui/x-ui.sh ]]; then
        chmod +x /usr/local/x-ui/x-ui.sh
    fi

    # Post-install security prompts
    config_after_install

    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui

    echo -e "${green}${GITHUB_REPO} ${last_version}${plain} installation complete, panel started"
    echo -e ""
    echo -e "x-ui management script usage:"
    echo -e "----------------------------------------------"
    echo -e "x-ui              - display management menu (more features)"
    echo -e "x-ui start        - start x-ui panel"
    echo -e "x-ui stop         - stop x-ui panel"
    echo -e "x-ui restart      - restart x-ui panel"
    echo -e "x-ui status       - view x-ui status"
    echo -e "x-ui enable       - enable x-ui on startup"
    echo -e "x-ui disable      - disable x-ui on startup"
    echo -e "x-ui log          - view x-ui logs"
    echo -e "x-ui v2-ui        - migrate this machine's v2-ui account data to x-ui"
    echo -e "x-ui update       - update x-ui panel"
    echo -e "x-ui install      - install x-ui panel"
    echo -e "x-ui uninstall    - uninstall x-ui panel"
    echo -e "----------------------------------------------"
}

echo -e "${green}Start installation${plain}"
install_base
# pass through any provided args properly (none if none)
install_x_ui "$@"

