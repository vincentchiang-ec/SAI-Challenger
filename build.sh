#!/bin/bash

# exit when any command fails
set -e

# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo ERROR: "\"${last_command}\" command filed with exit code $?."' ERR

IMAGE_TYPE="standalone"
ASIC_TYPE=""
ASIC_PATH=""
TARGET=""

generateTargetServise() {
    local TARGET=$1
    echo """[Unit]
Description=SAI Chalanger container

Requires=docker.service
After=docker.service
After=rc-local.service
StartLimitIntervalSec=1200
StartLimitBurst=3

[Service]
User=root
ExecStartPre=/usr/bin/sc_${TARGET}.sh start
ExecStart=/usr/bin/sc_${TARGET}.sh wait
ExecStop=/usr/bin/sc_${TARGET}.sh stop
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
""" > sc_${TARGET}.service
}

generateTargetScript() {
    local ASIC=$1
    local TARGET=$2
    echo """#!/bin/bash
HWSKU=\`grep HWSKU /home/admin/sonic_env | cut -d \"=\" -f2\`
PLATFORM=\`grep PLATFORM /home/admin/sonic_env | cut -d \"=\" -f2\`
start(){
    docker inspect --type container \${DOCKERNAME} 2>/dev/null > /dev/null
    if [ \"\$?\" -eq \"0\" ]; then
        echo \"Starting existing \${DOCKERNAME} container\"
        docker start \${DOCKERNAME}
        exit $?
    fi
    echo \"Creating new \${DOCKERNAME} container\"
    docker create --privileged -t \\
        -v /host/machine.conf:/etc/machine.conf \\
        -v /host/warmboot:/var/warmboot \\
        -v /usr/share/sonic/device/\${PLATFORM}/\${HWSKU}:/usr/share/sonic/hwsku:ro \\
        --name \${DOCKERNAME} \\
        -p 6379:6379 \\
        sc-server-\${ASIC}-\${TARGET}

    echo \"Starting \${DOCKERNAME} container\"
    docker start \${DOCKERNAME}
}
wait() {
    docker wait \${DOCKERNAME}
}
stop() {
    echo \"Stoping \${DOCKERNAME} container\"
    docker stop \${DOCKERNAME}
}

DOCKERNAME=sai-challenger
ASIC=${ASIC}
TARGET=${TARGET}

case \"\$1\" in
    start|wait|stop)
        \$1
        ;;
    *)
        echo \"Usage: \$0 {start|wait|stop}\"
        exit 1
        ;;
esac
""" > sc_${TARGET}.sh
}

generateInstallScript() {
    local TARGET=$1
    echo """#!/bin/bash
if [ -z \"\$1\" ]; then
    echo \"Need to specify DUT IP\"
    exit 1
fi
SSH=\"sshpass -p YourPaSsWoRd ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR admin@\$1\"
\$SSH \"sudo sonic-cfggen -d -t /usr/share/sonic/templates/sonic-environment.j2 > sonic_env\"
sshpass -p YourPaSsWoRd scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR sc-server.tgz admin@\$1:/home/admin/
\$SSH tar zxf sc-server.tgz
\$SSH rm sc-server.tgz
\$SSH docker load -i sc-server-${TARGET}.tgz
\$SSH rm sc-server-${TARGET}.tgz
\$SSH sudo mv sc_${TARGET}.service /usr/lib/systemd/system/
\$SSH sudo mv sc_${TARGET}.sh /usr/bin/
\$SSH sudo mv /etc/sonic/generated_services.conf /etc/sonic/generated_services.conf.bak
\$SSH sudo mv generated_services.conf /etc/sonic/
\$SSH sudo mv /usr/bin/database.sh /usr/bin/database.sh.bak
\$SSH sudo reboot
""" > sc_install.sh
}

generateRemoveScript() {
    local ASIC=$1
    local TARGET=$2
    echo """#!/bin/bash
if [ -z \"\$1\" ]; then
    echo \"Need to specify DUT IP\"
    exit 1
fi
SSH=\"sshpass -p YourPaSsWoRd ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR admin@\$1\"
\$SSH sudo rm /usr/lib/systemd/system/sc_${TARGET}.service
\$SSH sudo rm /usr/bin/sc_${TARGET}.sh
\$SSH docker stop sai-challenger
\$SSH docker rm sai-challenger
\$SSH docker rmi sc-server-${ASIC}-${TARGET}
\$SSH sudo rm /etc/sonic/generated_services.conf
\$SSH sudo mv /etc/sonic/generated_services.conf.bak /etc/sonic/generated_services.conf
\$SSH sudo mv /usr/bin/database.sh.bak /usr/bin/database.sh
\$SSH sudo reboot
""" > sc_remove.sh
}

