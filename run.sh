#!/usr/bin/env bash
#
# Priority:
# arguments > configuration file > environment variables

VALID_ARGS=$(getopt -o hk:m:t:c:q:s: --long help,kernel:,module:,totest:,config:,qemu-opts:,share-dir:,add: -- "$@")
if [[ $? -ne 0 ]]; then
    exit 1;
fi

LOCAL_CONFIG=".kd.toml"
SHARE_DIR="${SHARE_DIR:-/tmp/vmtest}"
KERNEL="$KERNEL"
MODULE="$MODULE"
TOTEST="$TOTEST"
TEST_CONFIG="$TEST_CONFIG"
QEMU_OPTS="$QEMU_OPTS"
LOG_FILE="/tmp/vmtest-$(date +%s).log"
SIMPLE_TEST="$SIMPLE_TEST"

function help() {
	cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [OPTION...]

DESCRIPTION
    Run Virtual Machine to test linux kernel with fstests.

OPTIONS
    -k IMAGE, --kernel IMAGE
        Specify path to bzImage <IMAGE> to use instead of pre-build kernel. Note
        that this kernel should have features necessary to run in QEMU
    -m MODULE, --module MODULE
        Compiled module to load before systemd task is being run.
    -t OPTIONS, --totest OPTIONS
        fstests's command line options or shell script to run instead of fstests
    -c CONFIG, --test-config CONFIG
        fstests's configuration file
    -q OPTIONS, --qemu-opts OPTIONS
        Options to add to QEMU
    -s SHAREDIR, --share-dir SHAREDIR
	Directory used for sharing files with VM (default /tmp/vmtest)
    -h, --help
        Print this help and exit
CONFIG
    Instead of using all the command line OPTIONS above the config file can be
    created. The file should be located in current working directory and named
    '.vmtest'. For example:

    ➜  cat .vmtest
    KERNEL = "./arch/x86_64/boot/bzImage"
    MODULE = "./fs/xfs/xfs.ko"
    TOTEST = "-d -s xfs_1k_quota -s xfs_4k_quota -g verity"
    TEST_CONFIG = "./xfstests-config"
    QEMU_OPTS = "-hdc /dev/sdc4 -hdd /dev/sdc5 -serial mon:stdio"
    SHARE_DIR = "/tmp/vmtest"

    The variables are capitalized options.
EOF
}

function eecho() {
	echo "$1" | tee -a $LOG_FILE
}

function load_config() {
	config=$1

	if ! tq --file $config . ; then
		echo "Invalid $config"
		exit 1
	fi

	if tq --file $config 'share_dir' > /dev/null; then
		export SHARE_DIR="$(tq --file $config 'share_dir')"
	fi
	if tq --file $config 'dummy' > /dev/null; then
		export SIMPLE_TEST="$(tq --file $config 'dummy')"
	fi
	if tq --file $config 'kernel.kernel' > /dev/null; then
		export KERNEL="$(tq --file $config 'kernel.kernel')"
	fi
	if tq --file $config 'xfstests.config' > /dev/null; then
		export TEST_CONFIG="$(tq --file $config 'xfstests.config')"
	fi
	if tq --file $config 'qemu.opts' > /dev/null; then
		export QEMU_OPTS="$(tq --file $config 'qemu.opts')"
	fi
	LOG_FILE="/tmp/vmtest-$(date +%s).log"

	eecho "config: $(pwd)/$config"
	eecho "SHARE_DIR: $SHARE_DIR"
	eecho "SIMPLE_TEST: $SIMPLE_TEST"
	eecho "KERNEL: $KERNEL"
	eecho "TEST_CONFIG: $TEST_CONFIG"
	eecho "QEMU_OPTS: $QEMU_OPTS"
}

