#!/usr/bin/env bash
# Exportacao NAO DESTRUTIVA de configuracoes do ambiente Hyprland.
# Uso: bash exportar_hyprland.sh [diretorio-de-saida]
# Executar na maquina de ORIGEM, com o usuario normal (sem sudo).
set -Eeuo pipefail
umask 077

if [[ "${EUID}" -eq 0 ]]; then
  printf 'ERRO: execute como seu usuario normal, sem sudo.\n' >&2
  exit 1
fi
if [[ -z "${HOME:-}" || ! -d "$HOME" ]]; then
  printf 'ERRO: HOME nao definido corretamente.\n' >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
DEFAULT_DIR="$HOME/hyprland-export-$STAMP"
OUT="${1:-$DEFAULT_DIR}"
if [[ -e "$OUT" ]]; then
  printf 'ERRO: a pasta de destino ja existe: %s\n' "$OUT" >&2
  exit 1
fi
mkdir -p -- "$OUT"/{inventario,home,relatorios}
OUT="$(cd -- "$OUT" && pwd -P)"
INVENTORY="$OUT/inventario"

printf '\n=== Exportacao Hyprland: %s ===\n' "$STAMP"
printf 'Destino: %s\n' "$OUT"
printf 'Somente leitura da configuracao atual; nenhuma instalacao sera realizada.\n\n'

# A falha ou ausencia de um comando de inventario nao interrompe o restante.
capture() {
  local name="$1"; shift
  if command -v -- "$1" >/dev/null 2>&1; then
    "$@" > "$INVENTORY/$name" 2>&1 || printf 'Aviso: falha parcial em %s\n' "$name" >&2
  else
    printf 'Comando indisponivel: %s\n' "$1" > "$INVENTORY/$name"
  fi
}

printf '[1/5] Inventariando distribuicao, aplicativos e drivers...\n'
{
  printf 'Data: %s\n' "$(date -Is)"
  printf 'Usuario: %s\n' "$(id -un)"
  printf 'Hostname: %s\n' "$(hostname)"
  printf 'Sessao: %s\n' "${XDG_CURRENT_DESKTOP:-desconhecido}"
  printf 'Tipo de sessao: %s\n' "${XDG_SESSION_TYPE:-desconhecido}"
  printf 'Kernel: %s\n' "$(uname -r)"
  [[ -f /etc/os-release ]] && cat /etc/os-release
} > "$INVENTORY/sistema.txt"
capture pacotes-rpm-completos.tsv rpm -qa --qf $'%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\n'
if command -v rpm >/dev/null 2>&1; then
  rpm -qa --qf '%{NAME}\n' | LC_ALL=C sort -u > "$INVENTORY/pacotes-rpm-nomes.txt"
fi
if command -v dnf >/dev/null 2>&1; then
  capture pacotes-dnf-userinstalled.txt dnf repoquery --userinstalled
  capture repositorios-dnf.txt dnf repolist --enabled
fi
if command -v flatpak >/dev/null 2>&1; then
  capture flatpak-aplicativos.tsv flatpak list --app --columns=application,origin,installation,arch,branch
  capture flatpak-remotos.txt flatpak remotes --show-details
fi
capture pacotes-cargo.txt cargo install --list
capture versao-rust.txt rustc --version
capture versao-cargo.txt cargo --version
capture asdf-plugins.txt asdf plugin list --urls
capture asdf-versoes.txt asdf current
capture versao-hyprland.txt hyprctl version
capture plugins-hyprland.txt hyprctl plugins list
capture gpu-lspci.txt lspci -nnk
capture gpu-nvidia.txt nvidia-smi

printf '[2/5] Inventariando aplicativos Hyprland, Alt+Tab e systemd...\n'
{
  for bin in Hyprland hyprctl hyprshell waybar hyprpaper swww swaybg waypaper rofi wofi fuzzel walker wlogout swaync mako dunst ghostty kitty foot alacritty grim slurp swappy hyprshot grimblast wl-copy cliphist nm-applet blueman-applet hypridle hyprlock hyprsunset; do
    printf '%-20s ' "$bin"
    command -v "$bin" 2>/dev/null || printf '(nao encontrado no PATH)\n'
  done
  printf '\nCandidatos do Hyprshell na pasta asdf/rust:\n'
  if [[ -d "$HOME/.asdf/installs/rust" ]]; then
    find "$HOME/.asdf/installs/rust" -maxdepth 4 -type f -name hyprshell -print 2>/dev/null || true
  fi
  printf '\nHyprshell no PATH:\n'
  hyprshell --version 2>&1 || true
} > "$INVENTORY/executaveis-e-hyprshell.txt"
capture systemd-user-habilitados.txt systemctl --user list-unit-files --type=service --state=enabled --no-pager
capture systemd-user-rodando.txt systemctl --user list-units --type=service --state=running --no-pager
capture systemd-hyprshell.txt systemctl --user list-unit-files 'hyprshell*' --no-pager

