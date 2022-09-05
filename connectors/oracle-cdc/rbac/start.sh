#!/bin/bash

export TAG=7.2.1

echo "----------Start zookeeper" 
docker-compose up -d --build --no-deps zookeeper1 zookeeper2 zookeeper3 
echo
echo
echo "----------Start Openldap---------"
docker-compose up -d --build --no-deps openldap
STARTED=false
while [ $STARTED == false ]
do
    docker-compose logs openldap | grep "started" &> /dev/null
    if [ $? -eq 0 ]; then
      STARTED=true
      echo "Openldap is started and ready"
    else
      echo "Waiting for Openldap to start..."
    fi
    sleep 5
done
echo ">> Pull Oracle docker container"
docker login -u $ORACLE_DOCKER_USERNAME -p $ORACLE_DOCKER_PASSWORD container-registry.oracle.com
docker pull container-registry.oracle.com/database/enterprise:19.3.0.0
docker logout container-registry.oracle.com
echo
echo "-----------Start brokers"
docker-compose up -d --build --no-deps kafka1 kafka2 kafka3 oracle
echo "Done"
echo
echo
MDS_STARTED=false
while [ $MDS_STARTED == false ]
do
    docker-compose logs kafka1 | grep "Started NetworkTrafficServerConnector" &> /dev/null
    if [ $? -eq 0 ]; then
      MDS_STARTED=true
      echo "MDS is started and ready"
    else
      echo "Waiting for MDS to start..."
    fi
    sleep 5
done
echo
OUTPUT=$(
  expect <<END
    log_user 1
    spawn confluent login --url https://localhost:1090 --ca-cert-path ./secrets/ca.crt
    expect "Username: "
    send "mds\r";
    expect "Password: "
    send "mds\r";
    expect "Logged in as "
    set result $expect_out(buffer)
END
)

KAFKA_CLUSTER_ID=`curl -sik https://localhost:1090/v1/metadata/id |grep id |jq -r ".id"`
if [ -z "$KAFKA_CLUSTER_ID" ]; then
    echo "Failed to retrieve kafka cluster id from MDS"
    exit 1
fi
echo "****Cluster ID is $KAFKA_CLUSTER_ID"
echo
echo ">>>Check metadata API endpoint"
curl -k -u mds:mds https://localhost:1090/security/1.0/authenticate
echo
echo ">>>Setup config file for token port"
docker-compose exec kafka1 bash -c 'cat << EOF > /tmp/client-rbac.properties
sasl.mechanism=OAUTHBEARER
security.protocol=SASL_SSL
ssl.truststore.location=/etc/kafka/secrets/user1.truststore.jks
ssl.truststore.password=confluent
sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="mds" password="mds" metadataServerUrls="https://kafka1:1090";
EOF'
echo
echo
echo 
echo "---- Setup Rest Proxy ---"
confluent iam rbac role-binding create --principal User:restproxy --role DeveloperRead --resource Topic:_confluent-command --kafka-cluster-id $KAFKA_CLUSTER_ID
confluent iam rbac role-binding create --principal User:restproxy --role DeveloperWrite --resource Topic:_confluent-command --kafka-cluster-id $KAFKA_CLUSTER_ID
echo

echo
echo "----Setup Schema Registry ----"
echo
echo ">> Adding role binding for user schemaregistry"
confluent iam rbac role-binding create \
    --principal User:schemaregistry \
    --role SecurityAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id schema-registry

confluent iam rbac role-binding create \
    --principal User:schemaregistry \
    --role ClusterAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

for resource in Topic:_schemas Topic:_confluent-command Topic:_confluent-license Group:schema-registry
do
    confluent iam rbac role-binding create \
        --principal User:schemaregistry \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done
echo
echo ">> Starting up schema registry"
docker-compose up -d --build --no-deps schemaregistry &>/dev/null
echo
echo
echo "-------------------------------------------------------------------"
echo
echo
echo "----Setup Kafka Connect------------"
echo
echo ">> Download Oracle CDC source connector"

