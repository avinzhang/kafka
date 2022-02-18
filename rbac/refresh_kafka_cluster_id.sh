#!/bin/bash

OUTPUT=$(
expect <<END
  log_user 1
  spawn confluent login --url https://localhost:1090 --ca-cert-path ./secrets/ca.crt
  expect "Username: "
  send "superUser\r";
  expect "Password: "
  send "superUser\r";
  expect "Logged in as "
  set result $expect_out(buffer)
END
)

echo "$OUTPUT"
echo
KAFKA_CLUSTER_ID=$(curl -sk  https://localhost:1090/v1/metadata/id  | grep id |jq -r ".id")
echo "Kafka cluster id is $KAFKA_CLUSTER_ID"

