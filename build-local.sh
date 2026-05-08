#!/usr/bin/env bash

SECONDS=0 # builtin bash timer

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Available models
VALID_MODELS=("bloomxq" "c1q" "c2q" "f2q" "gts7l" "gts7lwifi" "gts7xl" "gts7xlwifi" "r8q" "x1q" "y2q" "z3q")

# Models that do support EUR region
EUR_MODELS=("r8q" "gts7l" "gts7lwifi" "gts7xl" "gts7xlwifi" "f2q" "bloomxq")

# Available regions
VALID_REGIONS=("eur" "kor" "chn" "usa")

# Available build types
VALID_BUILDS=("ci" "perf" "recovery")

VALID_ADDITIONALS=("none" "ksu" "nethunter" "droidspaces" "droidspaces+nethunter")

# Prompt function
prompt() {
    echo "=============================================="
    echo "$1"
    echo "=============================================="
    shift
    for option in "$@"; do
        echo "$option"
    done
    echo "=============================================="
}

# Validate input
validate_choice() {
    local choice="$1"
    shift
    local valid_values=("$@")

    for value in "${valid_values[@]}"; do
        if [[ "$choice" == "$value" ]]; then
            return 0
        fi
    done

    return 1
}


# Model selection
prompt "Which project do you want to build?" "${VALID_MODELS[@]}"
read -p " - Enter your choice: " model_choice
model_choice=$(echo "$model_choice" | tr '[:upper:]' '[:lower:]')

if ! validate_choice "$model_choice" "${VALID_MODELS[@]}"; then
    echo "Invalid model choice! Exiting."
    exit 1
fi


# Region selection
prompt "Select region (or press enter for default)" "${VALID_REGIONS[@]}"
read -p " - Enter your choice: " region_choice
region_choice=$(echo "$region_choice" | tr '[:upper:]' '[:lower:]')

if [[ -n "$region_choice" ]] && ! validate_choice "$region_choice" "${VALID_REGIONS[@]}"; then
    echo "Invalid region choice! Exiting."
    exit 1
fi

# EUR restriction logic
if [[ "$region_choice" == "eur" && ! " ${EUR_MODELS[*]} " =~ " $model_choice " ]]; then
    echo "=============================================="
    echo "Error: This model doesn't support the EUR region."
    echo "=============================================="
    exit 1
fi


# Build type selection
prompt "Which build type do you want?" "${VALID_BUILDS[@]}"
read -p " - Enter your choice: " build_choice
build_choice=$(echo "$build_choice" | tr '[:upper:]' '[:lower:]')

if ! validate_choice "$build_choice" "${VALID_BUILDS[@]}"; then
    echo "Invalid build type! Exiting."
    exit 1
fi

# Aditional configs selection
prompt "Which aditionals do you want to include in the kernel? (select none for no ksu, every other option has it)" "${VALID_ADDITIONALS[@]}"
read -p " - Enter your choice: " add_choice
add_choice=$(echo "$add_choice" | tr '[:upper:]' '[:lower:]')

if ! validate_choice "$add_choice" "${VALID_ADDITIONALS[@]}"; then
    echo "Invalid build add-on! Exiting."
    exit 1
fi

# Target properties
MODEL=$model_choice
REGION=$region_choice

export PROJECT_NAME="${MODEL}"
[ -z "${PLATFORM_VERSION}" ] && export PLATFORM_VERSION=11

if [ -n "$REGION" ]; then
    PROJECT_CONFIG="vendor/samsung/${MODEL}_${REGION}.config"
else
    PROJECT_CONFIG="vendor/samsung/${MODEL}.config"
fi


# Build configuration switch
case "$build_choice" in
    ci)
        ZIPNAME="ci-$(date '+%Y%m%d').zip"
        PLATFORM_DEFCONFIG="vendor/kona-not_defconfig"
        COMMON_DEFCONFIG="vendor/samsung/kona-sec-not.config"
        ;;
    recovery)
        ZIPNAME="recovery-$(date '+%Y%m%d').zip"
        PLATFORM_DEFCONFIG="vendor/kona-not_defconfig"
        COMMON_DEFCONFIG="vendor/samsung/kona-sec-not.config"
        EXTRA_CONFIG="vendor/not/no_qcacld.config vendor/not/recovery.config"
        ;;
    perf)
        ZIPNAME="perf-$(date '+%Y%m%d').zip"
        PLATFORM_DEFCONFIG="vendor/kona-perf_defconfig"
        COMMON_DEFCONFIG="vendor/samsung/kona-sec-common.config"
        ;;
esac

