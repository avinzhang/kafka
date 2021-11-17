#!/bin/bash

kubectl delete -f ./plaintext-2.2.0.yaml
sleep 10
helm uninstall confluent-operator