function parse_args() {
	eval set -- "$VALID_ARGS"
	while [ : ]; do
		case "$1" in
			-k | --kernel)
				eecho "Processing 'kernel' option: $2"
				KERNEL="$2"
				shift
				shift
				;;
			-m | --module)
				eecho "Processing 'module' option: $2"
				MODULE="$2"
				shift
				shift
				;;
			-t | --totest)
				eecho "Processing 'totest' option: $2"
				TOTEST="$2"
				shift
				shift
				;;
			-c | --test-config)
				eecho "Processing 'test-config' option: $2"
				TEST_CONFIG="$2"
				shift
				shift
				;;
			-q | --qemu-opts)
				eecho "Processing 'qemu-opts' option: $2"
				QEMU_OPTS="$2"
				shift
				shift
				;;
			--dummy)
				eecho "Processing 'dummy' option: $2"
				SIMPLE_TEST="$2"
				shift
				shift
				;;
			-s | --share-dir)
				eecho "Processing 'share-dir' option: $2"
				SHARE_DIR="$2"
				shift
				shift
				;;
			--add)
				if [[ -z $SHARE_DIR ]]; then
					eecho "\$SHARE_DIR need to be set"
					exit 1
				fi
				eecho "Adding $2 test"
				rm -f $SHARE_DIR/test.sh
				ln $(readlink -f $2) $SHARE_DIR/test.sh
				exit 0
				shift
				;;
			-h | --help)
				help
				exit 0
				shift
				;;
			--) shift;
				break
				;;
		esac
	done
}

function init_share() {
	rm -rf "$SHARE_DIR/modules"
	rm -rf "$SHARE_DIR/results"
	rm -rf "$SHARE_DIR/dummy.sh"
	rm -rf "$SHARE_DIR/kd.toml"
	rm -rf "$SHARE_DIR/totest"
	rm -rf "$SHARE_DIR/xfstests-config"
	mkdir -p $SHARE_DIR

	if [ ! -w "$SHARE_DIR" ]; then
		eecho "$SHARE_DIR is not writable"
		return
	fi
	mkdir -p $SHARE_DIR/modules
	mkdir -p $SHARE_DIR/results
}

function set_kernel() {
	if [[ -z "$1" ]]; then
		return;
	fi

	if [[ ! -f "$1" ]]; then
		eecho "File $1 doesn't exist"
		return
	fi

	filename=$(basename $1)
	if [[ "$filename" != "vmlinux" && "$filename" != "bzImage" ]]; then
		eecho "File $1 is not a kernel (vmlinuz or bzImage)"
	fi

	export NIXPKGS_QEMU_KERNEL_${NODE_NAME}="$(realpath $1)"
	export QEMU_OPTS="$QEMU_OPTS"
	export NIX_DISK_IMAGE="$SHARE_DIR/$NODE_NAME.qcow2"
	eecho "Kernel is set to $(realpath $1)"
}

function add_module() {
	if [[ -z "$1" ]]; then
		rm -f -- "$SHARE_DIR/modules/*"
		return;
	fi

	if [[ ! -f "$1" ]]; then
		eecho "File $1 doesn't exist"
		return
	fi

	filename=$(basename $1)
	if [[ "$filename" != *.ko && "$filename" != *.o ]]; then
		eecho "File $filename is not a module (.ko or .o)"
	fi

	eecho "Module is set to $1"
	rm -f -- "$SHARE_DIR/modules/$1"
	cp $1 "$SHARE_DIR/modules"
}

function set_totest() {
	if [[ -f "$1" ]]; then
		cp "$1" $SHARE_DIR/test.sh
		return
	fi

	echo "${1:--g verity}" > $SHARE_DIR/totest
	if [[ ! -f "$2" ]]; then
		cat << EOF > $SHARE_DIR/xfstests-config
export FSTYP="xfs"
export RESULT_BASE=/root/results

export TEST_DEV=/dev/sdb
export TEST_DIR=/mnt/test
export SCRATCH_DEV=/dev/sdc
export SCRATCH_MNT=/mnt/scratch
EOF
	else
		cp "$2" $SHARE_DIR/xfstests-config
	fi
}

if [[ -f "$LOCAL_CONFIG" ]]; then
	eecho "Loading local config $LOCAL_CONFIG"
	load_config $LOCAL_CONFIG
fi

parse_args
init_share
set_kernel $KERNEL
add_module $MODULE
set_totest "$TOTEST" "$TEST_CONFIG"


cp "$(pwd)/$LOCAL_CONFIG" "$SHARE_DIR/kd.toml"

if [[ -f "$SIMPLE_TEST" ]]; then
	eecho "$SIMPLE_TEST will be used as simple test"
	cp "$SIMPLE_TEST" "$SHARE_DIR/dummy.sh"
fi

NODE_NAME=${NODE_NAME:-demo}
# After this line nix will insert more bash code. Don't exit
