#!/usr/bin/env bash
#
# ###################################################################################
# ##                                                                               ##
# ##                    ✨🛡️ Smart Linux System Cleaner  🛡️✨                      ##
# ##                                                                               ##
# ###################################################################################
#
# Purpose:
#   1. Update/Upgrade system packages for apt, dnf, yum, zypper, or Nix.
#   2. Remove old/unused packages (orphans) and old kernels safely.
#   3. Clean package caches, systemd journal logs, temporary directories,
#      user caches, Flatpak/Snap leftovers, and Docker resources.
#
# Warning:
#   - This script performs potentially destructive operations. Review carefully.
#   - Create backups of important data before running.
#   - The most dangerous operations (e.g., Docker volume deletion) are disabled
#     by default or require interactive confirmation.
#
# Supported Package Managers: apt, dnf, yum, zypper, nix
# Supported Additional Systems: Flatpak, Snap, Docker
# ###################################################################################

# --- Configuration ---
KEEP_KERNELS=2                    # Number of recent kernels to keep (dnf, yum, snap)
JOURNAL_VACUUM_TIME="3d"          # Max age for systemd journal logs (e.g., "3days", "1week")
TMP_FILE_MAX_AGE_DAYS=7           # Max age in days for files in /tmp and /var/tmp. (1 is very aggressive)

# --- IMPROVEMENT: Safer user cache cleaning configuration ---
CLEAN_USER_CACHE_FILES=true       # Set to false to ONLY clean Trash and Thumbnails, skipping general file cleanup in ~/.cache
USER_CACHE_MAX_AGE_DAYS=14        # More conservative default. Remove cache files older than this.

# --- IMPROVEMENT: Safer and more granular Docker cleanup configuration ---
CLEAN_DOCKER=true                 # Set to false to disable all Docker cleanup
CLEAN_DOCKER_VOLUMES=false        # ⚠️ DANGER: Set to true to enable pruning of UNUSED DOCKER VOLUMES.

# --- End Configuration ---

# --- Script Setup ---
set -euo pipefail # Exit on error; treat unset variables as error; fail on pipe errors

# --- Color Definitions ---
if [[ -t 1 ]]; then
  CLR_RESET='\e[0m'; CLR_RED='\e[0;31m'; CLR_GREEN='\e[0;32m'; CLR_YELLOW='\e[0;33m'; CLR_BLUE='\e[0;34m'; CLR_PURPLE='\e[0;35m'; CLR_CYAN='\e[0;36m'; CLR_BOLD='\e[1m'; CLR_DIM='\e[2m'
else
  CLR_RESET=''; CLR_RED=''; CLR_GREEN=''; CLR_YELLOW=''; CLR_BLUE=''; CLR_PURPLE=''; CLR_CYAN=''; CLR_BOLD=''; CLR_DIM=''
fi

# --- Logging Functions ---
msg() { echo -e "${CLR_BLUE}${CLR_BOLD}>>>${CLR_RESET} ${CLR_BOLD}${@}${CLR_RESET}"; }
msg_sub() { echo -e "  ${CLR_CYAN}==>${CLR_RESET} ${@}"; }
msg_warn() { echo -e "${CLR_YELLOW}${CLR_BOLD}⚠️ Warning:${CLR_RESET} ${CLR_YELLOW}${@}${CLR_RESET}"; }
msg_info() { echo -e "  ${CLR_PURPLE}::${CLR_RESET} ${@}"; }
msg_ok() { echo -e "${CLR_GREEN}${CLR_BOLD}✔ OK:${CLR_RESET} ${CLR_GREEN}${@}${CLR_RESET}"; }
msg_err() { echo -e "${CLR_RED}${CLR_BOLD}❌ Error:${CLR_RESET} ${CLR_RED}${@}${CLR_RESET}" >&2; }

# --- Helper Functions ---

# Ensure the script is run with root privileges where needed
if [[ $EUID -ne 0 ]]; then
  msg_warn "This script needs root privileges for many operations."
  msg_warn "It will use 'sudo' internally. You may be prompted for a password."
fi

