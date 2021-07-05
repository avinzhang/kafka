#!/bin/bash

OUTPUT=$(
expect <<END
  log_user 1
  spawn confluent login --url https://localhost:8090 --ca-cert-path ./secrets/ca.crt
  expect "Username: "
  send "superUser\r";
  expect "Password: "
  send "superUser\r";
  expect "Logged in as "
  set result $expect_out(buffer)
END
)

echo "$OUTPUT"

  if [[ ! "$OUTPUT" =~ "Logged in as" ]]; then
    echo "Failed to log into MDS.  Please check all parameters and run again"
    exit 1
  fi
echo
KAFKA_CLUSTER_ID=$(curl -sk  https://localhost:8090/v1/metadata/id  | grep id |jq -r ".id")
echo "Kafka cluster id is $KAFKA_CLUSTER_ID"

