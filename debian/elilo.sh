#! /bin/bash

###############################################################################
##
## elilo installs efi bootloader onto a bootstrap partition (based on ybin)
## Copyright (C) 2001 Ethan Benson
##
## This program is free software; you can redistribute it and/or
## modify it under the terms of the GNU General Public License
## as published by the Free Software Foundation; either version 2
## of the License, or (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
##
###############################################################################

PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"
## allow to run out of /target in boot-floppies
if [ -n "$PATH_PREFIX" ] ; then
    PATH="${PATH}:${PATH_PREFIX}/sbin:${PATH_PREFIX}/bin:${PATH_PREFIX}/usr/sbin:${PATH_PREFIX}/usr/bin:${PATH_PREFIX}/usr/local/sbin:${PATH_PREFIX}/usr/local/bin"
fi
PRG="${0##*/}"
SIGINT="$PRG: Interrupt caught ... exiting"
VERSION=##VERSION##
DEBUG=0
VERBOSE=0
TMP="${TMPDIR:-/tmp}"
TARGET=
# Beware, /EFI/ubuntu occurs with double backslashes in the script too
# so change those as well as EFIROOT, if need be.
EFIROOT=/EFI/ubuntu
export LC_COLLATE=C

ARCHITECTURE=$(dpkg --print-architecture)

## catch signals, clean up junk in /tmp.
trap "cleanup" 0
trap "cleanup; exit 129" HUP
trap "echo 1>&2 $SIGINT ; cleanup; exit 130" INT
trap "cleanup; exit 131" QUIT
trap "cleanup; exit 143" TERM

## define default config file
CONF=/etc/elilo.conf
bootconf=$CONF
ERR=" Error in $CONF:"

## define default configuration
boot=unconfigured

## allow default to work on packaged and non-packaged elilo. 
if [ -f /usr/local/lib/elilo/elilo.efi ] ; then
    install=/usr/local/lib/elilo/elilo.efi
elif [ -f /usr/lib/elilo/elilo.efi ] ; then
    install=/usr/lib/elilo/elilo.efi
fi

## defaults
efiboot=0
autoconf=0
fstype=vfat
umountproc=0

## elilo autoconf defaults
label=Linux
timeout=20
root=/dev/sda3

# image default is controlled by /etc/kernel-img.conf, if it exists
if [ -f /etc/kernel-img.conf ] &&
	grep -E -qi "^(image|link)_in_boot *= *yes" /etc/kernel-img.conf; then
    image=/boot/vmlinuz
    initrdline=initrd=/boot/initrd.img
    initrdoldline=initrd=/boot/initrd.img.old
else
    image=/vmlinuz
    initrdline=initrd=/initrd.img
    initrdoldline=initrd=/initrd.img.old
fi
if [ -f /etc/kernel-img.conf ] &&
	! grep -qi "^do_initrd *= *yes" /etc/kernel-img.conf; then
    initrdline=
    initrdoldline=
fi

## make fake `id' if its missing, outputs 0 since if its missing we
## are probably running on boot floppies and thus are root.
if (command -v id > /dev/null 2>&1) ; then 
    true
else
    id()
    {
    echo 0
    }
fi

## --version output
version()
{
echo \
"$PRG $VERSION
Written by Richard Hirst, based on work by Ethan Benson

This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE."
}

## --help output.
usage()
{
echo \
"Usage: $PRG [OPTION]...
Update/install bootloader onto a bootstrap partition.

  -b, --boot                 set bootstrap partition device [ -b /dev/sda1 ]
  -i, --install              pathname to the actual bootloader binary
                               default: /usr/{local/}lib/elilo/elilo.efi
  -C, --config               use alternate configuration file [ -C config_file ]
      --autoconf             auto-generate a /etc/elilo.conf
      --efiboot              elilo auto configuration: create an efi boot
                               manager entry for elilo
      --timeout              elilo auto configuration: sets the time elilo
			       will wait for user input before booting default
                               image default: 20 (2 seconds)
      --image                elilo auto configuration: sets the path to the
			       kernel image. default: /vmlinuz
      --label                elilo auto configuration: sets the image label
                               default: Linux
      --root                 elilo auto configuration: sets the root device
                               default: /dev/sda3
      --format               create a new FAT filesystem on the boot partition
  -v, --verbose              make $PRG more verbose
      --debug                print boring junk only useful for debugging
  -h, --help                 display this help and exit
  -V, --version              output version information and exit"
}

