#!/bin/bash
set -euo pipefail

red='\033[0;31m'; green='\033[0;32m'; yellow='\033[0;33m'; plain='\033[0m'

# ====== customize these if you ever move repos ======
GITHUB_OWNER="msbCyricTohoku"
GITHUB_REPO="my-x-ui"
FALLBACK_TAG="v1.0.0"   # used if GitHub API "latest" check fails
# ====================================================

# check root
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo -e "${red}Error:${plain} must run this script as root!\n"; exit 1
fi

# detect distro
if   [[ -f /etc/redhat-release ]]; then release="centos"
elif grep -Eqi "debian" /etc/issue 2>/dev/null; then release="debian"
elif grep -Eqi "ubuntu" /etc/issue 2>/dev/null; then release="ubuntu"
elif grep -Eqi "centos|red hat|redhat" /etc/issue 2>/dev/null; then release="centos"
elif grep -Eqi "debian" /proc/version 2>/dev/null; then release="debian"
elif grep -Eqi "ubuntu" /proc/version 2>/dev/null; then release="ubuntu"
elif grep -Eqi "centos|red hat|redhat" /proc/version 2>/dev/null; then release="centos"
else echo -e "${red}System version not detected${plain}"; exit 1; fi

# arch
arch=$(arch)
case "$arch" in
  x86_64|x64|amd64) arch="amd64" ;;
  aarch64|arm64)    arch="arm64" ;;
  s390x)            arch="s390x" ;;
  *) arch="amd64"; echo -e "${red}Unknown arch, using default: ${arch}${plain}";;
esac
echo "Architecture: ${arch}"

# 64-bit check
if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ]; then
  echo "This software does not support 32-bit systems."; exit 1; fi

# minimal deps
install_base() {
  if [[ x"${release}" == x"centos" ]]; then
    yum install -y wget curl tar
  else
    apt update -y && apt install -y wget curl tar
  fi
}

config_after_install() {
  echo -e "${yellow}For security, change the port and account password after installation/update${plain}"
  read -r -p "Continue? [y/n]: " config_confirm
  if [[ x"${config_confirm}" == x"y" || x"${config_confirm}" == x"Y" ]]; then
    read -r -p "Please set your account name: " config_account
    echo -e "${yellow}Your account name will be set to: ${config_account}${plain}"
    read -r -p "Please set your account password: " config_password
    echo -e "${yellow}Your account password will be set to: ${config_password}${plain}"
    read -r -p "Please set the panel access port: " config_port
    echo -e "${yellow}Your panel access port will be set to: ${config_port}${plain}"
    echo -e "${yellow}Confirming settings${plain}"
    /usr/local/x-ui/x-ui setting -username "${config_account}" -password "${config_password}"
    echo -e "${yellow}Account and password set${plain}"
    /usr/local/x-ui/x-ui setting -port "${config_port}"
    echo -e "${yellow}Panel port set${plain}"
  else
    echo -e "${red}Cancelled, defaults kept. Please modify promptly.${plain}"
  fi
}

resolve_version() {
  local maybe="${1:-}" tag=""
  if [[ -n "${maybe}" && "${maybe}" != "latest" ]]; then
    echo "${maybe}"; return 0
  fi
  local api_url="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest"
  tag=$(curl -Ls "${api_url}" | grep -m1 '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)
  if [[ -z "${tag}" || "${tag}" == "null" ]]; then
    echo -e "${yellow}Warning:${plain} Could not determine latest tag from API. Falling back to ${green}${FALLBACK_TAG}${plain}."
    tag="${FALLBACK_TAG}"
  fi
  echo "${tag}"
}

install_x_ui() {
  systemctl stop x-ui 2>/dev/null || true
  cd /usr/local/ || exit 1

  local requested="${1:-}" last_version
  last_version="$(resolve_version "${requested}")"
  echo -e "Installing ${green}${GITHUB_REPO}${plain} version ${green}${last_version}${plain}"

  local asset_url="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"
  echo "Downloading: ${asset_url}"
  wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz "${asset_url}"

  # Clean target; extract to temp
  rm -rf /usr/local/x-ui/
  mkdir -p /usr/local/x-ui-tmp
  tar zxvf /usr/local/x-ui-linux-${arch}.tar.gz -C /usr/local/x-ui-tmp
  rm -f /usr/local/x-ui-linux-${arch}.tar.gz

  # Handle both archive layouts:
  # 1) wrapped: /usr/local/x-ui-tmp/x-ui/<files>
  # 2) flat:    /usr/local/x-ui-tmp/<files>
  if [[ -d /usr/local/x-ui-tmp/x-ui ]]; then
    mv /usr/local/x-ui-tmp/x-ui /usr/local/x-ui
    rm -rf /usr/local/x-ui-tmp
  else
    mkdir -p /usr/local/x-ui
    shopt -s dotglob nullglob
    mv /usr/local/x-ui-tmp/* /usr/local/x-ui/
    shopt -u dotglob nullglob
    rm -rf /usr/local/x-ui-tmp
  fi

  cd /usr/local/x-ui

  # Ensure executables
  [[ -f x-ui ]] && chmod +x x-ui
  if [[ -f "bin/xray-linux-${arch}" ]]; then chmod +x "bin/xray-linux-${arch}"; fi
  if [[ -f x-ui.sh ]]; then chmod +x x-ui.sh; fi

  # Install/refresh service
  if [[ -f x-ui.service ]]; then
    cp -f x-ui.service /etc/systemd/system/
  fi

  # Install helper script to PATH (from your repo if not bundled)
  if [[ -f /usr/local/x-ui/x-ui.sh ]]; then
    cp -f /usr/local/x-ui/x-ui.sh /usr/bin/x-ui
    chmod +x /usr/bin/x-ui
  else
    wget --no-check-certificate -O /usr/bin/x-ui "https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/main/x-ui.sh"
    chmod +x /usr/bin/x-ui
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
install_x_ui "${1:-}"

