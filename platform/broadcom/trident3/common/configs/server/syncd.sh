#!/bin/bash  
CMD_SYNCD=/usr/local/bin/syncd
CMD_ARGS="-z redis_sync --diag"
CMD_ARGS+=" -p /usr/share/sonic/hwsku/sai.profile"

[ -e /dev/linux-bcm-knet ] || mknod /dev/linux-bcm-knet c 122 0
[ -e /dev/linux-user-bde ] || mknod /dev/linux-user-bde c 126 0
[ -e /dev/linux-kernel-bde ] || mknod /dev/linux-kernel-bde c 127 0

exec $CMD_SYNCD $CMD_ARGS
