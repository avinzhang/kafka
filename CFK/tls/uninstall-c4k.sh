#!/bin/bash

kubectl delete -f ./controlcenter.yaml 
kubectl delete -f ./ksqldb.yaml 
kubectl delete -f ./connect.yaml 
kubectl delete -f ./schemaregistry.yaml
sleep 20
kubectl delete -f ./kafka.yaml
kubectl delete -f ./zookeeper.yaml
sleep 30
#kubectl delete secret ca-pair-sslcerts

kubectl delete secret credential tls-zookeeper tls-kafka tls-schemaregistry tls-connect tls-ksql tls-controlcenter

sleep 20
helm uninstall confluent-operator