## we have to do some things differently with a retarded devfs name.
ckdevfs()
{
    case "$1" in
	/dev/ide/*|/dev/scsi/*|/dev/discs/*)
	return 0
	;;
    *)
	return 1
	;;
    esac
}

## the SmartArray RAID controllers use /dev/cciss/c0d0p1 kinds of names...
ckcciss()
{
    case "$1" in
	/dev/cciss/*)
	return 0
	;;
    *)
	return 1
	;;
    esac
}


## configuration file parsing. FIXME: need a method which can parse
## image= sections.
parseconf()
{
case "$1" in
    str)
       v=`grep "^$2[\ ,=]" "$CONF"` ; echo "${v#*=}"
       ;;
    flag)
       grep "^$2\>" "$CONF" > /dev/null && echo 0 || echo 1
       ;;
    ck)
       grep "^$2[\ ,=]" "$CONF" > /dev/null && echo 0 || echo 1
       ;;
esac
}

## check for existence of a configuration file, and make sure we have
## read permission.
confexist()
{
    if [ ! -e "$CONF" ] ; then
	echo 1>&2 "$PRG: $CONF: No such file or directory"
	return 1
    elif [ ! -f "$CONF" ] ; then
	echo 1>&2 "$PRG: $CONF: Not a regular file"
	return 1
    elif [ ! -r "$CONF" ] ; then
	echo 1>&2 "$PRG: $CONF: Permission denied"
	return 1
    else
	return 0
    fi
}

## check to make sure the configuration file is sane and correct.
## maybe this is an insane ammount of error checking, but I want to
## make sure (hopefully) nothing unexpected ever happens.  and i just
## like useful errors from programs.  every error just marks an error
## variable so we give the user as much info as possible before we
## abandon ship.
checkconf()
{
    if [ -L "$boot" ] ; then
	oldboot=$boot
	boot=$(readlink -f $oldboot)
    fi
    if [ ! -e "$boot" ] ; then
	echo 1>&2 "$PRG: $boot: No such file or directory"
	CONFERR=1
    elif [ ! -b "$boot" ] && [ ! -f "$boot" ] ; then
	echo 1>&2 "$PRG: $boot: Not a regular file or block device"
	CONFERR=1
    elif [ ! -w "$boot" ] || [ ! -r "$boot" ] ; then
	echo 1>&2 "$PRG: $boot: Permission denied"
	CONFERR=1
    fi

    ## sanity check, make sure boot=bootstrap and not something dumb
    ## like /dev/hda
    case "$boot" in
	*hda)
	    echo 1>&2 "$PRG:$ERR \`boot=$boot' would result in the destruction of all data on $boot"
	    CONFERR=1
	    ;;
	*sda)
	    echo 1>&2 "$PRG:$ERR \`boot=$boot' would result in the destruction of all data on $boot"
	    CONFERR=1
	    ;;
	*disc)
	    echo 1>&2 "$PRG:$ERR \`boot=$boot' would result in the destruction of all data on $boot"
	    CONFERR=1
	    ;;
    esac

    ## now make sure its not something dumb like the root partition
    ROOT="$(v=`df / 2> /dev/null | grep ^/dev/` ; echo ${v%%[ ]*})"
    BOOT="$(v=`df /boot 2> /dev/null | grep ^/dev/` ; echo ${v%%[ ]*})"
    if [ "$boot" = "$ROOT" ] ; then
	echo 1>&2 "$PRG:$ERR \`boot=$boot' would result in the destruction of the root filesystem"
	CONFERR=1
    elif [ "$boot" = "$BOOT" ] ; then
	echo 1>&2 "$PRG:$ERR \`boot=$boot' would result in the destruction of the /boot filesystem"
	CONFERR=1
    fi

    ## Make sure boot is not already mounted
    mount | grep "^$boot " > /dev/null
    if [ $? = 0 ] ; then
	echo 1>&2 "$PRG: $boot appears to be mounted"
	CONFERR=1
    fi

    if [ ! -e "$install" ] ; then
	echo 1>&2 "$PRG: $install: No such file or directory"
	CONFERR=1
    elif [ ! -f "$install" ] ; then
	echo 1>&2 "$PRG: $install: Not a regular file"
	CONFERR=1
    elif [ ! -r "$install" ] ; then
	echo 1>&2 "$PRG: $install: Permission denied"
	CONFERR=1
    fi

    if [ ! -e "$bootconf" ] ; then
	echo 1>&2 "$PRG: $bootconf: No such file or directory"
	CONFERR=1
    elif [ ! -f "$bootconf" ] ; then
	echo 1>&2 "$PRG: $bootconf: Not a regular file"
	CONFERR=1
    elif [ ! -r "$bootconf" ] ; then
	echo 1>&2 "$PRG: $bootconf: Permission denied"
	CONFERR=1
    fi

    # efibootmgr needs efivars, make sure kernel module is loaded
    if modprobe -q efivars ; then
        echo "Loaded efivars kernel module to enable use of efibootmgr"
    fi

    if [ ! -d /proc/efi/vars ] && [ ! -d /sys/firmware/efi/vars ] && [ "$efiboot" = 1 ] && ! modprobe -q efivars; then
	echo 1>&2 "$PRG: no efi/vars under /proc or /sys/firmware, boot menu not updated"
	efiboot=0
    fi

    if [ "$efiboot" = 1 ] ; then
	## see if efibootmgr exists and is executable
	if (command -v efibootmgr > /dev/null 2>&1) ; then
	    [ -x `command -v efibootmgr` ] || MISSING=1 ; else MISSING=1
	fi

	if [ "$MISSING" = 1 ] ; then
	    efiboot=0
	    echo 1>&2 "$PRG: Warning: \`efibootmgr' could not be found, boot menu not updated"
	fi

	if [ -f "$boot" ] ; then
	    echo 1>&2 "$PRG: $boot is a regular file, disabling boot menu update"
	    efiboot=0
	fi
    fi

    if [ "$CONFERR" = 1 ] ; then
	return 1
    else
	return 0
    fi
}


mnt()
{
    ## we can even create bootstrap filesystem images directly if you
    ## ever wanted too.
    if [ -f "$boot" ] ; then
	loop=",loop"
    fi

    if [ -e "$TMP/bootstrap.$$" ] ; then
	echo 1>&2 "$PRG: $TMP/bootstrap.$$ exists, aborting."
	return 1
    fi

    mkdir -m 700 "$TMP/bootstrap.$$"
    if [ $? != 0 ] ; then
	echo 1>&2 "$PRG: Could not create mountpoint directory, aborting."
	return 1
    fi

    mount | grep "^$boot " > /dev/null
    if [ $? = 0 ] ; then
	echo 1>&2 "$PRG: $boot appears to be mounted! aborting."
	return 1
    fi

    [ "$VERBOSE" = 1 ] && echo "$PRG: Mounting $boot..."
    mount -t "$fstype" -o codepage=437,rw,noexec,umask=077$loop "$boot" "$TMP/bootstrap.$$"
    if [ $? != 0 ] ; then
	echo 1>&2 "$PRG: An error occured mounting $boot"
	return 1
    fi

    TARGET="$TMP/bootstrap.$$"
    return 0
}

copyfiles()
{
    BTFILE=elilo.efi
    CFFILE=elilo.conf
    imagefiles=`grep '^image[[:space:]]*=' $bootconf | \
		sed 's/^image[[:space:]]*=[[:space:]]*//' | grep -v ':'`
    initrdfiles=`grep '^[[:space:]]*initrd[[:space:]]*=' $bootconf | \
		sed 's/.*=[[:space:]]*//' | grep -v ':'`
    vmmfiles=`grep '^[[:space:]]*vmm[[:space:]]*=' $bootconf | \
		sed 's/.*=[[:space:]]*//' | grep -v ':'`

    ## Point of no return, removing the old EFI/ubuntu tree
    rm -rf $TARGET/$EFIROOT
    if [ $? != 0 ]; then
	echo 2>&1 "$PRG: Failed to delete old boot files, aborting"
	return 1
    fi
    mkdir -p $TARGET/$EFIROOT

    ## Add a README to warn that this tree is deleted every time elilo is run
    echo -ne "\
This directory tree is managed by /usr/sbin/elilo, and is deleted and\n\
recreated every time elilo runs.  Any local changes will be lost.\n\
" > $TARGET/$EFIROOT/README.TXT

    ## this is probably insecure on modern filesystems, but i think
    ## safe on crippled hfs/dosfs.
    [ "$VERBOSE" = 1 ] && echo "$PRG: Installing primary bootstrap $install onto $boot..."
    cp -f "$install" "$TARGET/$EFIROOT/$BTFILE"
    if [ $? != 0 ] ; then
	echo 1>&2 "$PRG: An error occured while writing to $boot"
	return 1
    fi

    [ "$VERBOSE" = 1 ] && echo "$PRG: Installing $bootconf on $boot..."
    ## we comment out boot= and install=, because they are only really
    ## needed in the /etc/elilo.conf file, and elilo.efi currently
    ## doesn't understand them.  We also need to add /EFI/ubuntu on to
    ## the front of any paths that don't contain colons (device paths),
    ## and replace tabs with spaces.
    sed -e "s|^boot[[:space:]]*=|# &|" -e "s|^install[[:space:]]*=|# &|" \
	-e "s|\t| |g" \
	-e "s|\(^image[[:space:]]*=[[:space:]]*\)\([^:]*\)$|\1$EFIROOT\2|" \
	-e "s|\(^[[:space:]]*initrd[[:space:]]*=[[:space:]]*\)\([^:]*\)$|\1$EFIROOT\2|" \
	-e "s|\(^[[:space:]]*vmm[[:space:]]*=[[:space:]]*\)\([^:]*\)$|\1$EFIROOT\2|" \
	< "$bootconf" > "$TARGET/$EFIROOT/$CFFILE"
    if [ $? != 0 ] ; then
	echo 1>&2 "$PRG: An error occured while writing to $boot"
	return 1
    fi

    [ "$DEBUG" = 1 ] && echo "----" && cat "$TARGET/$EFIROOT/$CFFILE" && echo "----"

    for i in $imagefiles $initrdfiles $vmmfiles; do
	[ "$VERBOSE" = 1 ] && echo "$PRG: Installing $i on $boot..."
	if [ -f $i ]; then
	    mkdir -p `dirname "$TARGET/$EFIROOT/$i"`
	    if [ $? != 0 ] ; then
		echo 1>&2 "$PRG: An error occured creating directory `dirname $EFIROOT/$i` on $boot"
		return 1
	    fi
	    cp -f "$i" "$TARGET/$EFIROOT/$i"
	    if [ $? != 0 ] ; then
		echo 1>&2 "$PRG: An error occured writing $i to $boot"
		return 1
	    fi
	else
	    echo "$PRG: Warning: $i not found"
	fi
    done

    sync ; sync

    ## update the boot-device variable in EFI.
    if [ "$efiboot" = 1 ] ; then
	[ "$VERBOSE" = 1 ] && echo "$PRG: Updating EFI boot-device variable..."
	efiquiet="-q"
	[ "$VERBOSE" = 1 ] && efiquiet=""
	if ckdevfs "$boot" ; then
	    BOOTDISK="${boot%/*}/disc"
	    BOOTPART="${boot##*part}"
	elif ckcciss "$boot" ; then
	    BOOTDISK="${boot%p[0-9]*}"
	    BOOTPART="${boot##*[a-z]}"
	else
	    BOOTDISK="${boot%%[0-9]*}"
	    BOOTPART="${boot##*[a-z]}"
	fi
	if [ -z "$BOOTDISK" ] || [ -z "$BOOTPART" ] ; then
	    echo 2>&1 "$PRG: Could not determine boot disk, aborting..."
	    return 1
	fi

	[ "$DEBUG" = 1 ] && echo 1>&2 "$PRG: DEBUG: boot-disk      = $BOOTDISK"
	[ "$DEBUG" = 1 ] && echo 1>&2 "$PRG: DEBUG: boot-partition = $BOOTPART"
	# delete other entries with name "Ubuntu"
	for b in `efibootmgr | grep "Ubuntu" | awk '{print substr($1,5,4) }'`; do
	    efibootmgr $efiquiet -b $b -B
	done
	# Add a new entry for this installation
	efibootmgr $efiquiet -c -d $BOOTDISK -p $BOOTPART -w -L "Ubuntu" \
		-l \\EFI\\ubuntu\\elilo.efi -u -- elilo -C \\EFI\\ubuntu\\elilo.conf
	if [ $? != 0 ] ; then
	    echo 1>&2 "$PRG: An error occured while updating boot menu, we'll ignore it"
	fi
	# Now, if 2nd and 3rd boot entries are for floppy and CD/DVD,
	# move them up to 1st and 2nd, making our entry the 3rd.
	bootorder=$(efibootmgr | sed -n 's/^BootOrder: \(.*\)$/\1/p')
	boot1st=$(echo $bootorder | sed -n "s/\(....\).*$/\1/p")
	boot2nd=$(echo $bootorder | sed -n "s/....,\(....\).*$/\1/p")
	boot3rd=$(echo $bootorder | sed -n "s/....,....,\(....\).*$/\1/p")
	boot456=$(echo $bootorder | sed -n "s/....,....,....\(.*\).*$/\1/p")
	name2nd=$(efibootmgr | sed -n "s/^Boot$boot2nd[\*] \(.*\)$/\1/p")
	name3rd=$(efibootmgr | sed -n "s/^Boot$boot3rd[\*] \(.*\)$/\1/p")
	name23="@$name2nd@$name3rd"
	if ( echo $name23 | grep -qi "@floppy" ); then
	    if ( echo $name23 | grep -qi "@cd") || ( echo $name23 | grep -qi "@dvd"); then
		efibootmgr $efiquiet -o $boot2nd,$boot3rd,$boot1st$boot456
	    fi
	fi
    fi

    return 0
}

