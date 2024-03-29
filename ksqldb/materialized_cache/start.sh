#!/bin/bash

export TAG=7.1.1.arm64

echo "----Download  connector-----------"
mkdir -p ./confluent-hub-components
ls confluent-hub-components/debezium-debezium-connector-mysql/lib/debezium-connector-mysql-*.jar || confluent-hub install  --component-dir ./confluent-hub-components debezium/debezium-connector-mysql:1.9.2 --no-prompt
ls ./confluent-hub-components/confluentinc-kafka-connect-datagen/lib/kafka-connect-datagen-*.jar || confluent-hub install  --component-dir ./confluent-hub-components confluentinc/kafka-connect-datagen:latest --no-prompt
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
docker-compose exec mysql bash -c "mysql -uroot -proot <<EOF
GRANT ALL PRIVILEGES ON *.* TO 'example-user' WITH GRANT OPTION;
ALTER USER 'example-user'@'%' IDENTIFIED WITH mysql_native_password BY 'example-pw';
FLUSH PRIVILEGES;
EOF"
echo
echo
echo
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
sleep 10
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
);
EOF"
sleep 5

docker-compose exec ksqldb-server bash -c "ksql http://ksqldb-server:8088 <<EOF
CREATE STREAM pageviews (viewtime BIGINT, userid VARCHAR, pageid VARCHAR) WITH (KAFKA_TOPIC='pageviews', VALUE_FORMAT='AVRO');
CREATE TABLE users (userid VARCHAR PRIMARY KEY, registertime BIGINT, gender VARCHAR, regionid VARCHAR) WITH (KAFKA_TOPIC='users', VALUE_FORMAT='AVRO');
CREATE STREAM pageviews_female with (KAFKA_TOPIC='pageviews_female') AS SELECT users.userid AS userid, pageid, regionid, gender FROM pageviews LEFT JOIN users ON pageviews.userid = users.userid WHERE gender = 'FEMALE';
CREATE STREAM pageviews_female_like_89 WITH (kafka_topic='pageviews_enriched_r8_r9', value_format='AVRO') AS SELECT * FROM pageviews_female WHERE regionid LIKE '%_8' OR regionid LIKE '%_9';
CREATE TABLE pageviews_regions WITH (kafka_topic='pageviews_regions', value_format='AVRO', KEY_FORMAT='avro') AS SELECT gender, regionid , COUNT(*) AS numusers FROM pageviews_female WINDOW TUMBLING (size 30 second) GROUP BY gender, regionid HAVING COUNT(*) > 1;

exit;
EOF"


