# Linux System Cleaner and Updater 🧹

<center><img src="https://imgur.com/OV44KER.gif" width="80%" height="60%"></center>


This is a Bash script to clean up and update your Linux system. It works on various Linux distributions, including Debian, Arch, Fedora, and NixOS. The script automates common maintenance tasks to keep your system clean and up to date.

## Features

- Updates package repositories specific to your distribution.
- Upgrades system packages to the latest versions.
- Removes orphaned packages.
- Support and clean also snap & flatpak packages.
- Cleans package cache.
- Manages old kernel and logs.
- Empties the trash, cleans temporary files, and more.

## Usage

Clone the repository or download the script to your local machine.

```shell
git clone https://github.com/turtlecute33/linux-system-cleaner.git
```
 Make the script executable if it's not already:
```
chmod +x clean-script.sh
```
Run the script with sudo privileges:
```
sudo ./clean-script.sh
```
The script will automatically detect your Linux distribution and perform the necessary cleanup and updates.

## Customisation
You can customize the script to suit your specific needs by editing it. Be cautious when modifying the script, especially if you're not familiar with Bash scripting.

## Important notes
- Always back up your data before running the script.
- Make sure you understand what the script does before using it on a production system.
- Be prepared for potential differences in behavior on specific distributions.

  Happy cleaning! 🧹

