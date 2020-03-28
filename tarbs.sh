#!/bin/sh
# T's Auto Rice Boostrapping Script (TARBS)
# based on Luke Smiths LARBS <luke@lukesmith.xyz>

### OPTIONS AND VARIABLES ###

while getopts ":a:r:p:h:w" o; do case "${o}" in
	h) printf "Optional arguments for custom use:\\n  -r: Dotfiles repository (local file or url)\\n  -p: Dependencies and programs csv (local file or url)\\n  -a: AUR helper (must have pacman-like syntax)\\n  -h: Show this message\\n" && exit ;;
	r) dotfilesrepo=${OPTARG} && git ls-remote "$dotfilesrepo" || exit ;;
	p) progsfile=${OPTARG} ;;
	a) aurhelper=${OPTARG} ;;
	w) wallpapers=${OPTARG} ;;
	*) printf "Invalid option: -%s\\n" "$OPTARG" && exit ;;
esac done

# DEFAULTS:
[ -z "$dotfilesrepo" ] && dotfilesrepo="https://github.com/oveee92/.dotfiles.git"
[ -z "$progsfile" ] && progsfile="https://raw.githubusercontent.com/oveee92/tarbs/master/progs.csv"
[ -z "$aurhelper" ] && aurhelper="yay"
[ -z "$wallpapers" ] && wallpapers="https://github.com/oveee92/wallpapers.git"
[ -z "$tarbs" ] && tarbs="https://github.com/oveee92/tarbs.git"

### FUNCTIONS ###

error() { clear; echo "ERROR: $1" >> /root/errors.txt; exit;}

welcomemsg() { \
	dialog --title "Welcome!" --msgbox "Welcome to T's Auto-Rice Bootstrapping Script!\\n\\nThis script will automatically install a fully-featured i3wm Arch Linux desktop, which I use as my main machine.\\n\\n-Ove" 10 60
	}

