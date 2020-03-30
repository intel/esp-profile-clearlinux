#!/bin/bash

# Copyright (C) 2019 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause

set -a

#this is provided while using Utility OS
source /opt/bootstrap/functions

PROVISION_LOG="/tmp/provisioning.log"
run "Begin provisioning process..." \
    "sleep 0.5" \
    ${PROVISION_LOG}

PROVISIONER=$1

# --- Get kernel parameters ---
kernel_params=$(cat /proc/cmdline)

if [[ $kernel_params == *"proxy="* ]]; then
	tmp="${kernel_params##*proxy=}"
	export param_proxy="${tmp%% *}"

	export http_proxy=${param_proxy}
	export https_proxy=${param_proxy}
	export no_proxy="localhost,127.0.0.1,${PROVISIONER}"
	export HTTP_PROXY=${param_proxy}
	export HTTPS_PROXY=${param_proxy}
	export NO_PROXY="localhost,127.0.0.1,${PROVISIONER}"
	export DOCKER_PROXY_ENV="--env http_proxy='${http_proxy}' --env https_proxy='${https_proxy}' --env no_proxy='${no_proxy}' --env HTTP_PROXY='${HTTP_PROXY}' --env HTTPS_PROXY='${HTTPS_PROXY}' --env NO_PROXY='${NO_PROXY}'"
	export INLINE_PROXY="export http_proxy='${http_proxy}'; export https_proxy='${https_proxy}'; export no_proxy='${no_proxy}'; export HTTP_PROXY='${HTTP_PROXY}'; export HTTPS_PROXY='${HTTPS_PROXY}'; export NO_PROXY='${NO_PROXY}';"
elif [ $(
	nc -vz ${PROVISIONER} 3128
	echo $?
) -eq 0 ]; then
	export http_proxy=http://${PROVISIONER}:3128/
	export https_proxy=http://${PROVISIONER}:3128/
	export no_proxy="localhost,127.0.0.1,${PROVISIONER}"
	export HTTP_PROXY=http://${PROVISIONER}:3128/
	export HTTPS_PROXY=http://${PROVISIONER}:3128/
	export NO_PROXY="localhost,127.0.0.1,${PROVISIONER}"
	export DOCKER_PROXY_ENV="--env http_proxy='${http_proxy}' --env https_proxy='${https_proxy}' --env no_proxy='${no_proxy}' --env HTTP_PROXY='${HTTP_PROXY}' --env HTTPS_PROXY='${HTTPS_PROXY}' --env NO_PROXY='${NO_PROXY}'"
	export INLINE_PROXY="export http_proxy='${http_proxy}'; export https_proxy='${https_proxy}'; export no_proxy='${no_proxy}'; export HTTP_PROXY='${HTTP_PROXY}'; export HTTPS_PROXY='${HTTPS_PROXY}'; export NO_PROXY='${NO_PROXY}';"
fi

if [[ $kernel_params == *"proxysocks="* ]]; then
	tmp="${kernel_params##*proxysocks=}"
	param_proxysocks="${tmp%% *}"

	export FTP_PROXY=${param_proxysocks}

	tmp_socks=$(echo ${param_proxysocks} | sed "s#http://##g" | sed "s#https://##g" | sed "s#/##g")
	export SSH_PROXY_CMD="-o ProxyCommand='nc -x ${tmp_socks} %h %p'"
fi

if [[ $kernel_params == *"httppath="* ]]; then
	tmp="${kernel_params##*httppath=}"
	export param_httppath="${tmp%% *}"
fi

if [[ $kernel_params == *"parttype="* ]]; then
	tmp="${kernel_params##*parttype=}"
	export param_parttype="${tmp%% *}"
elif [ -d /sys/firmware/efi ]; then
	export param_parttype="efi"
else
	export param_parttype="msdos"
fi

if [[ $kernel_params == *"bootstrap="* ]]; then
	tmp="${kernel_params##*bootstrap=}"
	export param_bootstrap="${tmp%% *}"
	export param_bootstrapurl=$(echo $param_bootstrap | sed "s#/$(basename $param_bootstrap)\$##g")
fi