# Additionals configurations switch
case "$add_choice" in
    none)
        ZIPNAME="not-$ZIPNAME"
        ;;
    ksu)
        ZIPNAME="not-ksu-$ZIPNAME"
        EXTRA_CONFIG="$EXTRA_CONFIG vendor/not/ksu.config"
        ;;
    nethunter)
        ZIPNAME="not-nethunter-$ZIPNAME"
        PLATFORM_DEFCONFIG="vendor/kona-not_defconfig"
        COMMON_DEFCONFIG="vendor/samsung/kona-sec-not.config"
        EXTRA_CONFIG="$EXTRA_CONFIG vendor/not/ksu.config vendor/not/nethunter.config"
        ;;
    droidspaces)
        ZIPNAME="not-droidspaces-$ZIPNAME"
        PLATFORM_DEFCONFIG="vendor/kona-not_defconfig"
        COMMON_DEFCONFIG="vendor/samsung/kona-sec-not.config"
        EXTRA_CONFIG="$EXTRA_CONFIG vendor/not/ksu.config vendor/not/droidspace.config"
        ;;
    droidspaces+nethunter)
        ZIPNAME="not-droidspaces-$ZIPNAME"
        PLATFORM_DEFCONFIG="vendor/kona-not_defconfig"
        COMMON_DEFCONFIG="vendor/samsung/kona-sec-not.config"
        EXTRA_CONFIG="$EXTRA_CONFIG vendor/not/ksu.config vendor/not/nethunter.config vendor/not/droidspace.config"
        ;;
esac

DEFCONFIG="$PLATFORM_DEFCONFIG $COMMON_DEFCONFIG $PROJECT_CONFIG $EXTRA_CONFIG"


# Paths
AK3_REPO="https://github.com/skye-tachyon/AnyKernel3"
AK3_BRANCH="$MODEL"

TC_DIR="$(pwd)/tc/clang"
OUT_DIR="$(pwd)/out"
BOOT_DIR="$OUT_DIR/arch/arm64/boot"
DTS_DIR="$BOOT_DIR/dts/vendor/qcom"

# smth
if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
    ZIPNAME="${ZIPNAME::-4}-$(echo $head | cut -c1-8)-$MODEL.zip"
fi

git submodule update --init --recursive

export PATH="$TC_DIR/bin:$PATH"


# Toolchain setup
if ! [ -d "$TC_DIR" ]; then
    echo -e "${YELLOW}Clang not found! Downloading...${NC}"
    mkdir -p "$TC_DIR"
    if ! curl -L https://www.kernel.org/pub/tools/llvm/files/llvm-22.1.4-x86_64.tar.gz \
        | tar -xz -C "$TC_DIR" --strip-components=1; then
        echo -e "${RED}Download failed!${NC}"
        exit 1
    fi
    echo -e "${GREEN}Clang ready!${NC}"
fi

mkdir -p out

echo -e "${BLUE}Building with: $DEFCONFIG${NC}"

make O=out ARCH=arm64 $DEFCONFIG
make O=out ARCH=arm64 olddefconfig

# Common make flags
MAKE_ARGS="-j$(nproc --all) O=out ARCH=arm64 \
CC=clang LD=ld.lld AS=llvm-as AR=llvm-ar NM=llvm-nm \
OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
LLVM=1 LLVM_IAS=1"

echo -e "\n${GREEN}Starting compilation...${NC}"

rm -rf out/arch/arm64/boot #ok

make $MAKE_ARGS dtbo.img
make $MAKE_ARGS Image.gz


# Post build checks
if [ ! -f "$BOOT_DIR/Image.gz" ]; then
    echo -e "${RED}Compilation failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Kernel Image found!${NC}"

if [ ! -d "$DTS_DIR" ]; then
    echo -e "${RED}DTS directory missing!${NC}"
    exit 1
fi

echo -e "${BLUE}Generating DTB...${NC}"
cat $(find "$DTS_DIR" -name "*.dtb" | sort) > "$BOOT_DIR/kona.dtb"

if [ ! -f "$BOOT_DIR/kona.dtb" ]; then
    echo -e "${RED}DTB generation failed!${NC}"
    exit 1
fi

echo -e "${GREEN}DTB + DTBO ready!${NC}"


# AK3
rm -rf AnyKernel3
echo "[*] Cloning AnyKernel3..."
git clone -q -b "$AK3_BRANCH" "$AK3_REPO" AnyKernel3 || exit 1

cp "$BOOT_DIR/dtbo.img" AnyKernel3/
cp "$BOOT_DIR/Image.gz" AnyKernel3/
cp "$BOOT_DIR/kona.dtb" AnyKernel3/

# remove older builds
rm -rf *.zip

cd AnyKernel3
zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder
cd ..

echo -e "\n${GREEN}Completed in $((SECONDS / 60))m $((SECONDS % 60))s${NC}"
echo -e "${GREEN}Zip: $ZIPNAME${NC}"
