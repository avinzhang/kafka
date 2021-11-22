#!/bin/bash

dig +short `kubectl get svc nginx-ingress-controller --output jsonpath='{.status.loadBalancer.ingress[0].hostname}'`|head -1
