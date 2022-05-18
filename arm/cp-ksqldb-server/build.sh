#!/bin/bash

VERSION=7.1.1

mkdir artifacts
rsync -a /Users/avin/confluentinc/cpe/confluent-${VERSION}/share/java/ksqldb/ artifacts/

cd /Users/avin/confluentinc/kafka/src/ksql
git checkout ${VERSION}-post

rsync -a /Users/avin/confluentinc/kafka/src/ksql/bin/ ksqldb-console-scripts-${VERSION}/

cd "$(dirname "$(readlink -f "$0")")"
touch test
#docker build . -t confluentinc/cp-ksqldb-server:7.1.1.arm64
