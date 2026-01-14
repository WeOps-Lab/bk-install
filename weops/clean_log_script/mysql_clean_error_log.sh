#!/bin/bash
today=`date +%Y%m%d`
datadir=`docker exec mysql-client mysql --login-path=default-root -e "show variables like 'datadir';" |awk 'NR==2 {print $2}'`
log_error=`docker exec mysql-client mysql --login-path=default-root -e "show variables like 'log_error';" |awk 'NR==2 {print $2}'`
cd $datadir 
mv ${log_error} ${log_error}.${today}
docker exec mysql-client mysql --login-path=default-root -e "flush error logs;"