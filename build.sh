#!/bin/bash

VMLINUZ=${VMLINUZ:?"VMLINUZ not set"}
INITRAMFS=${INITRAMFS:?"INITRAMFS not set"}
KERNEL_PARAMETERS=${KERNEL_PARAMETERS:?"KERNEL_PARAMETERS not set"}

ROOTFS=${ROOTFS:-"rootfs/"}
OUTPUT=${OUTPUT:-"output/"}

LABEL=${LABEL:-"rootfs"}
BOOTLOADER=${BOOTLOADER:-"grub"}
TOTAL_SIZE=${TOTAL_SIZE:-"8GB"}
EFI_SIZE=${EFI_SIZE:-"261MiB"}
UUID=${UUID:-"dddddddd-0000-cccc-eeee-222222222222"}

mkdir --parents rootfs/
mkdir --parents output/
for bootloader in bootloaders/*/; do
    mkdir --parents $bootloader/output/
done

bootloader() {
    sudo podman build   --tag=podman2vm_boot \
                        --build-arg="VMLINUZ=$VMLINUZ" \
                        --build-arg="INITRAMFS=$INITRAMFS" \
                        --build-arg="KERNEL_PARAMETERS=$KERNEL_PARAMETERS" \
                        --build-arg="UUID=$UUID" \
                        "bootloaders/$BOOTLOADER" || exit 1

    sudo podman run     --mount=type=bind,source="bootloaders/$BOOTLOADER/output",destination="/output" \
                        --network="none" \
                        --replace \
                        --rm \
                        --name="podman2vm_boot" \
                        podman2vm_boot || exit 1
}

build_disk() {
    sudo podman build --tag="podman2vm_disk" disk-utility/ || exit 1
}

disk() {
    sudo podman run     --mount=type=bind,source="/run/shm",destination="/run/shm" \
                        --mount=type=bind,source="/dev",destination="/dev" \
                        --mount=type=bind,source="$OUTPUT",destination="/output" \
                        --mount=type=bind,source="$ROOTFS",destination="/rootfs" \
                        --mount=type=bind,source="bootloaders/$BOOTLOADER/output",destination="/EFI" \
                        --env="TOTAL_SIZE=$TOTAL_SIZE" \
                        --env="EFI_SIZE=$EFI_SIZE" \
                        --env="LABEL=$LABEL" \
                        --env="UUID=$UUID" \
                        --network="none" \
                        --replace \
                        --rm \
                        --privileged \
                        --name="podman2vm_disk" \
                        podman2vm_disk || exit 1
}

bootloader &
build_disk &

while [ -n "$(jobs)" ]; do
    wait -n || exit 1
done

disk

echo Done building. 