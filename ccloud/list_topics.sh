#!/bin/bash

echo "----Create config for connecting to ccloud"
cat > /tmp/config.properties <<EOF
sasl.mechanism=PLAIN
request.timeout.ms=20000
retry.backoff.ms=500
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \
username="$api_key" password="$api_secret";
security.protocol=SASL_SSL
EOF
echo
echo
echo "---List topics in ccloud"
kafka-topics --bootstrap-server $ccloud_bootstrap_server --command-config /tmp/config.properties --list
echo
echo
echo "----List ACLs"
kafka-acls --bootstrap-server $ccloud_bootstrap_server --command-config /tmp/config.properties --list --principal User:64808