print-help() {
    echo
    echo "$(basename ""$0"") [OPTIONS]"
    echo "Options:"
    echo "  -h Print script usage"
    echo "  -i [standalone|client|server]"
    echo "     Image type to be created"
    echo "  -a ASIC"
    echo "     ASIC to be tested"
    echo "  -t TARGET"
    echo "     Target device with this NPU"
    echo
    exit 0
}

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        "-h"|"--help")
            print-help
            exit 0
        ;;
        "-i"|"--image")
            IMAGE_TYPE="$2"
            shift
        ;;
        "-a"|"--asic")
            ASIC_TYPE="$2"
            shift
        ;;
        "-t"|"--target")
            TARGET="$2"
            shift
        ;;
    esac
    shift
done

if [[ "${IMAGE_TYPE}" != "standalone" && \
      "${IMAGE_TYPE}" != "client" && \
      "${IMAGE_TYPE}" != "server" ]]; then
    echo "Unknown image type \"${IMAGE_TYPE}\""
    exit 1
fi

if [[ "${IMAGE_TYPE}" != "client" ]]; then

    if [ -z "${ASIC_TYPE}" ]; then
        ASIC_TYPE="trident2"
    fi

    ASIC_PATH=$(find -L -type d -name "${ASIC_TYPE}")
    if [ -z "${ASIC_PATH}" ]; then
        echo "Unknown ASIC type \"${ASIC_TYPE}\""
        exit 1
    fi

    if [ ! -z "${TARGET}" ]; then
        if [ ! -d "${ASIC_PATH}/${TARGET}" ]; then
            echo "Unknown target \"${TARGET}\""
            exit 1
        fi
    else
        # Get first folder as a default target
        TARGETS=( $(find -L "${ASIC_PATH}" -mindepth 1 -maxdepth 1 -type d) )
        TARGET="${TARGETS[0]}"
        if [ -z "${TARGET}" ]; then
            echo "Not able to find a default target..."
            exit 1
        fi
        TARGET=$(basename $TARGET)
    fi
fi

print-build-options() {
    echo
    echo "==========================================="
    echo "     SAI Challenger build options"
    echo "==========================================="
    echo
    echo " Docker image type  : ${IMAGE_TYPE}"
    echo " ASIC name          : ${ASIC_TYPE}"
    echo " ASIC target        : ${TARGET}"
    echo " Platform path      : ${ASIC_PATH}"
    echo
    echo "==========================================="
    echo
}

trap print-build-options EXIT

# Build base Docker image
if [ "${IMAGE_TYPE}" = "standalone" ]; then
    docker build -f Dockerfile -t sc-base .
elif [ "${IMAGE_TYPE}" = "server" ]; then
    docker build -f Dockerfile.server -t sc-server-base .
else
    docker build -f Dockerfile.client -t sc-client .
fi

# Build target Docker image
pushd "${ASIC_PATH}/${TARGET}"
if [ "${IMAGE_TYPE}" = "standalone" ]; then
    docker build -f Dockerfile -t sc-${ASIC_TYPE}-${TARGET} .
elif [ "${IMAGE_TYPE}" = "server" ]; then
    docker build -f Dockerfile.server -t sc-server-${ASIC_TYPE}-${TARGET} .
fi
popd

# Save target Docker image and generate service/script files
if [ "${IMAGE_TYPE}" = "server" ]; then
    docker save sc-server-${ASIC_TYPE}-${TARGET} | gzip > sc-server-${TARGET}.tgz
    generateTargetServise ${TARGET}
    generateTargetScript ${ASIC_TYPE} ${TARGET}
    chmod +x sc_${TARGET}.sh
    echo "sc_${TARGET}.service" > generated_services.conf
    tar zcf sc-server.tgz sc-server-${TARGET}.tgz sc_${TARGET}.service sc_${TARGET}.sh generated_services.conf
    rm sc-server-${TARGET}.tgz sc_${TARGET}.service sc_${TARGET}.sh generated_services.conf

    generateInstallScript ${TARGET}
    chmod +x sc_install.sh
    generateRemoveScript ${ASIC_TYPE} ${TARGET}
    chmod +x sc_remove.sh
    tar cf sc-server-pack.tar sc-server.tgz sc_install.sh sc_remove.sh
    rm sc-server.tgz sc_install.sh sc_remove.sh
fi

