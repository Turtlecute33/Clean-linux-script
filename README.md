# Smart Linux System Cleaner 🧹✨

<center><img src="https://imgur.com/OV44KER.gif" width="80%" height="60%"></center>

A comprehensive, safe, and feature-rich Bash script to clean up and maintain your Linux system. Works across multiple Linux distributions with advanced safety features and extensive cleaning capabilities.

## ✨ Features

### Package Management
- 📦 Updates package repositories
- ⬆️ Upgrades system packages
- 🗑️ Removes orphaned packages
- 💾 Cleans package caches
- 🔧 Manages old kernels safely
- 📱 Supports Flatpak and Snap packages

### System Cleaning
- 🗂️ Cleans systemd journal logs (time and size based)
- 📁 Removes old temporary files
- 🖼️ Cleans thumbnail caches
- 🗑️ Empties user trash
- 📝 Manages application logs
- 🗜️ Removes old compressed system logs

### Browser Cleaning
- 🌐 Firefox cache cleaning
- 🌐 Chrome/Chromium cache cleaning
- 🔒 Optional history cleaning (disabled by default)

### Desktop Environment
- 📋 Clears recent documents (optional)
- 📌 Clears clipboard history (optional)
- 🎨 Cleans icon cache

### Docker Support
- 🐳 Docker system pruning
- 📦 Optional volume pruning (with confirmation)
- 🏗️ Optional builder cache cleaning

### Safety Features
- 🔍 **Dry run mode** to preview changes
- 📊 **Space tracking** shows freed space per operation
- ⚠️ **Interactive confirmations** for dangerous operations
- 🛡️ **Conservative defaults** to prevent data loss
- 🔐 Protects current kernel from deletion

## 🖥️ Supported Distributions

- **Debian/Ubuntu** (apt)
- **Fedora** (dnf)
- **RHEL/CentOS** (yum)
- **openSUSE** (zypper)
- **Arch Linux** (pacman)
- **NixOS** (nix)

## 🚀 Installation

Clone the repository:

```bash
git clone https://github.com/turtlecute33/linux-system-cleaner.git
cd linux-system-cleaner
```

Make the script executable:

```bash
chmod +x clean-script.sh
```

## 📖 Usage

### Basic Usage

Run with root privileges using your preferred method:

```bash
# Using sudo
sudo ./clean-script.sh

# Using doas
doas ./clean-script.sh

# As root
./clean-script.sh
```

### Dry Run Mode (Recommended First Time)

Preview what will be cleaned without actually deleting anything:

```bash
# Edit the script and set: DRY_RUN=true
sudo ./clean-script.sh
```

### Custom Configuration

Edit the configuration section at the top of the script to customize behavior:

```bash
# Example: Enable browser cache cleaning
CLEAN_BROWSER_CACHE=true

# Example: More aggressive temp file cleaning
TMP_FILE_MAX_AGE_DAYS=3

# Example: Keep only 1 old kernel
KEEP_KERNELS=1
```

## ⚙️ Configuration Options

### Basic Settings
```bash
KEEP_KERNELS=2                    # Number of old kernels to keep
JOURNAL_VACUUM_TIME="3d"          # Max age for journal logs
JOURNAL_VACUUM_SIZE="500M"        # Max size for journal logs
TMP_FILE_MAX_AGE_DAYS=7           # Age threshold for temp files
USER_CACHE_MAX_AGE_DAYS=14        # Age threshold for user cache
```

### Cleaning Options
```bash
CLEAN_USER_CACHE_FILES=true       # Clean general cache files
CLEAN_THUMBNAILS=true             # Clean thumbnail cache
CLEAN_TRASH=true                  # Empty trash
CLEAN_BROWSER_CACHE=false         # Clean browser caches
CLEAN_BROWSER_HISTORY=false       # Clean browser history (⚠️)
CLEAN_RECENT_DOCUMENTS=false      # Clear recent documents
CLEAN_CLIPBOARD_HISTORY=false     # Clear clipboard history
CLEAN_APPLICATION_LOGS=true       # Clean app logs
CLEAN_DOCKER=true                 # Enable Docker cleanup
CLEAN_DOCKER_VOLUMES=false        # Prune Docker volumes (⚠️)
```

### Advanced Options
```bash
AGGRESSIVE_PKG_CACHE_CLEAN=false  # More aggressive cache cleaning
DRY_RUN=false                     # Preview mode (no deletions)
```

## 🛡️ Safety Features

### What Gets Protected
- ✅ Current running kernel
- ✅ User documents and files
- ✅ Application configurations
- ✅ Database files
- ✅ Active Docker containers/images
- ✅ Browser bookmarks and passwords

