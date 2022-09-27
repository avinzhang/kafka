#!/bin/bash

TAG=7.2.1.arm64

echo "----Download aws cloudwatch log source connector"
ls confluent-hub-components/confluentinc-kafka-connect-aws-cloudwatch-logs/lib/kafka-connect-aws-cloudwatch-logs-*.jar || confluent-hub install --component-dir ./confluent-hub-components --no-prompt confluentinc/kafka-connect-aws-cloudwatch-logs:latest
echo
echo "----Start everything up--------------"
docker-compose up -d --build --no-deps  zookeeper1 zookeeper2 zookeeper3 kafka1 kafka2 kafka3 schemaregistry connect 
echo
echo 
echo ">>> Create AWS CloudWatch Log group"
aws logs describe-log-groups --region ap-southeast-2 --log-group avin-log-group |grep avin-log-group &> /dev/null || aws logs create-log-group --log-group avin-log-group --region ap-southeast-2
echo
echo ">>> Create AWS CloudWatch log stream"
aws logs describe-log-streams --region ap-southeast-2 --log-group avin-log-group |grep avin-log-stream &> /dev/null || aws logs create-log-stream --log-group avin-log-group --log-stream avin-log-stream --region ap-southeast-2
echo
echo ">>>> Waiting for CloudWatch log stream to be ready"
log_ready=false
while [ $log_ready == false ]
  do
    aws logs describe-log-streams --region ap-southeast-2 --log-group avin-log-group|grep avin-log-stream  &> /dev/null && log_ready=true && echo "*** CloudWatch log is ready ***"
    sleep 5
done
echo
echo "Insert 10 records into cloudwatch log stream"
num=0
while [ $num -lt 10 ]
do
  sequence_token=`aws logs describe-log-streams --region ap-southeast-2 --log-group avin-log-group | jq -r '.logStreams | .[]| .uploadSequenceToken'`
  aws logs describe-log-streams --region ap-southeast-2 --log-group avin-log-group | jq -r '.logStreams'| grep uploadSequenceToken &>/dev/null || aws logs put-log-events --region ap-southeast-2 --log-group avin-log-group --log-stream avin-log-stream --log-events timestamp=$(date +'%s')000,message=message-$num &>/dev/null
  aws logs describe-log-streams --region ap-southeast-2 --log-group avin-log-group | jq -r '.logStreams'| grep uploadSequenceToken &>/dev/null && aws logs put-log-events --region ap-southeast-2 --log-group avin-log-group --log-stream avin-log-stream --log-events timestamp=$(date +'%s')000,message=message-$num --sequence-token $sequence_token &>/dev/null
  echo "Insert message-$num"
  num=$(expr $num + 1)
done
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
echo
echo "* Create CloudWatch log source connector -----------done"
docker-compose exec connect curl -X POST -H "Content-Type: application/json" http://localhost:8083/connectors/ \
   --data '{
        "name": "aws-cloudwatch-source",
        "config": {
          "connector.class": "io.confluent.connect.aws.cloudwatch.AwsCloudWatchSourceConnector",
          "aws.cloudwatch.logs.url": "https://logs.ap-southeast-2.amazonaws.com",
          "aws.cloudwatch.log.group": "avin-log-group",
          "aws.cloudwatch.log.streams": "avin-log-stream",
          "confluent.topic.bootstrap.servers": "kafka1:1093,kafka2:2093,kafka3:3093",
          "confluent.topic.replication.factor": "1",
          "aws.access.key.id": "'"$AWS_ACCESS_KEY_ID"'",
          "aws.secret.access.key": "'"$AWS_SECRET_ACCESS_KEY"'",
          "value.converter": "org.apache.kafka.connect.json.JsonConverter",
          "tasks.max": "1"
          }
        }'
echo
sleep 5
echo
echo " >> checking  source connector status"
curl http://localhost:8083/connectors/aws-cloudwatch-source/status
echo
echo 
echo ">> Consume from topic"
kafka-console-consumer --bootstrap-server localhost:1092,localhost:2092,localhost:3092 --topic avin-log-group.avin-log-stream --from-beginning --timeout-ms 5000

## Cleanup 
# delete cloudwatch log stream
# aws logs delete-log-group --log-group avin-log-group --region ap-southeast-2

