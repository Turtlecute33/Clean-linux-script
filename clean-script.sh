#!/usr/bin/env bash
#
# ###################################################################################
# ##                                                                               ##
# ##              ✨🛡️ Smart Linux System Cleaner (Enhanced) 🛡️✨                  ##
# ##                                                                               ##
# ###################################################################################
#
# Purpose:
#   1. Update/Upgrade system packages for apt, dnf, yum, zypper, or Nix.
#   2. Remove old/unused packages (orphans) and old kernels safely.
#   3. Clean package caches, systemd journal logs, temporary directories,
#      user caches, Flatpak/Snap leftovers, and Docker resources.
#   4. Additional cleaning: browser caches, recent files, clipboard history,
#      application logs, and more (inspired by BleachBit).
#
# Warning:
#   This script performs potentially destructive operations. Review carefully.
#   Create backups of important data before running.
#   The most dangerous operations require interactive confirmation.
#
# Supported Package Managers: apt, dnf, yum, zypper, nix, pacman
# Supported Additional Systems: Flatpak, Snap, Docker, AppImage
# ###################################################################################

# ============================================================================
# CONFIGURATION SECTION
# ============================================================================

# Kernel and Package Management
KEEP_KERNELS=2                        # Number of recent kernels to keep

# Log Management
JOURNAL_VACUUM_TIME="3d"              # Max age for systemd journal logs
JOURNAL_VACUUM_SIZE="500M"            # Max size for journal logs
CLEAN_APPLICATION_LOGS=true           # Clean logs in ~/.local/share/*/logs
APP_LOG_MAX_AGE_DAYS=30               # Max age for application logs

# Temporary Files
TMP_FILE_MAX_AGE_DAYS=7               # Max age for files in /tmp and /var/tmp

# User Cache Management
CLEAN_USER_CACHE_FILES=true           # Clean general cache files in ~/.cache
USER_CACHE_MAX_AGE_DAYS=14            # Cache retention in days
CLEAN_THUMBNAILS=true                 # Clean thumbnail cache
CLEAN_TRASH=true                      # Empty user trash

# Browser Cache and History
CLEAN_BROWSER_CACHE=false             # Clean browser caches (Firefox, Chrome, Chromium)
CLEAN_BROWSER_HISTORY=false           # ⚠️ Clean browser history
BROWSER_CACHE_MAX_AGE_DAYS=30         # Max age for browser cache files

# Desktop Environment
CLEAN_RECENT_DOCUMENTS=false          # Clear recent documents list
CLEAN_CLIPBOARD_HISTORY=false         # Clear clipboard managers (Klipper, Clipman, etc.)

# Docker Configuration
CLEAN_DOCKER=true                     # Enable Docker cleanup
CLEAN_DOCKER_VOLUMES=false            # ⚠️ DANGER: Prune unused Docker volumes
CLEAN_DOCKER_BUILDER_CACHE=false     # Clean Docker builder cache

# Package Manager Cache
AGGRESSIVE_PKG_CACHE_CLEAN=false      # More aggressive package cache cleaning

# Backup Configuration
CREATE_BACKUP_LIST=false              # Create a list of files to be deleted before deletion
BACKUP_LIST_DIR="/var/log/system-cleaner"  # Where to store backup lists

# Dry Run Mode
DRY_RUN=false                         # Set to true to see what would be deleted without deleting

# ============================================================================
# END CONFIGURATION
# ============================================================================

# Script Setup
set -eo pipefail  # Exit on critical errors, but allow individual command failures
IFS=$'\n\t'

# Global Variables
SCRIPT_VERSION="2.0.0"
SCRIPT_START_TIME=$(date +%s)
TOTAL_FREED_SPACE=0

# Color Definitions
if [[ -t 1 ]]; then
  CLR_RESET='\e[0m'; CLR_RED='\e[0;31m'; CLR_GREEN='\e[0;32m'
  CLR_YELLOW='\e[0;33m'; CLR_BLUE='\e[0;34m'; CLR_PURPLE='\e[0;35m'
  CLR_CYAN='\e[0;36m'; CLR_BOLD='\e[1m'; CLR_DIM='\e[2m'
else
  CLR_RESET=''; CLR_RED=''; CLR_GREEN=''; CLR_YELLOW=''
  CLR_BLUE=''; CLR_PURPLE=''; CLR_CYAN=''; CLR_BOLD=''; CLR_DIM=''
fi

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

