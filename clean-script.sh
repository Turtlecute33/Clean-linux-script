#!/usr/bin/env bash
#
# #############################################################################
# ##                                                                      ##
# ##   🌈 Linux System Deep Cleaner and Updater Script 🚀                ##
# ##                                                                      ##
# #############################################################################
#
# Purpose:
#   1. Update/Upgrade system packages for apt, dnf, yum, zypper, or Nix.
#   2. Remove old/unused packages (orphans) and optionally old kernels.
#   3. Clean package caches, systemd journal logs, temporary directories,
#      user caches, Flatpak/Snap leftovers, and optionally Docker volumes.
#
# Warning:
#   - This script performs potentially destructive operations (removing packages,
#     kernels, caches, Docker volumes, etc.).
#   - Review carefully and create backups before running.
#   - Some operations require root privileges (run with sudo if not root).
#
# Supported Package Managers: apt, dnf, yum, zypper, nix
# Supported Additional Systems: Flatpak, Snap, Docker
# #############################################################################

# --- Configuration ---
KEEP_KERNELS=2              # Number of recent kernels to keep (dnf, yum, zypper, snap)
JOURNAL_VACUUM_TIME="2days" # Max age for systemd journal logs
TMP_FILE_MAX_AGE_DAYS=1     # Max age in days for files in /tmp and /var/tmp
CLEAN_DOCKER=true          # Set to false to disable Docker cleanup (uses 'docker system prune -a --volumes')
USER_CACHE_MAX_AGE_DAYS=7   # Remove user cache files older than this (use with caution)
# --- End Configuration ---

# --- Script Setup ---
set -euo pipefail # Exit on error; treat unset variables as error; fail on pipe errors

# --- Color Definitions ---
# Check if stdout is a terminal and define colors
if [[ -t 1 ]]; then
  CLR_RESET='\e[0m'
  CLR_RED='\e[0;31m'
  CLR_GREEN='\e[0;32m'
  CLR_YELLOW='\e[0;33m'
  CLR_BLUE='\e[0;34m'
  CLR_PURPLE='\e[0;35m'
  CLR_CYAN='\e[0;36m'
  CLR_WHITE='\e[0;37m'
  CLR_BOLD='\e[1m'
  CLR_DIM='\e[2m'
else # No colors if not a terminal
  CLR_RESET=''
  CLR_RED=''
  CLR_GREEN=''
  CLR_YELLOW=''
  CLR_BLUE=''
  CLR_PURPLE=''
  CLR_CYAN=''
  CLR_WHITE=''
  CLR_BOLD=''
  CLR_DIM=''
fi

# Helper function for printing colored messages
msg() {
  echo -e "${CLR_BLUE}${CLR_BOLD}>>>${CLR_RESET} ${CLR_BOLD}${@}${CLR_RESET}"
}
msg_sub() {
  echo -e " ${CLR_CYAN}==>${CLR_RESET} ${@}"
}
msg_warn() {
  echo -e "${CLR_YELLOW}${CLR_BOLD}⚠️ Warning:${CLR_RESET} ${CLR_YELLOW}${@}${CLR_RESET}"
}
msg_info() {
  echo -e "${CLR_PURPLE}::${CLR_RESET} ${@}"
}
msg_ok() {
  echo -e "${CLR_GREEN}${CLR_BOLD}✔ OK:${CLR_RESET} ${CLR_GREEN}${@}${CLR_RESET}"
}
msg_err() {
  echo -e "${CLR_RED}${CLR_BOLD}❌ Error:${CLR_RESET} ${CLR_RED}${@}${CLR_RESET}" >&2
}

# Ensure the script is run with root privileges where needed
if [[ $EUID -ne 0 ]]; then
  msg_warn "This script needs root privileges for many operations."
  msg_warn "It will attempt to use 'sudo' internally when required."
  msg_warn "If 'sudo' requires a password, you may be prompted."
  # Uncomment if you want to force exit if not run as root:
  # msg_err "This script must be run with root privileges (e.g., using sudo)."
  # exit 1
fi

# Cleanup function to handle errors or interruptions
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    msg_err "Script encountered an error on line $BASH_LINENO. Exit code: $exit_code"
  fi
  echo -e "${CLR_RESET}" # Ensure terminal colors are reset
}
trap cleanup EXIT ERR # Run cleanup on exit (error or normal)

# Function to execute commands with sudo if not already root
run_sudo() {
  if [[ $EUID -ne 0 ]]; then
    msg_info "Running with sudo: ${*}"
    sudo "$@"
  else
    msg_info "Running as root: ${*}"
    "$@"
  fi
}

# --- Helper Functions ---

