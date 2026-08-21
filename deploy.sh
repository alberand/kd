#!/usr/bin/env sh

set -eu

if [ -z "${TEST_HOST:-}" ]; then
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
REMOTE_DIR="/tmp/$NODE"

echo "Destroy running node if exists"
if virsh --connect "$SYSURI" domstate "$NODE" >/dev/null 2>&1; then
	virsh --connect "$SYSURI" destroy "$NODE"
fi

sha_local=$(awk '{print $1}' "$IMAGE.sha256sum")
sha_remote=$(ssh "$TEST_HOST" "cat $REMOTE_DIR/image.raw.sha256sum 2>/dev/null" | awk '{print $1}')
if [ "$sha_local" != "$sha_remote" ]; then
	echo "Removing $REMOTE_DIR from $TEST_HOST"
	ssh "$TEST_HOST" "sudo rm -rf -- $REMOTE_DIR && mkdir -p -- $REMOTE_DIR"

	echo "Uploading '$IMAGE' to '$TEST_HOST:$REMOTE_DIR'"
	# Upload the image first and the checksum last, so an interrupted
	# transfer never leaves a matching sha next to a truncated image.
	rsync -avz -P "$IMAGE" "$TEST_HOST:$REMOTE_DIR/image.raw"
	rsync -avz -P "$IMAGE.sha256sum" "$TEST_HOST:$REMOTE_DIR/image.raw.sha256sum"

	echo "Resizing the disk image"
	ssh "$TEST_HOST" << ENDSSH
set -eu
DISK_IMAGE="$REMOTE_DIR/image.raw"
chmod +w "\$DISK_IMAGE"
qemu-img resize -f raw "\$DISK_IMAGE" "+50G"
ENDSSH
fi

echo "Bringing up the node"
virt-install --connect "$SYSURI" \
	--name "$NODE" \
	--hvm \
	--osinfo "nixos-unstable" \
	--memory=4096 \
	--vcpu 4 \
	--disk path="$REMOTE_DIR/image.raw",target.bus=sata,driver.type=raw \
	--network network=anet \
	--boot loader=/usr/share/OVMF/OVMF_CODE.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/usr/share/OVMF/OVMF_VARS.fd,loader_secure=no \
	--import \
	--serial pty \
	--graphics none \
	--noautoconsole \
	--transient

echo "Open console with:"
printf '\tvirsh --connect %s console %s\n' "$SYSURI" "$NODE"
