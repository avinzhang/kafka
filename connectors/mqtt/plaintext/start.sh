#!/bin/bash

TAG=7.2.1.arm64

echo "----Download mqtt connector"
ls confluent-hub-components/confluentinc-kafka-connect-mqtt/lib/kafka-connect-mqtt-*.jar || confluent-hub install --component-dir ./confluent-hub-components --no-prompt confluentinc/kafka-connect-mqtt:latest
echo
echo "----Start everything up--------------"
docker-compose up -d --build --no-deps  zookeeper1 zookeeper2 zookeeper3 kafka1 kafka2 kafka3 schemaregistry connect mosquitto
echo
echo 
connect_ready=false
while [ $connect_ready == false ]
do
    docker-compose logs connect|grep "Herder started" &> /dev/null
    if [ $? -eq 0 ]; then
      connect_ready=true
      echo "*** Kafka Connect is ready ****"
    else
      echo ">>> Waiting for kafka connect to start"
    fi
    sleep 5
done
echo
echo
echo ">> Install mosquitto"
which mosquitto_pub || brew install mosquitto
echo ">> Publish a few messages to mosquitto"
mosquitto_pub -r -h localhost -t "baeldung" -m "sample-message"
echo
sleep 3
echo
echo "* Create mqtt source connector -----------done"
docker-compose exec connect curl -X POST -H "Content-Type: application/json" http://localhost:8083/connectors/ \
   --data '{
        "name": "mqtt-source",
        "config": {
          "connector.class": "io.confluent.connect.mqtt.MqttSourceConnector",
          "mqtt.server.uri": "tcp://mosquitto:1883",
          "mqtt.topics":"baeldung",
          "mqtt.qos": "2",
          "kafka.topic": "kafka-baeldung",
          "value.converter": "org.apache.kafka.connect.converters.ByteArrayConverter",
          "value.converter.schemas.enable": "false",
          "tasks.max": "1",
          "confluent.topic.bootstrap.servers": "kafka1:1093,kafka2:2093,kafka3:3093"
          }
        }'
echo
sleep 5
echo
echo " >> checking mqtt source connector status"
curl http://localhost:8083/connectors/mqtt-source/status
echo
echo 
echo ">> Consume from topic mymessage"
kafka-console-consumer --bootstrap-server localhost:1092 --topic kafka-baeldung --from-beginning