msg() { echo -e "${CLR_BLUE}${CLR_BOLD}>>>${CLR_RESET} ${CLR_BOLD}${*}${CLR_RESET}"; }
msg_sub() { echo -e "  ${CLR_CYAN}==>${CLR_RESET} ${*}"; }
msg_warn() { echo -e "${CLR_YELLOW}${CLR_BOLD}⚠️  Warning:${CLR_RESET} ${CLR_YELLOW}${*}${CLR_RESET}"; }
msg_info() { echo -e "  ${CLR_PURPLE}::${CLR_RESET} ${*}"; }
msg_ok() { echo -e "${CLR_GREEN}${CLR_BOLD}✔  OK:${CLR_RESET} ${CLR_GREEN}${*}${CLR_RESET}"; }
msg_err() { echo -e "${CLR_RED}${CLR_BOLD}❌ Error:${CLR_RESET} ${CLR_RED}${*}${CLR_RESET}" >&2; }
msg_debug() {
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo -e "${CLR_DIM}[DEBUG] ${*}${CLR_RESET}"
  fi
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Ensure root privileges
check_root() {
  if [[ $EUID -ne 0 ]]; then
    if ! command -v sudo &>/dev/null && ! command -v doas &>/dev/null; then
      msg_err "This script requires root privileges."
      msg_err "Please run as root or install sudo/doas."
      exit 1
    fi
    if command -v doas &>/dev/null; then
      msg_warn "This script needs root privileges. Using 'doas' for privilege escalation."
    else
      msg_warn "This script needs root privileges. Using 'sudo' for privilege escalation."
    fi
    msg_warn "You may be prompted for a password."
  fi
}

# Cleanup function
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    msg_err "Script encountered an error. Exit code: $exit_code"
  fi
  echo -e "${CLR_RESET}"
}
trap cleanup EXIT

# Execute commands with privilege escalation if needed
run_sudo() {
  if [[ $EUID -ne 0 ]]; then
    if command -v sudo &>/dev/null; then
      sudo "$@"
    elif command -v doas &>/dev/null; then
      doas "$@"
    else
      msg_err "Not running as root and neither sudo nor doas found."
      msg_err "Please run as root or install sudo/doas."
      exit 1
    fi
  else
    "$@"
  fi
}

# Get the home directory of the user who invoked sudo/doas
get_real_home() {
  if [[ $EUID -eq 0 ]]; then
    local real_user=""
    if [[ -n "${SUDO_USER:-}" ]]; then
      real_user="${SUDO_USER}"
    elif [[ -n "${DOAS_USER:-}" ]]; then
      real_user="${DOAS_USER}"
    fi
    
    if [[ -n "$real_user" ]]; then
      getent passwd "${real_user}" | cut -d: -f6
    else
      echo "${HOME}"
    fi
  else
    echo "${HOME}"
  fi
}

# Get the real user name
get_real_user() {
  if [[ $EUID -eq 0 ]]; then
    if [[ -n "${SUDO_USER:-}" ]]; then
      echo "${SUDO_USER}"
    elif [[ -n "${DOAS_USER:-}" ]]; then
      echo "${DOAS_USER}"
    else
      whoami
    fi
  else
    whoami
  fi
}

# Interactive confirmation
confirm() {
  local prompt="${1}"
  local default="${2:-n}"
  local response

  if [[ "${default,,}" == "y" ]]; then
    read -rp "$(echo -e "${CLR_YELLOW}❓ ${prompt} (Y/n): ${CLR_RESET}")" response
    response="${response:-y}"
  else
    read -rp "$(echo -e "${CLR_YELLOW}❓ ${prompt} (y/N): ${CLR_RESET}")" response
    response="${response:-n}"
  fi

  [[ "${response,,}" == "y" ]]
}

# Calculate directory size
get_dir_size() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    du -sb "$dir" 2>/dev/null | awk '{print $1}' || echo 0
  else
    echo 0
  fi
}

# Format bytes to human readable
format_bytes() {
  local bytes=$1
  if [[ $bytes -lt 1024 ]]; then
    echo "${bytes}B"
  elif [[ $bytes -lt 1048576 ]]; then
    echo "$(( bytes / 1024 ))KB"
  elif [[ $bytes -lt 1073741824 ]]; then
    echo "$(( bytes / 1048576 ))MB"
  else
    echo "$(( bytes / 1073741824 ))GB"
  fi
}

