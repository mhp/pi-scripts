#!/bin/bash

DEFAULT_IMAGE=$(ls -1 ~/Downloads/*raspbian*.zip | tail -1)
CARD=/dev/mmcblk0
SSID=$(nmcli --terse --fields name connection show --active)

if [ "$(zipinfo -1 $DEFAULT_IMAGE | wc -l)" -ne 1 ] ; then
	echo $DEFAULT_IMAGE does not look like a raspbian download
	zipinfo $DEFAULT_IMAGE
	exit 1
fi

echo "Using $(basename $DEFAULT_IMAGE)..."

if [ ! -b "$CARD" ] ; then
	echo $CARD is not a block device
	exit 1
fi

if [ "$(stat --format=%T $CARD)" -ne 0 ] ; then
	echo $CARD is a partition, not the physical device
	exit 1
fi

if mount | grep $CARD > /dev/null ; then
	echo $CARD already mounted
	exit 1
fi

echo "Copying $(basename $DEFAULT_IMAGE) to $CARD..."
unzip -p $DEFAULT_IMAGE *.img | sudo dd of=$CARD bs=4M conv=fsync status=progress

# Mount vfat partition and update the boot stuff...
P1=$(lsblk --list $CARD -o NAME,FSTYPE -np | grep vfat | cut -f 1 -d" ")
echo $P1 identified as boot partition, mounting...
mp=$(mktemp -d)
sudo mount $P1 $mp -o uid=$USER

echo Enabling ssh...
touch $mp/ssh

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

echo Reducing GPU memory...
echo "gpumem=16" >> $mp/config.txt

sudo umount $P1
rmdir $mp
echo $CARD unmounted and ready