# Cleanup function to handle errors or interruptions
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    msg_err "Script encountered an error on line $BASH_LINENO. Exit code: $exit_code"
  fi
  echo -e "${CLR_RESET}" # Ensure terminal colors are reset
}
trap cleanup EXIT ERR

# Function to execute commands with sudo if not already root
run_sudo() {
  if [[ $EUID -ne 0 ]]; then
    sudo "$@"
  else
    "$@"
  fi
}

# Function to get the home directory of the user who invoked sudo
get_real_home() {
  if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
    getent passwd "${SUDO_USER}" | cut -d: -f6
  else
    echo "${HOME}"
  fi
}

# --- IMPROVEMENT: Interactive confirmation function ---
confirm() {
    local prompt="${1}"
    local response
    read -rp "$(echo -e "${CLR_YELLOW}❓ ${prompt} (y/N): ${CLR_RESET}")" response
    if [[ "${response,,}" == "y" ]]; then
        return 0 # Success (yes)
    else
        return 1 # Failure (no)
    fi
}

detect_package_manager() {
  if command -v apt-get &>/dev/null; then echo "apt";
  elif command -v dnf &>/dev/null; then echo "dnf";
  elif command -v yum &>/dev/null; then echo "yum";
  elif command -v zypper &>/dev/null; then echo "zypper";
  elif command -v nix-env &>/dev/null; then echo "nix";
  else echo "unknown"; fi
}

# --- Package Management Functions ---

update_repos() {
  msg "[1/9] Updating package repositories..."
  case "$PM" in
    apt)    run_sudo apt-get update ;;
    dnf)    run_sudo dnf check-update || true ;; # Exits non-zero if updates found
    yum)    run_sudo yum check-update || true ;;
    zypper) run_sudo zypper --non-interactive refresh ;;
    nix)    run_sudo nix-channel --update; msg_info "Nix channels updated." ;;
    *)      msg_warn "Unsupported package manager ($PM) for repository update." ;;
  esac
}

upgrade_packages() {
  msg "[2/9] Upgrading system packages..."
  case "$PM" in
    apt)    run_sudo apt-get -y upgrade ;;
    dnf)    run_sudo dnf -y upgrade ;;
    yum)    run_sudo yum -y update ;;
    zypper) run_sudo zypper --non-interactive update ;;
    nix)    msg_info "Skipping automatic Nix upgrade. Run 'nixos-rebuild switch --upgrade' or 'nix-env -u \"*\"' manually." ;;
    *)      msg_warn "Unsupported package manager ($PM) for package upgrade." ;;
  esac
}

remove_orphans() {
  msg "[3/9] Removing orphaned/unneeded packages..."
  case "$PM" in
    apt)    run_sudo apt-get -y autoremove --purge ;;
    dnf)    run_sudo dnf -y autoremove ;;
    yum)
      if command -v package-cleanup &>/dev/null; then
        run_sudo package-cleanup --leaves --exclude-bin || true
        run_sudo package-cleanup --orphans || true
      else
        msg_warn "'package-cleanup' (from yum-utils) not found. Skipping."
      fi
      ;;
    zypper)
      # --- IMPROVEMENT: Use xargs for safer package list handling ---
      unneeded_packages=$(zypper packages --unneeded | awk -F '|' 'NR > 4 {gsub(/^[ \t]+|[ \t]+$/, "", $3); if ($3 != "") print $3}')
      if [[ -n "$unneeded_packages" ]]; then
        msg_info "Found unneeded packages:\n${unneeded_packages}"
        echo "$unneeded_packages" | xargs -r -- sudo zypper --non-interactive remove --clean-deps
      else
        msg_info "No unneeded packages found."
      fi
      ;;
    nix)
      msg_info "Running Nix garbage collection..."
      run_sudo nix-collect-garbage -d
      ;;
    *)      msg_warn "Unsupported package manager ($PM) for orphan removal." ;;
  esac
}

clean_package_cache() {
  msg "[4/9] Cleaning package cache..."
  case "$PM" in
    apt)    run_sudo apt-get clean ;;
    dnf)    run_sudo dnf clean all ;;
    yum)    run_sudo yum clean all ;;
    zypper) run_sudo zypper clean --all ;;
    nix)    msg_info "Running nix-store --optimise to deduplicate..."; run_sudo nix-store --optimise ;;
    *)      msg_warn "Unsupported package manager ($PM) for cache cleaning." ;;
  esac
}

