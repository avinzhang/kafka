#!/bin/bash

if [ "$1" == "ksqldb" ]
then
  dig +short `kubectl get svc ksqldb-bootstrap-lb --output jsonpath='{.status.loadBalancer.ingress[0].hostname}'`|head -1
elif [ "$1" == "controlcenter" ]
then
  dig +short `kubectl get svc controlcenter-bootstrap-lb --output jsonpath='{.status.loadBalancer.ingress[0].hostname}'`|head -1
fi
