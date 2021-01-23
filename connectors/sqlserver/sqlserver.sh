#!/bin/bash

TAG=6.0.1


echo "Download jdbc connector"
ls ./jar/confluentinc-kafka-connect-jdbc/kafka-connect-jdbc-*.jar || confluent-hub install  --component-dir ./jar confluentinc/kafka-connect-jdbc:5.5.2 --no-prompt
echo "Done"


echo "----Start everything up--------------"
docker-compose up -d --build --no-deps zookeeper kafka connect schemaregistry &>/dev/null
echo

echo "----Start Microsft sqlserver-----------"
docker-compose up -d --build --no-deps mssql &>/dev/null
echo "Done"
sqlserver_ready=false
while [ $sqlserver_ready == false ]
do
    docker-compose logs mssql|grep "Recovery is complete" &> /dev/null
    if [ $? -eq 0 ]; then
      sqlserver_ready=true
      echo "*** sqlserver is ready ****"
    else
      echo ">>> Waiting for sqlserver to start"
    fi
    sleep 5
done

echo "Create database and tables in sqlserver"
cat ./connectors/sqlserver/customers.sql|docker exec -i mssql bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Passw0rd'
echo "Done"

echo "List databases"
docker-compose exec mssql bash -c "/opt/mssql-tools/bin/sqlcmd -U sa -P Passw0rd -Q 'SELECT name FROM master.dbo.sysdatabases'"
echo
echo "List tables from kafka database"
docker-compose exec mssql bash -c "/opt/mssql-tools/bin/sqlcmd -U sa -P Passw0rd -Q 'select * from kafka.INFORMATION_SCHEMA.TABLES'"
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

echo "Create jdbc source connector"
curl -i -X POST -H "Accept:application/json" \
    -H  "Content-Type:application/json" http://localhost:8083/connectors/ \
    -d '{
      "name": "jdbc-sqlserver-connector",
      "config": {
        "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
        "key.converter":"io.confluent.connect.avro.AvroConverter",
        "value.converter":"io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url":"http://schemaregistry:8081",
        "value.converter.schema.registry.url":"http://schemaregistry:8081",
        "errors.log.enable":"true",
        "errors.log.include.messages":"true",
        "connection.url": "jdbc:jtds:sqlserver://mssql:1433/kafka;user=sa;password=Passw0rd;encrypt=true;trustServerCertificate=false;loginTimeout=30;",
        "auto.evolve": "true",
        "auto.create": "true",
        "value.converter.schemas.enable": "true",
        "table.whitelist": "customers",
        "mode":"timestamp",
        "timestamp.column.name": "update_ts",
        "topic.prefix":"jdbctest"
      }
    }'

echo 
echo "Check jdbc connector status"
curl http://localhost:8083/connectors/jdbc-sqlserver-connector/status
