#!/usr/bin/env sh

set -e

usage() {
	echo "$(basename "$0") <kernel version> <xfsprogs version> <xfstests version>"
}

if [ "$#" -ne 3 ]; then
	usage
	exit 1
fi

VERSION_KERNEL=$1
VERSION_XFSPROGS=$2
VERSION_XFSTESTS=$3

OUTPUT=./sources

rm -rf -- $OUTPUT
mkdir $OUTPUT

echo "💡Fetching new versions and updating hashes"
nurl \
	--fetcher fetchgit \
	--json \
	--indent 2 \
	git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git \
	$VERSION_KERNEL \
	> $OUTPUT/kernel.json
nurl \
	--fetcher fetchgit \
	--json \
	--indent 2 \
	git://git.kernel.org/pub/scm/fs/xfs/xfsprogs-dev.git \
	$VERSION_XFSPROGS \
	> $OUTPUT/xfsprogs.json
nurl \
	--fetcher fetchgit \
	--json \
	--indent 2 \
	git://git.kernel.org/pub/scm/fs/xfs/xfstests-dev.git \
	$VERSION_XFSTESTS \
	> $OUTPUT/xfstests.json

temp=$(mktemp)
for file in $OUTPUT/*.json; do
	jq .args $file > $temp
	cp $temp $file
done;

echo "💡Updating kernel configs"
nix build .#kconfig
cp result ./kconfigs/config-vm-$VERSION_KERNEL

nix build .#kconfig-debug
cp result ./kconfigs/config-debug-$VERSION_KERNEL

nix build .#kconfig-iso
cp result ./kconfigs/config-iso-$VERSION_KERNEL

chmod 666 ./kconfigs/*

echo "💡Updating Flake inputs"
nix flake update
nix flake update --flake ./templates/vm
