#!/bin/bash
# Script Name: bkmonitorv3_settings.sh
# Description: Script to configure bkmonitorv3 settings
# Author: Jerko
# Created: 2023-04-02 18:19:13
# Version: 1.0
# Last Updated: 2023-04-02 18:19:13
# Change Log:
# - <update_time> <version_number> <update_description>
# - <update_time> <version_number> <update_description>
# ...
# Variables:
# - <variable_1>: variable description
# - <variable_2>: variable description
# ...

# Source the common functions
source /data/install/utils.fc

# Solve the problem of the empty monitoring plugin page in the unified monitoring center
cp /data/src/bkmonitorv3/support-files/templates/monitor#bin#environ.sh /data/src/bkmonitorv3/support-files/templates/monitor#bin#environ.sh.bak
sed -i "s/export BK_IAM_V3_INNER_HOST/#&/" /data/src/bkmonitorv3/support-files/templates/monitor#bin#environ.sh
echo "export BK_IAM_PRIVATE_ADDR=$BK_IAM_IP" >> /data/src/bkmonitorv3/support-files/templates/monitor#bin#environ.sh
/data/install/bkcli sync bkmonitorv3
/data/install/bkcli render bkmonitorv3
/data/install/bkcli restart bkmonitorv3
