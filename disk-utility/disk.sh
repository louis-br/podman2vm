#!/bin/sh
DIR=/output
TOTAL_SIZE=${TOTAL_SIZE:-3G}
EFI_SIZE=${EFI_SIZE:-261MiB}
LABEL=${LABEL:-rootfs}
UUID=${UUID:?"UUID not set"}

attach_loop() {
    dev=$(losetup --find --show --partscan "$DIR/disk.img")
}

detach_loop() {
    losetup --detach "$dev"
}

new_disk() {
    unmount_disk
    detach_loop
    dd if=/dev/zero of="$DIR/disk.img" bs=1 count=0 seek="$TOTAL_SIZE" # status=progress
    parted --script "$DIR/disk.img" \
        mklabel gpt \
        mkpart EFI fat32 1MiB "$EFI_SIZE" \
        set 1 esp on \
        mkpart "$LABEL" ext4 "$EFI_SIZE" 100% \
        unit B print
    attach_loop || exit 1
    mkfs.vfat -n EFI -i "EF11EF11" "${dev}p1"
    mkfs.ext4 -vF -t ext4 -U $UUID "${dev}p2"
}

mount_disk() {
    mkdir --parents /mnt/EFI
    mkdir --parents /mnt/rootfs
    mount --uuid EF11-EF11 /mnt/EFI  || return $?
    mount --uuid "$UUID" /mnt/rootfs || return $?
}

unmount_disk() {
    umount --quiet --all-targets "$dev"
}

cleanup() {
    echo "SIGNAL $SIGNAL"
    kill -s ${SIGNAL:-INT} $rsync_rootfs $rsync_efi
    #wait $rsync_rootfs $rsync_efi
}

trap "SIGNAL=INT cleanup" SIGINT
trap "SIGNAL=TERM cleanup" SIGTERM
trap "SIGNAL=QUIT cleanup" SIGQUIT

attach_loop || new_disk || exit 1

unmount_disk
for i in 1 2; do
    mount_disk || (new_disk && continue)
    break
done

mkdir --parents /rootfs
cd /rootfs
if [ -f /rootfs.tar ]; then
    pv /rootfs.tar | tar x
fi

rsync   --archive \
        --executability \
        --acls \
        --xattrs \
        --specials \
        --atimes \
        --delete \
        --force \
        --stats \
        --human-readable \
        --info=progress2 \
        /rootfs/ /mnt/rootfs &

rsync_rootfs=$!

rsync   --recursive \
        --links \
        --times \
        --atimes \
        --delete \
        --force \
        --human-readable \
        --info=progress2 \
        /EFI/ /mnt/EFI/ &

rsync_efi=$!

wait $rsync_rootfs $rsync_efi

sync -f /mnt/rootfs
sync -f /mnt/EFI
unmount_disk
detach_loop