## mkefifs function.
mkefifs()
{
    mount | grep "^$boot\>" > /dev/null
    if [ $? = 0 ] ; then
	echo 1>&2 "$PRG: $boot appears to be mounted! aborting."
        return 1
    fi

    if (command -v mkdosfs > /dev/null 2>&1) ; then
	[ -x `command -v mkdosfs` ] || FAIL=1 ; else FAIL=1 ; fi
	if [ "$FAIL" = 1 ] ; then
	    echo 1>&2 "$PRG: mkdosfs is not installed or cannot be found"
	    return 1
	fi

    [ "$VERBOSE" = 1 ] && echo "$PRG: Creating DOS filesystem on $boot..."
    mkdosfs -n bootstrap "$boot" > /dev/null
    if [ $? != 0 ] ; then
	echo 1>&2 "$PRG: DOS filesystem creation failed!"
	return 1
    fi
    return 0
}

mkconf()
{
## defaults for this are defined at the beginning of the script with
## other variables.

# We want to create an append= line from the current /proc/cmdline,
# so things like console=ttyS0 get picked up automatically.
# We also want to filter out bits of cmdline we are not interested in.

if [ -f /proc/cmdline ]; then
  cmdline=`cat /proc/cmdline`
else
  echo 1>&2 "$PRG: Warning: couldn't read /proc/cmdline, may need to add append=... to elilo.conf"
  cmdline=""
fi

append=`echo $cmdline | tr ' ' '\n' | grep "^console=" | tr '\n' ' '`
if [ ! -z "$append" ]; then append="append=\"$append\""; fi

echo \
"## elilo configuration file generated by elilo $VERSION

install=$install
boot=$boot
delay=$timeout
default=$label
" > "$TMPCONF" || return 1

if [ "$ARCHITECTURE" = "ia64" ]
then
  echo "relocatable" >> "$TMPCONF" || return 1
fi

echo \
"$append

image=$image
	label=$label
	root=$root
	read-only
	$initrdline

image=${image}.old
	label=${label}OLD
	root=$root
	read-only
	$initrdoldline
" >> "$TMPCONF" || return 1

    ## Copy the new elilo.conf to /etc
    if [ -f $CONF ]; then
	echo 1>&2 "$PRG: backing up existing $CONF as ${CONF}-"
	rm -f ${CONF}-
	mv $CONF ${CONF}-
    fi
    cp -f "$TMPCONF" "$CONF"
    if [ $? != 0 ] ; then
	echo 1>&2 "$PRG: An error occured while writing to $conf"
	return 1
    fi

return 0
}

