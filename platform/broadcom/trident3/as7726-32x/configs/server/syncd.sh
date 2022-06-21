#!/bin/bash  
CMD_SYNCD=/usr/local/bin/syncd
HWSKU_DIR=/usr/share/sonic/hwsku
CMD_ARGS="-z redis_sync --diag"
if [ -f "/etc/sai.d/sai.profile" ]; then
    CMD_ARGS+=" -p /etc/sai.d/sai.profile"
else
    CMD_ARGS+=" -p $HWSKU_DIR/sai.profile"
fi

[ -e /dev/linux-bcm-knet ] || mknod /dev/linux-bcm-knet c 122 0
[ -e /dev/linux-user-bde ] || mknod /dev/linux-user-bde c 126 0
[ -e /dev/linux-kernel-bde ] || mknod /dev/linux-kernel-bde c 127 0

exec $CMD_SYNCD $CMD_ARGS