# Calculate freed space
calculate_freed() {
  local before=${1:-0}
  local after=${2:-0}
  local freed=0
  
  # Ensure we have valid numbers
  if [[ "$before" =~ ^[0-9]+$ ]] && [[ "$after" =~ ^[0-9]+$ ]]; then
    freed=$(( before - after ))
    if [[ $freed -gt 0 ]]; then
      TOTAL_FREED_SPACE=$(( TOTAL_FREED_SPACE + freed ))
      msg_ok "Freed $(format_bytes $freed)"
    fi
  fi
}

# Create backup list directory
init_backup_list() {
  if [[ "$CREATE_BACKUP_LIST" == "true" ]]; then
    run_sudo mkdir -p "$BACKUP_LIST_DIR"
    BACKUP_FILE="${BACKUP_LIST_DIR}/cleanup-$(date +%Y%m%d-%H%M%S).log"
    run_sudo touch "$BACKUP_FILE"
    msg_info "Backup list: $BACKUP_FILE"
  fi
}

# Log file to backup list
log_to_backup() {
  if [[ "$CREATE_BACKUP_LIST" == "true" && -n "${BACKUP_FILE:-}" ]]; then
    echo "$1" | run_sudo tee -a "$BACKUP_FILE" > /dev/null
  fi
}

# Safe delete with logging
safe_delete() {
  local target="$1"
  local description="${2:-}"

  if [[ ! -e "$target" ]]; then
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    msg_info "[DRY RUN] Would delete: $target"
    return 0
  fi

  log_to_backup "$target ${description}"

  if [[ -d "$target" ]]; then
    rm -rf "$target" 2>/dev/null || true
  else
    rm -f "$target" 2>/dev/null || true
  fi
}

# Detect package manager
detect_package_manager() {
  if command -v apt-get &>/dev/null; then echo "apt"
  elif command -v dnf &>/dev/null; then echo "dnf"
  elif command -v yum &>/dev/null; then echo "yum"
  elif command -v zypper &>/dev/null; then echo "zypper"
  elif command -v pacman &>/dev/null; then echo "pacman"
  elif command -v nix-env &>/dev/null; then echo "nix"
  else echo "unknown"
  fi
}

# Check if command exists
has_command() {
  command -v "$1" &>/dev/null
}

# ============================================================================
# PACKAGE MANAGEMENT FUNCTIONS
# ============================================================================

update_repos() {
  msg "[1/13] Updating package repositories..."
  case "$PM" in
    apt)
      run_sudo apt-get update
      ;;
    dnf)
      run_sudo dnf check-update || true
      ;;
    yum)
      run_sudo yum check-update || true
      ;;
    zypper)
      run_sudo zypper --non-interactive refresh
      ;;
    pacman)
      run_sudo pacman -Sy
      ;;
    nix)
      run_sudo nix-channel --update
      msg_info "Nix channels updated."
      ;;
    *)
      msg_warn "Unsupported package manager ($PM) for repository update."
      ;;
  esac
}

upgrade_packages() {
  msg "[2/13] Upgrading system packages..."
  case "$PM" in
    apt)
      run_sudo apt-get -y upgrade
      ;;
    dnf)
      run_sudo dnf -y upgrade
      ;;
    yum)
      run_sudo yum -y update
      ;;
    zypper)
      run_sudo zypper --non-interactive update
      ;;
    pacman)
      run_sudo pacman -Syu --noconfirm
      ;;
    nix)
      msg_info "Skipping automatic Nix upgrade."
      msg_info "Run 'nixos-rebuild switch --upgrade' or 'nix-env -u \"*\"' manually."
      ;;
    *)
      msg_warn "Unsupported package manager ($PM) for package upgrade."
      ;;
  esac
}

remove_orphans() {
  msg "[3/13] Removing orphaned/unneeded packages..."
  local before after
  before=$(df / | tail -1 | awk '{print $3}')

  case "$PM" in
    apt)
      run_sudo apt-get -y autoremove --purge
      ;;
    dnf)
      run_sudo dnf -y autoremove
      ;;
    yum)
      if has_command package-cleanup; then
        run_sudo package-cleanup --leaves --exclude-bin || true
        run_sudo package-cleanup --orphans || true
      else
        msg_warn "'package-cleanup' (from yum-utils) not found. Skipping."
      fi
      ;;
    zypper)
      local unneeded_packages
      unneeded_packages=$(zypper packages --unneeded | awk -F '|' 'NR > 4 {gsub(/^[ \t]+|[ \t]+$/, "", $3); if ($3 != "") print $3}')
      if [[ -n "$unneeded_packages" ]]; then
        msg_info "Found unneeded packages to remove"
        echo "$unneeded_packages" | xargs -r run_sudo zypper --non-interactive remove --clean-deps
      else
        msg_info "No unneeded packages found."
      fi
      ;;
    pacman)
      local orphans
      orphans=$(pacman -Qtdq 2>/dev/null || true)
      if [[ -n "$orphans" ]]; then
        echo "$orphans" | run_sudo pacman -Rns --noconfirm -
      else
        msg_info "No orphaned packages found."
      fi
      ;;
    nix)
      msg_info "Running Nix garbage collection..."
      run_sudo nix-collect-garbage -d
      ;;
    *)
      msg_warn "Unsupported package manager ($PM) for orphan removal."
      ;;
  esac

  after=$(df / | tail -1 | awk '{print $3}')
  calculate_freed "$before" "$after"
}

