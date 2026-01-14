#!/bin/bash
today=$(date +%Y%m%d)
slow_query_log_file=$(docker exec mysql-client mysql --login-path=default-root -e "show variables like 'slow_query_log_file';" |awk 'NR==2 {print $2}')
slow_log_dir=$(dirname $slow_query_log_file)
if [ $slow_log_dir = "." ];then
    docker exec mysql-client mysql --login-path=default-root -e "SET GLOBAL slow_query_log_file='slow-${today}.log'"
else
    docker exec mysql-client mysql --login-path=default-root -e "SET GLOBAL slow_query_log_file='${slow_log_dir}/slow-${today}.log'"
fi