# check partition will be big enough for all we want to add to it

chkspace()
{
    imagefiles=`grep '^image[[:space:]]*=' $bootconf | \
		sed 's/^image[[:space:]]*=[[:space:]]*//' | grep -v ':'`
    initrdfiles=`grep '^[[:space:]]*initrd[[:space:]]*=' $bootconf | \
		sed 's/.*=[[:space:]]*//' | grep -v ':'`
    vmmfiles=`grep '^[[:space:]]*vmm[[:space:]]*=' $bootconf | \
		sed 's/.*=[[:space:]]*//' | grep -v ':'`
    bytesneeded=`cat $imagefiles $initrdfiles $vmmfiles $install $bootconf 2>/dev/null | wc -c`
    # convert to KB, allowing 5% overhead
    kbneeded=$(( bytesneeded / 1024 + bytesneeded / 20480 ))
    kbavailable=$(df -P -k $TARGET | sed -n "s|^$boot[[:space:]]\+[0-9]\+[[:space:]]\+[0-9]\+[[:space:]]\+\([0-9]\+\).*$|\1|p")
    if [ -z $kbavailable ]; then
	echo 2>&1 "$PRG: unable to determine space on $boot, aborting"
	return 1
    fi
    if [ -d $TARGET/$EFIROOT ]; then
	kbused=$(du -ks $TARGET/$EFIROOT | sed -n "s/[ 	].*$//p")
    else
        kbused=0
    fi
    [ "$VERBOSE" = 1 ] && echo "$PRG: ${kbneeded}KB needed, ${kbavailable}KB free, ${kbused}KB to reuse"
    kbavailable=$(( kbavailable + kbused ))
    if [ "$kbavailable" -lt "$kbneeded" ] ; then
        echo 1>&2 "$PRG: Insufficient space on $boot, need ${kbneeded}KB, only ${kbavailable}KB available"
        return 1
    fi
return 0
}