clean_package_cache() {
  msg "[4/13] Cleaning package cache..."
  local before=0 after=0 cache_dir=""

  case "$PM" in
    apt)
      cache_dir="/var/cache/apt/archives"
      before=$(get_dir_size "$cache_dir") || before=0
      run_sudo apt-get clean || msg_warn "apt-get clean failed, continuing..."
      if [[ "$AGGRESSIVE_PKG_CACHE_CLEAN" == "true" ]]; then
        run_sudo apt-get autoclean || msg_warn "apt-get autoclean failed, continuing..."
      fi
      after=$(get_dir_size "$cache_dir") || after=0
      calculate_freed "$before" "$after"
      ;;
    dnf)
      cache_dir="/var/cache/dnf"
      before=$(get_dir_size "$cache_dir") || before=0
      run_sudo dnf clean all || msg_warn "dnf clean failed, continuing..."
      after=$(get_dir_size "$cache_dir") || after=0
      calculate_freed "$before" "$after"
      ;;
    yum)
      cache_dir="/var/cache/yum"
      before=$(get_dir_size "$cache_dir") || before=0
      run_sudo yum clean all || msg_warn "yum clean failed, continuing..."
      after=$(get_dir_size "$cache_dir") || after=0
      calculate_freed "$before" "$after"
      ;;
    zypper)
      cache_dir="/var/cache/zypp"
      before=$(get_dir_size "$cache_dir") || before=0
      run_sudo zypper clean --all || msg_warn "zypper clean failed, continuing..."
      after=$(get_dir_size "$cache_dir") || after=0
      calculate_freed "$before" "$after"
      ;;
    pacman)
      cache_dir="/var/cache/pacman/pkg"
      before=$(get_dir_size "$cache_dir") || before=0
      if [[ "$AGGRESSIVE_PKG_CACHE_CLEAN" == "true" ]]; then
        # Remove all cached packages
        run_sudo pacman -Scc --noconfirm || msg_warn "pacman cache clean failed, continuing..."
      else
        # Keep 3 most recent versions
        if has_command paccache; then
          run_sudo paccache -rk3 || msg_warn "paccache failed, continuing..."
        else
          msg_warn "paccache not found. Consider installing 'pacman-contrib'."
        fi
      fi
      after=$(get_dir_size "$cache_dir") || after=0
      calculate_freed "$before" "$after"
      ;;
    nix)
      msg_info "Running nix-store --optimise..."
      run_sudo nix-store --optimise || msg_warn "nix-store optimise failed, continuing..."
      ;;
    *)
      msg_warn "Unsupported package manager ($PM) for cache cleaning."
      ;;
  esac
}

