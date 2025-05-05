#!/usr/bin/env sh

src="$(pwd)"
mkdir "$src/build"
export INSTALL_MOD_PATH="$src/build"
export INSTALL_PATH="$src/build"
make -C $src install
