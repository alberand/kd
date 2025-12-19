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

echo "Removing /tmp/$NODE from $TEST_HOST"
ssh $TEST_HOST "sudo rm -f -- /tmp/$NODE"

echo "Destroy running node if exists"
if virsh --connect $SYSURI list | grep -q "$NODE"; then
	virsh --connect $SYSURI destroy $NODE
fi

echo "Uploading '$TEST_ISO' to '$TEST_HOST:/tmp/$NODE'"
rsync -avz -P \
       $TEST_ISO \
       $TEST_HOST:/tmp/$NODE
if [ $? -ne 0 ]; then
	exit 1;
fi;

ssh $TEST_HOST "sudo chmod u+w /tmp/$NODE"
echo "Bringing up the node"
virt-install --connect $SYSURI \
	--name "$NODE" \
	--hvm \
	--osinfo "nixos-unstable" \
	--memory=8000 \
	--vcpu 4 \
	--disk path="/tmp/$NODE",format=qcow2 \
	--disk size=20,target.bus=sata,format=raw \
	--disk size=20,target.bus=sata,format=raw \
	--disk size=1,target.bus=sata,format=raw \
	--disk size=1,target.bus=sata,format=raw \
	--disk size=1,target.bus=sata,format=raw \
	--network network=anet \
	--import \
	--serial pty \
	--graphics none \
	--noautoconsole \
	--transient

echo "Open console with:"
echo -e "\tvirsh --connect $SYSURI console $NODE"
