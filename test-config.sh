#!/bin/bash
export LLVM=1
git clone --depth 1 https://github.com/torvalds/linux.git
cd linux
make defconfig
make menuconfig
