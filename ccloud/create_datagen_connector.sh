#!/bin/bash

cat > /tmp/ccloud_datagen_pageviews.config <<EOF
{
    "name" : "datagen_ccloud_pageviews",
    "connector.class": "DatagenSource",
    "kafka.api.key": "$api_key",
    "kafka.api.secret" : "$api_secret",
    "kafka.topic" : "pageviews",
    "output.data.format" : "JSON",
    "quickstart" : "PAGEVIEWS",
    "max.interval": "500",
    "iterations": "1000000000",
    "tasks.max" : "1"
}
EOF

cat > /tmp/ccloud_datagen_users.config <<EOF
{
    "name" : "datagen_ccloud_users",
    "connector.class": "DatagenSource",
    "kafka.api.key": "$api_key",
    "kafka.api.secret" : "$api_secret",
    "kafka.topic" : "users",
    "output.data.format" : "JSON",
    "quickstart" : "USERS",
    "max.interval": "500",
    "iterations": "1000000000",
    "tasks.max" : "1"
}
EOF
ccloud connector create -vvv --config /tmp/ccloud_datagen_pageviews.config
ccloud connector create -vvv --config /tmp/ccloud_datagen_users.config
