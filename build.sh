#!/bin/sh
set -e
cd $(dirname "$0")

build_it() {
    local tag="$1"
    local prefix="${PWD}/gerbil-home"
    local output="${PWD}/modules"

    echo ">>> cloning gerbil"
    git clone https://github.com/mighty-gerbils/gerbil.git

    echo ">>> building gerbil"
    mkdir -p gerbil-home
    pushd gerbil
    git checkout $tag
    ./configure --prefix="${prefix}"
    make -j4
    make install
    popd

    echo ">>> building gambit modules"
    mkdir -p modules
    gerbil-home/bin/gxi build-modules.ss "${output}"
}

gerbil_tag=master

if [ "$#" -eq 0 ]; then
    build_it "$gerbil_tag"
elif [ "$#" -eq 1 ]; then
    build_it "$1"
else
    echo "Usage: $0 [gerbil-tag=master]"
    exit 1
fi
