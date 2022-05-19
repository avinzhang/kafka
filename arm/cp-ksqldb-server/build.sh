#!/bin/bash

VERSION=7.1.1


mkdir artifacts
rsync -a ~/confluentinc/cpe/confluent-${VERSION}/share/java/ksqldb/ artifacts/
#copy monitoring interceptor
cp ~/confluentinc/cpe/confluent-${VERSION}/share/java/monitoring-interceptors/* artifacts/

cd /Users/avin/confluentinc/kafka/src/ksql
git checkout ${VERSION}-post

mkdir ksqldb-console-scripts
rsync -a ~/confluentinc/kafka/src/ksql/bin/ ksqldb-console-scripts/

#docker build . -t confluentinc/cp-ksqldb-server:7.1.1.arm64