detect_package_manager() {
  if command -v apt-get &>/dev/null; then echo "apt";
  elif command -v dnf &>/dev/null; then echo "dnf";
  elif command -v yum &>/dev/null; then
      if command -v dnf &>/dev/null; then echo "dnf"; else echo "yum"; fi # Prefer dnf
  elif command -v zypper &>/dev/null; then echo "zypper";
  elif command -v nix-env &>/dev/null; then echo "nix";
  else echo "unknown"; fi
}

get_real_home() {
  # If running via sudo, pick up the original user's home
  if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
    getent passwd "${SUDO_USER}" | cut -d: -f6
  else
    echo "${HOME}"
  fi
}

# --- Package Management Functions ---

update_repos() {
  msg "[1/9] Updating package repositories..."
  case "$PM" in
    apt)    run_sudo apt-get update ;;
    dnf)    run_sudo dnf check-update || true ;; # Exits non-zero if updates found
    yum)    run_sudo yum check-update || true ;;
    zypper) run_sudo zypper --non-interactive refresh ;;
    nix)
      run_sudo nix-channel --update
      msg_info "Nix channels updated."
      msg_info "${CLR_DIM}For a full system upgrade, run 'nixos-rebuild switch --upgrade' (NixOS) or 'nix-env -u \"*\"' (profile) manually.${CLR_RESET}"
      ;;
    *) msg_warn "Unsupported package manager ($PM) for repository update." ;;
  esac
}

upgrade_packages() {
  msg "[2/9] Upgrading system packages..."
  case "$PM" in
    apt)    run_sudo apt-get -y upgrade ;;
    dnf)    run_sudo dnf -y upgrade ;;
    yum)    run_sudo yum -y update ;;
    zypper) run_sudo zypper --non-interactive update ;;
    nix)    msg_info "Skipping automatic NixOS/profile upgrade. Use appropriate 'nixos-rebuild' or 'nix-env' commands if needed." ;;
    *)      msg_warn "Unsupported package manager ($PM) for package upgrade." ;;
  esac
}

remove_orphans() {
  msg "[3/9] Removing orphaned/unneeded packages..."
  case "$PM" in
    apt)
      run_sudo apt-get -y autoremove --purge
      ;;
    dnf)
      run_sudo dnf -y autoremove
      ;;
    yum)
      if command -v package-cleanup &>/dev/null; then
        msg_sub "Removing unused leaf packages..."
        run_sudo package-cleanup --leaves --exclude-bin || true # Might exit non-zero if none found
        msg_sub "Removing orphaned packages..."
        run_sudo package-cleanup --orphans || true # Might exit non-zero if none found
      else
        msg_warn "'package-cleanup' (from yum-utils) not found. Skipping orphan removal for yum."
      fi
      ;;
    zypper)
      # Skip header lines, get unneeded packages (3rd field, trimmed)
      unneeded_packages=$(zypper packages --unneeded | awk -F '|' 'NR > 4 {gsub(/^[ \t]+|[ \t]+$/, "", $3); if ($3 != "") print $3}')
      if [[ -n "$unneeded_packages" ]]; then
        msg_info "Found unneeded packages:\n${unneeded_packages}"
        # Convert newline-separated list to space-separated for zypper remove
        # Use printf/paste for safer handling than just $unneeded_packages
        packages_arg=$(echo "$unneeded_packages" | paste -sd ' ')
        # shellcheck disable=SC2086 # We want word splitting here
        run_sudo zypper --non-interactive remove --clean-deps $packages_arg
      else
        msg_info "No unneeded packages found."
      fi
      ;;
    nix)
      msg_info "Running Nix garbage collection (removes unreferenced store paths)..."
      run_sudo nix-collect-garbage -d
      msg_info "${CLR_DIM}Consider running 'nix-store --optimise' for further optimization (can take time).${CLR_RESET}"
      ;;
    *)
      msg_warn "Unsupported package manager ($PM) for orphan removal."
      ;;
  esac
}

clean_package_cache() {
  msg "[4/9] Cleaning package cache..."
  case "$PM" in
    apt)    run_sudo apt-get clean ;;
    dnf)    run_sudo dnf clean packages ;;
    yum)    run_sudo yum clean all ;;
    zypper) run_sudo zypper clean --all ;;
    nix)    msg_info "Running nix-store --optimise to reduce disk usage by deduplication..."
            run_sudo nix-store --optimise ;;
    *)      msg_warn "Unsupported package manager ($PM) for cache cleaning." ;;
  esac
}

