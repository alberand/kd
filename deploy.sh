#!/usr/bin/env sh

if [ -z "$TEST_HOST" ]; then
    echo '$TEST_HOST is not defined' 1>&2
    exit 1
fi

if [ "$#" -ne 2 ]; then
    echo "Required path to image.qcow and name"
    exit 1
fi

IMAGE="$1"
PREFIX="aalbersh"
SYSURI="qemu+ssh://$TEST_HOST/system"
NODE="$PREFIX-$2"

echo "Destroy running node if exists"
if virsh --connect $SYSURI list | grep -q "$NODE"; then
	virsh --connect $SYSURI destroy $NODE
fi

echo "Removing /tmp/$NODE from $TEST_HOST"
ssh $TEST_HOST "sudo rm -f -- /tmp/$NODE"

echo "Uploading '$IMAGE' to '$TEST_HOST:/tmp/$NODE'"
rsync -avz -P \
       $IMAGE \
       $TEST_HOST:/tmp/$NODE
if [ $? -ne 0 ]; then
	exit 1;
fi;

ssh $TEST_HOST << ENDSSH
DISK_IMAGE="/tmp/$NODE"
chmod +w "\$DISK_IMAGE"
qemu-img resize -f raw "\$DISK_IMAGE" "+50G"
ENDSSH

echo "Bringing up the node"
virt-install --connect $SYSURI \
	--name "$NODE" \
	--hvm \
	--osinfo "nixos-unstable" \
	--memory=8000 \
	--vcpu 4 \
	--disk path="/tmp/$NODE",target.bus=sata,driver.type=raw \
	--network network=anet \
	--boot loader=/usr/share/OVMF/OVMF_CODE.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/usr/share/OVMF/OVMF_VARS.fd,loader_secure=no \
	--import \
	--serial pty \
	--graphics none \
	--noautoconsole \
	--transient

echo "Open console with:"
echo -e "\tvirsh --connect $SYSURI console $NODE"
