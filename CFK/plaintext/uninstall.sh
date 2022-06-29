#!/bin/bash

export TAG=7.1.2
export INIT_TAG=2.3.1
envsubst < ./controlcenter.yaml | kubectl delete -f -
envsubst < ./ksqldb.yaml | kubectl delete -f -
envsubst < ./connect.yaml | kubectl delete -f -
envsubst < ./schemaregistry.yaml | kubectl delete -f -
envsubst < ./kafka.yaml | kubectl delete -f -
envsubst < ./zookeeper.yaml | kubectl delete -f -
sleep 10
helm uninstall confluent-operator
