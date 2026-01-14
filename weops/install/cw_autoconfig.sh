#!/bin/bash
# Script Name: cw_autoconfig.sh
# Description: Automatically configure the installation environment of BlueKing
# Platform: Linux
# Usage : bash cw_autoconfig.sh control_ip appo_ip appt_ip
# Author: Jerko
# Created: 2023-04-05 11:00:00
# Version: 1.0
# Last Updated: 2023-12-12 10:51:00
# Change Log:
# - <update_time> <version_number> <update_description>
# - <update_time> <version_number> <update_description>
# ...
# Variables:
# - components: variable description
# - settings: variable description
# ...


## Source the all enviroment to C
source ./config.sh

# Get the current timestamp in the format of "yyyy-mm-dd hh:mm:ss".
get_timestamp() {
    printf "$(date +"%Y-%m-%d %H:%M:%S") \n"
}

# Output a normal message with a timestamp and white font.
# Parameter $@: the input messages to be output.
# Output format: [timestamp] message content
log_step(){
  printf "$(get_timestamp)\033[0m $@ \n"
  printf "$(get_timestamp)\033[0m $@ \n" >> ${log_file}
}

# Output a normal message with a timestamp and green font.
# Parameter $1: the message to be output.
# Output format: [timestamp] [INFO] message content
log_info() {
    printf "$(get_timestamp)\033[1;32;40m [INFO] $1 \033[0m \n"
    printf "$(get_timestamp)\033[1;32;40m [INFO] $1 \033[0m \n" >> ${log_file}
}

# Output a warning message with a timestamp and yellow font.
# Parameter $1: the message to be output.
# Output format: [timestamp] [WARN] message content
log_warn() {
    printf "$(get_timestamp)\033[1;33;40m [WARN] $1 \033[0m \n"
    printf "$(get_timestamp)\033[1;33;40m [WARN] $1 \033[0m \n" >> ${log_file}
}

# Output an error message with a timestamp and red font.
# Parameter $1: the message to be output.
# Output format: [timestamp] [ERROR] message content
log_error() {
    printf "$(get_timestamp)\033[1;31;40m [ERROR] $1 \033[0m \n"
    printf "$(get_timestamp)\033[1;31;40m [ERROR] $1 \033[0m \n" >> ${log_file}
}

# Output a normal message with a timestamp and blue font.
# Parameter $@: the input messages to be output.
# Output format: [timestamp] message content
log_menu(){
  printf "$(get_timestamp)\033[1;34m $@ \033[0m \n"
  printf "$(get_timestamp)\033[1;34m $@ \033[0m \n" >> ${log_file}
}

# Check whether a specific step has been completed by searching for it in the completed list.
# Arguments:
#   $1: The name of the step to be checked.
# Returns:
#   0 if the step has been completed, 1 otherwise. 
check_step() {
  local check_item="$1"
  if [ ! -f "${completed_list}" ]; then
    touch "${completed_list}"
  fi
  if grep -q "${check_item}" "${completed_list}"; then
    log_info "${check_item} ${completed_list} is existed"
    return 0
  else
    log_info "${check_item} ${completed_list} is not existed"
    return 1
  fi
}


# Add an item to the completed list to mark the completion of a step.
# Parameter $1: the step item to be added to the list.
# Output format: a line containing the step item appended to the completed list file.
step_done() {
  local log_item=$1
  echo "${log_item}" >> "${completed_list}"
}

# Check if all necessary files and install&src directories is not exist and their md5 is correct
# Return true if all checks pass, false otherwise.
check_init() {
  # check scripts

  # autoconfig_md5_temp=$(md5sum "${autoconfig_shell}" | awk '{print $1}')
  # log_info "The md5 of '${autoconfig_shell}' is ${autoconfig_md5_temp}"
  # if [ "${autoconfig_md5_temp}" != "${autoconfig_md5}" ]; then
    # log_warn "The md5 of '${autoconfig_shell}' is incorrect!(please check it.)"
    # return ${failed_code}
  # fi

  # check platform pkgs
  sorted_files=$(ls -r "${base_path}/weops-release-6.1.2"*.tar.gz 2> /dev/null)
  # 检查是否有符合条件的文件
  if [ -z "$sorted_files" ]; then
    log_warn "没有找到任何 'weops-release-6.1.2' 开头的文件，请下载后放置到 '${base_path}'。"
    return ${failed_code}
  fi
  # 提取最新的一个文件
  latest_file=$(echo "$sorted_files" | head -n 1)
  # 设置 bkce_basic_suite 变量
  bkce_basic_suite=$(basename "$latest_file")
  # 检查文件是否存在
  if [ ! -f "${base_path}/${bkce_basic_suite}" ]; then
    log_warn "文件 '${base_path}/${bkce_basic_suite}' 不存在！(请下载并放置到 '${base_path}')"
    return ${failed_code}
  fi

  if [ ! -f "${base_path}/${bkce_basic_suite}" ]; then
    log_warn "The '${base_path}/${bkce_basic_suite}' is not exist!(please download it and put it to '${base_path}'.)"
    return ${failed_code}
  fi

  if [ ! -f "${base_path}/${ssl_certificates}" ]; then
    log_warn "The '${base_path}/${ssl_certificates}' is not exist!(please download it and put it to '${base_path}'.)"
    return ${failed_code}
  fi

  if [ -d "${config_path}" ]; then
    log_warn "The '${config_path}' is exist!(please make sure that is not installed yet!)"
    return ${failed_code}
  fi

  if [ -d "${src_path}" ]; then
    log_warn "The '${src_path}' is exist!(please make sure that is not installed yet!)"
    return ${failed_code}
  fi

  log_info "Initialization check passed. Starting to prepare deployment environment."
  return ${success_code}
}


# Check if the given IP address is valid.
# Parameter $1: the IP address to be checked.
# Return: true if the IP address is valid, false otherwise.
check_ip() {
  local ip_addr=$1
  local ip_pattern='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
  if [[ "${ip_addr}" =~ ${ip_pattern} ]]; then
    log_step "It's checking [${ip_addr}] ..."
    ping=$(ping -c 3 ${ip_addr}|awk 'NR==7 {print $4}')
    if [ ${ping} -ne 3 ]; then
      log_error "Ping ${ip_addr}: failed."
      return ${failed_code}
    fi
  else
    log_error "The IP address '${ip_addr}' is invalid!"
    return ${failed_code}
  fi
  log_info "Ping ${ip_addr}: successed."
  return ${success_code}
}


## NO_1_CheckParms function: 
## Check if the input parameters are valid and reachable.
## Parameters:
##   Arguments: IP addresses of the nodes (must be exactly 3 or 5 or 7)
## Returns:
##   0 if successful, non-zero on failure.

NO_1_Check_init_parms(){
  local ip_list=("$@")

  check_init; checkrc=$?
  if [ ${checkrc} -ne 0 ]; then
    return ${failed_code}
  fi

  for ip_temp in ${ip_list[@]}
  do
    check_ip ${ip_temp}; checkrc=$?
    if [ ${checkrc} -ne 0 ]; then
      return ${failed_code}
    fi
  done
  return ${success_code}
}


## NO_2_Extract_platform_pkgs function: 
## Check and Tar the platform_pkgs.
## Parameters: None
## Returns:
##   0 if successful, non-zero on failure.

