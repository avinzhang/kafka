#!/bin/bash

kubectl delete -f ./controlcenter.yaml 
kubectl delete -f ./ksqldb.yaml 
kubectl delete -f ./connect.yaml 
kubectl delete -f ./schemaregistry.yaml
sleep 20
kubectl delete -f ./kafka.yaml
kubectl delete -f ./zookeeper.yaml
sleep 30
kubectl delete secret credential sr-mds-client c3-mds-client connect-mds-client mds-client ksqldb-mds-client rest-credential mds-token tls-zookeeper tls-kafka tls-schemaregistry tls-connect tls-ksqldb tls-controlcenter

sleep 20
helm uninstall confluent-operator 
helm uninstall openldap 


