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

echo "Loading identity"
IDENTITY=$(ssh-add -L)

if [ $(echo "$IDENTITY" | grep -c "^ssh") -ne 1 ] ; then
	echo "Please add one key to the agent for provisioning"
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

  # Do this as late as possible, as it makes sudo throw an error message
  send "sudo sed --in-place -e \"s/$DEFAULT_NAME/$NEW_NAME/\" /etc/hosts\n"
  expect ":~$ "

  send "sudo reboot now 2>&1 >/dev/null\n"
  expect ":~$ "
EOD
)

echo "Looking for Raspberry Pi with new name..."
wait_for_pi $NEW_NAME.local

ssh $SSH_OPTS pi@$NEW_NAME.local "echo It Worked!"
