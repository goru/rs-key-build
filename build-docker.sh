#!/bin/bash

docker run -it --rm -e USERID=$(id -u) -e GROUPID=$(id -g) --mount type=bind,source="$(pwd)",target=/work ubuntu:24.04 /bin/bash -c -ex "\
  export DEBIAN_FRONTEND=noninteractive;
  apt update;\
  apt install -y build-essential cmake libusb-1.0-0-dev git ca-certificates curl python3 gcc-arm-none-eabi libnewlib-arm-none-eabi libstdc++-arm-none-eabi-newlib;\
  userdel ubuntu;\
  groupadd -g \${GROUPID} user;\
  useradd -u \${USERID} -g \${GROUPID} -m user;\
  su - user -c 'cd /work; ./build.sh'"