remove_old_kernels() {
  msg "[5/9] Removing old kernels (keeping latest ${KEEP_KERNELS})..."
  case "$PM" in
    apt)
      msg_info "Kernel removal on apt-based systems is typically handled by 'apt autoremove'."
      msg_info "${CLR_DIM}Ensure 'autoremove' ran successfully in step 3. You can manually check with 'dpkg --list | grep 'linux-image''.${CLR_RESET}"
      ;;
    dnf)
      # List installed kernels, sort naturally, keep the last N
      kernel_pkgs_to_remove=$(rpm -q kernel-core --queryformat '%{BUILDTIME} %{NAME}-%{VERSION}-%{RELEASE}\n' | sort -k1,1n | head -n -${KEEP_KERNELS} | cut -d' ' -f2 || true)
      if [[ -n "$kernel_pkgs_to_remove" ]]; then
        msg_info "Found old DNF kernels to remove:\n${kernel_pkgs_to_remove}"
        # Convert newlines to spaces for removal
        kernels_arg=$(echo "$kernel_pkgs_to_remove" | paste -sd ' ')
        # shellcheck disable=SC2086 # We want word splitting here
        run_sudo dnf -y remove $kernels_arg
      else
        msg_info "No old DNF kernels to remove (or fewer than ${KEEP_KERNELS} installed)."
      fi
      ;;
    yum)
      if command -v package-cleanup &>/dev/null; then
        msg_sub "Using package-cleanup to remove old kernels..."
        run_sudo package-cleanup --oldkernels --count="${KEEP_KERNELS}" -y
      else
        msg_warn "'package-cleanup' (from yum-utils) not found. Skipping old kernel removal for yum."
      fi
      ;;
    zypper)
      msg_info "Old kernel removal for openSUSE/zypper is often handled automatically or via YaST."
      msg_info "${CLR_DIM}Orphan removal (step 3) might remove them if marked unneeded.${CLR_RESET}"
      ;;
    nix)
      msg_info "NixOS handles kernel updates and old generations via 'nixos-rebuild' and garbage collection (step 3)."
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
    msg_sub "Updating Flatpak applications..."
    run_sudo flatpak update -y
    msg_sub "Removing unused Flatpak runtimes..."
    run_sudo flatpak uninstall --unused -y
  else
    msg "[6/9] ${CLR_DIM}Flatpak not found. Skipping.${CLR_RESET}"
  fi
}

clean_snap() {
  if command -v snap &>/dev/null; then
    msg "[7/9] Cleaning Snap..."
    msg_sub "Refreshing Snaps..."
    run_sudo snap refresh # Refresh all snaps
    msg_sub "Configuring Snap to retain ${KEEP_KERNELS} revisions..."
    run_sudo snap set system refresh.retain="${KEEP_KERNELS}"
    msg_sub "Removing disabled/old Snap revisions..."
    # Set LANG=C to ensure consistent output format for parsing
    LANG=C snap list --all | awk '/disabled/{print $1, $3}' | while read -r snapname revision; do
      msg_info "Removing $snapname revision $revision"
      run_sudo snap remove "$snapname" --revision="$revision"
    done
    msg_info "Snap cleanup finished."
  else
     msg "[7/9] ${CLR_DIM}Snap not found. Skipping.${CLR_RESET}"
  fi
}

clean_journal() {
  msg "[8/9] Cleaning systemd journal logs..."
  if command -v journalctl &>/dev/null; then
    msg_sub "Vacuuming journal logs older than ${JOURNAL_VACUUM_TIME}..."
    run_sudo journalctl --vacuum-time="${JOURNAL_VACUUM_TIME}"
  else
    msg_warn "journalctl not found. Skipping journal cleaning."
  fi
}

clean_tmp_dirs() {
  msg "[8/9] Cleaning temporary directories..." # Combined with journal & user cache step
  msg_sub "Removing files older than ${TMP_FILE_MAX_AGE_DAYS} days in /tmp and /var/tmp..."
  # Use -xdev to stay on the same filesystem
  if ! run_sudo find /tmp -xdev -type f -atime +"${TMP_FILE_MAX_AGE_DAYS}" -delete ; then
     msg_warn "Could not clean all files in /tmp (permissions? files vanished?)"
  fi
   if ! run_sudo find /var/tmp -xdev -type f -atime +"${TMP_FILE_MAX_AGE_DAYS}" -delete ; then
     msg_warn "Could not clean all files in /var/tmp (permissions? files vanished?)"
   fi
}

