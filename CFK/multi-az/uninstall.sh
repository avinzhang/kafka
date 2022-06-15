#!/bin/bash

kubectl delete -f ./cp.yaml
sleep 10
helm uninstall confluent-operator

kubectl delete -f ./sa-rolebinding.yaml
