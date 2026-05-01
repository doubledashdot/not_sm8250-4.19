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

# Prompt function for cleaner code
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

# Function to validate input
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

# Check EUR region restriction
if [[ "$region_choice" == "eur" && " ${EUR_MODELS[*]} " =~ " $model_choice " ]]; then
    echo "=============================================="
    echo "Error: This project doesn't support the EUR region."
    echo "=============================================="
    exit 1
fi

echo "=============================================="
echo "Configuration Summary:"
echo "Model: $model_choice"
echo "Region: ${region_choice:-default}"
echo "=============================================="

# Target properties
MODEL=$model_choice
REGION=$region_choice

# Kona platform now belongs to platform 11
export PROJECT_NAME="${MODEL}"
[ -z "${PLATFORM_VERSION}" ] && export PLATFORM_VERSION=11

if [ -n "$REGION" ]; then
    PROJECT_CONFIG="vendor/samsung/${MODEL}_${REGION}.config"
else
    PROJECT_CONFIG="vendor/samsung/${MODEL}.config"
fi


# ===== AnyKernel3 =====
AK3_REPO="https://github.com/skye-tachyon/AnyKernel3"
AK3_BRANCH="$MODEL"
AK3_DIR="$(pwd)/android/AnyKernel3"

ZIPNAME="not-perf-$(date '+%Y%m%d').zip"
TC_DIR="$(pwd)/tc/clang"
PLATFORM_DEFCONFIG="vendor/kona-perf_defconfig"
COMMON_DEFCONFIG="vendor/samsung/kona-sec-common.config"
DEFCONFIG="$PLATFORM_DEFCONFIG $COMMON_DEFCONFIG $PROJECT_CONFIG"

OUT_DIR="$(pwd)/out"
BOOT_DIR="$OUT_DIR/arch/arm64/boot"
DTS_DIR="$BOOT_DIR/dts/vendor/qcom"

if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
    ZIPNAME="${ZIPNAME::-4}-$(echo $head | cut -c1-8)-$MODEL.zip"
fi

git submodule update --init --recursive

export PATH="$TC_DIR/bin:$PATH"

if ! [ -d "$TC_DIR" ]; then
    echo -e "${YELLOW}Clang not found! Cloning to $TC_DIR...${NC}"
    echo "=============================================="
    mkdir -p "$TC_DIR"
    if ! curl -L https://www.kernel.org/pub/tools/llvm/files/llvm-22.1.4-x86_64.tar.gz \
        | tar -xz -C "$TC_DIR" --strip-components=1; then
        echo ""
        echo "=============================================="
        echo -e "${RED}Cloning failed! Aborting...${NC}"
        echo "=============================================="
        exit 1
    fi
    echo -e "${GREEN}Cloning complete!${NC}"
    echo "=============================================="
fi

mkdir -p out
echo -e "${BLUE}building with: $DEFCONFIG${NC}"
echo "=============================================="

make O=out ARCH=arm64 $DEFCONFIG
make O=out ARCH=arm64 olddefconfig

echo ""
echo "=============================================="
echo -e "\n${GREEN}Starting compilation...${NC}\n"
echo "=============================================="
echo "Build Info"
echo "=============================================="
echo "Project: $PROJECT_NAME"
echo "Platform config: $PLATFORM_DEFCONFIG"
echo "Common config: $COMMON_DEFCONFIG"
echo "Project config: $PROJECT_CONFIG"
echo "Output directory: $OUT_DIR"
echo "=============================================="
echo ""

make -j$(nproc --all) O=out ARCH=arm64 \
    CC=clang LD=ld.lld AS=llvm-as AR=llvm-ar NM=llvm-nm \
    OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
    CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    LLVM=1 LLVM_IAS=1 dtbo.img
    
make -j$(nproc --all) O=out ARCH=arm64 \
    CC=clang LD=ld.lld AS=llvm-as AR=llvm-ar NM=llvm-nm \
    OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
    CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    LLVM=1 LLVM_IAS=1 Image


if [ -f "$BOOT_DIR/Image" ]; then
    echo "================================="
    echo -e "${GREEN}Kernel Image found!${NC}"
    echo "================================="

    if [ -d "$DTS_DIR" ]; then
        echo -e "${BLUE}Generating dtb from $DTS_DIR...${NC}"
        cat $(find "$DTS_DIR" -type f -name "*.dtb" | sort) > "$BOOT_DIR/kona.dtb"
        echo "================================="

        if [ -f "$BOOT_DIR/kona.dtb" ]; then
            echo ""
            echo "================================="
            echo -e "${GREEN}kona.dtb/dtbo.img generated successfully!${NC}"
            echo "================================="
        else
            echo ""
            echo "================================="
            echo -e "${RED}Failed to generate kona.dtb! Check if dtbs were compiled.${NC}"
            echo "================================="
            exit 1
        fi
    else
        echo ""
        echo "================================="
        echo -e "${RED}DTS directory not found. Compilation might be incomplete.${NC}"
        echo ""
        echo "================================="
        exit 1
    fi
else
    echo ""
    echo "${RED}=================================${NC}"
    echo -e "\n${RED}Compilation failed! Image not found.${NC}"
    echo "${RED}=================================${NC}"
    exit 1
fi

rm -rf AnyKernel3
echo "[*] Cloning AnyKernel3 for $MODEL"
echo "================================="
git clone -q -b "$AK3_BRANCH" "$AK3_REPO" AnyKernel3 || exit 1

echo -e "Preparing zip..."
echo -e "================================="

cp "$BOOT_DIR/dtbo.img" AnyKernel3/dtbo.img
cp "$BOOT_DIR/Image" AnyKernel3/Image
cp "$BOOT_DIR/kona.dtb" AnyKernel3/kona.dtb

cd AnyKernel3

zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder
cd ..

echo -e "================================="
echo -e "\n${GREEN}Completed in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)!${NC}"
echo -e "${GREEN}Zip: $ZIPNAME${NC}"
echo -e "================================="