printf '[3/5] Copiando configuracoes selecionadas, temas, fontes e wallpapers...\n'
# Relativos ao HOME. Configuracoes de apps fora do ecossistema desktop ficam
# apenas no inventario, nao sao copiadas indiscriminadamente.
PATHS=(
  .config/hypr
  .config/waybar
  .config/hyprshell
  .config/hyprpaper
  .config/hypridle
  .config/hyprlock
  .config/hyprsunset
  .config/waypaper
  .config/swww
  .config/swaybg
  .config/swaync
  .config/mako
  .config/dunst
  .config/rofi
  .config/wofi
  .config/fuzzel
  .config/walker
  .config/wlogout
  .config/ghostty
  .config/kitty
  .config/foot
  .config/alacritty
  .config/gtk-3.0
  .config/gtk-4.0
  .config/qt5ct
  .config/qt6ct
  .config/Kvantum
  .config/nwg-look
  .config/Thunar
  .config/systemd/user
  .config/fontconfig
  .config/fastfetch
  .local/share/fonts
  .local/share/icons
  .local/share/themes
  .local/share/wallpapers
  .local/share/backgrounds
  .fonts
  .icons
  .themes
  Pictures/Wallpapers
  Pictures/wallpapers
  Pictures/Backgrounds
  Pictures/backgrounds
  Imagens/Wallpapers
  Imagens/Papeis\ de\ Parede
  Wallpapers
  wallpapers
  Backgrounds
  .tool-versions
  .gtkrc-2.0
)
FOUND=()
for rel in "${PATHS[@]}"; do
  if [[ -e "$HOME/$rel" || -L "$HOME/$rel" ]]; then
    FOUND+=("$rel")
  fi