## take out the trash.
cleanup()
{
    if [ -n "$TARGET" ]; then
	TARGET=
        [ "$VERBOSE" = 1 ] && echo "$PRG: Unmounting $boot"
	umount "$boot"
	[ $? != 0 ] && echo 2>&1 "$PRG: Warning, failed to unmount $TARGET"
    fi
    if [ -n "$TMPCONF" ] ; then rm -f "$TMPCONF" ; fi
    if [ -d "$TMP/bootstrap.$$" ] ; then rmdir "$TMP/bootstrap.$$" ; fi
    if [ "$umountproc" = 1 ] ; then umount /proc ; fi
    return 0
}

##########
## Main ##
##########

## absurdly bloated case statement to parse command line options.
if [ $# != 0 ] ; then
    while true ; do
	case "$1" in 
	    -V|--version)
		version
		exit 0
		;;
	    -h|--help)
		usage
		exit 0
		;;
	    --debug)
		DEBUG=1
		shift
		;;
	    -v|--verbose)
		VERBOSE=1
		shift
		;;
	    --force)
		# allow --force for now, boot-floppies 3.0.20 and
		# systemconfigurator use that instead of --format
		echo 1>&2 "$PRG: Warning: --force is now deprecated.  Use --for\mat."
		echo 1>&2 "Try \`$PRG --help' for more information."
		FORMAT=yes
		shift
		;;
	    --format)
		FORMAT=yes
		shift
		;;
	    --autoconf)
		autoconf=1
		shift
		;;
	    -b|--boot)
		if [ -n "$2" ] ; then
		    boot="$2"
		    ARGBT=1
		    shift 2
		else
		    echo 1>&2 "$PRG: option requires an argument $1"
		    echo 1>&2 "Try \`$PRG --help' for more information."
		    exit 1
		fi
		;;
	    -i|--install)
		if [ -n "$2" ] ; then
		    install="$2"
		    ARGBF=1
		    shift 2
		else
		    echo 1>&2 "$PRG: option requires an argument $1"
		    echo 1>&2 "Try \`$PRG --help' for more information."
		    exit 1
		fi
		;;
	    -C|--config)
		if [ -n "$2" ] ; then
		    CONF="$2"
		    bootconf="$2"
		    ERR=" Error in $CONF:"
		    shift 2
		else
		    echo 1>&2 "$PRG: option requires an argument $1"
		    echo 1>&2 "Try \`$PRG --help' for more information."
		    exit 1
		fi
		;;
	    --efiboot)
		efiboot=1
		ARGNV=1
		shift
		;;
	    --timeout)
		if [ -n "$2" ] ; then
		    timeout="$2"
		    bootconf=auto
		    shift 2
		else
		    echo 1>&2 "$PRG: option requires an argument $1"
		    echo 1>&2 "Try \`$PRG --help' for more information."
		    exit 1
		fi
		;;
	    --image)
		if [ -n "$2" ] ; then
		    image="$2"
		    bootconf=auto
		    shift 2
		else
		    echo 1>&2 "$PRG: option requires an argument $1"
		    echo 1>&2 "Try \`$PRG --help' for more information."
		    exit 1
		fi
		;;
	    --label)
		if [ -n "$2" ] ; then
		    label="$2"
		    bootconf=auto
		    shift 2
		else
		    echo 1>&2 "$PRG: option requires an argument $1"
		    echo 1>&2 "Try \`$PRG --help' for more information."
		    exit 1
		fi
		;;
	    --root)
		if [ -n "$2" ] ; then
		    root="$2"
		    bootconf=auto
		    shift 2
		else
		    echo 1>&2 "$PRG: option requires an argument $1"
		    echo 1>&2 "Try \`$PRG --help' for more information."
		    exit 1
		fi
		;;
	    "")
		break
		;;
	    *)
		echo 1>&2 "$PRG: unrecognized option \`$1'"
		echo 1>&2 "Try \`$PRG --help' for more information."
		exit 1
		;;
	esac
    done
