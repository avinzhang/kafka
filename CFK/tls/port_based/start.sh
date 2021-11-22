#!/bin/bash -e
#supports up to kubernetes 1.18 only

export TAG=7.0.0
export INIT_TAG=2.2.0
echo
echo
echo "Namespace is confluent, creating it if it's not created in kubernetes"
kubectl get ns confluent || kubectl create ns confluent
echo
echo "Set current namespace to confluent"
kubectl config set-context --current --namespace confluent
echo "------------------------------------------"
echo
echo "Add helm repo"
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update

echo 
echo "---------------------------------------"
echo
echo
echo "Install confluent for kubernetes"
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes
echo
sleep 5
echo "Done"
echo
echo "---------------------------------------"
echo "Setup various secrets" 
echo 
echo ">>Create SSL secrets"
# For auto generated SSL certs only
#echo "Generate SSL CA"
#openssl genrsa -out /tmp/ca-key.pem 2048
#openssl req -new -key /tmp/ca-key.pem -x509 -days 1000 -out /tmp/ca.pem -subj '/CN=ca.cse.example.com/OU=CSE/O=CONFLUENT/L=MountainView/ST=Ca/C=US'
#
#echo "Add CA as a secret"
#kubectl -n confluent create secret tls ca-pair-sslcerts \
#  --cert=/tmp/ca.pem \
#  --key=/tmp/ca-key.pem
#
# To use your own SSL certs
echo "Setup TLS secrets for each component"
for i in zookeeper kafka connect schemaregistry ksqldb controlcenter
  do
    echo ">>>>>Creating secret tls-$i"
    kubectl create secret generic tls-$i \
    --from-file=fullchain.pem=../../certs/$i-ca1-signed.crt \
    --from-file=cacerts.pem=../../certs/ca.crt \
       --from-file=privkey.pem=../../certs/$i.key
done
echo
echo
echo "-----------------------------------------"
echo "Install zookeeper"
envsubst < ./zookeeper.yaml | kubectl apply -f -
sleep 20
echo "Wait for zookeeper pods"
kubectl wait --for=condition=Ready pod/zookeeper-0 --timeout=300s -n confluent
kubectl wait --for=condition=Ready pod/zookeeper-1 --timeout=300s -n confluent
kubectl wait --for=condition=Ready pod/zookeeper-2 --timeout=300s -n confluent
echo
echo 
echo "----------------------------------------"
echo "Install kafka broker"
envsubst < ./kafka.yaml | kubectl apply -f -
echo
echo
echo ">>Waiting for kafka pods to be created"
kafka_pod_created=false
while [ $kafka_pod_created == false ]
do
    kubectl get po kafka-0 &> /dev/null && kubectl get po kafka-1 &> /dev/null && kubectl get po kafka-2 &> /dev/null
    if [ $? -eq 0 ]; then
      kafka_pod_created=true
      echo ">>>>All kafka pods are created"
    else
      echo ">>>>Not all kafka pods are created..."
    fi
    sleep 5
done
echo
echo ">>>>Waiting for kafka pods to come up"
kubectl wait --for=condition=Ready pod/kafka-0 --timeout=600s 
kubectl wait --for=condition=Ready pod/kafka-1 --timeout=600s
kubectl wait --for=condition=Ready pod/kafka-2 --timeout=600s 
echo
echo
echo ">>Adding ssl client.properties to kafka-0 pod"
kubectl -n confluent exec -it kafka-0 -- bash -c 'cat << EOF > /tmp/client.properties
security.protocol=SSL
ssl.truststore.location=/mnt/sslcerts/truststore.jks
ssl.truststore.password=mystorepassword
EOF'
echo "Done"
echo 
echo "Install ingress controller for mapping kafka broker serivces"
helm upgrade --install nginx-ingress stable/nginx-ingress \
  --set controller.ingressClass=kafka \
  --set tcp.9094="confluent/kafka-0-internal:9092" \
  --set tcp.9095="confluent/kafka-1-internal:9092" \
  --set tcp.9096="confluent/kafka-2-internal:9092" \
  --set tcp.9093="confluent/kafka-bootstrap:9092"
echo 
kubectl get cm nginx-ingress-tcp
echo 
echo
echo "Install ingress resource for routing traffic"
kubectl apply -f ./ingress-postbased.yaml
echo
# Setup DNS for broker.mycfk.com
#kafka-topics --bootstrap-server broker.mycfk.com:9093 --list --command-config client.properties
