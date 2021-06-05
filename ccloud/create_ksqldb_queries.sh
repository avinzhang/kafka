#!/bin/bash

echo "Find ksqldb app endpoint"
ksqldb_endpoint=`ccloud ksql app list -o json |jq -r '.[].endpoint'`
echo $ksqldb_endpoint

echo "Create ksqldb tables and streams"
ksql -u $ksql_api_key -p $ksql_api_secret $ksqldb_endpoint <<EOF
SET 'auto.offset.reset'='earliest';
CREATE STREAM pageviews (viewtime BIGINT, userid VARCHAR, pageid VARCHAR) WITH (KAFKA_TOPIC='pageviews', REPLICAS=1, VALUE_FORMAT='JSON');
CREATE TABLE users (userid VARCHAR PRIMARY KEY, registertime BIGINT, gender VARCHAR, regionid VARCHAR) WITH (KAFKA_TOPIC='users', VALUE_FORMAT='JSON');
CREATE STREAM pageviews_female AS SELECT users.userid AS userid, pageid, regionid, gender FROM pageviews LEFT JOIN users ON pageviews.userid = users.userid WHERE gender = 'FEMALE';
CREATE STREAM pageviews_female_like_89 WITH (kafka_topic='pageviews_enriched_r8_r9', value_format='JSON') AS SELECT * FROM pageviews_female WHERE regionid LIKE '%_8' OR regionid LIKE '%_9';
CREATE TABLE pageviews_regions AS SELECT gender, regionid , COUNT(*) AS numusers FROM pageviews_female WINDOW TUMBLING (size 30 second) GROUP BY gender, regionid HAVING COUNT(*) > 1;
exit ;
EOF"

