#!/usr/bin/env bash

ARCH=$(uname -m)

if [[ -z "$THEOS" || ! -d "$THEOS" ]]; then
    echo "Error: THEOS directory not found. Please set the THEOS environment variable."
    exit 1
fi

if [[ -d "$THEOS/toolchain/linux/iphone/" ]]; then
    echo "Clearing existing toolchain directory..."
    rm -rf "$THEOS/toolchain/linux/iphone/"
fi

mkdir -p "$THEOS/toolchain/linux/iphone/"

# Non swift toolchain
# if [[ $ARCH == aarch64 || $ARCH == x86_64 ]]; then
#     echo "Downloading toolchain for $ARCH..."
#     curl -sL https://github.com/L1ghtmann/llvm-project/releases/download/main-ca1f250/iOSToolchain-$ARCH.tar.xz | tar -xJvf - -C "$THEOS/toolchain/"
# else
#     echo "Apologies, we do not currently provide precompiled toolchains for $ARCH Linux."
#     exit 1
# fi

# Swift toolchain
if [[ $ARCH == x86_64 ]]; then
    curl -sL https://github.com/L1ghtmann/swift-toolchain-linux/releases/download/1ddaf4f2-9726-470f-b53e-758dfe78fcb7/swift-6.0.2-ubuntu24.04.tar.xz | tar -xJvf - -C $THEOS/toolchain/
elif [[ $ARCH == aarch64 ]]; then
    curl -sL https://github.com/L1ghtmann/swift-toolchain-linux/releases/download/1ddaf4f2-9726-470f-b53e-758dfe78fcb7/swift-6.0.2-$ARCH.tar.xz | tar -xJvf - -C $THEOS/toolchain/
else
    common "Apologies, we do not currently provide precompiled toolchains for $ARCH Linux."
    exit 1
fi
