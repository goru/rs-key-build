#!/bin/bash -ex

BUILD_DIR="$PWD/build"
TARGET=thumbv8m.main-none-eabihf

# openssl ecparam -genkey -name secp256k1 -noout -out keys/rskey_sb.pem
SECURE_BOOT_PKEY="$PWD/keys/rskey_sb.pem"

mkdir -p build
cd build

[ -d pico-sdk ] || git clone --depth 1 --branch 2.1.1 --recurse-submodules --shallow-submodules https://github.com/raspberrypi/pico-sdk
[ -d picotool ] || git clone --depth 1 --branch 2.1.1 https://github.com/raspberrypi/picotool
[ -d RS-Key ]   || git clone --depth 1 --branch v0.4.11 https://github.com/TheMaxMur/RS-Key

# picotool
mkdir -p picotool/build
cd picotool/build
PICO_SDK_PATH="$BUILD_DIR/pico-sdk" cmake .. -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/picotool-install"
make
make install
cd -

export PATH="$BUILD_DIR/picotool-install/bin:$PATH"

# Rust toolchain and linker
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain none
. "$HOME/.cargo/env"
rustup toolchain install stable --profile minimal -c rust-src -c llvm-tools -t "$TARGET"
rustup default stable
cargo install flip-link --locked

export PATH="$(rustc --print sysroot)/lib/rustlib/x86_64-unknown-linux-gnu/bin:$PATH"

# Firmware
cd RS-Key

# disable idle led
sed -i '/^static STATUS_BRIGHTNESS/,/^];/c\
static STATUS_BRIGHTNESS: [AtomicU8; N_STATUS] = [\
    AtomicU8::new(0),\
    AtomicU8::new(DEFAULT_BRIGHTNESS),\
    AtomicU8::new(DEFAULT_BRIGHTNESS),\
    AtomicU8::new(DEFAULT_BRIGHTNESS),\
];' firmware/src/led.rs

env VIDPID=Yubikey5 FLASH_SIZE=16M LED_PIN=22 LED_ORDER=grb PRESENCE_PIN=bootsel \
  cargo build --release -p firmware

# Flash wiper
env FLASH_SIZE=16M LED_PIN=22 LED_ORDER=grb cargo build --release -p rsk-wipe
picotool uf2 convert "target/$TARGET/release/rsk-wipe" -t elf rsk-wipe.uf2

# Partition table, signature and UF2
scripts/pt.sh "target/$TARGET/release/firmware" firmware-pt.elf
picotool seal --sign --hash firmware-pt.elf -t elf firmware-signed.elf -t elf \
  "$SECURE_BOOT_PKEY" otp_secureboot.json --major 1 --minor 0 --rollback 1
picotool uf2 convert firmware-signed.elf -t elf firmware-signed.uf2
