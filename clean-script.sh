#!/usr/bin/env bash

# Update package repositories (may vary by distribution)
if [ -x "$(command -v apt-get)" ]; then
  sudo apt-get update
elif [ -x "$(command -v dnf)" ]; then
  sudo dnf check-update
elif [ -x "$(command -v yum)" ]; then
  sudo yum check-update
elif [ -x "$(command -v zypper)" ]; then
  sudo zypper refresh
elif [ -x "$(command -v nix-env)" ]; then
  sudo nixos-rebuild switch --upgrade
fi

# Upgrade system packages
if [ -x "$(command -v apt-get)" ]; then
  sudo apt-get -y upgrade
elif [ -x "$(command -v dnf)" ]; then
  sudo dnf -y upgrade
elif [ -x "$(command -v yum)" ]; then
  sudo yum -y update
elif [ -x "$(command -v zypper)" ]; then
  sudo zypper update
fi

# Remove orphaned packages (may vary by distribution)
if [ -x "$(command -v apt-get)" ]; then
  sudo apt-get autoremove --purge
elif [ -x "$(command -v dnf)" ]; then
  sudo dnf autoremove
elif [ -x "$(command -v yum)" ]; then
  sudo package-cleanup --leaves
elif [ -x "$(command -v zypper)" ]; then
  sudo zypper packages --unneeded
elif [ -x "$(command -v nix-env)" ]; then
  sudo sudo nix-collect-garbage --delete-older-than 14d
fi

# Clean package cache
if [ -x "$(command -v apt-get)" ]; then
  sudo apt-get clean
elif [ -x "$(command -v dnf)" ]; then
  sudo dnf clean packages
elif [ -x "$(command -v yum)" ]; then
  sudo yum clean all
elif [ -x "$(command -v zypper)" ]; then
  sudo zypper clean --all
elif [ -x "$(command -v nix-env)" ]; then
  sudo nix-store --optimise
fi

# Check if Flatpak is installed
if command -v flatpak &> /dev/null; then
    echo "Flatpak is installed. Updating and removing unused runtimes and apps..."
    
    # Update Flatpak
    flatpak update
    
    # Remove unused runtimes and apps
    flatpak uninstall --unused
    
    echo "Flatpak update and cleanup completed."
else
    echo "Flatpak is not installed. Skipping the process."
fi

# Check if Snap is installed
if command -v snap &> /dev/null; then
    echo "Snap is installed. Updating snap packages and cleaning unused ones..."
    
    # Update Snap packages
    sudo snap refresh
    
    # Clean unused Snap revisions
    sudo snap set system refresh.retain=2 # Keep 2 latest revisions
    sudo snap refresh --amend
    
    echo "Snap update and cleanup completed."
else
    echo "Snap is not installed. Skipping the process."
fi


# Remove old logs (may vary by distribution)
sudo journalctl --vacuum-time=2d

# Clean temporary files
sudo rm -rf /tmp/*

# Clean thumbnail cache
rm -rf ~/.cache/thumbnails/*

# Remove old kernels (may vary by distribution)
if [ -x "$(command -v apt-get)" ]; then
  sudo apt-get autoremove --purge
elif [ -x "$(command -v dnf)" ]; then
  sudo package-cleanup --oldkernels --count=1
elif [ -x "$(command -v yum)" ]; then
  sudo package-cleanup --oldkernels --count=1
elif [ -x "$(command -v zypper)" ]; then
  sudo zypper remove-old-kernels --keep 1
fi

# Remove old logs in /var/log
sudo find /var/log -type f -name '*.gz' -exec rm -f {} \;
sudo find /var/log -type f -name '*.1' -exec rm -f {} \;

# Remove cached package data (apt)
if [ -x "$(command -v apt-get)" ]; then
  sudo apt-get clean
  sudo rm -rf /var/lib/apt/lists/*
fi

# Print a message
echo "System cleanup and update completed."

