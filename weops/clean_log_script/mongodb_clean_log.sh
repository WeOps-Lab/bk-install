#!/bin/bash
datafile=/data/bkce/public/mongodb
datalog=/data/bkce/logs/mongodb
days=15
/bin/kill -SIGUSR1 `cat $datafile/mongod.lock`
find $datalog/ -mtime +$days -delete 
