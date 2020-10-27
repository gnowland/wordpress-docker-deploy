# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# see /usr/share/doc/bash/examples/startup-files for examples.
# the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# if running bash
if [ -n "$BASH_VERSION" ]; then
		# include .bashrc if it exists
		if [ -f "$HOME/.bashrc" ]; then
	. "$HOME/.bashrc"
		fi
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
		PATH="$HOME/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ] ; then
		PATH="$HOME/.local/bin:$PATH"
fi

### Aliases
alias la='ls -Flash --color=always'

### Functions
# ls with octal permissions (e.g. 755)
function lap { ls -Flah --color=always "$@" | awk '{k=0;for(i=0;i<=8;i++)k+=((substr($1,i+2,1)~/[rwx]/)*2^(8-i));if(k)printf(" %0o ",k);print}'; }

# find things
function ggg { grep -rIlnws --exclude-dir={tmp,boot,dev,media,mnt,proc,run} $@ / ; }

# restart nginx
function rnx {
	sudo nginx -t
	sudo nginx -s reload
}

# enter docker conainter
function bin {
				if [ $# -eq 0 ]; then
								echo "You must supply an app name!"
								return 1
				fi
	if [ $# -eq 2 ] && [ "$2" = "-s" ] || [ "$2" = "sudo" ]; then
		sudo docker exec -it $1.web.1 /bin/bash;
	else
		docker exec -it $1.web.1 /bin/bash;
	fi
}

# download git repo, extract, set ownership/permissions, clean up.
# @example wgit [<user/repo>]
function wgit {
	if [ $# -eq 0 ]; then
		echo "You must supply a valid user & repo (i.e. user/repo)!"
		return 1
	fi
	DIR=$(echo $1 | cut -d'/' -f2- ) && \
	sudo rm -f master.zip && \
	sudo wget https://github.com/$1/archive/master.zip && \
	sudo unzip -q master.zip && sudo rm -f master.zip && \
	sudo mv -n "$DIR-master" "$DIR" && \
	sudo chown -R 32767:32767 "$DIR" && \
	sudo find "$DIR" -type d -exec chmod -- 755 {} \; && \
	sudo find "$DIR" -type f -exec chmod -- 644 {} \; && \
	echo "" && \
	ls -Flahd "$DIR" | awk '{k=0;for(i=0;i<=8;i++)k+=((substr($1,i+2,1)~/[rwx]/)*2^(8-i));if(k)printf(" %0o ",k);print}';
}

# extract, set ownership & permissions
function uzp {
	file=$1
	if [ $# -eq 0 ] || [ ${file##*.} -ne "zip" ]; then
		echo "You must specify a .zip file!"
		return 1
	fi

	DIR=$(echo $1 | sed 's/\(.*\)\..*/\1/')
	sudo unzip -q $1 && sudo rm -f $1 && \
	sudo chown -R 32767:32767 "$DIR" && \
	sudo find "$DIR" -type d -exec chmod -- 755 {} \; && \
	sudo find "$DIR" -type f -exec chmod -- 644 {} \; && \
	echo "" && \
	ls -Flahd "$DIR" | awk '{k=0;for(i=0;i<=8;i++)k+=((substr($1,i+2,1)~/[rwx]/)*2^(8-i));if(k)printf(" %0o ",k);print}';
}

# fix permissions
function pfix {
	sudo chown -R 32767:32767 . && \
	sudo find . -type d -exec chmod -- 755 {} \; && \
	sudo find . -type f -exec chmod -- 644 {} \;
}

# turn on/off sophos av
function av {
	if [ $# -eq 0 ]; then
		echo "You must specify off (-o) or on (-i)!"
		return 1
	fi

	case $1 in
	"-o" | "--off" | "off" )
		sudo echo "turning OFF sophos av..."
		echo "$ sudo /opt/sophos-av/bin/savdctl disable"
		sudo /opt/sophos-av/bin/savdctl disable

		echo "$ sudo systemctl stop sav-protect.service"
		sudo systemctl stop sav-protect.service

		echo "$ sudo systemctl stop sav-rms.service"
		sudo systemctl stop sav-rms.service
	;;
	"-i" | "--on" | "on" )
		sudo echo "turning ON sophos av..."
		echo "$ sudo systemctl start sav-rms.service"
		sudo systemctl start sav-rms.service

		echo "$ sudo systemctl start sav-protect.service"
		sudo systemctl start sav-protect.service

		echo "$ sudo /opt/sophos-av/bin/savdctl enable"
		sudo /opt/sophos-av/bin/savdctl enable
	;;
	esac
}

# clear up ram
function clr {
	free -h

	echo "Clearing PageCache, dentries and inodes."
	echo 3 > sudo /proc/sys/vm/drop_caches 
	echo "Clearing Swapfile"
	sudo swapoff -a && sudo swapon -a
	printf '\n%s\n' 'Ram-cache and Swap Cleared'
	free -h
}

# export or import database dump
function db {
	if [ $# -eq 0 ]; then
		echo "You must specify export (-e) or import (-i)!"
		return 1
	fi

	case $1 in
	"export" | "-e" )
		if [ $# -eq 2 ]; then
			# destination filename provided
			dokku mariadb:export stdb-wp > ~/.sql/$2
		else
			local TIMESTAMP=$(date +"%Y%m%d%H%M%S")
			dokku mariadb:export stdb-wp > ~/.sql/stdb-wp_$TIMESTAMP.sql
			echo "~/.sql/stdb-wp_$TIMESTAMP.sql"
		fi
	;;
	"import" | "-i" )
		if [ $# -eq 1 ]; then
			echo "You must specify .sql file to import!"
			return 1
		fi
		dokku mariadb:import stdb-wp < $2
	;;
	esac
}

###
# SYNC DEV <--> PROD
# (Only works on Vagrant)
###

# sync wp-content files down (-d) or up (-u) to/from a specified host ([<hostname or USER@]HOST>])
function sync {
	if [ $# -eq 0 ]; then
		echo "You must specify down (-d) or up (-u)!"
		return 1
	elif [ $# -eq 1 ]; then
		echo "You must specify [<hostname or USER@]HOST>]"
		return 1
	fi

	case $1 in
	"down" | "-d" )
		rsync -rltzvpa --super --delete --filter='dir-merge,-n /.gitignore' $2:/var/lib/dokku/data/storage/new/wp-content/ /var/lib/dokku/data/storage/new/wp-content/
		rsync -rltzvpa --super --delete $2:~/.ssh/ ~/.ssh/
	;;
	"up" | "-u" )
		rsync -rltzv --super --delete  --filter='dir-merge,-n /.gitignore' --rsync-path="sudo rsync" --chmod=D0755,F0644 --perms --chown=32767:32767 --owner --group /var/lib/dokku/data/storage/new/wp-content/ $2:/var/lib/dokku/data/storage/new/wp-content/
		rsync -rltzv --super --delete ~/.ssh/ $2:~/.ssh/
	;;
	esac

}

###
# iTerm Integeration
###

test -e "${HOME}/.iterm2_shell_integration.bash" && source "${HOME}/.iterm2_shell_integration.bash"

