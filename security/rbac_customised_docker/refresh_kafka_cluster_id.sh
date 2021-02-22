#!/bin/bash


OUTPUT=$(
  expect <<END
    log_user 1
    spawn confluent login --url http://localhost:18090
    expect "Username: "
    send "mds\r";
    expect "Password: "
    send "mds\r";
    expect "Logged in as "
    set result $expect_out(buffer)
END
)

echo "$OUTPUT"

  if [[ ! "$OUTPUT" =~ "Logged in as" ]]; then
    echo "Failed to log into MDS.  Please check all parameters and run again"
    exit 1
  fi

KAFKA_CLUSTER_ID=$(confluent cluster describe --url http://localhost:18090|grep Resource|awk '{print $4}')
echo "Kafka cluster id is $KAFKA_CLUSTER_ID"
export KAFKA_CLUSTER_ID=$KAFKA_CLUSTER_ID
