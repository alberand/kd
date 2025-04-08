#!/usr/bin/env sh

if [ -z "$TEST_HOST" ]; then
    echo '$TEST_HOST is not defined' 1>&2
    exit 1
fi

if [ "$#" -ne 2 ]; then
    echo "Required path to image.iso and name"
    exit 1
fi

TEST_ISO="$1"
PREFIX="aalbersh"
SYSURI="qemu+ssh://$TEST_HOST/system"
NODE="$PREFIX-$2"

echo "Uploading '$TEST_ISO' to '$TEST_HOST:/tmp/$NODE.iso'"
rsync -avz -P \
       $TEST_ISO \
       $TEST_HOST:/tmp/$NODE.iso
if [ $? -ne 0 ]; then
	exit 1;
fi;

echo "Bringing up the node"
virt-install --connect $SYSURI \
	--name "$NODE" \
	--hvm \
	--osinfo "nixos-unstable" \
	--memory=8000 \
	--vcpu 4 \
	--disk size=10,target.bus=sata \
	--disk size=10,target.bus=sata \
	--network network=default \
	--cdrom "/tmp/$NODE.iso" \
	--serial pty \
	--graphics none \
	--noautoconsole \
	--transient

echo "Open console with:"
echo -e "\tvirsh --connect $SYSURI console $NODE"
