#!/usr/bin/env bash


USER=$2
CHROOTHOME=/home/$USER/sync
CMDS="sh rsync bash ls cp mv rm mkdir cat du wget grep chmod expr wc tee dd touch vi head id head less tail rmdir pwd zip unzip"
DIRS="bin sbin lib lib64 etc dev usr usr/bin usr usr/lib usr/lib/locale usr/share usr/share/i18n/charmaps usr/share/i18n/locale usr/share/zoneinfo usr/share/locale/ru usr/share/locale/ru_RU content"
PROFTPDCONF=$(find /etc/ -name proftpd.conf)
copy="cp -p -L -u"
CHECKTANK=$(zpool status | grep -c tank)



#create filesystem and home for USER set permission for home 

create_home_dir() 
{

	if [ "$CHECKTANK" -eq 0 ] ; then
		echo "You MUST create zfs pool with 'tank' name"
		exit 1
	else
		echo  "tank pool already was created"
	fi 

	if [ "$(zfs list -o name | grep -c tank/"$USER")" -eq 0  ]; then
		zfs create tank/"$USER" &&  echo "create tank/$USER filesystem"
		zfs mountpoint=/home/"$USER" tank/"$USER" && echo "mount filesystem to home/$USER"
		#zfs set compression=lzjb tank/$USER
	else 
		echo "pool tank/$USER aready exits"
		exit 1
	fi

	[ ! -d /home/"$USER" ] || mkdir -pv /home/"$USER"
	[ ! -d "$CHROOTHOME" ] || mkdir -pv "$CHROOTHOME" | chown root:root "$CHROOTHOME" | chmod 755 "$CHROOTHOME"

}

install_libs() 
{
	local libs path lib
	libs=$(ldd "$1" | grep -o '\(\/.*\s\)')
	if [ ! -z "${libs// }" ]; then
		while read -r lib; do
			path=$(echo "$lib" | grep -o '\(\/.*\/\)')
			[ ! -d "$CHROOTHOME""$path" ] && mkdir -p "$CHROOTHOME""$path"
			[ ! -f "$CHROOTHOME""$lib" ] && $copy "$lib" "$CHROOTHOME""$lib"
		done <<< "$libs"
	fi
}

install_chroot_program()
{
	local program filetype
	program="$1"

# Get full path of program
	if [ ! -e "$program" ]; then
		command -v "$program" 1>/dev/null 
		if [ $? -ne 0 ]; then
			echo "Error: file $program is not found" >&2
			return 1
		else
			program=$(sh -c "which $program")
		fi
	fi

	filetype=$(file -Lib "$program")
	case "$filetype" in
	application/x-executable*statically" "linked*)		;&
	application/x-shellscript*|text/x-shellscript*)		;&
	application/x-executable*|application/x-sharedlib*)
		install_libs "$program"
	;;
	*)
		echo "WARNING: $program is not a program (filetype $filetype). Skipping." >&2
		return 2
	;;
	esac

	$copy "$program" "$CHROOTHOME/bin/"
	return 0
}

