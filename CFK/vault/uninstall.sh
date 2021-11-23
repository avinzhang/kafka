#!/bin/bash

kubectl delete -f ./components.yaml
kubectl delete -f ./zk_broker.yaml
sleep 10
helm uninstall vault
sleep 10
helm uninstall consul
sleep 5
kubectl delete pvc data-confluent-consul-consul-server-0
helm uninstall postgresql
sleep 3
kubectl delete pvc data-postgresql-postgresql-0
helm uninstall confluent-operator 
kubectl delete sa connect