done
printf '%s\n' "${FOUND[@]}" > "$INVENTORY/caminhos-incluidos.txt"
if (( ${#FOUND[@]} > 0 )); then
  # NAO seguir links simbolicos. Excluir nomes comuns de segredos/cache.
  tar -C "$HOME" -cf - \
    --exclude='*/.git' \
    --exclude='*/cache' \
    --exclude='*/Cache' \
    --exclude='*/node_modules' \
    --exclude='*/target' \
    --exclude='*/.env' \
    --exclude='*/.env.*' \
    --exclude='*.pem' \
    --exclude='*.key' \
    --exclude='*.p12' \
    --exclude='*.pfx' \
    --exclude='id_rsa*' \
    --exclude='id_ed25519*' \
    --exclude='*credentials*' \
    --exclude='*secret*' \
    --exclude='*token*' \
    --exclude='*password*' \
    --exclude='*passwd*' \
    -- "${FOUND[@]}" | tar -C "$OUT/home" -xf -
fi

# Scripts personalizados podem estar fora da pasta Hyprland.
# Listamos todos, mas copiamos automaticamente apenas nomes relacionados ao desktop.
if [[ -d "$HOME/.local/bin" ]]; then
  find "$HOME/.local/bin" -maxdepth 1 \( -type f -o -type l \) -printf '%f\n' \
    | LC_ALL=C sort > "$INVENTORY/local-bin-nomes.txt"
  mkdir -p "$OUT/home/.local/bin"
  while IFS= read -r name; do
    case "${name,,}" in
      *hypr*|*waybar*|*wallpaper*|*screenshot*|*screen-shot*|*rofi*|*wofi*|*fuzzel*|*swww*|*swaync*|*lockscreen*|*powermenu*|*power-menu*)
        [[ -f "$HOME/.local/bin/$name" && ! -L "$HOME/.local/bin/$name" ]] || continue
        if [[ $(stat -c %s -- "$HOME/.local/bin/$name") -le 1048576 ]]; then
          cp -p -- "$HOME/.local/bin/$name" "$OUT/home/.local/bin/$name"
        fi
        ;;
    esac
  done < "$INVENTORY/local-bin-nomes.txt"
fi

printf '[4/5] Gerando pistas para localizar referencias externas e revisar segredos...\n'
{
  for dir in "$HOME/.config/hypr" "$HOME/.config/hyprpaper" "$HOME/.config/waypaper" "$HOME/.config/waybar" "$HOME/.config/hyprshell"; do
    if [[ -d "$dir" ]]; then
      grep -RInE --exclude='*.png' --exclude='*.jpg' --exclude='*.jpeg' --exclude='*.webp' \
        '(wallpaper|background|swww|swaybg|hyprpaper|exec-once|^exec[[:space:]]*=|hyprshell|image)' "$dir" 2>/dev/null || true
    fi
  done
} > "$INVENTORY/referencias-desktop.txt"
if [[ -d "$HOME/.config" ]]; then
  find "$HOME/.config" -mindepth 1 -maxdepth 1 -printf '%f\n' \
    | LC_ALL=C sort > "$INVENTORY/outras-pastas-config.txt"
fi
{
  printf 'Arquivos que podem conter credenciais. Revise antes de compartilhar!\n'
  if [[ -d "$OUT/home" ]]; then
    grep -RIlE -i '(api[_-]?key|access[_-]?token|client[_-]?secret|password|passwd|bearer[[:space:]]|authorization)' "$OUT/home" 2>/dev/null || true
  fi
} > "$OUT/relatorios/revisar-possiveis-segredos.txt"

cat > "$OUT/LEIA-ME.txt" <<'README'
EXPORTACAO DO AMBIENTE HYPRLAND
================================
Este pacote registra os softwares instalados e copia SOMENTE configuracoes
selecionadas do ambiente desktop: Hyprland, Waybar, Hyprshell, temas, fontes,
wallpapers e componentes relacionados.

NENHUM programa foi instalado, removido ou modificado na maquina de origem.

ESTRUTURA
- inventario/: pacotes RPM, Flatpak, Cargo, asdf, executaveis,
  servicos de usuario, repositorios e referencias a wallpapers.
- home/: arquivos a transferir para a HOME do novo usuario (apos revisao).
- relatorios/: lista de arquivos que TALVEZ contenham credenciais.

LIMITACOES / SEGURANCA
- Nao contem todo o sistema operacional ou todas as configuracoes de apps.
- Nao copia drivers, binarios compilados nem conteudo de /etc.
- Caminhos de wallpaper externos aos diretorios padrao podem faltar.
- O filtro por nome de arquivo NAO garante remocao de todas as credenciais.
- Revise arquivos em home/, relatorios/revisar-possiveis-segredos.txt e
  inventario/referencias-desktop.txt antes de compartilhar o pacote.
- Campos e scripts podem conter nome do usuario ou caminhos absolutos.
- Nao restaure cegamente arquivos de display/monitores ou servicos systemd:
  eles podem depender do hardware e paths da maquina antiga.
- No desktop Fedora 45 / NVIDIA RTX 4060 Ti, instalar e validar o driver
  NVIDIA e o ambiente Wayland/Hyprland antes de restaurar as configuracoes.
README

printf '[5/5] Empacotando...\n'
ARCHIVE="$OUT.tar.gz"
if [[ -e "$ARCHIVE" ]]; then
  printf 'ERRO: o arquivo de saida ja existe: %s\n' "$ARCHIVE" >&2
  exit 1
fi
tar -C "$(dirname -- "$OUT")" -czf "$ARCHIVE" -- "$(basename -- "$OUT")"
chmod 600 "$ARCHIVE"
printf '\nExportacao concluida.\n'
printf 'Diretorio: %s\n' "$OUT"
printf 'Arquivo:   %s\n' "$ARCHIVE"
printf 'Tamanho:   '
du -h "$ARCHIVE" | awk '{print $1}'
printf '\nATENCAO: reveja possiveis segredos em:\n  %s\n' "$OUT/relatorios/revisar-possiveis-segredos.txt"
printf 'Envie primeiro os arquivos de inventario, nao o pacote completo,\npara planejarmos a restauracao segura no Fedora 45.\n'
