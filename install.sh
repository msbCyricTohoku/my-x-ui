#!/bin/bash
set -euo pipefail

red='\033[0;31m'; green='\033[0;32m'; yellow='\033[0;33m'; plain='\033[0m'

GITHUB_OWNER="msbCyricTohoku"
GITHUB_REPO="my-x-ui"
FALLBACK_TAG="v1.0.0"

[[ ${EUID:-$(id -u)} -ne 0 ]] && echo -e "${red}Error:${plain} must run as root" && exit 1

if   [[ -f /etc/redhat-release ]]; then release="centos"
elif grep -Eqi "debian" /etc/issue 2>/dev/null; then release="debian"
elif grep -Eqi "ubuntu" /etc/issue 2>/dev/null; then release="ubuntu"
elif grep -Eqi "centos|red hat|redhat" /etc/issue 2>/dev/null; then release="centos"
elif grep -Eqi "debian" /proc/version 2>/dev/null; then release="debian"
elif grep -Eqi "ubuntu" /proc/version 2>/dev/null; then release="ubuntu"
elif grep -Eqi "centos|red hat|redhat" /proc/version 2>/dev/null; then release="centos"
else echo -e "${red}System version not detected${plain}"; exit 1; fi

arch=$(arch)
case "$arch" in
  x86_64|x64|amd64) arch="amd64" ;;
  aarch64|arm64)    arch="arm64" ;;
  s390x)            arch="s390x" ;;
  *) arch="amd64"; echo -e "${red}Unknown arch, using default: ${arch}${plain}";;
esac
echo "Architecture: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ]; then
  echo "32-bit not supported"; exit 1; fi

install_base() {
  if [[ x"${release}" == x"centos" ]]; then
    yum install -y wget curl tar unzip ca-certificates || true
    update-ca-trust || true
  else
    apt update -y && apt install -y wget curl tar unzip ca-certificates
    update-ca-certificates || true
  fi
}

config_after_install() {
  echo -e "${yellow}For security, change port and password${plain}"
  read -r -p "Continue? [y/n]: " ok
  if [[ "$ok" =~ ^[yY]$ ]]; then
    read -r -p "Account name: " u
    read -r -p "Account password: " p
    read -r -p "Panel port: " port
    /usr/local/x-ui/x-ui setting -username "$u" -password "$p"
    /usr/local/x-ui/x-ui setting -port "$port"
  else
    echo -e "${red}Skipped. Defaults kept—please change soon.${plain}"
  fi
}

resolve_version() {
  local maybe="${1:-}" tag=""
  if [[ -n "$maybe" && "$maybe" != "latest" ]]; then
    echo "$maybe"; return 0
  fi
  tag=$(curl -Ls "https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest" \
        | grep -m1 '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)
  [[ -z "$tag" || "$tag" == "null" ]] && tag="${FALLBACK_TAG}"
  echo "$tag"
}

ensure_xray_core() {
  local bindir="/usr/local/x-ui/bin"
  mkdir -p "$bindir"

  local core_file_linux="xray-linux-${arch}"
  local core_path_linux="${bindir}/${core_file_linux}"
  local stable_path="${bindir}/xray"

  # If tar contained the arch specific core, make it exec
  if [[ -f "${core_path_linux}" ]]; then
    chmod +x "${core_path_linux}" || true
  fi

  # If neither stable nor arch file exists, fetch from XTLS
  if [[ ! -x "${stable_path}" && ! -x "${core_path_linux}" ]]; then
    echo "Xray core not found in release; downloading core…"
    local zip url
    case "$arch" in
      amd64) zip="Xray-linux-64.zip" ;;
      arm64) zip="Xray-linux-arm64-v8a.zip" ;;
      s390x) zip="Xray-linux-s390x.zip" ;;
      *)     zip="Xray-linux-64.zip" ;;
    esac
    url="https://github.com/XTLS/Xray-core/releases/latest/download/${zip}"
    curl -L -o "${bindir}/xray.zip" "$url"
    unzip -j "${bindir}/xray.zip" xray -d "${bindir}"
    rm -f "${bindir}/xray.zip"
    chmod +x "${stable_path}"
    ln -sf "xray" "${core_path_linux}"
  fi

  # Ensure stable name exists and points to the arch file when present
  if [[ -x "${core_path_linux}" ]]; then
    ln -sf "${core_file_linux}" "${stable_path}"
  fi

  if [[ ! -x "${stable_path}" ]]; then
    echo -e "${red}Failed to prepare Xray core at ${stable_path}${plain}"
    exit 1
  fi
}

install_x_ui() {
  systemctl stop x-ui 2>/dev/null || true
  cd /usr/local/

  local requested="${1:-}" last_version
  last_version="$(resolve_version "$requested")"
  echo -e "Installing ${green}${GITHUB_REPO}${plain} version ${green}${last_version}${plain}"

  local url="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"
  echo "Downloading: $url"
  wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz "$url"

  rm -rf /usr/local/x-ui /usr/local/x-ui-tmp
  mkdir -p /usr/local/x-ui-tmp
  tar zxvf /usr/local/x-ui-linux-${arch}.tar.gz -C /usr/local/x-ui-tmp
  rm -f /usr/local/x-ui-linux-${arch}.tar.gz

  # Allow either "x-ui/..." or flat files in the tarball
  if [[ -d /usr/local/x-ui-tmp/x-ui ]]; then
    mv /usr/local/x-ui-tmp/x-ui /usr/local/x-ui
  else
    mkdir -p /usr/local/x-ui
    shopt -s dotglob nullglob
    mv /usr/local/x-ui-tmp/* /usr/local/x-ui/
    shopt -u dotglob nullglob
  fi
  rm -rf /usr/local/x-ui-tmp
  cd /usr/local/x-ui

  # Permissions
  [[ -f x-ui ]] && chmod +x x-ui
  [[ -f "bin/xray-linux-${arch}" ]] && chmod +x "bin/xray-linux-${arch}"
  [[ -f x-ui.sh ]] && chmod +x x-ui.sh

  # Service & CLI
  [[ -f x-ui.service ]] && cp -f x-ui.service /etc/systemd/system/
  if [[ -f /usr/local/x-ui/x-ui.sh ]]; then
    cp -f /usr/local/x-ui/x-ui.sh /usr/bin/x-ui && chmod +x /usr/bin/x-ui
  else
    wget --no-check-certificate -O /usr/bin/x-ui "https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/main/x-ui.sh"
    chmod +x /usr/bin/x-ui
  fi

  # Ensure the core exists at a stable path
  ensure_xray_core

  config_after_install

  systemctl daemon-reload
  systemctl enable x-ui
  systemctl start x-ui

  echo -e "${green}${GITHUB_REPO} ${last_version}${plain} installation complete, panel started"
  echo -e "Use: x-ui | start | stop | restart | status | enable | disable | log | update | install | uninstall"
}

echo -e "${green}Start installation${plain}"
install_base
install_x_ui "${1:-}"