getuserandpass() { \
	# Prompts user for new username an password.
	name=$(dialog --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit
	while ! echo "$name" | grep "^[a-z_][a-z0-9_-]*$" >/dev/null 2>&1; do
		name=$(dialog --no-cancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
	pass1=$(dialog --no-cancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
	pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
		pass1=$(dialog --no-cancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
		pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	done ;}

usercheck() { \
	! (id -u "$name" >/dev/null) 2>&1 ||
	dialog --colors --title "WARNING!" --yes-label "CONTINUE" --no-label "No wait..." --yesno "The user \`$name\` already exists on this system. TARBS can install for a user already existing, but it will \\Zboverwrite\\Zn any conflicting settings/dotfiles on the user account.\\n\\nTARBS will \\Zbnot\\Zn overwrite your user files, documents, videos, etc., so don't worry about that, but only click <CONTINUE> if you don't mind your settings being overwritten.\\n\\nNote also that TARBS will change $name's password to the one you just gave." 14 70
	}

preinstallmsg() { \
	dialog --title "Let's get this party started!" --yes-label "Let's go!" --no-label "No, nevermind!" --yesno "The rest of the installation will now be totally automated, so you can sit back and relax.\\n\\nIt will take some time, but when done, you can relax even more with your complete system.\\n\\nNow just press <Let's go!> and the system will begin installation!" 13 60 || { clear; exit; }
	}

adduserandpass() { \
	# Adds user `$name` with password $pass1.
	dialog --infobox "Adding user \"$name\"..." 4 50
	useradd -m -g wheel -s /bin/bash "$name" >/dev/null 2>&1 ||
	usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
	echo "$name:$pass1" | chpasswd
	unset pass1 pass2 ;}

refreshkeys() { \
	dialog --infobox "Refreshing Arch Keyring..." 4 40
	pacman --noconfirm -Sy archlinux-keyring >/dev/null 2>&1
	}

newperms() { \
	# Set special sudoers settings for install (or after).
	sed -i "/#TARBS/d" /etc/sudoers
	echo "$* #TARBS" >> /etc/sudoers ;}

manualinstall() { \
	# Installs $1 manually if not installed. Used only for AUR helper here.
	[ -f "/usr/bin/$1" ] || (
	dialog --infobox "Installing \"$1\", an AUR helper..." 4 50
	cd /tmp || exit
	rm -rf /tmp/"$1"*
	curl -sO https://aur.archlinux.org/cgit/aur.git/snapshot/"$1".tar.gz &&
	sudo -u "$name" tar -xvf "$1".tar.gz >/dev/null 2>&1 &&
	cd "$1" &&
	sudo -u "$name" makepkg --noconfirm -si >/dev/null 2>&1
	cd /tmp || return) ;}

maininstall() { \
	# Installs all needed programs from main repo.
	dialog --title "TARBS Installation" --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
	pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
	}

gitmakeinstall() { \
	dir=$(mktemp -d)
	dialog --title "TARBS Installation" --infobox "Installing \`$(basename "$1") \` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2" 5 70
	git clone --depth 1 "$1" "$dir" >/dev/null 2>&1
	cd "$dir" || exit
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return ;}

aurinstall() { \
	dialog --title "TARBS Installation" --infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 5 70
	echo "$aurinstalled" | grep "^$1$" >/dev/null 2>&1 && return
	sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
	}

pipinstall() { \
	dialog --title "TARBS Installation" --infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 5 70
	command -v pip || pacman -S --noconfirm --needed python-pip >/dev/null 2>&1 # Installs pip if not installed
	sudo -u "$name" python3 -m pip install "$1"
	}

installationloop() { \
	([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) || curl -Ls "$progsfile" | sed '/^#/d' > /tmp/progs.csv
	total=$(wc -l < /tmp/progs.csv)
	aurinstalled=$(pacman -Qm | awk '{print $1}')
	while IFS=, read -r tag program comment; do
		n=$((n+1))
		echo "$comment" | grep "^\".*\"$" >/dev/null 2>&1 && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		case "$tag" in
			"") maininstall "$program" "$comment" ;;
			"A") aurinstall "$program" "$comment" ;;
			"G") gitmakeinstall "$program" "$comment" ;;
			"P") pipinstall "$program" "$comment" ;;
		esac
	done < /tmp/progs.csv ;}

putgitrepo() { \
	# Downlods a gitrepo $1 and places the files in $2 only overwriting conflicts
	dialog --infobox "$3" 4 60
	dir=$(mktemp -d)
	[ ! -d "$2" ] && mkdir -p "$2" && chown -R "$name:wheel" "$2"
	chown -R "$name:wheel" "$dir"
	sudo -u "$name" git clone --depth 1 "$1" "$dir/gitrepo" >/dev/null 2>&1 &&
	sudo -u "$name" cp -rfT "$dir/gitrepo" "$2"
	}

serviceinit() { \
	for service in "$@"; do
	dialog --infobox "Enabling \"$service\"..." 4 40
	systemctl enable "$service"
	systemctl start "$service"
	done ;}

systembeepoff() { \
	dialog --infobox "Getting rid of that retarded error beep sound..." 10 50
	rmmod pcspkr
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf ;}

resetpulse() { \
	dialog --infobox "Reseting Pulseaudio..." 4 50
	killall pulseaudio
	sudo -n "$name" pulseaudio --start
}

configurelocale() { \
	sed -i '/nb_NO/ s/#//' /etc/locale.gen
	sed -i '/en_US/ s/#//' /etc/locale.gen
	locale-gen
	echo "LANG=en_US.utf8" > /etc/locale.conf
	echo "LC_CTYPE=\"nb_NO.utf8\"" >> /etc/locale.conf
	echo "LC_MESSAGES=\"en_US.utf8\"" >> /etc/locale.conf
	echo "LC_COLLATE=\"en_US.utf8\"" >> /etc/locale.conf
	localectl set-keymap no
	localectl set-x11-keymap no
	ln -sf /usr/share/zoneinfo/Europe/Oslo /etc/localtime
}


downloadwallpapers() { \
	# Download wallpapers from github
	dialog --colors --title "Download Ove's wallpapers?" --yes-label "Yes!" --no-label "I'll find my own." --yesno "Allright, stand by. This might take a while as the repo is pretty big!" 14 70 \
		|| putgitrepo "$wallpapers" "/home/$name/Pictures/wallpapers" "Downloading wallpapers..." \
		|| error "Failed to download wallpapers."
}

installdotfiles() { \
	putgitrepo "$dotfilesrepo" "/home/$name" "Installing dotfiles..." || error "Failed to download dotfiles."
	rm -f "/home/$name/README.md" "/home/$name/LICENSE"	|| error "Failed to delete README.md and LICENSE"
}

changetheme() { \
	# Replace greeter session with custom if installed
	pacman -Qi lightdm-webkit2-greeter 2>/dev/null && sed -i '/greeter-session/ {s/^#//;s/=.*/=lightdm-webkit2-greeter/;}' /etc/lightdm/lightdm.conf

	# Replace theme with custom (litarvan) if installed
	pacman -Qi lightdm-webkit-theme-litarvan 2>/dev/null && sed -i '/^webkit_theme/ s/=.*/= litarvan/' /etc/lightdm/lightdm-webkit2-greeter.conf

	# Add custom profile picture on login screen if litarvan is installed and if picture exists
#	pacman -Qi lightdm-webkit-theme-litarvan 2>/dev/null || sudo cp -p /home/$name/.icons/default_user.png /usr/share/lightdm-webkit/themes/litarvan/images/default_user.png
}

initgpg() { \
	echo "Initiating gpg keygen. Please follow the instructions, and remember the email you insert."
	gpg2 --full-gen-key
	read -p "Write the email you used for gpg2: " gpgemail
	pass init $gpgemail
	echo "All done! Use the command pass --init <gpg2 email> and then use mw add to configure mutt."
}

finalize(){ \
	dialog --infobox "Preparing welcome message..." 4 50
	echo "exec_always --no-startup-id notify-send -i ~/.scripts/larbs.png 'Welcome to TARBS:' 'Press Super+F1 for the manual.' -t 10000"  >> "/home/$name/.config/i3/config"
	dialog --title "All done!" --msgbox "Congrats! Provided there were no hidden errors, the script completed successfully and all the programs and configuration files should be in place.\\n\\nTo run the new graphical environment, log out and log back in as your new user, then run the command \"startx\" to start the graphical environment (it will start automatically in tty1).\\n\\n.t Luke" 12 80
	}

### THE ACTUAL SCRIPT ###

### This is how everything happens in an intuitive format and order.

# Check if user is root on Arch distro. Install dialog.
pacman -Syu --noconfirm --needed dialog ||  error "Are you sure you're running this as the root user? Are you sure you're using an Arch-based distro? Are you sure you have an internet connection? Are you sure your Arch keyring is updated?"

# Welcome user.
welcomemsg || error "User exited."

# Get and verify username and password.
getuserandpass || error "User exited."

# Give warning if user already exists.
usercheck || error "User exited."

# Last chance for user to back out before install.
preinstallmsg || error "User exited."

### The rest of the script requires no user input.

adduserandpass || error "Error adding username and/or password."

# Refresh Arch keyrings.
refreshkeys || error "Error automatically refreshing Arch keyring. Consider doing so manually."

dialog --title "TARBS Installation" --infobox "Installing \`basedevel\` and \`git\` for installing other software." 5 70
pacman --noconfirm --needed -S base-devel git >/dev/null 2>&1
[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

# Allow user to run sudo without password. Since AUR programs must be installed
# in a fakeroot environment, this is required for all builds with AUR.
newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

# Make pacman and yay colorful and adds eye candy on the progress bar because why not.
grep "^Color" /etc/pacman.conf >/dev/null || sed -i "s/^#Color/Color/" /etc/pacman.conf
grep "ILoveCandy" /etc/pacman.conf >/dev/null || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

manualinstall $aurhelper || error "Failed to install AUR helper."

# The command that does all the installing. Reads the progs.csv file and
# installs each needed program the way required. Be sure to run this only after
# the user has been created and has priviledges to run sudo without a password
# and all build dependencies are installed.
installationloop

# Install the dotfiles in the user's home directory
installdotfiles || error "Could not install dotfiles."

# Download the desktop background wallpapers from github
#downloadwallpapers || error "Could not download wallpapers."

# Download the tarbs repo from github
putgitrepo "$tarbs" "/home/$name/.tarbs" "Downloading tarbs..." || error "Failed to download tarbs."

# Pulseaudio, if/when initially installed, often needs a restart to work immediately.
[ -f /usr/bin/pulseaudio ] && resetpulse

# Install vim `plugged` plugins.
sudo -u "$name" mkdir -p "/home/$name/.config/nvim/autoload"
curl "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" > "/home/$name/.config/nvim/autoload/plug.vim"
dialog --infobox "Installing (neo)vim plugins..." 4 50
sudo -u "$name" nvim -E -c "PlugUpdate|visual|q|q" >/dev/null 2>&1

# Install plugin for i3 syntax highlighting
cd /home/$name/.config/nvim/plugged/
git clone https://github.com/PotatoesMaster/i3-vim-syntax.git

# Most important command! Get rid of the beep!
systembeepoff

# Set keyboard settings
configurelocale || error "Cannot configure locale."

# Change theme
changetheme

# This line, overwriting the `newperms` command above will allow the user to run
# serveral important commands, `shutdown`, `reboot`, updating, etc. without a password.
newperms "%wheel ALL=(ALL) ALL #TARBS
%wheel ALL=(ALL) NOPASSWD: /usr/bin/openvpn, /usr/bin/pkill openvpn, /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syu,/usr/bin/packer -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay,/usr/bin/pacman -Syyuw --noconfirm"

# Installing and configuring dropbox.
echo "Installing dropbox."
wget -O - "https://www.dropbox.com/download?plat=lnx.x86_64" | tar xzf -
echo "Setting correct owner and moving to owners home folder."
chown "$name":wheel ~/.dropbox-dist
mv ~/.dropbox-dist /home/$name/

# Installing linux dropbox script
echo "Installing dropbox service for linux."
sudo -u "$name" mkdir /home/$name/.dropbox
sudo -u "$name" wget -O - "https://www.dropbox.com/download?dl=packages/dropbox.py" > /home/$name/.dropbox/dropboxscript.py
chmod 775 /home/$name/.dropbox/dropboxscript.py
echo "Make it start on boot"
sudo -u "$name" /home/$name/.dropbox/dropboxscript.py autostart y

# Remove junk from muttrc:
echo "Cleaning up"
sed -i '/.*mw-autogenerated$/d' /home/$name/.config/mutt/muttrc
sudo -u "$name" mkdir /home/$name/Downloads

# Prepare for mutt-wizard install
#dialog --colors --title "Set up gpg?" --yes-label "Yes" --no-label "No" --yesno "Initiating gpg keygen. Please follow the instructions, and remember the email you insert." 14 70 || initgpg

#set gpg keys for
# VPN
# Keepass
# Other

# Enable services here.
serviceinit NetworkManager cronie

# Set up mopidy service at user level, both now and at boot
sudo -u "$name" systemctl --user enable mopidy --now || error "Cannot enable mopidy"
#sudo -u "$name" mopidy gmusic login

# Last message! Install complete!
finalize
serviceinit lightdm
clear
