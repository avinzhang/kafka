#!/bin/bash

echo ">>Disable resource reconciliation"
kubectl annotate connect connect platform.confluent.io/block-reconcile=true
kubectl annotate controlcenter controlcenter platform.confluent.io/block-reconcile=true
kubectl annotate kafkarest kafkarest platform.confluent.io/block-reconcile=true
kubectl annotate kafka kafka platform.confluent.io/block-reconcile=true
kubectl annotate ksqldb ksqldb platform.confluent.io/block-reconcile=true
kubectl annotate schemaregistry schemaregistry platform.confluent.io/block-reconcile=true
kubectl annotate zookeeper zookeeper platform.confluent.io/block-reconcile=true


echo 
echo 
echo ">>Check the current version for Confluent Operator"
export POD=`kubectl get pod -l app=confluent-operator -o name`
echo "Current CFK operator version: `kubectl get $POD -ojson|jq .metadata.labels.version`"
echo
echo
echo ">>Download CFK operator helm chart"
helm repo add confluentinc https://packages.confluent.io/helm &>/dev/null
helm repo update &>/dev/null
helm pull confluentinc/confluent-for-kubernetes --untar &>/dev/null

echo
echo
echo ">>Upgrade CRDs"
kubectl apply -f ./confluent-for-kubernetes/crds/
echo
echo
echo ">>Upgrade CFK operator"
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes &>/dev/null

echo ">>>>Waiting for CFK operator to be upgraded"
sleep 15
echo
echo
echo
echo ">>>>Verify the version of Confluent Operator"
export POD=`kubectl get pod -l app=confluent-operator -o name`
echo "Current CFK operator version: `kubectl get $POD -ojson|jq .metadata.labels.version`"
echo
echo
echo ">>Enable resrouce reconciliation for CP components"
kubectl annotate connect connect platform.confluent.io/block-reconcile-
kubectl annotate controlcenter controlcenter platform.confluent.io/block-reconcile-
kubectl annotate kafkarest kafkarest platform.confluent.io/block-reconcile-
kubectl annotate kafka kafka platform.confluent.io/block-reconcile-
kubectl annotate ksqldb ksqldb platform.confluent.io/block-reconcile-
kubectl annotate schemaregistry schemaregistry platform.confluent.io/block-reconcile-
kubectl annotate zookeeper zookeeper platform.confluent.io/block-reconcile-

echo
echo
echo ">>Check current inter broker protocol and log message version"
kubectl get kafka kafka -ojson|jq .spec.configOverrides.server
echo
echo
echo ">>Upgrade CP components"
echo
echo ">>>>Add broker protocol and log message"
cat << EOF > /tmp/patch.yaml 
---
apiVersion: platform.confluent.io/v1beta1
kind: Kafka
metadata:
  name: kafka
  namespace: confluent
spec:
  replicas: 3
  #license:
  #  globalLicense: true
  podTemplate:
    podSecurityContext:
      fsGroup: 1000
      runAsUser: 1000
      runAsNonRoot: true
  image:
    application: confluentinc/cp-server:$TAG
    init: confluentinc/confluent-init-container:$INIT_TAG
  dataVolumeCapacity: 10Gi
  metricReporter:
    enabled: true
  configOverrides:
    server:
      - auto.create.topics.enable=true
      - inter.broker.protocol.version=3.0
      - log.message.format.version=3.0
EOF
echo
echo ">>>> Apply the updated yaml"
export TAG=7.1.2
export INIT_TAG=2.3.1
envsubst < ./zookeeper.yaml | kubectl apply -f -
envsubst < /tmp/patch.yaml | kubectl apply -f -
envsubst < ./connect.yaml | kubectl apply -f -
envsubst < ./schemaregistry.yaml | kubectl apply -f -
envsubst < ./ksqldb.yaml | kubectl apply -f -
envsubst < ./controlcenter.yaml | kubectl apply -f -
sleep 5
kubectl rollout status sts kafka
echo
echo ">>>>Check current inter broker protocol and log message version"
kubectl get kafka kafka -ojson|jq .spec.configOverrides.server
echo
echo ">>>Change Broker protocol version and log message format version to the new version after you have done your check"
echo "    Apply the kafka component yaml again"

cat << EOF > /tmp/patch.yaml
---
apiVersion: platform.confluent.io/v1beta1
kind: Kafka
metadata:
  name: kafka
  namespace: confluent
spec:
  replicas: 3
  #license:
  #  globalLicense: true
  podTemplate:
    podSecurityContext:
      fsGroup: 1000
      runAsUser: 1000
      runAsNonRoot: true
  image:
    application: confluentinc/cp-server:$TAG
    init: confluentinc/confluent-init-container:$INIT_TAG
  dataVolumeCapacity: 10Gi
  metricReporter:
    enabled: true
  configOverrides:
    server:
      - auto.create.topics.enable=true
      - inter.broker.protocol.version=3.1
      - log.message.format.version=3.1
EOF
echo
envsubst < /tmp/patch.yaml | kubectl apply -f -
sleep 5
kubectl rollout status sts kafka
echo
echo ">>>>Check current inter broker protocol and log message version"
kubectl get kafka kafka -ojson|jq .spec.configOverrides.server
