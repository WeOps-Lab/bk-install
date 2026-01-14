#!/bin/bash
# Script Name: weops_install.sh
# Description: Script to configure weops 
# Author: Jerko
# Created: 2023-04-02 18:19:13
# Version: 1.1
# Last Updated: 2023-09-05 00:23:13
# Change Log:
# - <update_time> <version_number> <update_description>
# - <update_time> <version_number> <update_description>
# ...
# Variables:
# - components: variable description
# - settings: variable description
# ...


function usage {
  echo "Usage: $0 <parameter>"
  echo "Parameter options:"
  echo "  prepare <IP(s)>"
  echo "  components"
  echo "  settings"
  exit 1
}


# Define function for automatic configuration of WeOps settings
function weops_prepare() {
  local ip_list=("$@")
  
  bash cw_autoconfig.sh "${ip_list[@]}"
}


# Define function for installing and deploying WeOps dependent components
function weops_components() {
  echo "Executing code for WeOps dependent components"

  # Solve the problem of the empty monitoring plugin page
  bash bkmonitorv3_settings.sh
  bash weops_update_default_paasconf.sh
  
  # Run the script to install and deploy WeOps components
  bash weops_components.sh
  bash weops_kafka_components.sh
}

# Define function for automatic configuration of WeOps settings
function weops_settings() {
  echo "Executing code for WeOps configuration item"
  
  # bash weops_kafka_components.sh
  # Configure WeOps logs clean cycle
  bash weops_settings_logs.sh
  # Configure WeOps logs clean cycle
  bash weops_settings_dbbackup.sh all
  # Configure WeOps logs clean cycle
  bash weops_settings_custom.sh
}


# Check if parameter is passed
if [ $# -eq 0 ]; then
  usage
fi

# Execute the code for the specified parameter
case "$1" in
  prepare)
    if [ $# -lt 2 ]; then
      echo "IP address(es) missing"
      usage
    fi
    shift
    weops_prepare "$@"
    ;;
  components)
    weops_components
    ;;
  settings)
    weops_settings
    ;;
  *)
    echo "Invalid parameter: $1"
    usage
    ;;
esac

exit 0
