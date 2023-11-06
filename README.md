# Linux System Cleaner and Updater 🧹

![Clean Logo](https://img.itch.zone/aW1nLzQ5NTc4MDMuZ2lm/original/NP6Vjv.gif))

This is a Bash script to clean up and update your Linux system. It works on various Linux distributions, including Debian, Arch, Fedora, and NixOS. The script automates common maintenance tasks to keep your system clean and up to date.

## Features

- Updates package repositories specific to your distribution.
- Upgrades system packages to the latest versions.
- Removes orphaned packages.
- Cleans package cache.
- Manages old kernel and logs.
- Empties the trash, cleans temporary files, and more.

## Usage

1. Clone the repository or download the script to your local machine.

```shell
git clone https://github.com/turtlecute33/linux-system-cleaner.git
```
1. Make the script executable if it's not already:
```
chmod +x clean-script.sh
```
1. Run the script with sudo privileges:
```
sudo ./clean-script.sh
```
1. The script will automatically detect your Linux distribution and perform the necessary cleanup and updates.

## Customisation
You can customize the script to suit your specific needs by editing it. Be cautious when modifying the script, especially if you're not familiar with Bash scripting.

## Important notes
- Always back up your data before running the script.
- Make sure you understand what the script does before using it on a production system.
- Be prepared for potential differences in behavior on specific distributions.

  Happy cleaning! 🧹

