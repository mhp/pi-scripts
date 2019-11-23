#!/bin/bash

DEFAULT_NAME="raspberrypi"
NEW_NAME=$1

SSH_OPTS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

if [ -z "$1" ] ; then
	echo "Specify new hostname for Pi"
	exit 1
fi

if ! which expect >/dev/null 2>&1 ; then
	echo "Please install 'expect'"
	exit 1
fi

if [ -n "$KEYS" ] ; then
	echo "Reading ssh keys: $KEYS..."
	IDENTITY="$(cat $KEYS)"
else
	echo "Loading identity from ssh agent..."
	IDENTITY="$(ssh-add -L)"
fi

if [ $(echo "$IDENTITY" | grep -c "^ssh") -lt 1 ] ; then
	echo "Please provide at least one key for provisioning"
	exit 1
fi

function wait_for_pi {
	while ! ping -c 1 -W 2 $1 >/dev/null 2>&1 ; do
		sleep 5
	done

	# Wait for ssh service to start running too
	while ! timeout 1 echo -n >/dev/tcp/$1/22 2>/dev/null ; do
		sleep 1
	done
}

echo "Looking for Raspberry Pi..."
wait_for_pi $DEFAULT_NAME.local

echo "Found Pi at $(getent hosts $DEFAULT_NAME.local | cut -d" " -f 1)"

# Suppress colours from terminal prompt
export TERM=xterm-nocolor

# I've got some cheap USB Ethernet adaptors that need extra config
# to make them work reliably - they are identified by all having the
# same MAC address.  Prepare a new random MAC in case we detect one
BADMAC="00:e0:4c:53:44:58"
GOODMAC="02$(dd if=/dev/urandom count=5 bs=1 status=none | hexdump -v -e '/1 ":%02X"')"
MACUDEV="ACTION==\\\"add\\\", SUBSYSTEM==\\\"net\\\", ATTR{address}==\\\"$BADMAC\\\", RUN+=\\\"/sbin/ip link set dev \\\$name address $GOODMAC\\\""

expect <( cat << EOD
  spawn ssh $SSH_OPTS pi@$DEFAULT_NAME.local
  expect "assword:"
  send "raspberry\n"
  expect ":~$ "

  send "echo $NEW_NAME | sudo tee /etc/hostname >/dev/null\n"
  expect ":~$ "
  send "echo PasswordAuthentication no | sudo tee -a /etc/ssh/sshd_config >/dev/null\n"
  expect ":~$ "

  send "mkdir -m 700 -p ~/.ssh\n"
  expect ":~$ "
  send "echo \"$IDENTITY\" | tee -a ~/.ssh/authorized_keys >/dev/null\n"
  expect ":~$ "

  # Disable swap
  send "sudo dphys-swapfile swapoff\n"
  expect ":~$ "
  send "sudo dphys-swapfile uninstall\n"
  expect ":~$ "
  send "sudo update-rc.d dphys-swapfile remove\n"
  expect ":~$ "

  # Detect broken USB ethernet adaptors and apply
  # config fixups (new mac, enable promisc mode)
  send "grep -lR $BADMAC /sys/class/net 2>/dev/null\n"
  expect {
    -re {/sys/class/net/(\w+)/address} {
      set adaptor \$expect_out(1,string)
      puts "Found broken USB ethernet adaptor, fixing..."
      expect ":~$ "
      send "sudo sed -i '\\\$iip link set \$adaptor promisc on' /etc/rc.local\n"
      expect ":~$ "
      send "echo \'$MACUDEV\' | sudo tee /etc/udev/rules.d/42-fix-mac.rules >/dev/null\n"
      exp_continue
    }
    ":~$ "
  }

  # Do this as late as possible, as it makes sudo throw an error message
  send "sudo sed --in-place -e \"s/$DEFAULT_NAME/$NEW_NAME/\" /etc/hosts\n"
  expect ":~$ "

  send "sudo reboot now 2>&1 >/dev/null\n"
  expect ":~$ "
EOD
)

echo
echo "Looking for Raspberry Pi with new name..."
wait_for_pi $NEW_NAME.local

ssh $SSH_OPTS pi@$NEW_NAME.local "echo It Worked!"
