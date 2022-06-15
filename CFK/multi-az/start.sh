#!/bin/bash 

export TAG=7.1.0
export INIT_TAG=2.3.0
echo "Starting up Confluent for Kubernetes"
echo
echo
echo "Creating namespace Confluent if it's not created in kubernetes"
kubectl get ns confluent || kubectl create ns confluent
echo "Set current namespace to confluent"
kubectl config set-context --current --namespace confluent
echo
echo "------------------------------------------"
echo
echo "Add helm repo"
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update

echo 
echo "---------------------------------------"
echo
echo "Apply service account role binding"
kubectl apply -f ./sa-rolebinding.yaml
echo
echo "Install confluent for kubernetes"
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes
echo
echo
echo "Install Confluent Platform components"
envsubst < ./cp.yaml | kubectl apply -f -
echo 
export pod_created=false
while [ $pod_created == false ]
do
    kubectl get po kafka-0 &> /dev/null
    if [ $? -eq 0 ]; then
      pod_created=true
      echo ">>>>All kafka pods are created"
    else
      echo ">>>>Waiting for kafka pods to be created"
    fi
    sleep 5
done
echo
echo
echo "Check AZ details for nodes"
kubectl get nodes --label-columns failure-domain.beta.kubernetes.io/region,failure-domain.beta.kubernetes.io/zone
echo
kubectl wait --for=condition=Ready pod/kafka-0 --timeout=400s
kubectl wait --for=condition=Ready pod/kafka-1 --timeout=400s
kubectl wait --for=condition=Ready pod/kafka-0 --timeout=400s
echo
echo "Check which node broker pods are running on"
kubectl get po -l app=kafka -o wide