NO_2_Extract_platform_pkgs(){
  cd ${base_path};tar xf ${bkce_basic_suite}; tar_rc=$?
  if [ ${tar_rc} -ne 0 ]; then
    log_error "Tar the platform_pkgs ${bkce_basic_suite} failed."
    return ${failed_code}
  fi

  # 替换用户管理2.5.3
  # 检查BACKUP_DIR是否存在
#  if [ ! -d "${weops_backup}" ]; then
#    mkdir -p "${weops_backup}"
#    log_info "创建用户管理备份目录 ${weops_backup}."
#  fi

#  if [ -f "${bk_user_manage_old}" ] && [ -f "${bk_user_manage_new}" ] && [ -f "${usermgr_old}" ] && [ -f "${usermgr_new}" ]; then
#    mv "${bk_user_manage_old}" "${weops_backup}"
#    cp "${bk_user_manage_new}" "/data/src/official_saas/"
#    mv "${usermgr_old}" "${weops_backup}"
#    cp "${usermgr_new}" "/data/src/"
#  else
#    log_error "Required files for replacement are missing."
#    return ${failed_code}
#  fi
#  return ${success_code}
}


## NO_3_Create_install_config function:
## Create the installation configuration file for a multienode deployment
## Parameters:
##   Arguments: IP addresses of the nodes (must be exactly 3 or 5 or 7)
## Returns: 0 on success, non-zero on failure

NO_3_Create_install_config() {
  local ip_list=("$@")
  local ip_count=${#ip_list[@]}
  
  # Read the corresponding service template for the number of nodes
  case $ip_count in
    3) services=$(cat "$node_3_template");;
    5) services=$(cat "$node_5_template");;
    7) services=$(cat "$node_7_template");;
    *) log_error "Unsupported node count: $ip_count"; return ${failed_code};;
  esac

  # Replace the IP address placeholders in the service template
  for ((i=1; i<=ip_count; i++)); do
    services=${services//\{IP_ADDR_$i\}/${ip_list[i-1]}}
  done

  # Backup the old configuration file (if it exists)
  if [ -f "${config_path}/install.config" ]; then
    cp "${config_path}/install.config"{,.bak_$(date '+%Y%m%d%H%M%S')}
  fi

  # Write the new configuration file
  echo "$services" > "${config_path}/install.config"
  return ${success_code}
}


## Check if rsync is installed on all the specified IP addresses
check_rsync_installed(){
  local ip_list=("$@")
  
  for ip_temp in ${ip_list[@]}
  do
    log_info "Checking rsync on [${ip_temp}] ..."
    ssh ${ip_temp} "yum -y install rsync" >/dev/null 2>&1; ssh_rc=$?
    if [ ${ssh_rc} -ne 0 ]; then
      log_error "The rsync on [${ip_temp}] is not installed!"
      return ${failed_code}
    fi
  done
  log_info "The rsync has been installed on all IPs"
}


## Set up no-password login for SSH
set_no_pass() {
  # Execute the script that configures SSH without password login
  cd "${config_path}"
  bash "${config_path}/configure_ssh_without_pass"
  set_rc=$?

  # Check the return code of the script
  if [ ${set_rc} -ne 0 ]; then
    log_error "Failed to configure SSH without password login"
    return ${failed_code}
  fi

  # Log success message
  log_info "SSH no-password login has been set up"
  return ${success_code}
}


## NO_4_Check_no_pass function:
## Check if SSH password-less login is set up, and set it up if not
## Parameters:
##   Arguments: IP addresses of the nodes (must be exactly 3 or 5 or 7)
## Returns: 0 on success, non-zero on failure

NO_4_Check_no_pass() {
  local ip_list=("$@")

  for ip_temp in "${ip_list[@]}"; do
    log_info "Testing SSH connection to [${ip_temp}] ..."
    ssh "${ip_temp}" "date" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      log_error "Failed to connect to [${ip_temp}]!"
      log_info "Attempting to set up password-less login ..."
      Setnopass >/dev/null
      if [ $? -ne 0 ]; then
        log_error "Failed to set up password-less login for [${ip_temp}]!"
        return ${failed_code}
      fi
    fi
  done

  log_info "SSH password-less login is set up on all IPs."
  return ${success_code}
}


## NO_5_Check_yum function:
## Check if yum is configured properly and test connectivity
## Parameters:
##   Arguments: IP addresses of the nodes (must be exactly 3 or 5 or 7)
##   Package name: Name of package to check (optional, default is "zip")
## Returns: 0 on success, non-zero on failure

NO_5_Check_yum(){
  local ip_list=("$@")
  local pkg_name="${2:-zip}"
  
  for ip_temp in "${ip_list[@]}"
  do
    log_info "Checking yum on [${ip_temp}] ..."
    ssh ${ip_temp} "yum info ${pkg_name} > /dev/null 2>&1"
    if [ $? -ne 0 ]; then
      log_error "Yum is not properly configured on [${ip_temp}]!"
      return ${failed_code}
    fi
  done
  
  log_info "Yum is configured properly on all IPs."
  return ${success_code}
}


## NO_6_Check_epel function:
## Check if epel repository is configured properly and test connectivity
## Parameters:
##   Arguments: IP addresses of the nodes (must be exactly 3 or 5 or 7)
##   Package name: Name of package to check (optional, default is "pssh")
## Returns: 0 on success, non-zero on failure

NO_6_Check_epel(){
  local ip_list=("$@")
  local pkg_name="${2:-pssh}"
  
  for ip_temp in "${ip_list[@]}"
  do
    log_info "Testing epel on [${ip_temp}] ..."
    ssh "${ip_temp}" "yum info ${pkg_name} --enablerepo=epel > /dev/null 2>&1"
    if [ $? -ne 0 ]; then
      log_error "Epel is not properly configured on [${ip_temp}]!"
      return ${failed_code}
    fi
  done
  
  log_info "Epel is configured properly on all IPs."
  return ${success_code}
}


## NO.7 Check the rsync
## 安装 rsync pssh deltarpm jq 
NO_7_Install_pkgs() {
  local ip_list=("$@")
  local pkgs_list=("rsync" "pssh" "deltarpm" "jq")
  local ins=0
  local not_ins=0

  for pkg_temp in "${pkgs_list[@]}"; do
    for ip_temp in "${ip_list[@]}"; do
      log_info "Checking ${pkg_temp} of [${ip_temp}]..."
      if ssh "${ip_temp}" "yum list installed | grep -q ${pkg_temp}"; then
        log_info "${pkg_temp} has already installed."
        ((ins++))
      else
        log_info "Installing ${pkg_temp} of [${ip_temp}]..."
        if ssh "${ip_temp}" "yum install -y ${pkg_temp} > /dev/null 2>&1"; then
          log_info "${pkg_temp} has been installed."
          ((ins++))
        else
          not_ins=$((not_ins + 1))
          log_error "${pkg_temp} has not been installed."
        fi
      fi
    done
  done
  if [ ${not_ins} -ne 0 ]; then
     log_error "There are ${not_ins} pkgs has not been installed."
     return ${failed_code}
  fi
  return ${success_code}
}


## NO_8_Extract_src_pages function:
## Extract all gzipped files in the specified directory
## Parameters:
##   None
## Returns: 0 on success, non-zero on failure

