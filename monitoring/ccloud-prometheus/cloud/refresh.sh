#!/bin/bash

confluent login --save
echo
echo ">>Export api key as environment variables"
export TF_VAR_confluent_cloud_api_key=`cat ./cloud_api_key | jq -r .key`
export TF_VAR_confluent_cloud_api_secret=`cat ./cloud_api_key | jq -r .secret`
echo
echo ">> Set environment"
confluent environment use `confluent environment list -ojson | jq -r '.[]|select(.name == "avin").id'`
echo
echo ">> Set cluser"
confluent kafka cluster use `terraform output -json | jq -r '."cloud-cluster-id"."value"'`


