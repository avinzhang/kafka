#!/bin/bash

echo ">>Start 6 zookeepers in hierarchical mode and 6 brokers to simulate 2DC stretched setup"
docker-compose up -d --build --no-deps zookeeper1 zookeeper2 zookeeper3 zookeeper4 zookeeper5 zookeeper6 kafka6 kafka1 kafka2 kafka3 kafka4 kafka5 
echo ">>>Waiting for the nodes to start"
echo
for zk_node in zookeeper1 zookeeper2 zookeeper3 zookeeper4 zookeeper5 zookeeper6
  do
    ZK_STARTED=false
    while [ $ZK_STARTED == false ]
    do
        if [ -z `docker ps -q --no-trunc | grep $(docker-compose ps -q $zk_node)` ]; then
          echo "Waiting for $zk_node to start..."
        else
          ZK_STARTED=true
          echo "$zk_node is running"
        fi
        sleep 5
    done
done
echo
echo ">>>Checking zookeeper leader status, there should be one leader"
echo "zookeeper1 `echo srvr | nc localhost 1181 | grep Mode`"
echo "zookeeper2 `echo srvr | nc localhost 2181 | grep Mode`"
echo "zookeeper3 `echo srvr | nc localhost 3181 | grep Mode`"
echo "zookeeper4 `echo srvr | nc localhost 4181 | grep Mode`"
echo "zookeeper5 `echo srvr | nc localhost 5181 | grep Mode`"
echo "zookeeper6 `echo srvr | nc localhost 6181 | grep Mode`"
echo
echo
for broker_node in kafka1 kafka2 kafka3 kafka4 kafka5 kafka6 
  do
    MDS_STARTED=false
    while [ $MDS_STARTED == false ]
    do
        docker-compose logs $broker_node | grep "Started NetworkTrafficServerConnector" &> /dev/null
        if [ $? -eq 0 ]; then
          MDS_STARTED=true
          echo "$broker_node is started and ready"
        else
          echo "Waiting for $broker_node to start..."
          sleep 3
        fi
    done
done

echo ">>>Check brokers topic"
kafka-topics --bootstrap-server localhost:1092 --list
echo
echo ">>>Creat a topic"
echo ">>>>kafka-topics --bootstrap-server localhost:1092 --create --topic test --partitions 2 --replication-factor 3"
kafka-topics --bootstrap-server localhost:1092 --create --topic test --partitions 2 --replication-factor 3
echo
echo ">>>Stop zookeeper4 zookeeper5 zookeeper6 "
docker-compose stop zookeeper4 zookeeper5 zookeeper6 
sleep 10
echo 
echo ">>Checking zookeeper leader, it should not return anything"
echo ">>>>zookeeper1 'echo srvr | nc localhost 1181'"
echo ">>>>`echo srvr | nc localhost 1181`"
echo ">>>>zookeeper2 'echo srvr | nc localhost 2181'"
echo ">>>>`echo srvr | nc localhost 2181`"
echo ">>>>zookeeper3 'echo srvr | nc localhost 3181'"
echo ">>>>`echo srvr | nc localhost 3181`"
echo
echo ">>Check brokers topic - this should still work"
kafka-topics --bootstrap-server localhost:1092 --list
echo
echo ">>You cannot create any topics, it will hang"
echo "***Ctrl+c once to cancel"
echo ">>>>kafka-topics --bootstrap-server localhost:1092 --create --topic test1 --partitions 2 --replication-factor 3"
kafka-topics --bootstrap-server localhost:1092 --create --topic test1 --partitions 2 --replication-factor 3
echo 
echo
echo ">>Restart zookeeper3 zookeeper1 zookeeper2 with no reference to the stopped zookeepers"
docker-compose -f ./docker-compose-single-quorum.yml up -d --build --no-deps zookeeper3 zookeeper1 zookeeper2 
docker-compose -f ./docker-compose-single-quorum.yml up -d --build --no-deps --force-recreate kafka1 kafka2 kafka3 kafka4 kafka5 kafka6

for zk_node in zookeeper1 zookeeper2 zookeeper3 
  do
    ZK_STARTED=false
    while [ $ZK_STARTED == false ]
    do
        if [ -z `docker ps -q --no-trunc | grep $(docker-compose ps -q $zk_node)` ]; then
          echo "Waiting for $zk_node to start..."
          sleep 3
        else
          ZK_STARTED=true
          echo "$zk_node is running"
        fi
    done
done
echo
echo ">>Checking leader info"
sleep 5
echo "zookeeper1 `echo srvr | nc localhost 1181 | grep Mode`"
echo "zookeeper2 `echo srvr | nc localhost 2181 | grep Mode`"
echo "zookeeper3 `echo srvr | nc localhost 3181 | grep Mode`"
echo
echo
for broker_node in kafka1 kafka2 kafka3 kafka4 kafka5 kafka6
  do
    BROKER_STARTED=false
    while [ $BROKER_STARTED == false ]
    do
        docker-compose logs $broker_node | grep "Started NetworkTrafficServerConnector" &> /dev/null
        if [ $? -eq 0 ]; then
          BROKER_STARTED=true
          echo "$broker_node started"
        else
          echo "Waiting for $broker_node to start..."
        fi
    done
done
echo
echo ">>Try creating a topic again, it should work"
echo ">>>>kafka-topics --bootstrap-server localhost:1092 --create --topic test2 --partitions 2 --replication-factor 3"
kafka-topics --bootstrap-server localhost:1092 --create --topic test2 --partitions 2 --replication-factor 3


