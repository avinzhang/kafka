#!/bin/bash

docker run -it confluentinc/cp-ksqldb-cli:$TAG -u $ksql_api_key -p $ksql_api_secret $ksql_endpoint