install_chroot_base()
{

# Create skeleton directories
	for dir in $DIRS; do
	mkdir -p -m 755 "$CHROOTHOME"/"$dir"
	done
	if [ -d /lib/x86_64-linux-gnu ]; then
		mkdir -p "$CHROOTHOME/lib64/"
		$copy /lib/x86_64-linux-gnu/libnss_*.so.2  "$CHROOTHOME/lib/x86_64-linux-gnu"
		$copy /lib64/ld-linux* "$CHROOTHOME/lib64/"
	else
		libcheck=$(ls /lib/ld-linux* 2> /dev/null | wc -l)
		if [ "$libcheck" -ne 0 ]; then
			$copy /lib/ld-linux* /lib/libnss_*.so.2  "$CHROOTHOME/lib"
		fi
		if [ -d /lib64 ]; then
			$copy /lib64/ld-linux* /lib64/libnss_*.so.2  "$CHROOTHOME/lib64"
		fi
	fi

	for f in $CMDS; do
		install_chroot_program "$f"
	done

	$copy /etc/{resolv.conf,localtime,hosts,nsswitch.conf,bashrc,services,hosts} "$CHROOTHOME"/etc/ 2>/dev/null
	$copy /usr/lib/locale/locale-archive "$CHROOTHOME"/usr/lib/locale/
	$copy /usr/share/i18n/locales/ru_RU "$CHROOTHOME"/usr/share/i18n/locales 2>/dev/null
	$copy /usr/share/i18n/charmaps/{UTF-8.gz,CP1251.gz} "$CHROOTHOME"/usr/share/i18n/charmaps
	$copy /usr/share/locale/ru/* "$CHROOTHOME"/usr/share/locale/ru/ 2>/dev/null
	$copy /usr/share/zoneinfo/posixrules "$CHROOTHOME"/usr/share/zoneinfo/

	if [ -f /etc/default/locale ]; then
		mkdir -m 755 -p "$CHROOTHOME/etc/default"
		$copy /etc/default/locale "$CHROOTHOME/etc/default/locale"
	elif [ -f /etc/locale.conf ]; then
		$copy /etc/locale.conf "$CHROOTHOME/etc/locale.conf"
	else
		echo "Couldn't find locale configuration, skipping."
	fi


	if test -r /etc/termcap; then
		$copy /etc/termcap "$CHROOTHOME/etc/termcap"
	fi

	mknod -m 666 "$CHROOTHOME"/dev/null c 1 3 2>/dev/null
	mknod -m 666 "$CHROOTHOME"/dev/tty c 5 0 2>/dev/null
	mknod -m 666 "$CHROOTHOME"/dev/urandom c 1 9 2>/dev/null

}

#create user, set Яussian language, add user to proftpd.conf
create_chroot_user() 
{
	if id "$USER" >/dev/null 2>&1; then
		echo "User $1 Already exist"
		exit 1
	else
		useradd "$USER"
		usermod -a -G sftp "$USER"
		usermod -m -d /content/ "$USER"
		chown "$USER"."$USER" -Rv "$CHROOTHOME"/content
		echo "export PATH=/bin 
		export LC_ALL="ru_RU.UTF-8"
		export PS1='[$USER@\h \W]\$ '" >> "$CHROOTHOME"/etc/profile
		grep -e "$USER" /etc/passwd > "$CHROOTHOME"/etc/passwd
		grep -e "$USER" /etc/group > "$CHROOTHOME"/etc/group
		[ ! -d /home/"$USER"/.ssh ] && mkdir /home/"$USER"/.ssh
		touch /home/"$USER"/.ssh/authorized_keys
		touch /home/"$USER"/.ssh/known_hosts
		chown -R "$USER":"$USER" /home/"$USER"/.ssh
	fi
#add in proftpd.conf
	if [[ $(grep -R "$USER" "$PROFTPDCONF") ]]; then  
			echo "User alredy added in $PROFTPDCONF" 
	else
		var=$(grep userhere "$PROFTPDCONF")
		var1=$var",$USER"
		sed -i "s/$var/$var1/g" "$PROFTPDCONF"
	fi
}


#clear enviroment for upadte
clear_env() 
{
rm -rf "$CHROOTHOME"/lib64/*
rm -rf "$CHROOTHOME"/bin/*
rm -rf "$CHROOTHOME"/etc/*
}
usage () 
{
	cat <<HELP
Add update and remove chrooted users

Usage: 
	$0 --add username
	$0 --update username
	$0 --remove username
HELP
}
prepare() 
{
local PROGRAMM
#checkroot

if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root" 
	exit 1
fi

#check ssh and proftpd and other utils

PROGRAMM="sshd proftpd"
for i in ${CMD[*]}; do
	isinstall=$(rpm -q "$i")
	if [ ! "$isinstall" == "package $i is not installed" ] ; then
		echo Package "$i" already installed
	else
		echo "$i" is not installed
		 
		yum install -y "$i" 
	fi
done
for j in ${PROGRAMM[*]}; do
	isinstalled=$(rpm -q "$j")
	if [ ! "$isinstalled" == "package $i is not installed" ] ; then 
		echo  Package "$j" already installed
	else
		echo "$j"  is not installed
		yum install -y "$j" 1>/dev/null
	fi
done
# Get correct SFTP path
	sftp_path="$(awk '/^Subsystem[[:space:]]sftp.*$/ {print $3}' < /etc/ssh/sshd_config)"
	
	if [ "$sftp_path" == "internal-sftp" ]; then 
		echo "Use default sftp-bin its fine"
	else
	    echo "changing /etc/ssh/sshd"
	    sed -i 's/^Subsystem[[:space:]]sftp.*$/Subsystem\tsftp\tinternal-sftp/g' /etc/ssh/sshd_config
	fi
# Change SFTP settings
	sftp_own="$(awk '/^#Match[[:space:]].*$/ { print $2}' < /etc/ssh/sshd_config)"
	if [ "$sftp_own" == "User" ]; then
		awk '/^#Match User/{s=1}s{if($0~/^#}/)s=0;sub("#"," ")}1' /etc/ssh/sshd_config
		sed -i '/^Match User/s/User anoncvs/Group sftp/g' /etc/ssh/sshd_config
		sed -e 's@ForceCommand cvs server@ChrootDirectory /home/%u/sync/ @' < /etc/ssh/sshd_config
	fi

	if grep -q "$0" "$PROFTPDCONF";  then
		echo "config $PROFTPDCONF already modifyed"
	else
		mv "$PROFTPDCONF" $PROFTPDCONF.bak
		cat > "$PROFTPDCONF" << EOF
#config generated from $0 script
ServerName                      "ProFTPD Default Installation"
ServerType                      standalone
DefaultServer                   on
ScoreboardFile          /var/run/proftpd/proftpd.scoreboard
Port                            21
UseIPv6                         off
Umask                           022
MaxInstances                    30
CommandBufferSize       512
User                            nobody
Group                           ftp
AllowOverwrite          on
PassivePorts 30000 30010
DefaultRoot  /home/%u/sync/content/
LangDefault ru_RU.UTF-8
LangEngine on
UseEncoding UTF-8 WINDOWS-CP1251
<Limit LOGIN>
  AllowUser
	userhere
Deny All
</Limit>        
EOF
	fi

 
}
#Add our proftpd settings
remove_chroot_user () 
{
	zfs destroy tank/"$USER" 2>/dev/null
	pkill -u "$USER"
	userdel -r "$USER" 2>/dev/null
	rm -rf /home/"$USER"
}
case "$1" in 
	-h|--help)
		usage
		exit 0
		;;
	--add)
		shift
		if [ -z "$USER" ] ; then
			echo "user not specify"
		else 
			prepare
			create_home_dir "$@"
			install_chroot_base
			create_chroot_user
		fi
		;;
	--update)
		shift
		if [ -z "$USER" ] ; then
			echo "user not specify"
		else
			clear_env
			install_chroot_base
		fi
		;;
	--remove)
		remove_chroot_user
		;;
	*)
	echo " Unknown option $1" >&2
	usage
	exit 1
	;;
esac 	
exit 0