clean_user_cache() {
  msg "[8/9] Cleaning user cache..." # Combined with journal & tmp step
  local real_home
  real_home="$(get_real_home)"
  local current_user="${SUDO_USER:-$(whoami)}" # Get original user if using sudo

  if [[ -z "$real_home" || ! -d "$real_home" ]]; then
    msg_warn "Could not determine user home directory for '$current_user'. Skipping user cache cleaning."
    return
  fi

  msg_sub "Cleaning cache for user: ${CLR_BOLD}${current_user}${CLR_RESET} (Home: ${real_home})"

  msg_info "Cleaning thumbnail cache: ${real_home}/.cache/thumbnails"
  # No need for sudo here, should be user's directory
  rm -rf "${real_home}/.cache/thumbnails/"* 2>/dev/null || true

  msg_info "Cleaning general application cache (files older than ${USER_CACHE_MAX_AGE_DAYS} days in ${real_home}/.cache)..."
  msg_info "${CLR_DIM}Note: This removes files, not necessarily empty directories immediately unless using -delete.${CLR_RESET}"
  # Use find directly as the user (or root if script run as root initially)
  find "${real_home}/.cache/" -mindepth 1 -type f -mtime +"${USER_CACHE_MAX_AGE_DAYS}" -delete 2>/dev/null || \
    msg_warn "Could not remove some old cache files in ${real_home}/.cache"
  # Attempt to remove empty directories left behind
  find "${real_home}/.cache/" -mindepth 1 -type d -empty -delete 2>/dev/null || true

  msg_info "Cleaning user Trash folder: ${real_home}/.local/share/Trash"
  rm -rf "${real_home}/.local/share/Trash/files/"* 2>/dev/null || true
  rm -rf "${real_home}/.local/share/Trash/info/"* 2>/dev/null || true

  msg_ok "User cache cleaning finished for ${current_user}."
}

clean_docker() {
  if [[ "$CLEAN_DOCKER" == "true" ]]; then
    if command -v docker &>/dev/null; then
      msg "[9/9] Cleaning Docker system..."
      msg_warn "This will remove: all stopped containers, all networks not used by at least one container,"
      msg_warn "all dangling images, all build cache, AND ${CLR_RED}${CLR_BOLD}ALL UNUSED VOLUMES${CLR_RESET}${CLR_YELLOW}.${CLR_RESET}"

      # Optional interactive prompt (kept commented out by default)
      # local confirm_docker
      # read -rp "$(echo -e ${CLR_YELLOW}"❓ Proceed with 'docker system prune -a --volumes'? (y/N): "${CLR_RESET})" confirm_docker
      # if [[ "${confirm_docker,,}" == "y" ]]; then
      #   run_sudo docker system prune -a -f --volumes
      #   msg_ok "Docker prune executed."
      # else
      #   msg_info "Skipping Docker prune."
      # fi

      # Unattended execution:
      run_sudo docker system prune -a -f --volumes
      msg_ok "Docker prune executed."

    else
       msg "[9/9] ${CLR_DIM}Docker command not found. Skipping Docker cleanup.${CLR_RESET}"
    fi
  else
     msg "[9/9] ${CLR_DIM}Docker cleanup is disabled in configuration. Skipping.${CLR_RESET}"
  fi
}

# --- Main Execution ---
echo -e "${CLR_BOLD}${CLR_GREEN}"
echo "###########################################################"
echo "##       🚀 Starting Linux Deep Clean & Update 🚀      ##"
echo "###########################################################"
echo -e "${CLR_RESET}"

msg "--- Initial Disk Usage ---"
df -hT / /home /var /tmp || msg_warn "Could not retrieve initial disk usage."
echo "--------------------------"

msg "Syncing filesystem buffers..."
sync

PM=$(detect_package_manager)
if [[ "$PM" == "unknown" ]]; then
  msg_err "Could not detect a supported package manager (apt, dnf, yum, zypper, nix). Aborting."
  exit 1
fi
msg "Detected Package Manager: ${CLR_BOLD}${PM}${CLR_RESET}"

REAL_HOME=$(get_real_home)
CURRENT_USER="${SUDO_USER:-$(whoami)}"
msg "Detected User: ${CLR_BOLD}${CURRENT_USER}${CLR_RESET}, Home: ${CLR_BOLD}${REAL_HOME}${CLR_RESET}"
echo # Add a blank line for spacing

# --- Main Tasks ---
update_repos        # 1
upgrade_packages    # 2
remove_orphans      # 3
clean_package_cache # 4
remove_old_kernels  # 5
clean_flatpak       # 6
clean_snap          # 7

# Combine Journal, Tmp, and User Cache into one step for numbering
msg "[8/9] System & User Cleanup Tasks..."
clean_journal
clean_tmp_dirs
clean_user_cache

clean_docker        # 9

msg "Flushing final filesystem buffers..."
sync
sleep 1 # Small delay for effect and ensure sync completes

echo # Add a blank line for spacing
msg "--- Final Disk Usage ---"
df -hT / /home /var /tmp || msg_warn "Could not retrieve final disk usage."
echo "------------------------"

echo -e "${CLR_BOLD}${CLR_GREEN}"
echo "###########################################################"
echo "## ✅ System cleanup and update script completed! ✅      ##"
echo "###########################################################"
echo -e "${CLR_RESET}"

exit 0 # Explicitly exit with success
