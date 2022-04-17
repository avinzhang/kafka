#!/bin/bash

export TAG=7.1.0.arm64

echo "----------Start zookeeper and broker -------------"
docker compose up -d --build --no-deps zookeeper1 zookeeper2 
STARTED=false
while [ $STARTED == false ]
do
    docker compose logs zookeeper1 | grep "binding to port" &> /dev/null
    if [ $? -eq 0 ]; then
      STARTED=true
      echo "ZK1 is started and ready"
    else
      echo "Waiting for ZK1 to start..."
    fi
    sleep 5
done
STARTED=false
while [ $STARTED == false ]
do
    docker compose logs zookeeper2 | grep "binding to port" &> /dev/null
    if [ $? -eq 0 ]; then
      STARTED=true
      echo "ZK2 is started and ready"
    else
      echo "Waiting for ZK2 to start..."
    fi
    sleep 5
done
docker compose up -d --build --no-deps kafka1 kafka2 
echo
echo
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker compose logs kafka1 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "kafka1 is started and ready"
    else
      echo "Waiting for kafka1 to start..."
    fi
    sleep 5
done

MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker compose logs kafka2 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "Kafka2 is started and ready"
    else
      echo "Waiting for kafka2 to start..."
    fi
    sleep 5
done
echo
echo
docker compose up -d --build --no-deps schemaregistry1 schemaregistry2 

STARTED=false
while [ $STARTED == false ]
do
    docker compose logs schemaregistry1 | grep "Server started" &> /dev/null
    if [ $? -eq 0 ]; then
      STARTED=true
      echo "SR1 is started and ready"
    else
      echo "Waiting for SR1 to start..."
    fi
    sleep 5
done

STARTED=false
while [ $STARTED == false ]
do
    docker compose logs schemaregistry2 | grep "Server started" &> /dev/null
    if [ $? -eq 0 ]; then
      STARTED=true
      echo "SR2 is started and ready"
    else
      echo "Waiting for SR2 to start..."
    fi
    sleep 5
done

echo ">>Register schemas on schemaregistry1"
curl -s -X POST -H "Content-Type: application/json" --data '{"schema": "{\"type\":\"record\",\"name\":\"Users\",\"fields\":[{\"name\":\"Name\",\"type\":\"string\"},{\"name\":\"Age\",\"type\":\"int\"},{\"name\":\"Phone\",\"type\":\"int\"}]}"}' http://localhost:1081/subjects/:.people:users/versions
#curl -s http://localhost:1081/subjects/:.people:users/versions/1
echo
echo
cat << EOF > /tmp/test.avro
{
      "schema":
        "{
               \"type\": \"record\",
               \"connect-name\": \"myname\",
               \"connect-donuts\": \"mydonut\",
               \"name\": \"test\",
               \"doc\": \"some doc info\",
                 \"fields\":
                   [
                     {
                       \"type\": \"string\",
                       \"doc\": \"doc for field1\",
                       \"name\": \"field1\"
                     },
                     {
                       \"type\": \"int\",
                       \"doc\": \"doc for field2\",
                       \"name\": \"field2\"
                     }
                   ]
               }"
     }
EOF
curl -s -X POST -H "Content-Type: application/json" --data @/tmp/test.avro http://localhost:1081/subjects/donuts/versions

echo 
echo ">>Check schemas on schemeregistry1"
curl --silent -X GET http://localhost:1081/subjects?subjectPrefix=":*:" | jq


echo ">>Create exporter on source schema registry"
cat << EOF > /tmp/config.txt
schema.registry.url=http://schemaregistry2:2081
EOF
schema-exporter --create --name myschemalink --context-type CUSTOM --context-name myschemalink --subjects ":*:" --schema.registry.url http://localhost:1081/ --config-file /tmp/config.txt

echo ">>List schema exporter"
schema-exporter --list --schema.registry.url http://localhost:1081

echo
echo ">>Describe schema exporter"
schema-exporter --describe --name myschemalink --schema.registry.url http://localhost:1081

echo
echo ">>Get status of exporter"
schema-exporter --get-status --name myschemalink --schema.registry.url http://localhost:1081
echo
sleep 5
echo
echo ">>Check schemas on schemaregistry2"
curl --silent -X GET http://localhost:2081/subjects?subjectPrefix=":*:" | jq