if [[ $kernel_params == *"basebranch="* ]]; then
	tmp="${kernel_params##*basebranch=}"
	export param_basebranch="${tmp%% *}"
fi

if [[ $kernel_params == *"token="* ]]; then
	tmp="${kernel_params##*token=}"
	export param_token="${tmp%% *}"
fi

if [[ $kernel_params == *"agent="* ]]; then
	tmp="${kernel_params##*agent=}"
	export param_agent="${tmp%% *}"
else
	export param_agent="master"
fi

if [[ $kernel_params == *"kernparam="* ]]; then
	tmp="${kernel_params##*kernparam=}"
	temp_param_kernparam="${tmp%% *}"
	export param_kernparam=$(echo ${temp_param_kernparam} | sed 's/#/ /g' | sed 's/:/=/g')
fi

if [[ $kernel_params = *"clearlinuxversion="* ]]; then
	tmp="${kernel_params##*clearlinuxversion=}"
	param_clearlinuxversion="${tmp%% *}"
else
	param_clearlinuxversion="latest"
fi

# The following is bandaid for Disco Dingo
if [ $param_ubuntuversion = "disco" ]; then
	export DOCKER_UBUNTU_RELEASE="cosmic"
else
	export DOCKER_UBUNTU_RELEASE=$param_ubuntuversion
fi

if [[ $kernel_params == *"arch="* ]]; then
	tmp="${kernel_params##*arch=}"
	export param_arch="${tmp%% *}"
else
	export param_arch="amd64"
fi

if [[ $kernel_params == *"insecurereg="* ]]; then
	tmp="${kernel_params##*insecurereg=}"
	export param_insecurereg="${tmp%% *}"
fi

if [[ $kernel_params == *"username="* ]]; then
	tmp="${kernel_params##*username=}"
	export param_username="${tmp%% *}"
else
	export param_username="sys-admin"
fi

if [[ $kernel_params == *"password="* ]]; then
	tmp="${kernel_params##*password=}"
	export param_password="${tmp%% *}"
else
	export param_password="password"
fi

if [[ $kernel_params = *"hostsshport="* ]]; then
	tmp="${kernel_params##*hostsshport=}"
	param_hostsshport="${tmp%% *}"
else
	param_hostsshport="22"
fi

if [[ $kernel_params == *"debug="* ]]; then
	tmp="${kernel_params##*debug=}"
	export param_debug="${tmp%% *}"
fi

if [[ $kernel_params == *"release="* ]]; then
	tmp="${kernel_params##*release=}"
	export param_release="${tmp%% *}"
else
	export param_release='dev'
fi

if [[ $param_release == 'prod' ]]; then
	export kernel_params="$param_kernparam" # ipv6.disable=1
else
	export kernel_params="$param_kernparam"
fi

# --- Clear Linux Bundles ---
clearlinux_bundles="\
	os-core \
	os-core-update \
	kernel-install \
	kernel-native \
	sysadmin-basic \
	network-basic \
	containers-basic \
	editors \
	openssh-server"

# --- Get free memory
export freemem=$(grep MemTotal /proc/meminfo | awk '{print $2}')

# --- Detect HDD ---
if [ -d /sys/block/nvme[0-9]n[0-9] ]; then
	export DRIVE=$(echo /dev/$(ls -l /sys/block/nvme* | grep -v usb | head -n1 | sed 's/^.*\(nvme[a-z0-1]\+\).*$/\1/'))
	if [[ $param_parttype == 'efi' ]]; then
		export EFI_PARTITION=${DRIVE}p1
		export BOOT_PARTITION=${DRIVE}p2
		export SWAP_PARTITION=${DRIVE}p3
		export ROOT_PARTITION=${DRIVE}p4
	else
		export BOOT_PARTITION=${DRIVE}p1
		export SWAP_PARTITION=${DRIVE}p2
		export ROOT_PARTITION=${DRIVE}p3
	fi