remove_old_kernels() {
  msg "[5/9] Removing old kernels (keeping latest ${KEEP_KERNELS})..."
  local current_kernel
  current_kernel=$(uname -r)

  case "$PM" in
    apt)
      msg_info "Kernel removal on apt systems is handled by 'apt autoremove'."
      ;;
    dnf|yum) # --- IMPROVEMENT: Combined DNF/YUM logic for kernels ---
      if ! command -v rpm &>/dev/null; then
        msg_warn "rpm command not found. Cannot remove kernels."
        return
      fi
      # List installed kernel packages, sort by build time, exclude the running kernel, then select the oldest ones to remove.
      kernel_pkgs_to_remove=$(rpm -q kernel kernel-core --queryformat '%{BUILDTIME} %{NAME}-%{VERSION}-%{RELEASE}\n' | \
        sort -k1,1n | \
        grep -vF "${current_kernel}" | \
        head -n -${KEEP_KERNELS} | \
        cut -d' ' -f2 || true)

      if [[ -n "$kernel_pkgs_to_remove" ]]; then
        msg_info "Found old kernels to remove:\n${kernel_pkgs_to_remove}"
        # --- IMPROVEMENT: Use xargs for safer argument passing ---
        echo "$kernel_pkgs_to_remove" | xargs -r -- sudo dnf -y remove
      else
        msg_info "No old kernels found to remove (or protected by 'keep' count)."
      fi
      ;;
    zypper)
      msg_info "Old kernel removal for openSUSE/zypper is handled by YaST or orphan removal."
      ;;
    nix)
      msg_info "NixOS handles kernel generations via 'nixos-rebuild' and garbage collection."
      ;;
    *)
      msg_warn "Unsupported package manager ($PM) for kernel removal."
      ;;
  esac
}

# --- Other System Cleaning Functions ---

clean_flatpak() {
  if command -v flatpak &>/dev/null; then
    msg "[6/9] Cleaning Flatpak..."
    run_sudo flatpak update -y
    run_sudo flatpak uninstall --unused -y
  else
    msg "[6/9] ${CLR_DIM}Flatpak not found. Skipping.${CLR_RESET}"
  fi
}

clean_snap() {
  if command -v snap &>/dev/null; then
    msg "[7/9] Cleaning Snap..."
    msg_sub "Refreshing Snaps..."
    run_sudo snap refresh
    msg_sub "Setting revision retention to ${KEEP_KERNELS}..."
    run_sudo snap set system refresh.retain="${KEEP_KERNELS}"
    msg_sub "Removing disabled/old Snap revisions..."
    # Set LANG=C to ensure consistent output format for parsing
    LANG=C snap list --all | awk '/disabled/{print $1, $3}' | while read -r snapname revision; do
      msg_info "Removing $snapname revision $revision"
      run_sudo snap remove "$snapname" --revision="$revision"
    done
  else
    msg "[7/9] ${CLR_DIM}Snap not found. Skipping.${CLR_RESET}"
  fi
}