NO_8_Extract_src_pages() {
  if [ ! -d "${src_path}" ]; then
    log_warn "The directory ${src_path} does not exist!"
    return "${failed_code}"
  fi

  # Check if there are any files to extract
  shopt -s nullglob
  local gz_files=( "${src_path}"/*gz )
  shopt -u nullglob
  if [ ${#gz_files[@]} -eq 0 ]; then
    log_warn "No *gz files found in ${src_path}"
    return "${failed_code}"
  fi

  log_info "Extracting *.gz files in ${src_path} ..."
  for f in "${src_path}"/*gz; do
    log_info "Extracting $f ..."
    tar xf "$f" -C "${src_path}" || {
      log_error "Failed to extract $f"
      return "${failed_code}"
    }
  done

  log_info "Successfully extracted all *.gz files in ${src_path}"
  return "${success_code}"
}



## NO_9_Extract_licence_file function:
## Extracts the license file to the specified directory
## Parameters:
##   None
## Returns: 0 on success, non-zero on failure

NO_9_Extract_licence_file() {
  local target_dir="${src_path}/cert"

  if [ -d "$target_dir" ]; then
    log_warn "The directory $target_dir already exists!"
    return ${failed_code}
  fi

  if [ ! -f "${base_path}/${ssl_certificates}" ]; then
    log_warn "The file ${base_path}/${ssl_certificates} does not exist!"
    return ${failed_code}
  fi

  # Create the target directory and extract the license file
  install -d -m 755 "$target_dir"
  tar xf "${base_path}/${ssl_certificates}" -C "$target_dir/"
  chmod 644 "$target_dir"/*
  if [ $? -ne 0 ]; then
    log_error "Failed to extract the license page."
    return ${failed_code}
  fi

  log_info "Extracted the license page to $target_dir."
  return ${success_code}
}


## NO_10_Copy_rpm function:
## Copies the /data/src/yum directory to /opt directory
## If /data/src/yum directory does not exist, logs a warning message and returns failure.
## Parameters:
##   Arguments: None
## Returns: 0 on success, non-zero on failure

NO_10_Copy_rpm() {
  local dest_path="/opt"
  
  if [ ! -d "${src_path}/yum" ]; then
    log_warn "The '${src_path}/yum' directory does not exist! You should tar the entire installation directory."
    return ${failed_code}
  fi

  cp -a "${src_path}/yum" "${dest_path}" >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    log_error "Failed to copy the rpm to ${dest_path}."
    return ${failed_code}
  fi
  
  log_info "Rpm copy to ${dest_path} successful."
  return ${success_code}
}

## NO_11_Check_os_version function:
## Check whether the OS version is equal to or greater than the specified version.
##   Arguments: IP addresses of the nodes (must be exactly 3 or 5 or 7)
## Returns: 0 on success, non-zero on failure
NO_11_Check_os_version() {
  local ip_list=("$@")
  
  for ip_temp in "${ip_list[@]}"; do
    log_info "Checking OS version on [${ip_temp}] ..."
    
    # Check if /etc/redhat-release file exists
    if ! ssh "${ip_temp}" "[ -f /etc/redhat-release ]" >/dev/null 2>&1; then
      log_error "Please provide a CentOS Linux operating system on [${ip_temp}]!"
      return ${failed_code}
    fi
    
    # Extract major and minor version number
    osv=$(ssh "${ip_temp}" "cat /etc/redhat-release | awk '{print \$4}' | awk -F '.' '{printf \"%d.%d\", \$1, \$2}'")

    # Compare with the target version
    if [ "${osv}" = "${osv_goat}" ]; then
      log_info "The OS version on [${ip_temp}] is ${osv}, which meets the requirement of ${osv_goat}."
    else
      log_error "The OS version on [${ip_temp}] is ${osv}, which does not meet the requirement of ${osv_goat}."
      return ${failed_code}
    fi
  done
  
  log_info "All nodes meet the OS version requirement."
  return ${success_code}
}


## NO_12_Check_cpu function:
## Check the cpu count is equal to or greater than the specified count.
##   Arguments: IP addresses of the nodes (must be exactly 3 or 5 or 7)
## Returns: 0 on success, non-zero on failure

NO_12_Check_cpu() {
  local ip_list=("$@")
  
  for ip in "${ip_list[@]}"; do
    log_info "Checking CPU count on [${ip}] ..."
    
    # get cpu count through ssh.
    cpu_num=$(ssh "${ip}" "cat /proc/cpuinfo | grep 'processor' | wc -l" 2>/dev/null)
    if [ -z "${cpu_num}" ]; then
      log_error "Failed to get CPU count on [${ip}]!"
      return ${failed_code}
    fi
    
    # compare the cpu num
    if [ "${cpu_num}" -lt "${cpu_goat}" ]; then
      log_error "Please provide a system with ${cpu_goat} or more CPU cores on [${ip}]!"
      return ${failed_code}
    fi
    
    log_info "CPU count on [${ip}] is ${cpu_num}."
  done
  
  log_info "CPU count check passed for all IPs."
  return ${success_code}
}


## NO_13_Check_mem function:
## Check the mem size is equal to or greater than the specified size.
##   Arguments: IP addresses of the nodes (must be exactly 3 or 5 or 7)
## Returns: 0 on success, non-zero on failure
NO_13_Check_mem(){
  # Accepts IP addresses as arguments
  local ip_list=("$@")
  
  # Loop through each IP address
  for ip_temp in "${ip_list[@]}"; do
    log_info "Checking memory size on [${ip_temp}] ..."
    
    # Get the total memory size in GB
    mem_size=$(ssh "${ip_temp}" "free |grep -i mem |gawk -F : '{print \$2}' |gawk '{print \$1}'")
    mem_size=$((${mem_size}/1024/1024))
    
    # Compare the memory size with the threshold value
    if [ ${mem_size} -lt ${mem_goat} ]; then
      log_error "Please provide a system with RAM ${mem_goat} or higher on [${ip_temp}]."
      return ${failed_code}
    fi
    
    log_info "Memory size on [${ip_temp}] meets the requirement."
  done
  
  log_info "Memory size meets the requirement on all IPs."
  return ${success_code}
}


## NO_14_Check_disk_size function:
## Check the disk size is equal to or greater than the specified size(> 100 GB per os).
##   Arguments: IP addresses of the nodes (must be exactly 3 or 5 or 7)
## Returns: 0 on success, non-zero on failure
NO_14_Check_disk_size(){
  local ip_list=("$@")

  for ip in "${ip_list[@]}"; do
    if ! ssh "${ip}" "[ -d \"/data\" ]"; then
      log_error "The path '/data' is not exist!(please create it first.) [IP: ${ip}]"
      return ${failed_code}
    fi

    disk_size=$(ssh "${ip}" "df -h | grep -w '/data$' | awk '{print \$4}' | awk -F 'G' '{print \$1}'")
    if [ -z "${disk_size}" ]; then
      log_warn "The path '/data' is not a separate mount. (you can use lvm mode to create it.) [IP: ${ip}]"
      disk_size=$(ssh "${ip}" "df -h | grep -w '/' | awk '{print \$4}' | awk -F 'G' '{print \$1}'")
    fi

    if [ "${disk_size}" -lt "${disk_goat}" ]; then
      log_error "The disk size is not sufficient. (expect:${disk_goat}G, actual:${disk_size}G) [IP: ${ip}]"
      return ${failed_code}
    fi
    log_info "Disk size on [${ip_temp}] meets the requirement."
  done
  log_info "Disk size meets the requirement on all IPs."
  return ${success_code}
}


## NO_15_Check_selinux function:
## Check and set SELinux to closed
##   Arguments: IP addresses of the nodes (must be exactly 3 or 5 or 7)
## Returns: 0 on success, non-zero on failure
NO_15_Check_selinux() {
  local ip_list=("$@")

  for ip in "${ip_list[@]}"; do
    if ! ssh "${ip}" "sestatus >/dev/null 2>&1"; then
      log_error "Failed to connect to ${ip} or sestatus command is not available."
      return ${failed_code}
    fi

    ## Check SELinux status
    nowstatus=$(ssh "${ip}" "sestatus|grep 'Current mode'|awk '{print \$3}'")
    if [[ "${nowstatus}" == "enforcing" ]]; then
      log_warn "SELinux is enabled on ${ip}."
      ## Set SELinux to disabled
      log_info "Disabling SELinux on ${ip}..."
      ssh "${ip}" "sudo setenforce 0 >/dev/null 2>&1 && sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config"
      nowstatus=$(ssh "${ip}" "sestatus|grep 'Current mode'|awk '{print \$3}'")
      if [[ "${nowstatus}" == "enforcing" ]]; then
        log_error "Failed to disable SELinux on ${ip}."
        return ${failed_code}
      fi
      log_info "SELinux is disabled on ${ip}. Please reboot the server to take effect."
    else
    log_info "SELinux is disabled on ${ip}."
    fi
  
  done
  log_info "SELinux is disabled on all IPs."
  return ${success_code}
}


## NO_16_Check_firewalld function:
## Check and set the firewalld on each server in the IP array
##   Arguments: IP addresses of the nodes
## Returns: 0 on success, non-zero on failure
NO_16_Check_firewalld() {
  local ip_list=("$@")

  for ip in "${ip_list[@]}"; do
    local fw_status=$(ssh "${ip}" 'systemctl is-active --quiet firewalld && echo active || echo inactive')
    local fw_enable=$(ssh "${ip}" 'systemctl is-enabled --quiet firewalld && echo enabled || echo disabled')
    if [[ "${fw_status}" == "active" || "${fw_enable}" == "enabled" ]]; then
      log_warn "The firewalld is active or enabled on ${ip}."
      ## Stop and disable the firewalld
      ssh "${ip}" 'systemctl stop firewalld && systemctl disable firewalld && service iptables stop && chkconfig iptables off >/dev/null 2>&1; \
                    setfirc=$?; if [ "${setfirc}" -ne 0 ]; then echo "Failed to disable the firewalld."; exit 1; fi'
      ## Check if the firewalld is disabled
      local fw_enable=$(ssh "${ip}" 'systemctl is-enabled --quiet firewalld && echo enabled || echo disabled')
      if [[ "${fw_enable}" == "enabled" ]]; then
        log_error "Failed to disable the firewalld on ${ip}."
        return ${failed_code}
      else
        log_info "The firewalld is disabled on ${ip}."
      fi
    else
      log_info "The firewalld is not active or enabled on ${ip}."
    fi
  done
  log_info "The firewalld is not active or enabled on all IPs."
  return ${success_code}
}


## NO_17_Set_max_openfiles function:
## config max openfiles
## Arguments: IP addresses of the nodes (must be exactly 3 or 5 or 7)
## Returns: 0 on success, non-zero on failure
NO_17_Set_max_openfiles(){
  local ip_list=("$@")

  for ip in "${ip_list[@]}"; do
    ## Check if the max open files is less than 102400
    max_open=$(ssh "${ip}" "ulimit -n")
    if [ "${max_open}" -lt 102400 ]; then
      log_warn "The max open files is less than 102400 on ${ip}."
      ssh "${ip}" "if [ -f /etc/security/limits.conf ]; then cp /etc/security/limits.conf{,.bak_$(date '+%Y%m%d%H%M%S')}; fi; \
                    echo -e '\nroot soft nofile 102400\nroot hard nofile 102400' >> /etc/security/limits.conf; \
                    rc=\$?; if [ \${rc} -ne 0 ]; then echo 'Failed to set the max open files.'; exit 1; fi"
      if [ $? -ne 0 ]; then
        log_error "Failed to set the max open files on ${ip}."
        return ${failed_code}
      else
        max_open_check=$(ssh "${ip}" "ulimit -n")
        if [ "${max_open_check}" -eq 102400 ]; then
          log_info "The max open files has been set to 102400 on ${ip}."
        else
          log_error "Failed to set the max open files to 102400 on ${ip}."
          return ${failed_code}
        fi
      fi
    else
      log_info "The max open files is already set to 102400 or higher on ${ip}."
    fi
  done
  log_info "The max open files has been set to 102400 or higher on all IPs."
  return ${success_code}
}



## Check the time difference between the three servers
check_time(){
  if [ ${1} -ge -"${diff_time}" -a ${1} -le "${diff_time}" ]; then
    return ${success_code}
  else
    return ${failed_code}
  fi
}

## NO_18_Check_host_time function:
## Check the time difference between the servers, Confirm that the server times are synchronized
## Parameters:
##   Arguments: IP addresses of the nodes (must be exactly 3 or 5 or 7)
## Returns: 0 on success, non-zero on failure
NO_18_Check_host_time(){
  local ip_list=("$@")

  if [ ${#ip_list[@]} -lt 2 ]; then
    log_warn "Only one ip is provided. Skipping time check."
    return ${success_code}
  fi

  local time_array=()
  for ip_temp in "${ip_list[@]}"; do
    time_array+=("$(ssh ${ip_temp} "date +%s")")
  done

  for i in $(seq 0 $((${#time_array[@]}-2))); do
    for j in $(seq $((${i}+1)) $((${#time_array[@]}-1))); do
      to_diff=$((${time_array[$i]} - ${time_array[$j]}))
      check_time "${to_diff}"; rc=$?
      if [ ${rc} -ne 0 ]; then
        log_error "It's failed between ${ip_list[$i]} and ${ip_list[$j]}. (> ${diff_time}s)"
        log_info "You can set the date by [ssh ${ip_list[$i]} 'date -s \"yyyy-mm-dd hh24:mi:ss\";clock -w']"
        return ${failed_code}
      fi
    done
  done
  return ${success_code}
}


## NO_19_Check_proxy function:
## Check the http_proxy and https_proxy
## Parameters:
##   Arguments: IP addresses of the nodes (must be exactly 3 or 5 or 7)
## Returns: 0 on success, non-zero on failure
NO_19_Check_proxy(){
  local ip_list=("$@")
  local rc=0

  for ip in "${ip_list[@]}"; do
    if ssh "${ip}" "test -z \"\$http_proxy\" && test -z \"\$https_proxy\""; then
      log_info "No global HTTP proxy is set on ${ip}."
    else
      log_warn "A global HTTP proxy is set on ${ip}."
      rc=1
    fi
  done

  if [ ${rc} -eq 0 ]; then
    log_info "No global HTTP proxy is set on all IPs."
    return ${success_code}
  else
    log_error "A global HTTP proxy is set on one or more IPs."
    return ${failed_code}
  fi
}


## NO_20_Check_hostname function:
## Check if hostnames are matching, and set them if not
## Parameters:
##   Arguments: IP addresses of the nodes
## Returns: 0 on success, non-zero on failure
NO_20_Check_hostname() {
  local ip_list=("$@")
  local num_ips=${#ip_list[@]}

  # Assign the appropriate set_hostname array based on the number of IPs
  case $num_ips in
    3) set_hostname=("${set_3_hostname[@]}");;
    5) set_hostname=("${set_5_hostname[@]}");;
    7) set_hostname=("${set_7_hostname[@]}");;
    *) log_error "Invalid number of IP addresses"; return ${failed_code};;
  esac

  # Get current hostnames of all IPs and set new hostnames if not matching
  for ((i=0; i<${num_ips}; i++)); do
    current_hostname=$(ssh ${ip_list[$i]} "hostname")
    if [ -z "${current_hostname}" ]; then
      log_error "Failed to get hostname for ${ip_list[$i]}"
      return ${failed_code}
    fi
    
    # If current hostname does not match expected hostname, set the new hostname
    if [ "${current_hostname}" != "${set_hostname[$i]}" ]; then
      log_warn "The current hostname ${current_hostname} for ${ip_list[$i]} does not match the expected hostname. Changing hostname to ${set_hostname[$i]}"
      set_hostname_cmd="hostnamectl set-hostname ${set_hostname[$i]}"
      ssh ${ip_list[$i]} "${set_hostname_cmd}"
      if [ $? -ne 0 ]; then
        log_error "Failed to set new hostname for ${ip_list[$i]}"
        return ${failed_code}
      else
        log_info "Changed hostname for ${ip_list[$i]} to [${set_hostname[$i]}] Successfully"
      fi
    fi
  done

  log_info "Check hostname is OK"
  return ${success_code}
}


## NO_21_Check_resolv function:
## Check if DNS configuration file /etc/resolv.conf is locked
## Parameters:
##   Arguments: IP addresses of the nodes (must be exactly 3 or 5 or 7)
## Returns: 0 on success, non-zero on failure
NO_21_Check_resolv(){
  local ip_list=("$@")

  for ip in "${ip_list[@]}"; do
    if ssh "${ip}" "lsattr /etc/resolv.conf|awk '{print \$1}' | grep -q '^[-]'"; then
      log_info "DNS configuration file is not locked on ${ip}."
    else
      log_error "DNS configuration file is locked on ${ip}."
      return ${failed_code}
    fi
  done
  log_info "DNS configuration file is not locked on all IPs."
  return ${success_code}
}


## NO_22_Set_network_manager function:
## Check if NetworkManager is active and enabled
## Parameters:
##   Arguments: IP addresses of the nodes (must be exactly 3 or 5 or 7)
## Returns: 0 on success, non-zero on failure
NO_22_Set_network_manager(){
  local ip_list=("$@")
  
  for ip in "${ip_list[@]}"; do
    # Check if NetworkManager is active and enabled
    if ssh "${ip}" 'systemctl is-active NetworkManager > /dev/null && systemctl is-enabled NetworkManager > /dev/null'; then
      log_warn "NetworkManager is active and enabled on ${ip}. Disabling it..."
      # Disable NetworkManager
      if ssh "${ip}" 'systemctl stop NetworkManager > /dev/null && systemctl disable NetworkManager > /dev/null'; then
        log_info "NetworkManager has been disabled on ${ip}."
      else
        log_error "Failed to disable NetworkManager on ${ip}."
        return ${failed_code}
      fi
    else
      log_info "NetworkManager is not active or enabled on ${ip}."
    fi
  done
  return ${success_code}
}


NO_23_Change_timeout() {
  local paas_agent_config="/data/src/paas_agent/support-files/templates/#etc#paas_agent_config.yaml.tpl"
  local settings_production="/data/src/open_paas/support-files/templates/paas#conf#settings_production.py.tpl"
  local starter="/data/src/paas_agent/paas_agent/etc/build/docker/saas/starter"

  # Define an array of config files to be modified
  local config_files=("$paas_agent_config" "$settings_production" "$starter")

  # Check if config files exist, create backups, and modify
  for config_file in "${config_files[@]}"; do
    if [ ! -f "${config_file}" ]; then
      log_error "The '${config_file}' does not exist!"
      return ${failed_code}
    fi
    cp "${config_file}" "${config_file}.bak_${timestamp}"

    case "${config_file}" in
      "${paas_agent_config}")
        sed -i "s/EXECUTE_TIME_LIMIT: 300/EXECUTE_TIME_LIMIT: 3000/g" "${config_file}"
        ;;
      "${settings_production}")
        grep "EVENT_STATE_EXPIRE_SECONDS = 3600$" "${config_file}" >/dev/null 2>&1 || sed -i "52i EVENT_STATE_EXPIRE_SECONDS = 3600" "${config_file}"
        ;;
      "${starter}")
        sed -i "37s/^/#/" "${config_file}"
        grep "\"\$BK_CRYPT_VERSION\" == '3'" "${config_file}" >/dev/null 2>&1 || sed -i "38i \    if [ \"\$BK_CRYPT_VERSION\" == '3' ]; then" "${config_file}"
        ;;
    esac
  done

  return ${success_code}
}


## NO_24_Setting_profile function:
## Set history cmd time format to display
## Parameters:
##   Arguments: IP addresses of the nodes (must be exactly 3 or 5 or 7)
## Returns: 0 on success, non-zero on failure
NO_24_Setting_profile(){
  local ip_list=("$@")
  local profile_config="/etc/profile"
  local histtimeformat_line='export HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S $ "'

  # Modify the HISTTIMEFORMAT variable in the profile file
  for ip in "${ip_list[@]}"; do
    # Check if profile file exists
    if ! ssh "${ip}" -f "${profile_config}" &> /dev/null; then
      log_warn "The '${profile_config}' file does not exist on ${ip}!"
      return ${failed_code}
    fi

    # Add the HISTTIMEFORMAT line to profile file if not already set
    if ssh "${ip}" "grep -q '^export HISTTIMEFORMAT=' ${profile_config}"; then
      log_info "HISTTIMEFORMAT variable of ${profile_config} is already set on ${ip}."
      ssh "${ip}" "sed -i 's|^export HISTTIMEFORMAT=.*|${histtimeformat_line}|' ${profile_config}"
    else
      log_warn "HISTTIMEFORMAT variable of ${profile_config} is not set on ${ip}."
      ssh "${ip}" "echo '${histtimeformat_line}' >> ${profile_config}"
    fi

    if [ $? -ne 0 ]; then
      log_error "Failed to modify the HISTTIMEFORMAT variable on ${ip}."
      return ${failed_code}
    fi
  done

  log_info "The HISTTIMEFORMAT variable has been modified on all IPs."
  return ${success_code}
}


NO_25_BKSettings() {
  # Set domain
  if [ -f "${last_answer2}" ]; then
    website_tmp_last=$(grep website "${last_answer2}" | awk '{print $2}')
  fi
  default2="${website_tmp_last:-weops.net}"
  read -p "Please set the Blueking PAAS platform login domain [default: ${default2}]: " website_tmp
  website="${website_tmp:-$default2}"
  echo "website ${website}" > "${last_answer2}"
  log_info "${website}"

  # Set admin password
  for i in {1..3}; do
    if [ -f "${last_answer3}" ]; then
      bk_admin_passwd=$(grep bk_admin_passwd "${last_answer3}" | awk '{print $2}')
    fi
    default3="${bk_admin_passwd:-WeOps2024}"
    read -p "Please set the Blueking PAAS platform login user admin password [default: ${default3}]: " password01
    if [ -n "${password01}" ]; then
      read -p "Please re-enter the Blueking PAAS platform login user admin password: " password02
      if [ "${password01}" != "${password02}" ]; then
        log_warn "The two entered passwords are not the same! Please re-enter."
      else
        bk_admin_passwd="${password02}"
        echo "bk_admin_passwd ${bk_admin_passwd}" > "${last_answer3}"
        log_info "${bk_admin_passwd}"
        break
      fi
    else
      bk_admin_passwd="${default3}"
      echo "bk_admin_passwd ${bk_admin_passwd}" > "${last_answer3}"
      log_info "${bk_admin_passwd}"
      break
    fi

    if [ ${i} -eq 3 ]; then
      log_error "After 3 attempts, you still enter an error letter."
      return ${failed_code}
    fi
  done

  local usermgr_env_file="${config_path}/bin/03-userdef/usermgr.env"

  # Create usermgr.env file with BK_PAAS_ADMIN_PASSWORD
  echo "BK_PAAS_ADMIN_PASSWORD=${bk_admin_passwd}" > "${usermgr_env_file}"
  if [ $? -ne 0 ]; then
    log_error "Set BK_PAAS_ADMIN_PASSWORD failed."
    return ${failed_code}
  fi

  # Run configure script with specified domain and install path
  cd "${config_path}"
  ./configure -d "${website}" -p "${install_path}" >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    log_error "Configure domain failed."
    return ${failed_code}
  fi

  return ${success_code}
}


## NO_26_Setting_timezone function:
## Check time zone and set it to the specified time zone if not set
## Parameters:
##   Arguments:
##     1. Time zone to set (optional, default is "Asia/Shanghai")
##     2. IP addresses of the nodes (must be exactly 3 or 5 or 7)
## Returns: 0 on success, non-zero on failure
NO_26_Setting_timezone() {
  local ip_list=("$@")

  for ip in "${ip_list[@]}"; do
    # Check current time zone
    current_time_zone=$(ssh "${ip}" "timedatectl status | sed -n 's/.*Time zone:[[:space:]]*\\([^ ]*\\).*/\\1/p'")
    if [ "${current_time_zone}" != "${timezone}" ]; then
      log_warn "The time zone on ${ip} is not set to '${timezone}'."
      log_info "Setting the time zone on ${ip} to '${timezone}' now ..."
      ssh "${ip}" "timedatectl set-timezone ${timezone}"
      if [ $? -ne 0 ]; then
        log_error "Failed to set the time zone on ${ip}."
        return "${failed_code}"
      fi
      # Check if the time zone is set correctly
      current_time_zone=$(ssh "${ip}" "timedatectl status | sed -n 's/.*Time zone:[[:space:]]*\\([^ ]*\\).*/\\1/p'")
      if [ "${current_time_zone}" != "${timezone}" ]; then
        log_error "Failed to set the time zone on ${ip} to '${timezone}'."
        return "${failed_code}"
      fi
      log_info "The time zone on ${ip} has been set to '${timezone}'."
    else
      log_info "The time zone on ${ip} is already set to '${timezone}'."
    fi
  done

  log_info "The time zone has been set to '${timezone}' on all nodes."
  return "${success_code}"
}


NO_27_Change_functions() {
  # Get all non-local IPs
  other_ip=$(ip a | grep "inet " | grep -v "inet 127" | awk '{print $2}' | awk -F '/' '{print $1}')

  for ip_tmp in ${other_ip[@]}; do
    other_ip1=$(echo ${ip_tmp} | awk -F '.' '{print $1}')
    other_ip2=$(echo ${ip_tmp} | awk -F '.' '{print $1"."$2}')

    # Check if the IP does not belong to private IP ranges
    if [ "${other_ip1}" != "10" ] && [ "${other_ip1}" != "172" ] && [ "${other_ip2}" != "192.168" ]; then
      cp ${config_path}/functions{,.bak_${timestamp}}

      # Add the condition to the 'functions' file
      other="                  if (\$3 ~ /^${other_ip1}\\\./) {\n                      print \$3\n                  }"
      sed -i "22i${other}" ${config_path}/functions >/dev/null 2>&1
      res=$?

      if [ "${res}" -ne 0 ]; then
        log_error "Change functions failed."
        return ${failed_code}
      fi
    fi
  done

  return ${success_code}
}


NO_28_Check_time_service() {
  local ip_list=("$@")

  for ip_temp in "${ip_list[@]}"; do
    ssh ${ip_temp} 'bash -s' <<- EOF
      ## Check chronyd and ntpd process status
      systemctl status chronyd | grep "Active: " | awk '{print \$3}' | grep -q running
      chronyd_status=\$?

      systemctl status ntpd | grep "Active: " | awk '{print \$3}' | grep -q running
      ntpd_status=\$?

      ## If both chronyd and ntpd are not running, return failed_code
      if [ \$chronyd_status -ne 0 ] && [ \$ntpd_status -ne 0 ]; then
        exit ${failed_code}
      fi

      ## Otherwise, return success_code
      exit ${success_code}
EOF
    checkrc=$?

    if [ ${checkrc} -ne 0 ]; then
      for i in {1..3}; do
        log_info "Server[${ip_temp}] does not have time synchronization service enabled! Do you want to continue with the configuration? [y/n]"
        read -p ">>> " IfContinue

        if [ -z "${IfContinue}" ] || [ "${IfContinue}" = "y" ]; then
          log_info "${IfContinue:-y}"
          break
        elif [ "${IfContinue}" = "n" ]; then
          log_info "Since the target server does not have time synchronization service enabled, please prepare and try executing this script again later!"
          log_error "It's failed in ${ip_temp}."
          return ${checkrc}
        else
          log_error "You should enter y or n."
        fi

        if [ ${i} -eq 3 ]; then
          log_error "After 3 attempts, you still enter an error letter."
          return ${failed_code}
        fi
      done
    else
    log_info "It's successful in ${ip}."
    fi
  done
  return ${success_code}
}


NO_29_Config_hosts() {
  local ip_list=("$@")
  local config_file="${config_path}/install.config"
  local nginx_ip=""
  local nodeman_ip=""

  while IFS= read -r line; do
    if echo "${line}" | grep -q "nginx"; then
      nginx_ip="$(echo "${line}" | awk '{print $1}')"
    fi
    if echo "${line}" | grep -q "nodeman"; then
      nodeman_ip="$(echo "${line}" | awk '{print $1}')"
    fi
  done < "${config_file}"

  if [ -z "${nginx_ip}" ] || [ -z "${nodeman_ip}" ]; then
    log_error "Could not find both nginx and nodeman IPs in the config file."
    return ${failed_code}
  fi

  for ip_temp in "${ip_list[@]}"; do
    local file_path="${base_path}/hosts_${ip_temp}"
    ssh "${ip_temp}" "grep '${website}' /etc/hosts" > "${file_path}" 2>/dev/null

    if ! grep -q "${website}" "${file_path}"; then
      cat <<- EOF >> "${file_path}"
${nginx_ip} paas.${website} cmdb.${website} job.${website} jobapi.${website} weops.${website}
${nodeman_ip} nodeman.${website}
EOF
      ssh "${ip_temp}" "cp /etc/hosts{,.bak_$(date '+%Y%m%d%H%M%S')}" >/dev/null 2>&1
      scp "${file_path}" "${ip_temp}:/etc/hosts" >/dev/null 2>&1

      if [ $? -ne 0 ]; then
        log_error "Config /etc/hosts failed on ${ip_temp}."
        return ${failed_code}
      fi
    fi
  done

  return ${success_code}
}


NO_30_Config_bash() {
  local ip_list=("$@")
  local file_name="/root/.bash_profile"

  for ip_temp in "${ip_list[@]}"; do
    ssh "${ip_temp}" "grep ^'cd /data/install && source /data/install/utils.fc' ~/.bash_profile" >/dev/null 2>&1
    local ssh_rc=$?

    if [ ${ssh_rc} -ne 0 ]; then
      local file_path="${base_path}/.bash_profile_${ip_temp}"
      ssh "${ip_temp}" "cat ${file_name}" > "${file_path}"

      cat << EOF >> "${file_path}"
cd /data/install && source /data/install/utils.fc
EOF
      ssh "${ip_temp}" "cp ${file_name}{,.bak_$(date '+%Y%m%d%H%M%S')}" >/dev/null 2>&1
      scp "${file_path}" "${ip_temp}:${file_name}" >/dev/null 2>&1

      if [ $? -ne 0 ]; then
        log_error "Config ${file_name} failed on ${ip_temp}."
        return ${failed_code}
      fi
    fi
  done

  return ${success_code}
}


## Clean IPTables
NO_31_Clean_iptables() {
  # Accepts IP addresses as arguments
  local ip_list=("$@")
  
  # Loop through each IP address
  for ip in "${ip_list[@]}"; do
    log_info "Cleaning IPTables on [${ip}] ..."
    
    # Backup existing firewall rules
    if ! ssh "${ip}" "iptables-save > /etc/sysconfig/iptables.bak_$(date '+%Y%m%d%H%M%S')" >/dev/null 2>&1; then
      log_error "Failed to backup IPTables rules on [${ip}]!"
      return ${failed_code}
    fi
    
    # Flush all rules in the default table "filter"
    if ! ssh "${ip}" "iptables -F" >/dev/null 2>&1; then
      log_error "Failed to flush filter table rules on [${ip}]!"
      return ${failed_code}
    fi
    
    # Delete user-defined chains in the default table "filter"
    if ! ssh "${ip}" "iptables -X" >/dev/null 2>&1; then
      log_error "Failed to delete user-defined chains on [${ip}]!"
      return ${failed_code}
    fi
    
    # Reset the packet and byte counters for all chains
    if ! ssh "${ip}" "iptables -Z" >/dev/null 2>&1; then
      log_error "Failed to reset packet and byte counters on [${ip}]!"
      return ${failed_code}
    fi
    
    log_info "Successfully cleaned IPTables on [${ip}]."
  done
  
  log_info "IPTables cleaned successfully on all IPs."
  return ${success_code}
}


## Disable swap to prevent OOM
NO_32_Disabled_swap() {
  # Accepts IP addresses as arguments
  local ip_list=("$@")
  
  # Loop through each IP address
  for ip_temp in "${ip_list[@]}"; do
    log_info "Disabling swap on [${ip_temp}] ..."
    
    # Temporarily disable swap partition, changes lost on reboot
    if ! ssh "${ip_temp}" "swapoff -a" >/dev/null 2>&1; then
      log_error "Failed to disable swap on [${ip_temp}]!"
      return ${failed_code}
    fi
    
    # Permanently disable swap partition
    # Backup /etc/fstab
    if ! ssh "${ip_temp}" "cp /etc/fstab{,.bak_$(date '+%Y%m%d%H%M%S')}" >/dev/null 2>&1; then
      log_error "Failed to backup /etc/fstab on [${ip_temp}]!"
      return ${failed_code}
    fi
    
    # Disable swap in /etc/fstab
    if ! ssh "${ip_temp}" "sed -ri 's/.*swap.*/#&/' /etc/fstab" >/dev/null 2>&1; then
      log_error "Failed to modify /etc/fstab on [${ip_temp}]!"
      return ${failed_code}
    fi
    
    log_info "Successfully disabled swap on [${ip_temp}]."
  done
  
  log_info "Swap disabled successfully on all IPs."
  return ${success_code}
}


## Configure network settings to prevent /etc/resolv.conf from being overwritten
NO_33_Config_network() {
  local ip_list=("$@")
  
  for ip_temp in "${ip_list[@]}"; do
    log_info "Configuring network on [${ip_temp}] ..."
    
    # Check if DNS1=127.0.0.1 is already present in /etc/sysconfig/network
    ssh "${ip_temp}" "grep -q '^DNS1=127.0.0.1' /etc/sysconfig/network"
    if [ $? -ne 0 ]; then
      # If not present, add DNS1=127.0.0.1 to /etc/sysconfig/network
      ssh "${ip_temp}" "grep '^nameserver' /etc/resolv.conf | awk '{print \$2}' | sort -u | sed -e 's/^/DNS/' -e 's/$/=/' -e '1s/^/DNS1=127.0.0.1\n/'" | sudo tee -a /etc/sysconfig/network >/dev/null
      if [ $? -ne 0 ]; then
        log_error "Failed to add DNS1=127.0.0.1 to /etc/sysconfig/network on [${ip_temp}]!"
        return ${failed_code}
      fi
    fi

    # Check which network interface files have DNS settings configured
    file_names=$(ssh "${ip_temp}" "grep -l '^DNS' /etc/sysconfig/network-scripts/ifcfg-*")
    for each_file in $file_names; do
      # Add PEERDNS=no to the network interface file
      ssh "${ip_temp}" "grep -q '^PEERDNS=no' ${each_file}" || sudo sed -i '/^BOOTPROTO=/a PEERDNS=no' "${each_file}"
      if [ $? -ne 0 ]; then
        log_error "Failed to add PEERDNS=no to ${each_file} on [${ip_temp}]!"
        return ${failed_code}
      fi
      # Restart the network service
      ssh "${ip_temp}" "/etc/init.d/network restart" >/dev/null
      if [ $? -ne 0 ]; then
        log_error "Failed to restart network service on [${ip_temp}]!"
        return ${failed_code}
      fi
    done
    
    log_info "Network configured successfully on [${ip_temp}]."
  done
  
  log_info "Network configured successfully on all IPs."
  return ${success_code}
}


NO_999_Show_tips(){
  ## Tips of install
  log_menu "======================================================"
  log_menu "Please follow the steps below to install the Blueking:"
  log_menu "Step  0: cd ${config_path}"
  log_menu "Step  1: ./bk_install common                    # 初始化环境"
  log_menu "Step  2: ./health_check/check_bk_controller.sh  # 校验环境和部署的配置"
  log_menu "Step  3: ./bk_install paas                      # 安装 PaaS 平台及其依赖服务"
  log_menu "Step  4: ./bk_install app_mgr                   # 部署 SaaS 运行环境，正式环境及测试环境"
  log_menu "Step  5: ./bk_install cmdb                      # 安装配置平台及其依赖服务"
  log_menu "Step  6: ./bk_install job                       # 安装作业平台后台模块及其依赖组件"
  log_menu "Step  7: ./bk_install bknodeman                 # 安装节点管理后台模块、节点管理 SaaS 及其依赖组件"
  log_menu "Step  8: ./bk_install bkmonitorv3               # 监控平台"
  log_menu "Step 11: ./bk_install saas-o bk_iam             # 权限中心"
  log_menu "Step 12: ./bk_install saas-o bk_user_manage     # 用户管理"
  log_menu "Step 13: ./bk_install saas-o bk_sops            # 标准运维"
  log_menu "Step 16: ./bkcli initdata topo                  # 初始化蓝鲸业务拓扑"
  log_menu "======================================================"
}


execute_step() {
  local message="$1"
  local function_name="$2"
  shift 2
  local args=("$@")

  log_step "${message}"
  # local if_done=$(check_step "${function_name}")
  if check_step "${function_name}"; then
    log_info "[Skipped] step: ${function_name}."
  else
    # log_warn "${if_done} test ...."
    "${function_name}" "${args[@]}"; rc=$?
    if [ ${rc} -ne 0 ]; then
      log_error "${function_name} is Failed."
      return ${rc}
    fi
    log_info "${function_name} is successfully"
    step_done "${function_name}"
  fi
}


Welcome_functions(){
 # Welcome message
 echo -e "\033[1;32m"
 cat << "EOF"
 __          __   ____              _  _  __   __
\ \        / /  / __ \            | || | \ \ / /
 \ \  /\  / /__| |  | |_ __  ___  | || |_ \ V / 
  \ \/  \/ / _ \ |  | | '_ \/ __| |__   _| > <  
   \  /\  /  __/ |__| | |_) \__ \    | |_ / . \ 
    \/  \/ \___|\____/| .__/|___/    |_(_)_/ \_\
                      | |                       
                      |_|                        
EOF
  echo -e "\033[0m"
  echo -e "\033[1;33mWelcome to WeOps Auto Config Script!\033[0m"
  echo ""

  echo -e "\033[1;32m╔══════════════════════════════════════════════════════════════════════════════════╗\033[0m"
  echo -e "\033[1;32m║                              【WeOps平台部署】                                   ║\033[0m"
  echo -e "\033[1;32m║ 欢迎使用本自动化配置脚本，它将帮助您标准快速地完成平台部署的前置准备工作！       ║\033[0m"
  echo -e "\033[1;32m║ 为了您可以顺利地完成前置准备，您需要确保部署用到的各台服务器均已满足：           ║\033[0m"
  echo -e "\033[1;32m║   1、符合《嘉为WeOps资源需求清单》中的 [资源要求]                                ║\033[0m"
  echo -e "\033[1;32m║   2、在每台机上操作：配置好 [不同的ip地址] 且不同服务器之间 [网络可互达]         ║\033[0m"
  echo -e "\033[1;32m║   3、在每台机上操作：配置好 [rsync包]。                                          ║\033[0m"
  echo -e "\033[1;32m║                              祝您生活愉快！！！                                  ║\033[0m"
  echo -e "\033[1;32m╚══════════════════════════════════════════════════════════════════════════════════╝\033[0m"
  echo ""
}