remove_old_kernels() {
  msg "[5/13] Removing old kernels (keeping latest ${KEEP_KERNELS})..."
  local current_kernel before after
  current_kernel=$(uname -r)
  before=$(df / | tail -1 | awk '{print $3}')

  msg_info "Current kernel: ${CLR_BOLD}${current_kernel}${CLR_RESET}"

  case "$PM" in
    apt)
      msg_info "Kernel removal on apt systems is handled by 'apt autoremove'."
      # Optional: manually remove old kernels
      if [[ "$AGGRESSIVE_PKG_CACHE_CLEAN" == "true" ]]; then
        local old_kernels
        old_kernels=$(dpkg -l | grep -E 'linux-image-[0-9]' | grep -v "$current_kernel" | awk '{print $2}' | sort -V | head -n -"${KEEP_KERNELS}" || true)
        if [[ -n "$old_kernels" ]]; then
          msg_info "Found old kernels to remove"
          echo "$old_kernels" | xargs -r run_sudo apt-get -y purge
        fi
      fi
      ;;
    dnf|yum)
      if ! has_command rpm; then
        msg_warn "rpm command not found. Cannot remove kernels."
        return
      fi
      local kernel_pkgs_to_remove
      kernel_pkgs_to_remove=$(rpm -q kernel kernel-core --queryformat '%{BUILDTIME} %{NAME}-%{VERSION}-%{RELEASE}\n' 2>/dev/null | \
        sort -k1,1n | \
        grep -vF "${current_kernel}" | \
        head -n -"${KEEP_KERNELS}" | \
        cut -d' ' -f2 || true)

      if [[ -n "$kernel_pkgs_to_remove" ]]; then
        msg_info "Found old kernels to remove"
        echo "$kernel_pkgs_to_remove" | xargs -r run_sudo "$PM" -y remove
      else
        msg_info "No old kernels to remove."
      fi
      ;;
    zypper)
      msg_info "Old kernel removal for openSUSE is handled by package management."
      ;;
    pacman)
      local installed_kernels removed_count
      installed_kernels=$(pacman -Q | grep -E '^linux ' | wc -l)
      if [[ $installed_kernels -gt $KEEP_KERNELS ]]; then
        msg_warn "Multiple kernels detected. Manual review recommended."
        msg_info "Use 'pacman -Q | grep linux' to list kernels."
      fi
      ;;
    nix)
      msg_info "NixOS handles kernel generations via system profiles."
      ;;
    *)
      msg_warn "Unsupported package manager ($PM) for kernel removal."
      ;;
  esac

  after=$(df / | tail -1 | awk '{print $3}')
  calculate_freed "$before" "$after"
}

# ============================================================================
# FLATPAK AND SNAP CLEANING
# ============================================================================

clean_flatpak() {
  if ! has_command flatpak; then
    msg "[6/13] ${CLR_DIM}Flatpak not found. Skipping.${CLR_RESET}"
    return
  fi

  msg "[6/13] Cleaning Flatpak..."
  local before after
  before=$(df / | tail -1 | awk '{print $3}')

  run_sudo flatpak update -y
  run_sudo flatpak uninstall --unused -y

  # Clean Flatpak cache
  local flatpak_cache="/var/tmp/flatpak-cache"
  if [[ -d "$flatpak_cache" ]]; then
    msg_sub "Cleaning Flatpak cache..."
    safe_delete "$flatpak_cache/*" "Flatpak cache"
  fi

  after=$(df / | tail -1 | awk '{print $3}')
  calculate_freed "$before" "$after"
}

clean_snap() {
  if ! has_command snap; then
    msg "[7/13] ${CLR_DIM}Snap not found. Skipping.${CLR_RESET}"
    return
  fi

  msg "[7/13] Cleaning Snap..."
  local before after
  before=$(df / | tail -1 | awk '{print $3}')

  msg_sub "Refreshing Snaps..."
  run_sudo snap refresh

  msg_sub "Setting revision retention to ${KEEP_KERNELS}..."
  run_sudo snap set system refresh.retain="${KEEP_KERNELS}"

  msg_sub "Removing disabled/old Snap revisions..."
  LANG=C snap list --all | awk '/disabled/{print $1, $3}' | while read -r snapname revision; do
    if [[ -n "$snapname" && -n "$revision" ]]; then
      msg_info "Removing $snapname revision $revision"
      run_sudo snap remove "$snapname" --revision="$revision"
    fi
  done

  after=$(df / | tail -1 | awk '{print $3}')
  calculate_freed "$before" "$after"
}

# ============================================================================
# SYSTEM LOGS AND TEMP FILES
# ============================================================================

clean_system_logs() {
  msg "[8/13] Cleaning System Logs..."
  local before after

  # JournalD
  if has_command journalctl; then
    msg_sub "Vacuuming journal logs..."
    before=$(get_dir_size "/var/log/journal")
    run_sudo journalctl --vacuum-time="${JOURNAL_VACUUM_TIME}"
    run_sudo journalctl --vacuum-size="${JOURNAL_VACUUM_SIZE}"
    after=$(get_dir_size "/var/log/journal")
    calculate_freed "$before" "$after"
  fi

  # Rotate logs
  if has_command logrotate; then
    msg_sub "Forcing log rotation..."
    run_sudo logrotate -f /etc/logrotate.conf 2>/dev/null || true
  fi

  # Clean old logs
  msg_sub "Removing old compressed logs..."
  before=$(df /var | tail -1 | awk '{print $3}')
  run_sudo find /var/log -type f -name "*.gz" -mtime +30 -delete 2>/dev/null || true
  run_sudo find /var/log -type f -name "*.old" -mtime +30 -delete 2>/dev/null || true
  run_sudo find /var/log -type f -name "*.[0-9]" -mtime +30 -delete 2>/dev/null || true
  after=$(df /var | tail -1 | awk '{print $3}')
  calculate_freed "$before" "$after"
}

