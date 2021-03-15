#!/bin/bash

echo "Start 3 zookeepers"
docker-compose -f docker-compose.yml -f ./zookeeper/docker-compose-multi-zookeeper.yml up -d --build --no-deps zookeeper zookeeper1 zookeeper2