clean_system_and_user() {
  msg "[8/9] Cleaning System Logs, Temp Files, and User Caches..."

  # Clean JournalD
  if command -v journalctl &>/dev/null; then
    msg_sub "Vacuuming journal logs older than ${JOURNAL_VACUUM_TIME}..."
    run_sudo journalctl --vacuum-time="${JOURNAL_VACUUM_TIME}"
  else
    msg_warn "journalctl not found. Skipping journal cleaning."
  fi

  # Clean Temp Dirs
  msg_sub "Removing temp files older than ${TMP_FILE_MAX_AGE_DAYS} days..."
  # Use -xdev to stay on the same filesystem and ignore most errors
  run_sudo find /tmp /var/tmp -xdev -type f -atime +"${TMP_FILE_MAX_AGE_DAYS}" -delete 2>/dev/null || true

  # Clean User Caches
  local real_home
  real_home="$(get_real_home)"
  local current_user="${SUDO_USER:-$(whoami)}"

  if [[ -z "$real_home" || ! -d "$real_home" ]]; then
    msg_warn "Could not find home directory for '$current_user'. Skipping user cache."
    return
  fi
  msg_sub "Cleaning caches for user: ${CLR_BOLD}${current_user}${CLR_RESET}"

  msg_info "Cleaning Thumbnail cache: ${real_home}/.cache/thumbnails"
  rm -rf "${real_home}/.cache/thumbnails/"* 2>/dev/null || true

  msg_info "Cleaning user Trash folder: ${real_home}/.local/share/Trash"
  rm -rf "${real_home}/.local/share/Trash/files/"* 2>/dev/null || true
  rm -rf "${real_home}/.local/share/Trash/info/"* 2>/dev/null || true

  # --- IMPROVEMENT: Make general cache cleaning optional ---
  if [[ "$CLEAN_USER_CACHE_FILES" == "true" ]]; then
    msg_info "Cleaning general app cache files older than ${USER_CACHE_MAX_AGE_DAYS} days..."
    # Find and delete old files, ignoring errors
    find "${real_home}/.cache/" -mindepth 1 -type f -mtime +"${USER_CACHE_MAX_AGE_DAYS}" -delete 2>/dev/null || true
    # Attempt to clean up empty directories left behind
    find "${real_home}/.cache/" -mindepth 1 -type d -empty -delete 2>/dev/null || true
  else
    msg_info "${CLR_DIM}General user cache file cleaning is disabled in configuration. Skipping.${CLR_RESET}"
  fi
}

clean_docker() {
  if [[ "$CLEAN_DOCKER" != "true" ]]; then
    msg "[9/9] ${CLR_DIM}Docker cleanup is disabled in configuration. Skipping.${CLR_RESET}"
    return
  fi
  if ! command -v docker &>/dev/null; then
    msg "[9/9] ${CLR_DIM}Docker command not found. Skipping Docker cleanup.${CLR_RESET}"
    return
  fi

  msg "[9/9] Cleaning Docker system..."
  msg_sub "This will remove all stopped containers, dangling images, and unused networks."
  run_sudo docker system prune -f

  # --- IMPROVEMENT: Handle dangerous volume pruning separately and interactively ---
  if [[ "$CLEAN_DOCKER_VOLUMES" == "true" ]]; then
    msg_warn "Docker Volume Pruning is enabled. This will delete ALL volumes NOT currently attached to a container."
    if confirm "Proceed with deleting unused Docker volumes?"; then
      msg_info "Pruning Docker volumes..."
      run_sudo docker volume prune -f
      msg_ok "Docker volumes pruned."
    else
      msg_info "Skipping Docker volume pruning."
    fi
  else
    msg_info "${CLR_DIM}Docker volume pruning is disabled in configuration. To enable, set CLEAN_DOCKER_VOLUMES=true.${CLR_RESET}"
  fi
}

# --- Main Execution ---
echo -e "${CLR_BOLD}${CLR_GREEN}"
echo "###########################################################"
echo "##      🚀 Starting Linux Deep Clean & Update 🚀         ##"
echo "###########################################################"
echo -e "${CLR_RESET}"

msg "--- Initial Disk Usage ---"
df -hT / /home /var /tmp || msg_warn "Could not retrieve initial disk usage."

msg "Syncing filesystem buffers..."
sync

PM=$(detect_package_manager)
if [[ "$PM" == "unknown" ]]; then
  msg_err "Could not detect a supported package manager. Aborting."
  exit 1
fi
msg "Detected Package Manager: ${CLR_BOLD}${PM}${CLR_RESET}"
echo

# --- Main Tasks ---
update_repos
upgrade_packages
remove_orphans
clean_package_cache
remove_old_kernels
clean_flatpak
clean_snap
clean_system_and_user # Combines journal, tmp, and user cache
clean_docker

msg "Flushing final filesystem buffers..."
sync; sleep 1

echo
msg "--- Final Disk Usage ---"
df -hT / /home /var /tmp || msg_warn "Could not retrieve final disk usage."

echo -e "\n${CLR_BOLD}${CLR_GREEN}"
echo "###########################################################"
echo "##   ✅ System cleanup and update script completed! ✅     ##"
echo "###########################################################"
echo -e "${CLR_RESET}"

exit 0
