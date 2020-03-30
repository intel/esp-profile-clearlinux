#!/bin/bash

# Copyright (C) 2019 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause

set -a

#this is provided while using Utility OS
source /opt/bootstrap/functions

# User can execute specific tasks which needs to be performed while installation using this script


# --- Add Packages ---
clearlinux_bundles="\
        desktop \
        desktop-autostart"

# --- List out any docker images you want pre-installed separated by spaces. ---
pull_sysdockerimagelist=""

# --- List out any docker tar images you want pre-installed separated by spaces.  We be pulled by wget. ---
wget_sysdockerimagelist="" 



run "Installing Clear Linux bundles" "docker run -i --rm --privileged --name cl-installer ${DOCKER_PROXY_ENV} -v /dev:/dev -v /sys/:/sys/ -v $ROOTFS:/target/root clearlinux:latest sh -c \
  'mount --bind dev /target/root/dev && \
  mount -t proc proc /target/root/proc && \
  mount -t sysfs sysfs /target/root/sys && \
  chroot /target/root sh -c \
    \"swupd bundle-add ${clearlinux_bundles}\"'" "$TMP/provisioning.log"

# --- Install Docker Compose ---
run "Installing Docker Compose" "mkdir -p $ROOTFS/usr/local/bin/ && \
wget -O $ROOTFS/usr/local/bin/docker-compose \"https://github.com/docker/compose/releases/download/1.25.4/docker-compose-$(uname -s)-$(uname -m)\" && \
chmod a+x $ROOTFS/usr/local/bin/docker-compose" "$TMP/provisioning.log"

# --- Create system-docker database on $ROOTFS ---
run "Preparing system-docker database" "mkdir -p $ROOTFS/var/lib/docker && \
docker run -d --privileged --name system-docker ${DOCKER_PROXY_ENV} -v $ROOTFS/etc/docker:/etc/docker -v $ROOTFS/var/lib/docker:/var/lib/docker docker:stable-dind ${REGISTRY_MIRROR}" "$TMP/provisioning.log"

# --- Pull any and load any system images ---
for image in $pull_sysdockerimagelist; do
	run "Installing system-docker image $image" "docker exec -i system-docker docker pull $image" "$TMP/provisioning.log"
done
for image in $wget_sysdockerimagelist; do
	run "Installing system-docker image $image" "wget -O- $image 2>> $TMP/provisioning.log | docker exec -i system-docker docker load" "$TMP/provisioning.log"
done