clean_temp_files() {
  msg "[9/13] Cleaning Temporary Files..."
  local before after

  before=$(df / | tail -1 | awk '{print $3}')

  msg_sub "Removing temp files older than ${TMP_FILE_MAX_AGE_DAYS} days..."
  run_sudo find /tmp -xdev -type f -atime +"${TMP_FILE_MAX_AGE_DAYS}" -delete 2>/dev/null || true
  run_sudo find /var/tmp -xdev -type f -atime +"${TMP_FILE_MAX_AGE_DAYS}" -delete 2>/dev/null || true

  # Clean empty directories
  run_sudo find /tmp -xdev -type d -empty -delete 2>/dev/null || true
  run_sudo find /var/tmp -xdev -type d -empty -delete 2>/dev/null || true

  after=$(df / | tail -1 | awk '{print $3}')
  calculate_freed "$before" "$after"
}

# ============================================================================
# USER CACHE AND DATA CLEANING
# ============================================================================

clean_user_cache() {
  msg "[10/13] Cleaning User Cache..."
  local real_home real_user before after
  real_home="$(get_real_home)"
  real_user="$(get_real_user)"

  if [[ -z "$real_home" || ! -d "$real_home" ]]; then
    msg_warn "Could not find home directory for '$real_user'. Skipping."
    return
  fi

  msg_sub "Cleaning caches for user: ${CLR_BOLD}${real_user}${CLR_RESET}"
  before=$(get_dir_size "${real_home}/.cache")

  # Thumbnails
  if [[ "$CLEAN_THUMBNAILS" == "true" ]]; then
    msg_info "Cleaning thumbnail cache..."
    safe_delete "${real_home}/.cache/thumbnails" "Thumbnails"
  fi

  # Trash
  if [[ "$CLEAN_TRASH" == "true" ]]; then
    msg_info "Emptying trash..."
    safe_delete "${real_home}/.local/share/Trash/files" "Trash files"
    safe_delete "${real_home}/.local/share/Trash/info" "Trash info"
  fi

  # General cache
  if [[ "$CLEAN_USER_CACHE_FILES" == "true" ]]; then
    msg_info "Cleaning cache files older than ${USER_CACHE_MAX_AGE_DAYS} days..."
    find "${real_home}/.cache/" -mindepth 1 -type f -mtime +"${USER_CACHE_MAX_AGE_DAYS}" -delete 2>/dev/null || true
    find "${real_home}/.cache/" -mindepth 1 -type d -empty -delete 2>/dev/null || true
  fi

  # Application logs
  if [[ "$CLEAN_APPLICATION_LOGS" == "true" ]]; then
    msg_info "Cleaning application logs older than ${APP_LOG_MAX_AGE_DAYS} days..."
    find "${real_home}/.local/share" -path "*/logs/*.log" -type f -mtime +"${APP_LOG_MAX_AGE_DAYS}" -delete 2>/dev/null || true
    find "${real_home}/.local/share" -path "*/logs/*.log.*" -type f -mtime +"${APP_LOG_MAX_AGE_DAYS}" -delete 2>/dev/null || true
  fi

  after=$(get_dir_size "${real_home}/.cache")
  calculate_freed "$before" "$after"
}

# ============================================================================
# BROWSER CLEANING (inspired by BleachBit)
# ============================================================================