mkdir -p ./confluent-hub-components
ls confluent-hub-components/confluentinc-kafka-connect-oracle-cdc/lib/kafka-connect-oracle-cdc-*.jar || confluent-hub install  --component-dir ./confluent-hub-components confluentinc/kafka-connect-oracle-cdc:latest --no-prompt
echo "Done"

echo
echo ">> Adding role binding for connectAdmin"
confluent iam rbac role-binding create --principal User:connectAdmin --role SecurityAdmin --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster
# ResourceOwner for groups and topics on broker
declare -a ConnectResources=(
    "Topic:connect-configs"
    "Topic:connect-offsets"
    "Topic:connect-status"
    "Group:connect-cluster"
    "Topic:_confluent-monitoring"
    "Topic:_confluent-secrets"
    "Topic:_confluent-command"
    "Group:secret-registry"
)
for resource in ${ConnectResources[@]}
do
    confluent iam rbac role-binding create \
        --principal User:connectAdmin \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done

echo
echo
echo ">> Starting up Kafka connect"
docker-compose up -d --build --no-deps connect
echo
echo
CONNECT_STARTED=false
while [ $CONNECT_STARTED == false ]
do
    docker-compose logs connect | grep "Herder started" &> /dev/null
    if [ $? -eq 0 ]; then
      CONNECT_STARTED=true
      echo "Kafka connect is started and ready"
    else
      echo "Waiting for Kafka Connect..."
    fi
    sleep 5
done

echo ">> Add role binding for connectUser for managing connectors"
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Connector:oracle-cdc --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster


#Idempotent producers require cluster write
confluent iam rbac role-binding create --principal User:connectUser --role DeveloperWrite --resource Cluster:kafka-cluster --kafka-cluster-id $KAFKA_CLUSTER_ID

#confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Group:connect-datagen-users --kafka-cluster-id $KAFKA_CLUSTER_ID
#confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Group:connect-datagen-pageviews --kafka-cluster-id $KAFKA_CLUSTER_ID
#for connector to access topic, subject
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Topic:ORCLCDB --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rbac role-binding create --principal User:connectAdmin --role ResourceOwner --resource Topic:ORCLCDB --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Subject:ORCLCDB --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry --prefix
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Topic:_confluent-command --kafka-cluster-id $KAFKA_CLUSTER_ID 


# User to check all connector status
#confluent iam rbac role-binding create --principal User:connectorViewer --role ResourceOwner --resource 'Connector:*' --kafka-cluster-id $KAFKA_CLUSTER_ID --connect-cluster-id connect-cluster
#confluent iam rbac role-binding create --principal User:connectorViewer --role ResourceOwner --resource 'Topic:*' --kafka-cluster-id $KAFKA_CLUSTER_ID --prefix
#confluent iam rbac role-binding create --principal User:connectorViewer --role ResourceOwner --resource 'Subject:*' --kafka-cluster-id $KAFKA_CLUSTER_ID --schema-registry-cluster-id schema-registry

echo
STARTED=false
while [ $STARTED == false ]
do
    docker-compose logs oracle | grep "DATABASE IS READY TO USE" &> /dev/null
    if [ $? -eq 0 ]; then
      STARTED=true
      echo "Oracle DB is started and ready"
    else
      echo "Waiting for Oracle DB..."
    fi
    sleep 5