elif [ -d /sys/block/[vsh]da ]; then
	export DRIVE=$(echo /dev/$(ls -l /sys/block/[vsh]da | grep -v usb | head -n1 | sed 's/^.*\([vsh]d[a-z]\+\).*$/\1/'))
	if [[ $param_parttype == 'efi' ]]; then
		export EFI_PARTITION=${DRIVE}1
		export BOOT_PARTITION=${DRIVE}2
		export SWAP_PARTITION=${DRIVE}3
		export ROOT_PARTITION=${DRIVE}4
	else
		export BOOT_PARTITION=${DRIVE}1
		export SWAP_PARTITION=${DRIVE}2
		export ROOT_PARTITION=${DRIVE}3
	fi
elif [ -d /sys/block/mmcblk[0-9] ]; then
	export DRIVE=$(echo /dev/$(ls -l /sys/block/mmcblk[0-9] | grep -v usb | head -n1 | sed 's/^.*\(mmcblk[0-9]\+\).*$/\1/'))
	if [[ $param_parttype == 'efi' ]]; then
		export EFI_PARTITION=${DRIVE}p1
		export BOOT_PARTITION=${DRIVE}p2
		export SWAP_PARTITION=${DRIVE}p3
		export ROOT_PARTITION=${DRIVE}p4
	else
		export BOOT_PARTITION=${DRIVE}p1
		export SWAP_PARTITION=${DRIVE}p2
		export ROOT_PARTITION=${DRIVE}p3
	fi
else
	echo "No supported drives found!" 2>&1 | tee -a /dev/tty0
	sleep 300
	reboot
fi

export BOOTFS=/target/boot
export ROOTFS=/target/root
mkdir -p $BOOTFS
mkdir -p $ROOTFS

echo "" 2>&1 | tee -a /dev/tty0
echo "" 2>&1 | tee -a /dev/tty0
echo "Installing on ${DRIVE}" 2>&1 | tee -a /dev/tty0
echo "" 2>&1 | tee -a /dev/tty0
echo "" 2>&1 | tee -a /dev/tty0

# --- Partition HDD ---
run "Partitioning drive ${DRIVE}" \
    "if [[ $param_parttype == 'efi' ]]; then
        parted --script ${DRIVE} \
        mklabel gpt \
        mkpart ESP fat32 1MiB 551MiB \
        set 1 esp on \
        mkpart primary linux-swap 551MiB 1575MiB \
        mkpart primary 1575MiB 100%;
    else
        parted --script ${DRIVE} \
        mklabel gpt \
        mkpart primary ext4 1MiB 551MiB \
        set 1 legacy_boot on \
        mkpart primary linux-swap 551MiB 1575MiB \
        mkpart primary 1575MiB 100%;
    fi" \
    ${PROVISION_LOG}

# --- Create BOOT file system ---
if [[ $param_parttype == 'efi' ]]; then
    run "Creating boot partition on drive ${DRIVE}" \
        "mkfs -t vfat -n BOOT ${BOOT_PARTITION} && \
        mkdir -p $BOOTFS && \
        mount ${BOOT_PARTITION} $BOOTFS" \
        ${PROVISION_LOG}
else
    run "Creating boot partition on drive ${DRIVE}" \
        "mkfs -t ext4 -L BOOT -F ${BOOT_PARTITION} && \
        e2label ${BOOT_PARTITION} BOOT && \
        mkdir -p $BOOTFS && \
        mount ${BOOT_PARTITION} $BOOTFS" \
        ${PROVISION_LOG}
fi

run "Creating root file system" \
    "mkfs -t ext4 ${ROOT_PARTITION} && \
    mount ${ROOT_PARTITION} $ROOTFS && \
    e2label ${ROOT_PARTITION} STATE_PARTITION " \
    ${PROVISION_LOG}

run "Creating swap file system" \
    "mkswap ${SWAP_PARTITION}" \
    ${PROVISION_LOG}

# --- check if we need to add memory ---
if [ $freemem -lt 6291456 ]; then
    fallocate -l 2G $ROOTFS/swap
    chmod 600 $ROOTFS/swap
    mkswap $ROOTFS/swap
    swapon $ROOTFS/swap
fi

# --- check if we need to move tmp folder ---
if [ $freemem -lt 6291456 ]; then
    mkdir -p $ROOTFS/tmp
    export TMP=$ROOTFS/tmp
    export PROVISION_LOG="$TMP/provisioning.log"
