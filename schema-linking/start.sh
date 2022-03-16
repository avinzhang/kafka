#!/bin/bash

export TAG=7.0.1

echo "----------Start zookeeper and broker -------------"
docker-compose up -d --build --no-deps zookeeper1 zookeeper2 kafka1 kafka2 schemaregistry1 schemaregistry2
echo "Done"
echo
echo
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker-compose logs kafka1 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "kafka1 is started and ready"
    else
      echo "Waiting for MDS to start..."
    fi
    sleep 5
done

MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker-compose logs kafka2 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "Kafka2 is started and ready"
    else
      echo "Waiting for MDS to start..."
    fi
    sleep 5
done
echo
echo
echo ">> start C3"
docker-compose up -d --build --no-deps controlcenter
echo


echo "Register schema on kafka1"
curl -X POST -H "Content-Type: application/json" --data '{"schema": "{\"type\":\"record\",\"name\":\"Users\",\"fields\":[{\"name\":\"Name\",\"type\":\"string\"},{\"name\":\"Age\",\"type\":\"int\"},{\"name\":\"Phone\",\"type\":\"int\"}]}"}' http://localhost:1081/subjects/users-value/versions

echo "List the schema"
curl -s http://localhost:1081/subjects/users-value/versions/1

echo "Create exporter on source schema registry"
echo "schema.registry.url=http://localhost:2081" > ./config.txt
schema-exporter --create --name myschemalink --subjects ":*:" --schema.registry.url http://localhost:1081/ --config-file ./config.txt

echo "List schema exporter"
schema-exporter --list --schema.registry.url http://localhost:1081

#currently schema-exporter doesn't work, it could be it's still in preview mode
