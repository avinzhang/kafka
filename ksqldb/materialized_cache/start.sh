#!/bin/bash

export TAG=7.0.1

echo "----Download  connector-----------"
mkdir -p ./jar/debezium
ls jar/debezium-debezium-connector-mysql/lib/debezium-connector-mysql-*.jar || confluent-hub install  --component-dir ./jar debezium/debezium-connector-mysql:1.1.0
ls ./jar/confluentinc-kafka-connect-datagen/lib/kafka-connect-datagen-*.jar || confluent-hub install  --component-dir ./jar confluentinc/kafka-connect-datagen:latest --no-prompt
echo "Done"
echo
echo
echo "----Start everything up with version $TAG------------"
docker-compose up -d --build --no-deps zookeeper kafka schemaregistry ksqldb-server mysql #&>/dev/null
echo

echo
ksql_ready=false
while [ $ksql_ready == false ]
do
    docker-compose logs ksqldb-server|grep "Server up and running" &> /dev/null
    if [ $? -eq 0 ]; then
      ksql_ready=true
      echo "*** ksqldb is ready ****"
    else
      echo ">>> Waiting for ksqldb to start"
    fi
    sleep 5
done
exit
docker-compose exec mysql bash -c "mysql -uroot -proot <<EOF
GRANT ALL PRIVILEGES ON *.* TO 'example-user' WITH GRANT OPTION;
ALTER USER 'example-user'@'%' IDENTIFIED WITH mysql_native_password BY 'example-pw';
FLUSH PRIVILEGES;
EOF"

echo "----Create connector in ksqldb----------------"
docker-compose exec ksqldb-server bash -c "ksql http://ksqldb-server:8088 <<EOF
SET 'auto.offset.reset'='earliest';
CREATE SOURCE CONNECTOR calls_reader WITH (
    'connector.class' = 'io.debezium.connector.mysql.MySqlConnector',
    'database.hostname' = 'mysql',
    'database.port' = '3306',
    'database.user' = 'example-user',
    'database.password' = 'example-pw',
    'database.allowPublicKeyRetrieval' = 'true',
    'database.server.id' = '184054',
    'database.server.name' = 'call-center-db',
    'database.whitelist' = 'call-center',
    'database.history.kafka.bootstrap.servers' = 'kafka:9093',
    'database.history.kafka.topic' = 'call-center',
    'table.whitelist' = 'call-center.calls',
    'include.schema.changes' = 'false'
);
exit;
EOF" 

sleep 5
echo 
echo 
echo "Create materialized views"
docker-compose exec ksqldb-server bash -c "ksql http://ksqldb-server:8088 <<EOF
SET 'auto.offset.reset'='earliest';
SHOW TOPICS;

DESCRIBE CONNECTOR calls_reader;

CREATE STREAM calls WITH (
    kafka_topic = 'call-center-db.call-center.calls',
    value_format = 'avro'
);

CREATE TABLE support_view AS
    SELECT after->name AS name,
           count_distinct(after->reason) AS distinct_reasons,
           latest_by_offset(after->reason) AS last_reason
    FROM calls
    GROUP BY after->name
    EMIT CHANGES;

CREATE TABLE lifetime_view AS
    SELECT after->name AS name,
           count(after->reason) AS total_calls,
           (sum(after->duration_seconds) / 60) as minutes_engaged
    FROM calls
    GROUP BY after->name
    EMIT CHANGES;

exit;
EOF;"
echo
echo
echo "Query materialized views"
sleep 3
docker-compose exec ksqldb-server bash -c "ksql http://ksqldb-server:8088 <<EOF
SET 'auto.offset.reset'='earliest';
SELECT name, distinct_reasons, last_reason FROM support_view WHERE name = 'derek';

SELECT name, total_calls, minutes_engaged FROM lifetime_view WHERE name = 'michael';
exit;
EOF"




echo 
echo "---Create datagen connector"
docker-compose exec ksqldb-server bash -c "ksql http://ksqldb-server:8088 <<EOF
SET 'auto.offset.reset'='earliest';
CREATE SOURCE CONNECTOR datagenusers WITH (
    'connector.class' = 'io.confluent.kafka.connect.datagen.DatagenConnector',
    'quickstart' = 'users',
    'kafka.topic' = 'users',
    'max.interval' = '1000',
    'key.converter' = 'org.apache.kafka.connect.storage.StringConverter',
    'value.converter' = 'io.confluent.connect.avro.AvroConverter',
    'iterations' = '1000000000',
    'key.converter.schema.registry.url' = 'http://schemaregistry:8081',
    'value.converter.schema.registry.url' = 'http://schemaregistry:8081'
);

CREATE SOURCE CONNECTOR datagenpageviews WITH (
    'connector.class' = 'io.confluent.kafka.connect.datagen.DatagenConnector',
    'quickstart' = 'pageviews',
    'kafka.topic' = 'pageviews',
    'max.interval' = '1000',
    'key.converter' = 'org.apache.kafka.connect.storage.StringConverter',
    'value.converter' = 'io.confluent.connect.avro.AvroConverter',
    'iterations' = '1000000000',
    'key.converter.schema.registry.url' = 'http://schemaregistry:8081',
    'value.converter.schema.registry.url' = 'http://schemaregistry:8081'
exit;
EOF"


