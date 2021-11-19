#!/bin/bash

dig +short `kubectl get ing ingress-with-sni --output jsonpath='{.status.loadBalancer.ingress[0].hostname}'`|head -1
