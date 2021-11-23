#!/bin/bash

kubectl delete -f ./components.yaml
kubectl delete -f ./zk_broker.yaml
sleep 10
helm uninstall vault 
sleep 3
helm uninstall confluent-operator -n confluent
kubectl delete sa confluent-sa -n confluent