### What Gets Cleaned (Safely)
- ✅ Package manager caches
- ✅ Old system logs
- ✅ Thumbnail caches
- ✅ Temporary files (older than threshold)
- ✅ Trash contents
- ✅ Browser caches (if enabled)
- ✅ Old kernels (keeping recent ones)

### Dangerous Operations (Require Confirmation)
- ⚠️ Browser history deletion
- ⚠️ Docker volume pruning
- ⚠️ Docker builder cache cleaning

## 📊 Output Example

```
###############################################################
##  🚀 Smart Linux System Cleaner v2.0.0 🚀             ##
###############################################################

>>> Configuration Summary:
  :: Keep Kernels: 2
  :: Journal Vacuum: 3d / 500M
  :: Temp Files Age: 7 days
  :: User Cache Age: 14 days
  :: Dry Run Mode: false

>>> Initial Disk Usage
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1       900G   40G  815G   5% /

>>> Detected Package Manager: apt

>>> [1/13] Updating package repositories...
>>> [2/13] Upgrading system packages...
>>> [3/13] Removing orphaned/unneeded packages...
✔ OK: Freed 128MB
>>> [4/13] Cleaning package cache...
✔ OK: Freed 2GB
...

>>> Final Disk Usage
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1       900G   37G  818G   5% /

###############################################################
##   ✅ System Cleanup Completed Successfully! ✅              ##
###############################################################
✔ OK: Total Space Freed: 3GB
✔ OK: Script Duration: 45 seconds
```

## 🔧 Privilege Escalation Support

The script automatically detects and uses the available privilege escalation method:

- **root**: Runs commands directly
- **sudo**: Standard Linux privilege escalation
- **doas**: OpenBSD-style privilege escalation (Alpine, Void, etc.)

## ⚡ Quick Tips

### Safe First Run
```bash
# 1. Preview what will be cleaned
# Edit script: DRY_RUN=true
sudo ./clean-script.sh

# 2. Review the output
# 3. Adjust configuration if needed
# 4. Run for real
# Edit script: DRY_RUN=false
sudo ./clean-script.sh
```

### Regular Maintenance
```bash
# Run monthly with default settings
sudo ./clean-script.sh
```

### Aggressive Cleaning
```bash
# Edit these settings in the script:
TMP_FILE_MAX_AGE_DAYS=3
USER_CACHE_MAX_AGE_DAYS=7
CLEAN_BROWSER_CACHE=true
AGGRESSIVE_PKG_CACHE_CLEAN=true
```

## 🔍 Troubleshooting

### "Command not found" errors
Some optional tools may not be installed:
- `paccache`: Install `pacman-contrib` on Arch
- `package-cleanup`: Install `yum-utils` on RHEL/CentOS

### Script requires root privileges
```bash
# Make sure to run with sudo, doas, or as root
sudo ./clean-script.sh
```

### Nothing gets deleted
Check if `DRY_RUN=true` is set in the configuration.

## ⚠️ Important Notes

### Before Running
- 🔴 **Backup important data** before first run
- 🔴 Test with **dry run mode** first
- 🔴 Review configuration options carefully
- 🔴 Understand what each option does

### During Execution
- ✅ Read confirmation prompts carefully
- ✅ Don't interrupt kernel removal operations
- ✅ Watch for warnings and errors

### After Running
- ✅ Review freed space statistics
- ✅ Verify system still boots properly
- ✅ Check that applications work correctly

## 🎯 Recommended Settings

### For Desktop Users
```bash
KEEP_KERNELS=2
USER_CACHE_MAX_AGE_DAYS=14
CLEAN_BROWSER_CACHE=false         # Enable if needed
CLEAN_DOCKER=false                # Unless you use Docker
```

### For Servers
```bash
KEEP_KERNELS=2
JOURNAL_VACUUM_TIME="7d"          # Keep more logs
CLEAN_BROWSER_CACHE=false         # No browsers on servers
CLEAN_DOCKER=true                 # If running containers
```

### For Privacy-Focused Users
```bash
CLEAN_BROWSER_CACHE=true
CLEAN_RECENT_DOCUMENTS=true
CLEAN_CLIPBOARD_HISTORY=true
# Keep CLEAN_BROWSER_HISTORY=false unless you're sure
```

## 🤝 Contributing

Contributions are welcome! Please:
1. Test changes thoroughly
2. Maintain backward compatibility
3. Document new features
4. Follow existing code style
5. Add safety checks for new operations

## 📝 License

This project is open source. Feel free to modify and distribute as needed.

## 🙏 Acknowledgments

Inspired by various Linux maintenance tools and best practices from the community.

## 📞 Support

If you encounter issues:
1. Check the troubleshooting section
2. Review your configuration
3. Test with dry run mode
4. Open an issue on GitHub with details

---

**Happy cleaning! 🧹✨**

Made with ❤️ for the Linux community
