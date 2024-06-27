#!/bin/bash
set -uo pipefail
ips=("$@")
for ip in ${ips[@]};do
    echo lib文件同步到${ip}
    scp lib/* $ip:/lib64
    echo pssh包同步到${ip}
    scp rpms/pssh-2.3.1-29.el8.noarch.rpm $ip:/tmp/
    echo 安装pssh到${ip}
    ssh $ip "yum install -y /tmp/pssh-2.3.1-29.el8.noarch.rpm"
    ssh $ip "ln -s /lib64/libssl.so.1.0.2k /lib64/libssl.so.10 2>/dev/null"
    ssh $ip "ln -s /lib64/libcrypto.so.1.0.2k /lib64/libcrypto.so.10 2>/dev/null"
    ssh $ip "ls -l /lib64/libssl.so.10"
    ssh $ip "ls -l /lib64/libcrypto.so.10"
    ssh $ip "yum install langpacks-en glibc-all-langpacks -y"
    ssh $ip "dnf module disable mysql redis -y"
done

rsync -a rpms/ /data/src/yum/

echo 注释uwsgi的requirement
sed -i "s/uWSGI/#uWSGI/g" /data/src/open_paas/*/requirements.txt

echo 注释不需要的paas console服务
sed -i '29,35s/^/# /' /data/src/open_paas/projects.yaml

echo 注释不需要的bkmonitorv3 grafana服务
sed -i '23,29s/^/# /' /data/src/bkmonitorv3/projects.yaml

echo 替换rhel专用install
rsync -a ./install /data/install

echo patch 完成