done
echo
echo
echo ">> Setup Oracle permission"
docker exec -i oracle bash -c "export ORACLE_SID=ORCLCDB; sqlplus /nolog" << EOF
     CONNECT sys/Admin123 AS SYSDBA
     CREATE ROLE C##CDC_PRIVS;
     GRANT CREATE SESSION TO C##CDC_PRIVS;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR TO C##CDC_PRIVS;
     GRANT LOGMINING TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$LOGMNR_CONTENTS TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$DATABASE TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$THREAD TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$PARAMETER TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$NLS_PARAMETERS TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$TIMEZONE_NAMES TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_INDEXES TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_OBJECTS TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_USERS TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_CATALOG TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_CONSTRAINTS TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_CONS_COLUMNS TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_TAB_COLS TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_IND_COLUMNS TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_ENCRYPTED_COLUMNS TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_LOG_GROUPS TO C##CDC_PRIVS;
   --  GRANT SELECT ON ALL_TAB_PARTITIONS TO C##CDC_PRIVS;
   --  GRANT SELECT ON SYS.DBA_REGISTRY TO C##CDC_PRIVS;
     GRANT SELECT ON SYS.OBJ$ TO C##CDC_PRIVS;
   --  GRANT SELECT ON DBA_TABLESPACES TO C##CDC_PRIVS;
   --  GRANT SELECT ON DBA_OBJECTS TO C##CDC_PRIVS;
   --  GRANT SELECT ON SYS.ENC$ TO C##CDC_PRIVS;
     GRANT SELECT ANY TABLE TO C##CDC_PRIVS;
     -- Following privileges are required additionally for 19c compared to 12c.
     GRANT SELECT ON V_\$ARCHIVED_LOG TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$LOG TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$LOGFILE TO C##CDC_PRIVS;
     GRANT SELECT ON V_\$INSTANCE to C##CDC_PRIVS;
     CREATE USER C##MYUSER IDENTIFIED BY mypassword DEFAULT TABLESPACE USERS;
     ALTER USER C##MYUSER QUOTA UNLIMITED ON USERS;
     GRANT C##CDC_PRIVS to C##MYUSER;
     GRANT CREATE TABLE TO C##MYUSER container=all;
     GRANT CREATE SEQUENCE TO C##MYUSER container=all;
     GRANT CREATE TRIGGER TO C##MYUSER container=all;
     GRANT FLASHBACK ANY TABLE TO C##MYUSER container=all;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR TO C##CDC_PRIVS;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR_D TO C##CDC_PRIVS;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR_LOGREP_DICT TO C##CDC_PRIVS;
     GRANT EXECUTE ON SYS.DBMS_LOGMNR_SESSION TO C##CDC_PRIVS;
     
     -- Enable Supplemental Logging for All Columns
     ALTER SESSION SET CONTAINER=cdb\$root;
     ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
     ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
     exit;
EOF
echo " >> Insert data"
docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB << EOF
     create table CUSTOMERS (
          id NUMBER(10) GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH 42) NOT NULL PRIMARY KEY,
          first_name VARCHAR(50),
          last_name VARCHAR(50),
          email VARCHAR(50),
          gender VARCHAR(50),
          club_status VARCHAR(20),
          comments VARCHAR(90),
          create_ts timestamp DEFAULT CURRENT_TIMESTAMP ,
          update_ts timestamp
     );
     CREATE OR REPLACE TRIGGER TRG_CUSTOMERS_UPD
     BEFORE INSERT OR UPDATE ON CUSTOMERS
     REFERENCING NEW AS NEW_ROW
     FOR EACH ROW
     BEGIN
     SELECT SYSDATE
          INTO :NEW_ROW.UPDATE_TS
          FROM DUAL;
     END;
     /
     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (1, 'Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy');
     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (2, 'Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface');
     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (3, 'Mariejeanne', 'Cocci', 'mcocci2@techcrunch.com', 'Female', 'bronze', 'Multi-tiered bandwidth-monitored capability');
     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (4, 'Hashim', 'Rumke', 'hrumke3@sohu.com', 'Male', 'platinum', 'Self-enabling 24/7 firmware');
     insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (5, 'Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach');
     exit;
EOF


