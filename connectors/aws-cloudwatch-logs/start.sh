#!/bin/bash

TAG=6.1.2

CONNECTOR_VERSION=1.1.2

echo "Download aws cloudWatch logs connector if it's not present"
ls ./jar/confluentinc-kafka-connect-aws-cloudwatch-logs/lib/kafka-connect-aws-cloudwatch-logs-$CONNECTOR_VERSION.jar || confluent-hub install  --component-dir ./jar confluentinc/kafka-connect-aws-cloudwatch-logs:$CONNECTOR_VERSION --no-prompt
echo "Done"


echo "----Start everything up--------------"
docker-compose up -d --build --no-deps zookeeper kafka schemaregistry connect &>/dev/null
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
echo "Create AWS cloudWatch log"
aws logs create-log-group --log-group avin-log-group --region ap-southeast-2
echo
echo "Create AWS cloudWatch log stream"
aws logs create-log-stream --log-group avin-log-group --log-stream avin-log-stream --region ap-southeast-2
echo
log_ready=false
while [ $log_ready == false ]
do
    aws logs put-log-events --region ap-southeast-2 --log-group avin-log-group --log-stream avin-log-stream --log-events timestamp=$(date +'%s')000,message=apple  &> /dev/null
    if [ $? -eq 0 ]; then
      log_ready=true
      echo "*** CloudWatch log is ready ****"
    else
      echo ">>> Waiting for CloudWatch log to be ready"
    fi
    sleep 5
done

echo "Insert 10 records into cloudwatch log stream"
num=0
while [ $num -lt 10 ] 
do
  sequence_token=`aws logs describe-log-streams --region ap-southeast-2 --log-group avin-log-group | jq -r '.logStreams | .[]| .uploadSequenceToken'`
  aws logs put-log-events --region ap-southeast-2 --log-group avin-log-group --log-stream avin-log-stream --log-events timestamp=$(date +'%s')000,message=message-$num --sequence-token $sequence_token  &> /dev/null
  echo "Insert message-$num"
  num=$(expr $num + 1)
done
echo
echo "Create cloudwatch log  source connector"
curl -i -X POST -H "Accept:application/json" \
    -H  "Content-Type:application/json" http://localhost:8083/connectors/ \
    -d '{
        "name": "cloudwatch-source",
        "config": {
            "name": "cloudwatch-source",
            "tasks.max": 1,
            "connector.class": "io.confluent.connect.aws.cloudwatch.AwsCloudWatchSourceConnector",
            "aws.cloudwatch.logs.url": "https://logs.ap-southeast-2.amazonaws.com",
            "aws.cloudwatch.log.group": "avin-log-group",
            "aws.cloudwatch.log.streams": "avin-log-stream",
            "name": "cloudwatch-source",
            "confluent.topic.bootstrap.servers": "kafka:9093",
            "confluent.topic.replication.factor": "1",
            "aws.access.key.id": "'"$AWS_ACCESS_KEY_ID"'",
            "aws.secret.access.key": "'"$AWS_SECRET_ACCESS_KEY"'"
        }
    }'  &> /dev/null
echo
sleep 5
echo "Check cloudwatch source connector status"
curl http://localhost:8083/connectors/cloudwatch-source/status
echo
echo "Consume records from topic"
kafka-console-consumer --bootstrap-server localhost:9092 --topic avin-log-group.avin-log-stream --from-beginning --timeout-ms 5000 2> /dev/null


### to delete the log
##  aws logs delete-log-group --log-group avin-log-group --region ap-southeast-2
