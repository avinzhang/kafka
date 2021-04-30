#!/bin/bash

TAG=6.1.1

docker-compose -f docker-compose.yml -f ./security/zookeeper_mtls/docker-compose-zk-mtls.yml up -d --build --no-deps zookeeper kafka
