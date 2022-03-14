#!/bin/bash

echo "`ansible aws_ec2 --list-hosts| tail -n +2|sed -n '1p' | awk '{print $3}'` zookeeper1.example.com" > /tmp/myhosts_internal
echo "`ansible aws_ec2 --list-hosts| tail -n +3|sed -n '1p' | awk '{print $3}'` zookeeper2.example.com" >> /tmp/myhosts_internal
echo "`ansible aws_ec2 --list-hosts| tail -n +4|sed -n '1p' | awk '{print $3}'` zookeeper3.example.com" >> /tmp/myhosts_internal


echo "`ansible aws_ec2 --list-hosts| tail -n +5|sed -n '1p' | awk '{print $3}'` kafka1.example.com" >> /tmp/myhosts_internal
echo "`ansible aws_ec2 --list-hosts| tail -n +6|sed -n '1p' | awk '{print $3}'` kafka2.example.com" >> /tmp/myhosts_internal
echo "`ansible aws_ec2 --list-hosts| tail -n +7|sed -n '1p' | awk '{print $3}'` kafka3.example.com" >> /tmp/myhosts_internal

echo "`ansible aws_ec2 --list-hosts| tail -n +8|sed -n '1p' | awk '{print $3}'` openldap.example.com" >> /tmp/myhosts_internal
echo "`ansible aws_ec2 --list-hosts| tail -n +9|sed -n '1p' | awk '{print $3}'` schemaregistry.example.com" >> /tmp/myhosts_internal
