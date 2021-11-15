#!/bin/bash

IMAGE=${IMAGE:-$(ls -1 ~/Downloads/*-raspios-*.zip | tail -1)}
CARD=${CARD:-/dev/mmcblk0}
SSID=${SSID-$(iwgetid --raw)}

if [ "$(zipinfo -1 $IMAGE | wc -l)" -ne 1 ] ; then
	echo $IMAGE does not look like a raspios download
	zipinfo $IMAGE
	exit 1
fi

echo "Using $(basename $IMAGE)..."

if [ ! -b "$CARD" ] ; then
	echo $CARD is not a block device
	exit 1
fi

if [ "$(lsblk -ndao TYPE $CARD 2>/dev/null)" != "disk" ] ; then
	echo $CARD is not a physical device
	exit 1
fi

if mount | grep $CARD > /dev/null ; then
	echo $CARD already mounted
	exit 1
fi

echo "Copying $(basename $IMAGE) to $CARD..."
unzip -p $IMAGE *.img | sudo dd of=$CARD bs=4M conv=fsync status=progress

echo "Looking for boot partition..."
for retries in $(seq 5) ; do
	# Mount vfat partition and update the boot stuff...
	P1=$(lsblk --list $CARD -o NAME,FSTYPE -np | grep vfat | cut -f 1 -d" ")
	[ -n "$P1" ] && break
	sleep 1
done

if [ -z "$P1" ] ; then
	echo "Can't find boot partition"
	exit 1
fi

echo $P1 identified as boot partition, mounting...
mp=$(mktemp -d)
sudo mount $P1 $mp -o uid=$USER

echo Enabling ssh...
touch $mp/ssh

if [ -n "$SSID" ] ; then
	echo Configuring wifi for $SSID...
	cat <<-EOF >$mp/wpa_supplicant.conf
		ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
		update_config=1
		country=GB

		network={
		    ssid="$SSID"
		    psk="$(nmcli -s --terse --fields 802-11-wireless-security.psk connection show $SSID | cut -d: -f2)"
		    key_mgmt=WPA-PSK
		}
	EOF
fi

echo Reducing GPU memory...
echo "gpumem=16" >> $mp/config.txt

sudo umount $P1
rmdir $mp
echo $CARD unmounted and ready