fi

## check that are root
if [ `id -u` != 0 ] ; then
    echo 1>&2 "$PRG: requires root privileges, go away."
    exit 1
fi

## check that autoconf options are only specified with --autoconf
if [ "$bootconf" = "auto" ] && [ "$autoconf" = "0" ] ; then
    echo 1>&2 "$PRG: Auto-config options specified without --autoconf."
    exit 1;
fi

## check that specified config file exists, unless we are to generate it,
## which case we assume all options are done on the command line.
if [ "$autoconf" = "0" ] ; then
    confexist || exit 1
fi

## /proc is needed to parse /proc/partitions, etc.
if [ ! -f /proc/uptime ]; then
    [ "$VERBOSE" = 1 ] && echo "$PRG: Mounting /proc..."
    mount -t proc proc /proc 2> /dev/null
    if [ $? != 0 ]; then
	echo 1>&2 "$PRG: Failed to mount /proc, aborting."
	exit 1
    fi
    umountproc=1
fi

# We need vfat support, so make sure it is loaded
modprobe vfat >/dev/null 2>&1

## elilo.conf autogeneration. MUST have secure mktemp to
## avoid race conditions. Debian's mktemp qualifies.
if [ "$autoconf" = "1" ] ; then
    TMPCONF=`mktemp -q "$TMP/$PRG.XXXXXX"`
    if [ $? != 0 ] ; then
	echo 1>&2 "$PRG: Could not create temporary file, aborting."
	exit 1
    fi
    mkconf
    if [ $? != 0 ] ; then
	echo 1>&2 "$PRG: An error occured generating elilo.conf, aborting."
	exit 1
    fi

    bootconf="$TMPCONF"
