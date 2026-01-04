#!/usr/bin/env bash
# 用途：生成中控机需要的，以及后续要分发到其他机器上的资源以及配置文件。

# 安全模式
set -euo pipefail
DEBIAN_FRONTEND=noninteractive

SELF_DIR="$(dirname "$(readlink -f "$0")")"
EXTAR_INSTALL=0

while (( $# > 0 )); do
    case "$1" in
        -e | --extar-rpm )
            EXTAR_INSTALL=1
            ;;
    esac
    shift
done

#COMMON_LIST=(pssh parallel zip unzip rsync gawk curl lsof tar sed iproute uuid psmisc wget at \
#        rsync jq expect uuid bash-completion lsof openssl-devel readline-devel libcurl-devel libxml2-devel glibc-devel \
#        zlib-devel iproute sysvinit-tools procps-ng bind-utils)
COMMON_LIST=(pssh parallel zip unzip rsync gawk curl lsof tar sed iproute2 uuid psmisc wget at \
	  rsync jq expect uuid bash-completion lsof openssl libssl-dev  libreadline-dev libcurl4-openssl-dev libcurl4 libxml2-dev \
          zlib1g zlib1g-dev dnsutils dpkg-dev)
EXTAR_LIST=(mysql-client)

if [[ "${EXTAR_INSTALL}" -ne 1 ]]; then
    for rpm in "${COMMON_LIST[@]}"; do
        if ! dpkg -l "$rpm" > /dev/null 2>&1; then
            apt-get install -y "${rpm}"
        fi
    done
else
    for rpm in "${EXTAR_LIST[@]}"; do
        if ! dpkg -l "$rpm" > /dev/null 2>&1; then
            apt-get install -y "${rpm}"
        fi
    done
fi

# 配置parallel免声明
if ! [[ -r $HOME/.parallel/will-cite ]]; then
    mkdir "$HOME"/.parallel
    touch "$HOME"/.parallel/will-cite
fi