echo ">> Add connector: oracle-cdc-connector"
curl -i -X POST \
    --cacert ./secrets/ca.crt \
    -u connectUser:connectUser \
    -H "Accept:application/json" \
    -H  "Content-Type:application/json" \
   https://localhost:8083/connectors/ -d '
  {
      "name": "oracle-cdc",
      "config": {
           "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
           "tasks.max": "1",
           "key.converter": "io.confluent.connect.avro.AvroConverter",
           "key.converter.schema.registry.url": "https://schemaregistry:8081",
           "key.converter.schema.registry.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks",
           "key.converter.schema.registry.ssl.truststore.password": "confluent",
           "key.converter.basic.auth.credentials.source": "USER_INFO",
           "key.converter.basic.auth.user.info": "connectUser:connectUser",
           "value.converter": "io.confluent.connect.avro.AvroConverter",
           "value.converter.schema.registry.url": "https://schemaregistry:8081",
           "value.converter.schema.registry.ssl.truststore.location": "/etc/kafka/secrets/connect.truststore.jks",
           "value.converter.schema.registry.ssl.truststore.password": "confluent",
           "value.converter.basic.auth.credentials.source": "USER_INFO",
           "value.converter.basic.auth.user.info": "connectUser:connectUser",
           "oracle.server": "oracle",
           "oracle.port": "1521",
           "oracle.sid": "ORCLCDB",
           "oracle.username": "C##MYUSER",
           "oracle.password": "mypassword",
           "start.from":"snapshot",
           "redo.log.topic.name": "redo-log-topic",
           "redo.log.consumer.bootstrap.servers":"kafka1:1092,kafka2:2093,kafka3:3093",
           "table.inclusion.regex": ".*CUSTOMERS.*",
           "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
           "numeric.mapping": "best_fit",
           "connection.pool.max.size": "20",
           "redo.log.row.fetch.size": "1",
           "oracle.dictionary.mode": "auto",
           "errors.tolerance": "all",
           "errors.log.enable": "true",
           "errors.log.include.messages": "true",
           "topic.creation.groups": "redo",
           "topic.creation.redo.include": "redo-log-topic",
           "topic.creation.redo.replication.factor": "1",
           "topic.creation.redo.partitions": "1",
           "topic.creation.redo.cleanup.policy": "delete",
           "topic.creation.redo.retention.ms": "1209600000",
           "topic.creation.default.replication.factor": "1",
           "topic.creation.default.partitions": "1",
           "topic.creation.default.cleanup.policy": "delete",
           "producer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectUser\" password=\"connectUser\" metadataServerUrls=\"https://kafka1:1090\";"
       }
   }'
echo
sleep 5
echo ">> Check connector status"
echo "Oracle CDC source: `curl -s --cacert ./secrets/ca.crt -u connectUser:connectUser https://localhost:8083/connectors/oracle-cdc/status`"
echo
echo ">>> List topics"
docker-compose exec kafka1 kafka-topics -bootstrap-server kafka1:1093 --command-config /tmp/client-rbac.properties --list
echo
docker-compose exec connect bash -c 'cat << EOF > /tmp/connectUser-rbac.properties
sasl.mechanism=OAUTHBEARER
security.protocol=SASL_SSL
ssl.truststore.location=/etc/kafka/secrets/user1.truststore.jks
ssl.truststore.password=confluent
sasl.login.callback.handler.class=io.confluent.kafka.clients.plugins.auth.token.TokenUserLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username="connectUser" password="connectUser" metadataServerUrls="https://kafka1:1090";
EOF'
echo
confluent iam rbac role-binding create --principal User:connectUser --role ResourceOwner --resource Group:oracle-consumer-group --kafka-cluster-id $KAFKA_CLUSTER_ID 
echo
docker-compose exec connect kafka-avro-console-consumer --group=oracle-consumer-group --property schema.registry.url=https://schemaregistry:8081 --property schema.registry.ssl.truststore.location=/etc/kafka/secrets/user1.truststore.jks --property schema.registry.ssl.truststore.password=confluent --property schema.registry.basic.auth.user.info=connectUser:connectUser --property basic.auth.credentials.source=USER_INFO --bootstrap-server kafka1:1093 --consumer.config /tmp/connectUser-rbac.properties --from-beginning --topic ORCLCDB.C__MYUSER.CUSTOMERS
