#!/bin/bash

# Note: This script is based/from thecatvoid's build script: https://github.com/thecatvoid/actions_kernel_build

# Check if GCC or GAS were given as command-line argument
if [ "${1}" != "gas" ] && [ "${1}" != "gcc" ]; then
     echo "Usage: bash work/build.sh <gas or gcc>"
     exit 1
else
     echo "What's your kernel tree repository?"
     read kernel_tree
     echo "What's your kernel tree repository branch?"
     read kernel_branch
     echo "What's your kernel tree defconfig?"
     read kernel_defconfig
     
    # Setup missing packages (always, since web IDE instance always going back it its default state)
    sudo apt-get install flex bc device-tree-compiler bison cpio build-essential openssl libssl-dev libfl-dev -y
    
    # Set Base Path, it call your current root directory as your HOME dir.
    PROJECT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
    
    source ${PROJECT_DIR}/vars.sh
    
    # Kernel Soure Path
    KERNEL_PATH="${PROJECT_DIR}/${KERNEL_DIR}"

    # Prepare Directory
    mkdir -p "${PROJECT_DIR}"
    cd "${PROJECT_DIR}" || exit 1
    
    echo "Preparing all the necessary files."
    
    # Toolchain
    if [ ! -d clang ]; then
        echo "Downloading Clang prebuilt..."
        mkdir clang
        curl -Lsq "${CLANG_TAR_URL}" -o clang.tgz
        tar -xzf clang.tgz -C clang;
    else
        echo "Clang prebuilt already exists!"
    fi
    
    # Assembler
    if [ "${1}" = "gas" ]; then
        if [ ! -d gas ]; then
            if [ -d gcc-64 ] && [ -d gcc-32 ]; then
                echo "Removing GCC..."
                rm -rf gcc-64 gcc-32
            fi
            echo "Cloning Gas prebuilt..."
            git clone --depth=1 "${GAS_UTILS}" -b "${UTILS_BRANCH}" ./gas
        else
            echo "Gas prebuilt already exists!"
        fi
    elif [ "${1}" = "gcc" ]; then
        if [ ! -d gcc-64 ] && [ ! -d gcc-32 ]; then
            if [ -d gas ]; then
                echo "Removing GAS..."
                rm -rf gas
            fi
            echo "Cloning Gcc prebuilt..."
            git clone --depth=1 "${GCC_64}" -b "${UTILS_BRANCH}" ./gcc-64
            git clone --depth=1 "${GCC_32}" -b "${UTILS_BRANCH}" ./gcc-32
        else
            echo "Gcc prebuilt already exists!"
        fi
    fi
    
    # Kernel Source
    if [ ! -d "${KERNEL_DIR}" ]; then
        echo "Cloning kernel source..."
        git clone --depth=1 $kernel_tree -b $kernel_branch "${KERNEL_DIR}"
    else
        echo "Kernel source already exist!"
    fi
    
    # AnyKernel3 Template
    if [ ! -d AnyKernel3 ]; then
        echo "Cloning AnyKernel3..."
        git clone --depth=1 "${AK3}" -b "${AK3_BRANCH}" ./AnyKernel3
    else
        echo "AnyKernel3 already exists!"
    fi
    
    # Build Path
    if [ "${1}" = "gas" ]; then
        echo "Setting PATH for CLANG and GAS..."
        PATH="${PROJECT_DIR}/clang/bin:${PROJECT_DIR}/gas:${PATH}"
    elif [ "${1}" = "gcc" ]; then
        echo "Setting PATH for CLANG and GCC..."
        PATH="${PROJECT_DIR}/clang/bin:${PROJECT_DIR}/gcc-64/bin:${PROJECT_DIR}/gcc-32/bin:${PATH}"
    fi

    # Cleanup, if it exist
    if [ -d out ]; then
        echo "Removing previous build in out directory..."
        rm -rf out/arch/arm64/boot/Image
        rm -rf out/arch/arm64/boot/Image.gz
        echo "Proceed in compiling."
    else
        echo "Directory do not have out folder, proceed in compiling."
    fi
    
    # Preparing Build Process
    cd "${KERNEL_PATH}" || exit 1
    
    # Pull latest commit from remote, remove if local tree has changes to avoid merge conflict while pulling
    git pull
    
    # Setup make command
    if [ "${1}" = "gas" ]; then
        make O=${PROJECT_DIR}/out ARCH=arm64 LLVM=1 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- $kernel_defconfig
        make O=${PROJECT_DIR}/out ARCH=arm64 LLVM=1 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- -j3 2>&1 | tee ${PROJECT_DIR}/build.log
    elif [ "${1}" = "gcc" ]; then
        make O=${PROJECT_DIR}/out ARCH=arm64 CC=clang HOSTCC=clang CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-android- CROSS_COMPILE_ARM32=arm-linux-androideabi- $kernel_defconfig
        make O=${PROJECT_DIR}/out ARCH=arm64 CC=clang HOSTCC=clang CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-android- CROSS_COMPILE_ARM32=arm-linux-androideabi- -j3 2>&1 | tee ${PROJECT_DIR}/build.log
    fi
    
    # Setup AnyKernel3
    if [ -f ${PROJECT_DIR}/out/arch/arm64/boot/Image.gz ]; then
        cd ${PROJECT_DIR}/out/arch/arm64/boot
        echo "Kernel exist, copying..."
        cp -r Image.gz ${PROJECT_DIR}/AnyKernel3
        echo "Preparing AnyKernel3 zip..."
        cd ${PROJECT_DIR}/AnyKernel3
        echo "Start compressing new kernel zip..."
        zip -r9 UPDATE-AnyKernel3.zip * -x .git README.md *placeholder
        if [ -f UPDATE-AnyKernel3.zip ]; then
            echo "Uploading Kernel Zip to bashupload..."
            curl https://bashupload.com/ -T UPDATE-AnyKernel3.zip > ${PROJECT_DIR}/transfer.txt || exit 1
            grep -o 'https://[^[:space:]]*' ${PROJECT_DIR}/transfer.txt
            echo "Check transfer.txt for the download link."
            exit 1
        fi
    else
        echo "Kernel did not exist at all!"
        exit 1
    fi
fi