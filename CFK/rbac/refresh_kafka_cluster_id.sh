#!/bin/bash

OUTPUT=$(
expect <<END
  log_user 1
  spawn confluent login --url https://localhost:8090 --ca-cert-path ./certs/ca.crt
  expect "Username: "
  send "kafka\r";
  expect "Password: "
  send "kafka\r";
  expect "Logged in as "
  set result $expect_out(buffer)
END
)

echo "$OUTPUT"

  if [[ ! "$OUTPUT" =~ "Logged in as" ]]; then
    echo "Failed to log into MDS.  Please check all parameters and run again"
    exit 1
  fi

KAFKA_CLUSTER_ID=$(curl -ik  https://localhost:8090/v1/metadata/id  &> /dev/null | grep id |jq -r ".id")
echo $KAFKA_CLUSTER_ID
echo "Kafka cluster id is $KAFKA_CLUSTER_ID"
