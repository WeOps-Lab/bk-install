#!/bin/bash
# Script Name: weops_update_default_paasconf.sh
# Description: Script to configure weops custom settings after deployment saas
# Author: Jerko
# Created: 2023-12-12 10:20:13
# Version: 1.0
# Last Updated: 2023-12-12 10:20:13
# Change Log:
# - <update_time> <version_number> <update_description>
# - <update_time> <version_number> <update_description>
# ...
# Variables:
# - <variable_1>: variable description
# - <variable_2>: variable description
# ...

source /data/install/utils.fc

CONFIG_FILE="/etc/consul-template/templates/paas.conf"

# 检查远程服务器 IP 和配置文件路径是否已设置
if [ -z "$CONFIG_FILE" ]; then
    echo "默认Ningx配置模板文件路径未设置。"
    exit 1
fi

# 使用 SSH 执行 sed 命令修改配置文件
/data/install/pcmd.sh -m nginx "sed -i 's/client_max_body_size[[:space:]]\+512m;/client_max_body_size    2048m;/' $CONFIG_FILE"

# 检查 sed 命令执行是否成功
if [ $? -ne 0 ]; then
    echo "修改配置文件失败"
    exit 1
else
    echo "配置文件已成功修改"
fi

# 重新加载 Nginx 配置
/data/install/bkcli restart nginx

echo "Nginx 配置已重新加载"
