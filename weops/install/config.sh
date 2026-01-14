#!/bin/bash
# Script Name: config.sh
# Description: Initializing and setting environment variables for cw_autoconfig_bkenv.sh
# Platform: Linux
# Usage : bash cw_autoconfig_bkenv.sh control_ip appo_ip appt_ip
# Author: Jerko
# Created: 2023-04-05 11:00:00
# Version: 1.0
# Last Updated: 2023-04-05 18:00:00
# Change Log:
# - <update_time> <version_number> <update_description>
# - <update_time> <version_number> <update_description>
# ...
# Variables:
# - components: variable description
# - settings: variable description
# ...

# Set the all enviroment to C
export LC_ALL=C
export timestamp=$(date +"%Y%m%d%H%M%S")
export failed_code=5
export success_code=0

# Determine the type of installation package
export install_type="weops"

# Set the MD5 checksums for various files
export autoconfig_md5="628eed12c5ac48845510c4c83efecee5"
# Set the names of various files and packages
export ssl_certificates="ssl_certificates.tar.gz"

# Set the configures requires
export osv_goat="7.9"    ## 最低系统版本，79代表7.9
export cpu_goat=4     ## 最低cpu核数，4代表4核
export mem_goat=15    ## 最低内存大小，15代表15 GB，因系统显示问题，需要比实际需求小1G，即要求16G，那么阈值写15G即可。
export disk_goat=100  ## 最低磁盘大小，100代表100 GB

# Set the paths for various files and directories
export base_path="/data"
export config_path="${base_path}/install"
export src_path="${base_path}/src"
export install_path="${base_path}/bkce"

export pwd_path=$(pwd)
export autoconfig_shell="${pwd_path}/cw_autoconfig.sh"
export checkeos_shell="${pwd_path}/cw_checkeos.sh"


export node_3_template="${pwd_path}/templates/3_node_deployment.template"
export node_5_template="${pwd_path}/templates/5_node_deployment.template"
export node_7_template="${pwd_path}/templates/7_node_deployment.template"

# Define set_3_hostname, set_5_hostname, and set_7_hostname
export set_3_hostname=("control" "appo" "appt")
export set_5_hostname=("control" "appo" "appt" "node4" "node5")
export set_7_hostname=("control" "appo" "node3" "node4" "appt" "node6" "node7")

export log_file="${pwd_path}/cw_autoconfig_${timestamp}.log"
export last_answer1="${pwd_path}/.last_answer1.log"
export last_answer2="${pwd_path}/.last_answer2.log"
export last_answer3="${pwd_path}/.last_answer3.log"
export completed_list="${pwd_path}/.completed.list"


# export src_bkmonitorv3_ce_bkofficial="bkmonitorv3_ce-3.6.3656-bkofficial.tgz"
# export saas_bk_monitorv3_V3_bkofficial="bk_monitorv3_V3.6.3656-bkofficial.tar.gz"

# Set other variables as needed
export diff_time=60
export pageslist=("rsync" "pssh" "deltarpm" "jq")

export timezone="Asia/Shanghai"

# export usermgr pkgs
#export bk_user_manage_old="/data/src/official_saas/bk_user_manage_V2.4.2-bkofficial.tar.gz"
#export bk_user_manage_new="/data/weops/upgrade/bk_user_manage_V2.5.3-bkofficial.tar.gz"
#export usermgr_old="/data/src/usermgr_ce-2.4.2-bkofficial.tar.gz"
#export usermgr_new="/data/weops/upgrade/usermgr_ce-2.5.3-bkofficial.tar.gz"
export weops_backup="/data/weops_backup/"
