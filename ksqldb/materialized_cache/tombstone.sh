#!/bin/bash

export TAG=7.1.1.arm64

echo "---Start postgres with data"
docker-compose up -d --build --no-deps postgres
echo
ready=false
while [ $ready == false ]
do
    docker-compose logs postgres|grep "database system is ready to accept connections" &> /dev/null
    if [ $? -eq 0 ]; then
      ready=true
      echo "*** postgres is ready ****"
    else
      echo ">>> Waiting for postgres to start"
    fi
    sleep 5
done
echo

echo ">>>> Test trigger"
docker-compose exec postgres bash -c "psql -U postgres postgres <<EOF
update orders set item='Chocolate Cake' where order_id=1;
SELECT * FROM orders;
EOF"


echo "----Download  jdbc connector-----------"
mkdir -p ./confluent-hub-components
ls confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/kafka-connect-jdbc-*.jar || confluent-hub install  --component-dir ./confluent-hub-components confluentinc/kafka-connect-jdbc:latest --no-prompt
ls confluent-hub-components/confluentinc-kafka-connect-elasticsearch/lib/kafka-connect-elasticsearch-*.jar || confluent-hub install  --component-dir ./confluent-hub-components confluentinc/kafka-connect-elasticsearch:latest --no-prompt
echo "Done"
echo
echo
echo "----Start everything up with version $TAG------------"
docker-compose up -d --build --no-deps zookeeper kafka schemaregistry ksqldb-server #&>/dev/null
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
echo
echo ">>> Available connector plugins"
docker-compose exec ksqldb-server bash -c "curl -s localhost:8083/connector-plugins" | jq '.[].class'
echo
echo
echo "----Create JDBC source connector in ksqldb----------------"
ksql http://localhost:8088 <<EOF
SET 'auto.offset.reset'='earliest';
CREATE SOURCE CONNECTOR source_orders WITH (
    'connector.class' = 'io.confluent.connect.jdbc.JdbcSourceConnector',
    'connection.url' = 'jdbc:postgresql://postgres:5432/',
    'connection.user'       = 'postgres',
    'connection.password'   = 'postgres',
    'poll.interval.ms'      = '1000',
    'mode'                  = 'timestamp',
    'table.whitelist'       = 'orders',
    'topic.prefix'          = '',
    'timestamp.column.name' = 'update_ts',
    'validate.non.null'     = 'false',
    'numeric.mapping'       = 'best_fit',
    'transforms'            = 'copyFieldToKey,extractKeyFromStruct,removeKeyFromValue',
    'transforms.copyFieldToKey.type'         = 'org.apache.kafka.connect.transforms.ValueToKey',
    'transforms.copyFieldToKey.fields'       = 'order_id',
    'transforms.extractKeyFromStruct.type'   = 'org.apache.kafka.connect.transforms.ExtractField\$Key',
    'transforms.extractKeyFromStruct.field'  = 'order_id',
    'transforms.removeKeyFromValue.type'     = 'org.apache.kafka.connect.transforms.ReplaceField\$Value',
    'transforms.removeKeyFromValue.blacklist'= 'order_id',
    'key.converter'                          = 'org.apache.kafka.connect.converters.IntegerConverter'
);
exit;
EOF
echo 
echo 
echo "Create materialized views"
docker-compose exec ksqldb-server bash -c "ksql http://ksqldb-server:8088 <<EOF
SET 'auto.offset.reset'='earliest';
SHOW TOPICS;

DESCRIBE CONNECTOR source_orders;

CREATE STREAM orders_src (ORDER_ID INT KEY) WITH (
    kafka_topic = 'orders',
    value_format = 'avro'
);
exit;
EOF;"
echo
echo ">>Create a stream for orders that has not been logically deleted"
docker-compose exec ksqldb-server bash -c "ksql http://ksqldb-server:8088 <<EOF
SET 'auto.offset.reset' = 'earliest';
CREATE STREAM ORDERS_NOT_DELETED
          WITH (KAFKA_TOPIC='orders_processed', VALUE_FORMAT='AVRO') AS
            SELECT * FROM ORDERS_SRC
            WHERE CANCELLED_IND = FALSE;
EOF"
echo
echo ">> Write a NULL for the value if order has been logically deleted"
docker-compose exec ksqldb-server bash -c "ksql http://ksqldb-server:8088 <<EOF
SET 'auto.offset.reset' = 'earliest';
CREATE STREAM ORDERS_DELETED
          WITH (KAFKA_TOPIC='orders_processed', VALUE_FORMAT='KAFKA') AS
            SELECT ORDER_ID, CAST(NULL AS VARCHAR) FROM ORDERS_SRC
            WHERE CANCELLED_IND = TRUE;
EOF"
echo
echo "Delete an order in postgres"
docker-compose exec postgres bash -c "psql -U postgres postgres <<EOF
UPDATE orders SET cancelled_ind=TRUE WHERE order_id=3;
EOF"
sleep 3
echo 
echo
echo
echo "Stream to Elasticsearch"
docker-compose up -d --build --no-deps elasticsearch 

export ready=false
while [ $ready == "false" ]
do
    docker-compose logs elasticsearch|grep "started" &> /dev/null
    if [ $? -eq 0 ]; then
      ready=true
      echo "*** elasticsearch is ready ****"
    else
      echo ">>> Waiting for elasticsearch to start"
    fi
    sleep 5
done
curl -s -XPUT "http://localhost:9200/_template/orders/" -H 'Content-Type: application/json' -d'
          {
            "template": "*",
            "mappings": { "dynamic_templates": [ { "dates": { "match": "*_TS", "mapping": { "type": "date" } } } ]  }
          }'

echo "Create elasticsearch sink connector"
ksql http://localhost:8088 <<EOF
SET 'auto.offset.reset' = 'earliest';
CREATE SINK CONNECTOR SINK_ELASTIC_01 WITH (
        'connector.class'                     = 'io.confluent.connect.elasticsearch.ElasticsearchSinkConnector',
        'topics'                              = 'orders_processed',
        'key.converter'                       = 'org.apache.kafka.connect.converters.IntegerConverter',
        'connection.url'                      = 'http://elasticsearch:9200',
        'type.name'                           = '_doc',
        'key.ignore'                          = 'false',
        'schema.ignore'                       = 'true',
        'behavior.on.null.values'             = 'delete',
        'transforms'                               = 'setTimestampType0',
        'transforms.setTimestampType0.type'        = 'org.apache.kafka.connect.transforms.TimestampConverter\$Value',
        'transforms.setTimestampType0.field'       = 'UPDATE_TS',
        'transforms.setTimestampType0.target.type' = 'Timestamp'
        );
exit;
EOF

export ready=false
while [ $ready == "false" ]
do
    docker-compose logs elasticsearch|grep "\[orders_processed\] creating index" &> /dev/null
    if [ $? -eq 0 ]; then
      ready=true
      echo "*** elasticsearch index is ready ****"
    else
      echo ">>> Waiting for elasticsearch to create index"
    fi
    sleep 5
done
echo
echo ">> Elasticsearch hits"
curl -s http://localhost:9200/orders_processed/_search \
    -H 'content-type: application/json' | jq '.hits.hits'

echo
echo "Add new row to orders"
docker-compose exec postgres bash -c "psql -U postgres postgres <<EOF
INSERT INTO orders VALUES (4,12.13,'Parkin',false);
EOF"
echo
sleep 5
echo ">> Elasticsearch hits again, the new order should be shown up"
curl -s http://localhost:9200/orders_processed/_search \
    -H 'content-type: application/json' | jq '.hits.hits'


