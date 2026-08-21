#!/usr/bin/env sh

set -eu

step() { printf ':: %s\n' "$*"; }

if [ -z "${TEST_HOST:-}" ]; then
    echo '$TEST_HOST is not defined' 1>&2
    exit 1
fi

if [ "$#" -ne 2 ]; then
    echo "Usage: deploy.sh <image.raw> <name>"
    exit 1
fi

IMAGE="$1"
PREFIX="aalbersh"
SYSURI="qemu+ssh://$TEST_HOST/system"
NODE="$PREFIX-$2"
REMOTE_DIR="/tmp/$NODE"

step "Stopping old VM (if running)"
if virsh --connect "$SYSURI" domstate "$NODE" >/dev/null 2>&1; then
	virsh --connect "$SYSURI" destroy "$NODE" >/dev/null
fi

sha_local=$(awk '{print $1}' "$IMAGE.sha256sum")
sha_remote=$(ssh "$TEST_HOST" "cat $REMOTE_DIR/image.raw.sha256sum 2>/dev/null" | awk '{print $1}')
if [ "$sha_local" != "$sha_remote" ]; then
	step "Image changed -- uploading to $TEST_HOST:$REMOTE_DIR"
	ssh "$TEST_HOST" "sudo rm -rf -- $REMOTE_DIR && mkdir -p -- $REMOTE_DIR"
	# Upload the image first and the checksum last, so an interrupted
	# transfer never leaves a matching sha next to a truncated image.
	rsync -az -P "$IMAGE" "$TEST_HOST:$REMOTE_DIR/image.raw"
	rsync -az -P "$IMAGE.sha256sum" "$TEST_HOST:$REMOTE_DIR/image.raw.sha256sum"

	step "Resizing disk image (+50G)"
	ssh "$TEST_HOST" << ENDSSH
set -eu
DISK_IMAGE="$REMOTE_DIR/image.raw"
chmod +w "\$DISK_IMAGE"
qemu-img resize -f raw "\$DISK_IMAGE" "+50G" >/dev/null
ENDSSH
else
	step "Image unchanged -- skipping upload"
fi

step "Starting VM: $NODE"
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
	--transient \
	--quiet

step "Done. Console:"
printf '   virsh --connect %s console %s\n' "$SYSURI" "$NODE"