clean_browsers() {
  msg "[11/13] Cleaning Browser Data..."
  local real_home real_user
  real_home="$(get_real_home)"
  real_user="$(get_real_user)"

  if [[ -z "$real_home" || ! -d "$real_home" ]]; then
    msg_warn "Could not find home directory. Skipping browser cleaning."
    return
  fi

  local total_before total_after
  total_before=0
  total_after=0

  # Firefox
  if [[ -d "${real_home}/.mozilla/firefox" ]]; then
    msg_sub "Cleaning Firefox..."
    local ff_before ff_after
    ff_before=$(get_dir_size "${real_home}/.mozilla/firefox")

    find "${real_home}/.mozilla/firefox" -type d -name "cache2" -exec rm -rf {} + 2>/dev/null || true
    find "${real_home}/.mozilla/firefox" -type d -name "startupCache" -exec rm -rf {} + 2>/dev/null || true
    find "${real_home}/.mozilla/firefox" -type d -name "thumbnails" -exec rm -rf {} + 2>/dev/null || true

    if [[ "$CLEAN_BROWSER_CACHE" == "true" ]]; then
      find "${real_home}/.mozilla/firefox" -type f -name "*.sqlite-wal" -delete 2>/dev/null || true
      find "${real_home}/.mozilla/firefox" -type f -name "*.sqlite-shm" -delete 2>/dev/null || true
    fi

    if [[ "$CLEAN_BROWSER_HISTORY" == "true" ]]; then
      if confirm "Delete Firefox browsing history?"; then
        find "${real_home}/.mozilla/firefox" -type f -name "places.sqlite" -delete 2>/dev/null || true
        find "${real_home}/.mozilla/firefox" -type f -name "formhistory.sqlite" -delete 2>/dev/null || true
      fi
    fi

    ff_after=$(get_dir_size "${real_home}/.mozilla/firefox")
    total_before=$((total_before + ff_before))
    total_after=$((total_after + ff_after))
  fi

  # Chrome/Chromium
  for browser_dir in ".config/google-chrome" ".config/chromium"; do
    local browser_path="${real_home}/${browser_dir}"
    if [[ -d "$browser_path" ]]; then
      msg_sub "Cleaning ${browser_dir##*/}..."
      local chrome_before chrome_after
      chrome_before=$(get_dir_size "$browser_path")

      find "$browser_path" -type d -name "Cache" -exec rm -rf {} + 2>/dev/null || true
      find "$browser_path" -type d -name "Code Cache" -exec rm -rf {} + 2>/dev/null || true
      find "$browser_path" -type d -name "GPUCache" -exec rm -rf {} + 2>/dev/null || true
      find "$browser_path" -type d -name "Service Worker" -path "*/Cache/*" -exec rm -rf {} + 2>/dev/null || true

      if [[ "$CLEAN_BROWSER_HISTORY" == "true" ]]; then
        if confirm "Delete ${browser_dir##*/} browsing history?"; then
          find "$browser_path" -type f -name "History" -delete 2>/dev/null || true
          find "$browser_path" -type f -name "History-journal" -delete 2>/dev/null || true
        fi
      fi

      chrome_after=$(get_dir_size "$browser_path")
      total_before=$((total_before + chrome_before))
      total_after=$((total_after + chrome_after))
    fi
  done

  calculate_freed "$total_before" "$total_after"
}

# ============================================================================
# DESKTOP ENVIRONMENT CLEANING
# ============================================================================

clean_desktop_environment() {
  msg "[12/13] Cleaning Desktop Environment Data..."
  local real_home real_user
  real_home="$(get_real_home)"
  real_user="$(get_real_user)"

  if [[ -z "$real_home" || ! -d "$real_home" ]]; then
    msg_warn "Could not find home directory. Skipping."
    return
  fi

  local before after
  before=0
  after=0

  # Recent documents
  if [[ "$CLEAN_RECENT_DOCUMENTS" == "true" ]]; then
    msg_sub "Clearing recent documents..."
    local recent_files=(
      "${real_home}/.local/share/recently-used.xbel"
      "${real_home}/.recently-used"
      "${real_home}/.local/share/RecentDocuments"
    )
    for file in "${recent_files[@]}"; do
      if [[ -e "$file" ]]; then
        before=$((before + $(get_dir_size "$file")))
        safe_delete "$file" "Recent documents"
      fi
    done
  fi

  # Clipboard managers
  if [[ "$CLEAN_CLIPBOARD_HISTORY" == "true" ]]; then
    msg_sub "Clearing clipboard history..."
    local clipboard_files=(
      "${real_home}/.local/share/klipper"
      "${real_home}/.config/clipit/history"
      "${real_home}/.cache/clipman.json"
    )
    for file in "${clipboard_files[@]}"; do
      if [[ -e "$file" ]]; then
        before=$((before + $(get_dir_size "$file")))
        safe_delete "$file" "Clipboard history"
      fi
    done
  fi

  # Icon cache
  msg_sub "Cleaning icon cache..."
  if [[ -d "${real_home}/.cache/icon-cache" ]]; then
    before=$((before + $(get_dir_size "${real_home}/.cache/icon-cache")))
    safe_delete "${real_home}/.cache/icon-cache" "Icon cache"
  fi

  after=0
  calculate_freed "$before" "$after"
}