fi

## Checks if each option was defined on the command line, and if so
## don't read it from the configuration file. this avoids
## configuration options from being set null, as well as command line
## options from being clobbered.
[ "$ARGBT" != 1 ] && [ $(parseconf ck boot) = 0 ] && boot=`parseconf str boot`

## ffs!! rtfm! foad!
if [ "$boot" = unconfigured ] ; then
    echo 1>&2 "$PRG: You must specify the device for the bootstrap partition. (ie: -b /dev/hdaX)"
    echo 1>&2 "$PRG: Try \`$PRG --help' for more information."
    exit 1
fi

## validate configuration for sanity.
checkconf || exit 1

if [ "$FORMAT" = "yes" ]; then
    mkefifs || exit 1
fi

[ "$VERBOSE" = 1 ] && echo "$PRG: Checking filesystem on $boot..."
dosfsck $boot > /dev/null
if [ $? != 0 ]; then
    echo 1>&2 "$PRG: Filesystem on $boot is corrupt, please fix that and rerun $PRG."
    exit 1
fi

mnt || exit 1
chkspace || exit 1
copyfiles || exit 1

umount $TARGET
if [ $? != 0 ]; then
    echo 1>&2 "$PRG: Failed to unmount $boot"
    exit 1
fi
TARGET=

[ "$VERBOSE" = 1 ] && echo "$PRG: Installation complete."

exit 0
