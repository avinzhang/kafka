#!/bin/bash

kubectl delete -f ./components.yaml
kubectl delete -f ./zk_broker.yaml
sleep 10
helm uninstall vault -n confluent
sleep 10
helm uninstall consul -n confluent
sleep 5
kubectl -n confluent delete pvc data-confluent-consul-consul-server-0
helm uninstall postgresql -n confluent
sleep 3
kubectl -n confluent delete pvc data-postgresql-postgresql-0
helm uninstall confluent-operator -n confluent
kubectl -n confluent delete sa connect
