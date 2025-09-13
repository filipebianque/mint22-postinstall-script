#!/usr/bin/env bash
# Pós-instalação Linux Mint 22.2 "Zara" (Ubuntu 24.04 "noble")
# Atualizado: fail-fast, sem apt-key, WineHQ moderno, Flatpak/Flathub por padrão
# Detecta automaticamente libldap-2.x-0:i386
# Autor original citado no seu script; revisão/atualização por você.

set -euo pipefail
IFS=$'\n\t'

# ===== Utils =====
red()   { printf "\e[1;31m%s\e[0m\n" "$*"; }
green() { printf "\e[1;32m%s\e[0m\n" "$*"; }
yellow(){ printf "\e[1;33m%s\e[0m\n" "$*"; }

trap 'red "[ERRO] Linha $LINENO falhou. Verifique o log acima."' ERR

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then SUDO="sudo"; else SUDO=""; fi

START_TS="$(date +%F_%H-%M-%S)"
LOG="/tmp/postinstall_${START_TS}.log"
exec > >(tee -a "$LOG") 2>&1

clear
yellow "== Pós-instalação Linux Mint 22.2 “Zara” =="

# ===== Pré-checagens =====
REQUIRED_CMDS=(dpkg apt wget curl gpg flatpak ping)
for c in "${REQUIRED_CMDS[@]}"; do
  command -v "$c" >/dev/null || { red "[FALTA] $c não encontrado"; exit 1; }
done

yellow "Verificando conectividade..."
if ping -c 3 8.8.8.8 >/dev/null 2>&1 || ping -c 3 www.google.com >/dev/null 2>&1; then
  green "[OK] Internet disponível."
else
  red "[ERRO] Sem internet. Conecte-se e rode novamente."
  exit 1
fi

# Evita conflitos com APT em uso
if pgrep -x apt >/dev/null || pgrep -x apt-get >/dev/null || pgrep -x unattended-upgrade >/dev/null; then
  yellow "[AVISO] APT em uso. Aguardando liberar..."
  while pgrep -x apt >/dev/null || pgrep -x apt-get >/dev/null || pgrep -x unattended-upgrade >/dev/null; do
    sleep 3
  done
fi

# ===== Metadados =====
CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-noble}")"
yellow "Codinome detectado: $CODENAME"

# ===== APT básico & i386 =====
$SUDO dpkg --add-architecture i386 || true
$SUDO apt-get update -y

# ===== WineHQ repo (modo moderno, sem apt-key) =====
yellow "Configurando WineHQ para ${CODENAME}..."
$SUDO install -d -m 0755 /usr/share/keyrings
curl -fsSL https://dl.winehq.org/wine-builds/winehq.key \
  | gpg --dearmor \
  | $SUDO tee /usr/share/keyrings/winehq-archive.keyring >/dev/null

echo "deb [signed-by=/usr/share/keyrings/winehq-archive.keyring] https://dl.winehq.org/wine-builds/ubuntu/ ${CODENAME} main" \
  | $SUDO tee /etc/apt/sources.list.d/winehq-${CODENAME}.list >/dev/null

$SUDO apt-get update -y

# ===== Funções auxiliares =====
add_pkg_if_exists() {
  # Uso: add_pkg_if_exists "nome"  -> adiciona ao array BASE_PKGS se existir no APT
  local pkg="$1"
  if apt-cache policy "$pkg" 2>/dev/null | grep -q Candidate; then
    BASE_PKGS+=("$pkg")
  else
    yellow "[AVISO] Pacote não encontrado nesta release: $pkg"
  fi
}

detect_ldap_i386_pkg() {
  # Detecta libldap-2.x-0:i386 disponível (2.6 no noble, mas deixa genérico)
  apt-cache search -n '^libldap-2\..*-0:i386' \
    | awk '{print $1}' \
    | head -n1
}

# ===== Pacotes base =====
BASE_PKGS=(
  mint-meta-codecs
  build-essential
  curl wget ca-certificates gnupg
  software-properties-common
  flatpak
  p7zip-full unzip
  gufw
  flameshot
  gparted
  ratbagd piper
  steam-installer
  libvulkan1 libvulkan1:i386
  mesa-vulkan-drivers mesa-vulkan-drivers:i386
  libgnutls30:i386
  libgpg-error0:i386
  libxml2:i386
  libasound2-plugins:i386
  libsdl2-2.0-0:i386
  libfreetype6:i386
  libdbus-1-3:i386
  libsqlite3-0:i386
)

# Detecta e acrescenta libldap i386 correta
LDAP_I386_PKG="$(detect_ldap_i386_pkg || true)"
if [[ -n "${LDAP_I386_PKG:-}" ]]; then
  BASE_PKGS+=("$LDAP_I386_PKG")
  yellow "[OK] Usando $LDAP_I386_PKG"
else
  yellow "[AVISO] Nenhum libldap i386 encontrado para esta release."
fi

yellow "Instalando pacotes base..."
$SUDO apt-get install -y "${BASE_PKGS[@]}"

# ===== WineHQ estável =====
yellow "Instalando WineHQ estável (amd64 + i386)..."
$SUDO apt-get install -y --install-recommends \
  winehq-stable wine-stable wine-stable-amd64 wine-stable-i386

# ===== Flatpak & Flathub =====
if ! flatpak remote-list | grep -qi flathub; then
  yellow "Adicionando Flathub..."
  $SUDO flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

FLATPAKS=(
  com.obsproject.Studio          # OBS Studio
  com.simplenote.Simplenote      # Simplenote
  com.slack.Slack                # Slack
  com.skype.Client               # Skype
  com.spotify.Client             # Spotify
  org.videolan.VLC               # VLC
  net.lutris.Lutris              # Lutris
)
yellow "Instalando aplicativos Flatpak..."
for app in "${FLATPAKS[@]}"; do
  flatpak install -y flathub "$app" || true
done

# ===== Google Chrome (deb oficial) =====
TMPDIR="$(mktemp -d)"
yellow "Baixando Google Chrome .deb..."
CHROME_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
wget -q --show-progress -O "${TMPDIR}/google-chrome.deb" "$CHROME_URL"
yellow "Instalando Google Chrome..."
$SUDO dpkg -i "${TMPDIR}/google-chrome.deb" || $SUDO apt-get -f install -y

# ===== (Opcional) VirtualBox =====
INSTALL_VBOX=false
if $INSTALL_VBOX; then
  yellow "Instalando VirtualBox (opcional)..."
  $SUDO apt-get install -y virtualbox
fi

# ===== Pós-instalação & limpeza =====
yellow "Atualizando sistema e limpando..."
$SUDO apt-get update -y
$SUDO apt-get dist-upgrade -y
flatpak update -y || true
$SUDO apt-get autoremove -y
$SUDO apt-get autoclean -y

green "== Concluído! Log: ${LOG} =="