else
    mkdir -p /build
    export TMP=/build
fi

if [ $(wget http://${PROVISIONER}:5000/v2/_catalog -O-) ] 2>/dev/null; then
    export REGISTRY_MIRROR="--registry-mirror=http://${PROVISIONER}:5000"
fi

run "Configuring Image Database" \
    "mkdir -p $ROOTFS/tmp/docker && \
    killall dockerd && sleep 2 && \
    /usr/local/bin/dockerd ${REGISTRY_MIRROR} --data-root=$ROOTFS/tmp/docker > /dev/null 2>&1 &" \
    "$TMP/provisioning.log"

sleep 2

# --- Begin Clear Linux Install Process ---
run "Preparing Clear Linux installer" \
    "docker pull clearlinux:latest" \
    "$TMP/provisioning.log"

mkdir -p $ROOTFS/usr/share/clear/bundles/ && \
for bundle in $clearlinux_bundles; do
    touch $ROOTFS/usr/share/clear/bundles/$bundle;
done

run "Installing Clear Linux" \
    "docker run -i --rm --privileged --name cl-installer ${DOCKER_PROXY_ENV} -v /dev:/dev -v /sys/:/sys/ -v $ROOTFS:/target/root clearlinux:latest \
    swupd verify --install --path='/target/root' --manifest $param_clearlinuxversion \
    --url https://cdn.download.clearlinux.org/update \
    --statedir '/target/root/tmp/swupd-state' --no-boot-update" \
    "$TMP/provisioning.log"

# --- Enabling Clear Linux boostrap items ---
if [[ $param_parttype == 'efi' ]]; then
    bootfs_partuuid=$(lsblk -no PARTUUID ${BOOT_PARTITION})
    swapfs_partuuid=$(lsblk -no PARTUUID ${SWAP_PARTITION})
    run "Enabling Clear Linux boostrap items" \
        "mkdir -p $ROOTFS/etc/systemd/system/multi-user.target.wants/ && \
        mkdir -p $ROOTFS/etc/systemd/system/network-online.target.wants/ && \
        ln -s /usr/lib/systemd/system/docker.service $ROOTFS/etc/systemd/system/network-online.target.wants/docker.service && \
        ln -s /dev/null $ROOTFS/etc/systemd/system/swupd-update.service && \
        ln -s /dev/null $ROOTFS/etc/systemd/system/swupd-update.time && \
        wget --header \"Authorization: token ${param_token}\" -O $ROOTFS/etc/systemd/system/show-ip.service ${param_basebranch}/systemd/show-ip.service && \
        ln -s /etc/systemd/system/show-ip.service $ROOTFS/etc/systemd/system/multi-user.target.wants/show-ip.service; \
        echo 'PARTUUID=$bootfs_partuuid /boot           vfat    defaults        0 2' >> $ROOTFS/etc/fstab && \
        echo 'PARTUUID=$swapfs_partuuid none            swap    sw              0 0' >> $ROOTFS/etc/fstab && \
        echo -e 'root ALL=(ALL:ALL) ALL\\\n%wheel ALL=(ALL) ALL' > $ROOTFS/etc/sudoers" \
        "$TMP/provisioning.log"
else
    run "Enabling Clear Linux boostrap items" \
        "mkdir -p $ROOTFS/etc/systemd/system/multi-user.target.wants/ && \
        mkdir -p $ROOTFS/etc/systemd/system/network-online.target.wants/ && \
        ln -s /usr/lib/systemd/system/docker.service $ROOTFS/etc/systemd/system/multi-user.target.wants/docker.service && \
        ln -s /dev/null $ROOTFS/etc/systemd/system/swupd-update.service && \
        ln -s /dev/null $ROOTFS/etc/systemd/system/swupd-update.time && \
        wget --header \"Authorization: token ${param_token}\" -O $ROOTFS/etc/systemd/system/show-ip.service ${param_basebranch}/systemd/show-ip.service && \
        ln -s /etc/systemd/system/show-ip.service $ROOTFS/etc/systemd/system/network-online.target.wants/show-ip.service; \
        echo '$BOOT_PARTITION /boot           ext4    defaults        0 2' >> $ROOTFS/etc/fstab && \
        echo '$SWAP_PARTITION none            swap    sw              0 0' >> $ROOTFS/etc/fstab && \
        echo -e 'root ALL=(ALL:ALL) ALL\\\n%wheel ALL=(ALL) ALL' > $ROOTFS/etc/sudoers" \
        "$TMP/provisioning.log"
fi

HOSTNAME="clr-$(< /dev/urandom tr -dc a-f0-9 | head -c10)"
run "Set Host Name" \
    "echo \"${HOSTNAME}\" > $ROOTFS/etc/hostname" \
    "$TMP/provisioning.log"

run "Enabling Kernel Modules at boot time" \
    "mkdir -p $ROOTFS/etc/modules-load.d/ && \
    echo 'kvmgt' > $ROOTFS/etc/modules-load.d/kvmgt.conf && \
    echo 'vfio-iommu-type1' > $ROOTFS/etc/modules-load.d/vfio.conf && \
    echo 'dm-crypt' > $ROOTFS/etc/modules-load.d/dm-crypt.conf && \
    echo 'fuse' > $ROOTFS/etc/modules-load.d/fuse.conf && \
    echo 'nbd' > $ROOTFS/etc/modules-load.d/nbd.conf && \
    echo 'i915 enable_gvt=1' > $ROOTFS/etc/modules-load.d/i915.conf" \
    "$TMP/provisioning.log"

run "Enabling Networking" \
    "mkdir -p $ROOTFS/etc/systemd/network/ && \
    wget --header \"Authorization: token ${param_token}\" -O $ROOTFS/etc/systemd/network/wired.network ${param_basebranch}/files/etc/systemd/network/wired.network && \
    docker run -i --rm --privileged --name cl-installer ${DOCKER_PROXY_ENV} -v /dev:/dev -v /sys/:/sys/ -v $ROOTFS:/target/root clearlinux:latest sh -c \
    'mount --bind dev /target/root/dev && \
    mount -t proc proc /target/root/proc && \
    mount -t sysfs sysfs /target/root/sys && \
    chroot /target/root sh -c \
    \"systemctl enable systemd-networkd\"'" \
    "$TMP/provisioning.log"

mkdir -p $ROOTFS/etc/systemd/system/sshd.socket.d && \
echo "[Socket]
ListenStream=
ListenStream=${param_hostsshport}" > $ROOTFS/etc/systemd/system/sshd.socket.d/override.conf

run "Adding user ${param_username}" \
    "docker run -i --rm --privileged --name cl-installer ${DOCKER_PROXY_ENV} -v /dev:/dev -v /sys/:/sys/ -v $ROOTFS:/target/root clearlinux:latest sh -c \
    'mount --bind dev /target/root/dev && \
    mount -t proc proc /target/root/proc && \
    mount -t sysfs sysfs /target/root/sys && \
    chroot /target/root sh -c \
    \"usermod -p \\\$(mkpasswd -m sha-512 $(< /dev/urandom tr -dc a-z0-9 | head -c32)) root && \
    useradd -m -p \\\$(mkpasswd -m sha-512 ${param_password}) -s /bin/bash ${param_username} && \
    usermod -G wheel -a ${param_username}\"'" \
    "$TMP/provisioning.log"

if [ ! -z "${param_proxy}" ]; then
    run "Enabling Proxy Environment Variables" \
        "echo -e '\
        http_proxy=${param_proxy}\n\
        https_proxy=${param_proxy}\n\
        no_proxy=localhost,127.0.0.1\n\
        HTTP_PROXY=${param_proxy}\n\
        HTTPS_PROXY=${param_proxy}\n\
        NO_PROXY=localhost,127.0.0.1'\ >> $ROOTFS/etc/environment && \
        mkdir -p $ROOTFS/etc/systemd/system/docker.service.d && \
        echo -e '\
        [Service]\n\
        Environment=\"HTTPS_PROXY=${param_proxy}\" \"HTTP_PROXY=${param_proxy}\" \"NO_PROXY=localhost,127.0.0.1\"' > $ROOTFS/etc/systemd/system/docker.service.d/https-proxy.conf && \
        mkdir -p $ROOTFS/root/ && \
        echo 'source /etc/environment' >> $ROOTFS/root/.bashrc" \
        "$TMP/provisioning.log"
fi

if [ ! -z "${param_proxysocks}" ]; then
    run "Enabling Socks Proxy Environment Variables" \
        "echo -e '\
        ftp_proxy=${param_proxysocks}\n\
        FTP_PROXY=${param_proxysocks}' >> $ROOTFS/etc/environment" \
        "$TMP/provisioning.log"
fi

export clearlinux_kernel=$(readlink $ROOTFS/usr/lib/kernel/default*)

# --- Install SYSLINUX and Kernel ---
if [[ $param_parttype == 'efi' ]]; then
    run "Installing Clear Linux Kernel - $clearlinux_kernel" \
        "mkdir -p $BOOTFS/EFI/org.clearlinux && \
        cp $ROOTFS/usr/lib/kernel/$clearlinux_kernel $BOOTFS/EFI/org.clearlinux/" \
        "$TMP/provisioning.log"

    rootfs_partuuid=$(lsblk -no PARTUUID ${ROOT_PARTITION})
    run "Installing SYSLINUX on drive ${DRIVE}" \
        "docker run -i --rm --privileged -v /dev:/dev -v /sys/:/sys/ --name cl-installer ${DOCKER_PROXY_ENV} -v $ROOTFS:/target/root clearlinux:latest /bin/bash -c \"systemd-machine-id-setup && mount $BOOT_PARTITION /boot && bootctl install --path /boot\" && \
        dd bs=440 count=1 conv=notrunc if=/usr/share/syslinux/gptmbr.bin of=${DRIVE} && \
        wget --header \"Authorization: token ${param_token}\" -O - ${param_basebranch}/syslinux/efi.syslinux.cfg.tmp | \
        sed -e \"s#CLEARLINUXKERNEL#${clearlinux_kernel}#g\" | \
        sed -e \"s#ROOTFS#PARTUUID=${rootfs_partuuid}#g\" > $BOOTFS/loader/entries/${clearlinux_kernel}.conf && \
        echo \"default ${clearlinux_kernel}\" > $BOOTFS/loader/loader.conf" \
        "$TMP/provisioning.log"
else
    run "Installing Clear Linux Kernel - $clearlinux_kernel" \
        "cp $ROOTFS/usr/lib/kernel/$clearlinux_kernel $BOOTFS" \
        "$TMP/provisioning.log"

    run "Installing SYSLINUX on drive ${DRIVE}" \
        "extlinux --install $BOOTFS && dd bs=440 count=1 conv=notrunc if=/usr/share/syslinux/gptmbr.bin of=${DRIVE} && \
        wget --header \"Authorization: token ${param_token}\" -O - ${param_basebranch}/syslinux/syslinux.cfg.tmp | \
        sed -e \"s#CLEARLINUXKERNEL#${clearlinux_kernel}#g\" | \
        sed -e \"s#ROOTFS#${ROOT_PARTITION}#g\" >> $BOOTFS/syslinux.cfg" \
        "$TMP/provisioning.log"
fi

# --- Create system-docker database on $ROOTFS ---
run "Preparing system-docker database" \
    "mkdir -p $ROOTFS/var/lib/docker && \
    docker run -d --privileged --name system-docker ${DOCKER_PROXY_ENV} -v $ROOTFS/var/lib/docker:/var/lib/docker docker:stable-dind ${REGISTRY_MIRROR}" \
    "$TMP/provisioning.log"

# --- Install Docker Compose ---
run "Installing Docker Compose" "mkdir -p $ROOTFS/usr/local/bin/ && \
wget -O $ROOTFS/usr/local/bin/docker-compose \"https://github.com/docker/compose/releases/download/1.25.4/docker-compose-$(uname -s)-$(uname -m)\" && \
chmod a+x $ROOTFS/usr/local/bin/docker-compose" "$TMP/provisioning.log"
