#!/bin/bash

kubectl delete -f ./kafka.yaml
kubectl delete -f ./zookeeper.yaml
sleep 20
#kubectl delete secret ca-pair-sslcerts

kubectl delete secret tls-zookeeper tls-kafka tls-schemaregistry tls-connect tls-ksqldb tls-controlcenter

kubectl delete -f ./ingress-portbased.yaml
sleep 10 
helm uninstall confluent-operator

helm uninstall nginx-ingress