Main_functions(){
  local ip_list=("$@")
  local num_ips=${#ip_list[@]}
  local failed_steps=()
  if [ -z $1 ] ;then
    log_warn "Usage: bash $0 control_ip appo_ip appt_ip"
    log_warn "For example: bash $0 '192.168.65.166' '192.168.65.167' '192.168.65.168'"
    return ${failed_code}
  fi

  if [ $((${num_ips} % 2)) -ne 1 ] ;then
    log_error "The number of input parameters is incorrect! You need to enter 3, 5, 7 parameters."
    return ${failed_code}
  fi
  
  Welcome_functions

  for i in {1..3}
  do
    if [ -f "${last_answer1}" ]; then
      default1=$(grep IfRestart "${last_answer1}" | awk '{print $2}')
    else
      default1="y"
    fi

    log_info "请确认以上准备工作是否已完成?[可选：y/n，默认：${default1}]"
    read -p ">>> " IfRestart
    IfRestart=${IfRestart:-${default1}}

    if [ "${IfRestart}" = "y" ] || [ "${IfRestart}" = "n" ]; then
      echo "IfRestart ${IfRestart}" > "${last_answer1}"
      log_info "${IfRestart}"
      if [ "${IfRestart}" = "n" ]; then
        log_info "由于前期准备工作未完成，请准备就绪后再尝试执行此脚本！"
        return ${failed_code}
      fi
      break
    else
      log_warn "You should enter y or n."
      if [ ${i} -eq 3 ];then
        log_warn "After 3 attempts, you still enter an incorrect letter."
        return ${failed_code}
      fi
    fi
  done

  execute_step "[NO.1 / 33] It's checking and Extracting the installation package ..." "NO_1_Check_init_parms" || exit 1
  execute_step "[NO.2 / 33] It's checking and Extracting the installation package ..." "NO_2_Extract_platform_pkgs" || failed_steps+=("NO_2_Extract_platform_pkgs")
  execute_step "[NO.3 / 33] It's creating the install config ..." "NO_3_Create_install_config" "${ip_list[@]}" || failed_steps+=("NO_3_Create_install_config")
  execute_step "[NO.4 / 33] It's checking the no secret ..." "NO_4_Check_no_pass" "${ip_list[@]}" || failed_steps+=("NO_4_Check_no_pass")
  # execute_step "[NO.5 / 33] It's checking the yum repo ..." "NO_5_Check_yum" "${ip_list[@]}" || failed_steps+=("NO_5_Check_yum")
  # execute_step "[NO.6 / 33] It's checking the epel repo ..." "NO_6_Check_epel" "${ip_list[@]}" || failed_steps+=("NO_6_Check_epel")
  execute_step "[NO.7 / 33] It's checking the packages ..." "NO_7_Install_pkgs" "${ip_list[@]}" || failed_steps+=("NO_7_Install_pkgs")
  execute_step "[NO.8 / 33] It's tarring the src packages ..." "NO_8_Extract_src_pages" || failed_steps+=("NO_8_Extract_src_pages")
  execute_step "[NO.9 / 33] It's checking the license packages ..." "NO_9_Extract_licence_file" || failed_steps+=("NO_9_Extract_licence_file")
  execute_step "[NO.10 / 33] It's copying the rpms ..." "NO_10_Copy_rpm" || failed_steps+=("NO_10_Copy_rpm")
  execute_step "[NO.11 / 33] It's checking the OS version ..." "NO_11_Check_os_version" "${ip_list[@]}" || failed_steps+=("NO_11_Check_os_version")
  execute_step "[NO.12 / 33] It's checking the CPU num ..." "NO_12_Check_cpu" "${ip_list[@]}" || failed_steps+=("NO_12_Check_cpu")
  execute_step "[NO.13 / 33] It's checking the memory size ..." "NO_13_Check_mem" "${ip_list[@]}" || failed_steps+=("NO_13_Check_mem")
  execute_step "[NO.14 / 33] It's checking the disk size ..." "NO_14_Check_disk_size" "${ip_list[@]}" || failed_steps+=("NO_14_Check_disk_size")
  execute_step "[NO.15 / 33] It's checking the SELinux setting ..." "NO_15_Check_selinux" "${ip_list[@]}" || failed_steps+=("NO_15_Check_selinux")
  execute_step "[NO.16 / 33] It's checking the firewalld ..." "NO_16_Check_firewalld" "${ip_list[@]}" || failed_steps+=("NO_16_Check_firewalld")
  execute_step "[NO.17 / 33] It's checking the max open files ..." "NO_17_Set_max_openfiles" "${ip_list[@]}" || failed_steps+=("NO_17_Set_max_openfiles")
  execute_step "[NO.18 / 33] It's checking the time difference ..." "NO_18_Check_host_time" "${ip_list[@]}" || failed_steps+=("NO_18_Check_host_time")
  execute_step "[NO.19 / 33] It's checking the http_proxy and https_proxy ..." "NO_19_Check_proxy" "${ip_list[@]}" || failed_steps+=("NO_19_Check_proxy")
  execute_step "[NO.20 / 33] It's checking the hostname ..." "NO_20_Check_hostname" "${ip_list[@]}" || failed_steps+=("NO_20_Check_hostname")
  execute_step "[NO.21 / 33] It's checking the resolv.conf ..." "NO_21_Check_resolv" "${ip_list[@]}" || failed_steps+=("NO_21_Check_resolv")
  execute_step "[NO.22 / 33] It's checking the NetworkManager ..." "NO_22_Set_network_manager" "${ip_list[@]}" || failed_steps+=("NO_22_Set_network_manager")
  execute_step "[NO.23 / 33] It's changing the time out setting ..." "NO_23_Change_timeout" || failed_steps+=("NO_23_Change_timeout")
  execute_step "[NO.24 / 33] It's changing the os setting ..." "NO_24_Setting_profile" "${ip_list[@]}" || failed_steps+=("NO_24_Setting_profile")
  execute_step "[NO.25 / 33] It's setting the blueking setting ..." "NO_25_BKSettings" || failed_steps+=("NO_25_BKSettings")
  execute_step "[NO.26 / 33] It's checking the time zone ..." "NO_26_Setting_timezone" "${ip_list[@]}" || failed_steps+=("NO_26_Setting_timezone")
  execute_step "[NO.27 / 33] It's changing the functions ..." "NO_27_Change_functions" || failed_steps+=("NO_27_Change_functions")
  execute_step "[NO.28 / 33] It's changing the time service ..." "NO_28_Check_time_service" "${ip_list[@]}" || failed_steps+=("NO_28_Check_time_service")
  execute_step "[NO.29 / 33] It's configing the hosts ..." "NO_29_Config_hosts" "${ip_list[@]}" || failed_steps+=("NO_29_Config_hosts")
  execute_step "[NO.30 / 33] It's configing the bash ..." "NO_30_Config_bash" "${ip_list[@]}" || failed_steps+=("NO_30_Config_bash")
  execute_step "[NO.31 / 33] It's configing the iptables ..." "NO_31_Clean_iptables" "${ip_list[@]}" || failed_steps+=("NO_31_Clean_iptables")
  execute_step "[NO.32 / 33] It's disabling the swap ..." "NO_32_Disabled_swap" "${ip_list[@]}" || failed_steps+=("NO_32_Disabled_swap")
  # execute_step "[NO.33 / 33] It's configing the network ..." "NO_33_Config_network" "${ip_list[@]}" || failed_steps+=("NO_33_Config_network")

  if [ ${#failed_steps[@]} -gt 0 ]; then
    log_error "The following steps failed: ${failed_steps[*]}"
    return ${failed_code}
  else
    log_info "All steps are completed successfully."
    return ${success_code}
  fi
}

Main_functions "$@"; rc=$?
if [ ${rc} -ne 0 ]; then
  log_error "Auto Config Blueking Env is failed."
  exit ${rc}
fi
log_menu ""
log_menu "Auto Config Blueking Env is successful..."
log_menu ""
NO_999_Show_tips
exit ${rc}
