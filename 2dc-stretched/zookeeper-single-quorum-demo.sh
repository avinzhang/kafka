#!/bin/bash

echo ">>Start 6 zookeepers in hierarchical mode and 6 brokers to simulate 2DC stretched setup"
docker-compose up -d --build --no-deps zookeeper1 zookeeper2 zookeeper3 zookeeper4 zookeeper5 zookeeper6 kafka kafka1 kafka2 kafka3 kafka4 kafka5 
echo ">>>Waiting for the nodes to start"
sleep 30
echo
echo
echo ">>>Checking zookeeper leader status, there should be one leader"
echo "zookeeper1 `echo srvr | nc localhost 12181 | grep Mode`"
echo "zookeeper2 `echo srvr | nc localhost 22181 | grep Mode`"
echo "zookeeper3 `echo srvr | nc localhost 32181 | grep Mode`"
echo "zookeeper4 `echo srvr | nc localhost 42181 | grep Mode`"
echo "zookeeper5 `echo srvr | nc localhost 52181 | grep Mode`"
echo "zookeeper6 `echo srvr | nc localhost 62181 | grep Mode`"
echo
echo ">>>Check brokers topic"
kafka-topics --bootstrap-server localhost:19092 --list
echo
echo ">>>Creat a topic"
echo ">>>>kafka-topics --bootstrap-server localhost:19092 --create --topic test --partitions 2 --replication-factor 3"
kafka-topics --bootstrap-server localhost:19092 --create --topic test --partitions 2 --replication-factor 3
echo
echo ">>>Stop zookeeper4 zookeeper5 zookeeper6"
docker-compose stop zookeeper6 zookeeper4 zookeeper5
sleep 10
echo 
echo ">>Checking zookeeper leader, it should not return anything"
echo ">>>>zookeeper1 'echo srvr | nc localhost 12181'"
echo ">>>>`echo srvr | nc localhost 12181`"
echo ">>>>zookeeper2 'echo srvr | nc localhost 22181'"
echo ">>>>`echo srvr | nc localhost 22181`"
echo ">>>>zookeeper3 'echo srvr | nc localhost 33181'"
echo ">>>>`echo srvr | nc localhost 32181`"
echo
echo ">>Check brokers topic - this should still work"
kafka-topics --bootstrap-server localhost:19092 --list
echo
echo ">>You cannot create any topics, it will hang"
echo "***Ctrl+c once to cancel"
echo ">>>>kafka-topics --bootstrap-server localhost:19092 --create --topic test1 --partitions 2 --replication-factor 3"
kafka-topics --bootstrap-server localhost:19092 --create --topic test1 --partitions 2 --replication-factor 3
echo 
echo
echo ">>Restart zookeeper1 zookeeper2 zookeeper3 with no reference to the rest of the zookeepers"
docker-compose -f docker-compose.yml -f ./docker-compose-single-quorum.yml up -d --build --no-deps zookeeper3 zookeeper1 zookeeper2

echo ">>>>Wait for a few seconds"
sleep 20
echo
echo ">>Checking leader info"
echo "zookeeper1 `echo srvr | nc localhost 12181 | grep Mode`"
echo "zookeeper2 `echo srvr | nc localhost 22181 | grep Mode`"
echo "zookeeper3 `echo srvr | nc localhost 32181 | grep Mode`"
echo
echo
echo ">>Try creating a topic again, it should work"
echo ">>>>kafka-topics --bootstrap-server localhost:19092 --create --topic test2 --partitions 2 --replication-factor 3"
kafka-topics --bootstrap-server localhost:19092 --create --topic test2 --partitions 2 --replication-factor 3