# ============================================================================
# DOCKER CLEANING
# ============================================================================

clean_docker() {
  if [[ "$CLEAN_DOCKER" != "true" ]]; then
    msg "[13/13] ${CLR_DIM}Docker cleanup disabled. Skipping.${CLR_RESET}"
    return
  fi

  if ! has_command docker; then
    msg "[13/13] ${CLR_DIM}Docker not found. Skipping.${CLR_RESET}"
    return
  fi

  msg "[13/13] Cleaning Docker..."
  local before after
  before=$(df / | tail -1 | awk '{print $3}')

  msg_sub "Removing stopped containers, dangling images, and unused networks..."
  run_sudo docker system prune -f

  # Builder cache
  if [[ "$CLEAN_DOCKER_BUILDER_CACHE" == "true" ]]; then
    if confirm "Clean Docker builder cache?"; then
      msg_info "Pruning builder cache..."
      run_sudo docker builder prune -af
    fi
  fi

  # Volumes
  if [[ "$CLEAN_DOCKER_VOLUMES" == "true" ]]; then
    msg_warn "Volume pruning will delete ALL volumes not attached to a container!"
    if confirm "Proceed with Docker volume pruning?"; then
      run_sudo docker volume prune -f
      msg_ok "Docker volumes pruned."
    else
      msg_info "Skipping volume pruning."
    fi
  fi

  after=$(df / | tail -1 | awk '{print $3}')
  calculate_freed "$before" "$after"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

print_header() {
  echo -e "${CLR_BOLD}${CLR_GREEN}"
  echo "###############################################################"
  echo "##  🚀 Smart Linux System Cleaner v${SCRIPT_VERSION} 🚀             ##"
  echo "###############################################################"
  echo -e "${CLR_RESET}"
}

print_config() {
  msg "Configuration Summary:"
  msg_info "Keep Kernels: ${KEEP_KERNELS}"
  msg_info "Journal Vacuum: ${JOURNAL_VACUUM_TIME} / ${JOURNAL_VACUUM_SIZE}"
  msg_info "Temp Files Age: ${TMP_FILE_MAX_AGE_DAYS} days"
  msg_info "User Cache Age: ${USER_CACHE_MAX_AGE_DAYS} days"
  msg_info "Dry Run Mode: ${DRY_RUN}"
  echo
}

print_disk_usage() {
  local label="$1"
  msg "${label}"
  df -hT / /home /var /tmp 2>/dev/null || msg_warn "Could not retrieve disk usage."
  echo
}

main() {
  print_header
  check_root

  if [[ "$DRY_RUN" == "true" ]]; then
    msg_warn "DRY RUN MODE: No files will be deleted."
    echo
  fi

  print_config
  print_disk_usage "Initial Disk Usage"

  msg "Syncing filesystem buffers..."
  sync

  PM=$(detect_package_manager)
  if [[ "$PM" == "unknown" ]]; then
    msg_err "Could not detect a supported package manager. Aborting."
    exit 1
  fi
  msg "Detected Package Manager: ${CLR_BOLD}${PM}${CLR_RESET}"
  echo

  init_backup_list

  # Execute all cleaning tasks
  update_repos
  upgrade_packages
  remove_orphans
  clean_package_cache
  remove_old_kernels
  clean_flatpak
  clean_snap
  clean_system_logs
  clean_temp_files
  clean_user_cache
  clean_browsers
  clean_desktop_environment
  clean_docker

  msg "Flushing final filesystem buffers..."
  sync
  sleep 1

  echo
  print_disk_usage "Final Disk Usage"

  # Calculate script duration
  local script_end_time duration
  script_end_time=$(date +%s)
  duration=$((script_end_time - SCRIPT_START_TIME))

  echo -e "\n${CLR_BOLD}${CLR_GREEN}"
  echo "###############################################################"
  echo "##   ✅ System Cleanup Completed Successfully! ✅              ##"
  echo "###############################################################"
  echo -e "${CLR_RESET}"
  msg_ok "Total Space Freed: $(format_bytes $TOTAL_FREED_SPACE)"
  msg_ok "Script Duration: ${duration} seconds"

  if [[ "$CREATE_BACKUP_LIST" == "true" ]]; then
    msg_info "Backup list saved to: ${BACKUP_FILE}"
  fi
}

# Run main function
main

exit 0
