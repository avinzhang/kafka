#!/bin/bash

EC2_HOSTS=(`ansible aws_ec2 --list-hosts | tail -n +2|awk '{print $3}'`)
NUM=0
while [ $NUM -lt ${#EC2_HOSTS[@]} ]
  do
    if [ $NUM -eq 0 ]
      then
        echo "${EC2_HOSTS[$NUM]} openldap.example.com" > /tmp/myhosts_internal
    elif [ $NUM -eq 1 ]
    then
      echo "${EC2_HOSTS[$NUM]} zookeeper1.example.com" >> /tmp/myhosts_internal
    elif [ $NUM -eq 2 ]
    then
      echo "${EC2_HOSTS[$NUM]} zookeeper2.example.com" >> /tmp/myhosts_internal
    elif [ $NUM -eq 3 ]
    then
      echo "${EC2_HOSTS[$NUM]} zookeeper3.example.com" >> /tmp/myhosts_internal
    elif [ $NUM -eq 4 ]
    then
      echo "${EC2_HOSTS[$NUM]} kafka1.example.com" >> /tmp/myhosts_internal
    elif [ $NUM -eq 5 ]
    then
      echo "${EC2_HOSTS[$NUM]} kafka2.example.com" >> /tmp/myhosts_internal
    elif [ $NUM -eq 6 ]
    then
      echo "${EC2_HOSTS[$NUM]} kafka3.example.com" >> /tmp/myhosts_internal
    elif [ $NUM -eq 7 ]
    then
      echo "${EC2_HOSTS[$NUM]} schemaregistry.example.com" >> /tmp/myhosts_internal
    elif [ $NUM -eq 8 ]
    then
      echo "${EC2_HOSTS[$NUM]} connect.example.com" >> /tmp/myhosts_internal
    elif [ $NUM -eq 9 ]
    then
      echo "${EC2_HOSTS[$NUM]} ksqldb.example.com" >> /tmp/myhosts_internal
    elif [ $NUM -eq 10 ]
    then
      echo "${EC2_HOSTS[$NUM]} controlcenter.example.com" >> /tmp/myhosts_internal
    fi
    NUM=$((NUM+1))
done

