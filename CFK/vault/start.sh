#!/bin/bash
echo
export TAG=7.0.0
export INIT_TAG=2.2.0
echo
echo "Namespace is Confluent, creating it if it's not created in kubernetes"
kubectl get ns confluent || kubectl create ns confluent
echo "Set current namespace to confluent"
kubectl config set-context --current --namespace confluent
echo "------------------------------------------"
echo
echo "-----Install postgresql-------------"
helm install postgresql stable/postgresql --set postgresqlDatabase=demo --set postgresqlPassword=postgrespass &> /dev/null
echo "Done"
echo

echo
echo "----Install Consul --------"
echo ">> Add hashicorp helm repo"
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
echo
helm install consul hashicorp/consul --set global.datacenter=vault-data --set "client.enabled=true" --set "server.replicas=1" --set "server.disruptionBudget.maxUnavailable=0" &> /dev/null
echo
echo ">> waiting for consul"
kubectl wait --for=condition=Ready pod/consul-consul-server-0 --timeout=300s -n confluent &> /dev/null
echo "Done"
echo
echo
echo "----Install vault----------------------"
helm install vault hashicorp/vault --set "server.ha.enabled=true" &> /dev/null
sleep 10
echo ">> Waiting for vault to be ready"
vault_ready=false
while [ $vault_ready == false ]
do
    kubectl logs vault-0 |grep "seal configuration missing, not initialized"  &> /dev/null
    if [ $? -eq 0 ]; then
      vault_ready=true
      echo "Vault is ready to be intialized"
    else
      echo "Waiting for vault to be ready..."
    fi
    sleep 5
done

kubectl exec vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > /tmp/cluster-keys.json
VAULT_UNSEAL_KEY=$(cat /tmp/cluster-keys.json|jq -r ".unseal_keys_b64[]")
kubectl exec vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY &> /dev/null
kubectl exec vault-1 -- vault operator unseal $VAULT_UNSEAL_KEY &> /dev/null
kubectl exec vault-2 -- vault operator unseal $VAULT_UNSEAL_KEY &> /dev/null

kubectl wait --for=condition=Ready pod/vault-0 --timeout=300s 
echo
echo
echo ">> Vault login"
VAULT_ROOT_TOKEN=$(cat /tmp/cluster-keys.json|jq -r ".root_token")
kubectl exec -it vault-0 -- sh -c "vault login - <<EOF
$VAULT_ROOT_TOKEN
EOF"
echo
echo ">> Add postgres database password to vault"
kubectl exec -it vault-0 -- sh -c "vault secrets enable -path=internal kv-v2; vault kv put internal/database/postgres password='postgrespass'"
echo
echo ">> Add keystores to vault"
kubectl cp ../certs/kafka.keystore.jks vault-0:/tmp/
kubectl cp ../certs/kafka.truststore.jks vault-0:/tmp/
kubectl cp ../certs/connect.keystore.jks vault-0:/tmp/
kubectl cp ../certs/connect.truststore.jks vault-0:/tmp/
kubectl cp ../certs/schemaregistry.keystore.jks vault-0:/tmp/
kubectl cp ../certs/schemaregistry.truststore.jks vault-0:/tmp/
kubectl exec -it vault-0 -- sh -c "vault kv put internal/keystore/jksPassword.txt password=jksPassword=confluent"
kubectl exec -it vault-0 -- sh -c 'cat /tmp/kafka.keystore.jks | base64 | vault kv put internal/keystore/kafka.keystore.jks keystore=-'
kubectl exec -it vault-0 -- sh -c 'cat /tmp/kafka.truststore.jks | base64 | vault kv put internal/keystore/kafka.truststore.jks keystore=-'
kubectl exec -it vault-0 -- sh -c 'cat /tmp/connect.keystore.jks | base64 | vault kv put internal/keystore/connect.keystore.jks keystore=-'
kubectl exec -it vault-0 -- sh -c 'cat /tmp/connect.truststore.jks | base64 | vault kv put internal/keystore/connect.truststore.jks keystore=-'
kubectl exec -it vault-0 -- sh -c 'cat /tmp/schemaregistry.keystore.jks | base64 | vault kv put internal/keystore/schemaregistry.keystore.jks keystore=-'
kubectl exec -it vault-0 -- sh -c 'cat /tmp/schemaregistry.truststore.jks | base64 | vault kv put internal/keystore/schemaregistry.truststore.jks keystore=-'
echo ">> Setup vault kubernetes auth config"
kubectl exec -it vault-0 -- sh -c 'vault auth enable kubernetes; vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
echo
echo ">> Add vault policy"
echo
kubectl exec -it vault-0 -- sh -c 'vault policy write postgres-read - <<EOF
path "internal/data/*" {
  capabilities = ["read"]
}
EOF'
echo
echo ">> Bound vault policy to service account"
kubectl exec -it vault-0 -- sh -c 'vault write auth/kubernetes/role/connect bound_service_account_names=default bound_service_account_namespaces=confluent policies=postgres-read ttl=24h'
echo
echo "----Confluent for kubernetes helm repo"
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update
echo
echo "----Install CFK ----"
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes
echo
echo "----Create service account for connect---------"
kubectl create serviceaccount connect 
echo
echo "-----Install Zookeeper and brokers-----------"
envsubst < ./zk_broker.yaml | kubectl apply -f -
echo
echo ">>Waiting for Kafka broker to be ready"
broker_pod_created=false
while [ $broker_pod_created == false ]
do
    kubectl get po kafka-0 &> /dev/null && kubectl get po kafka-1 &> /dev/null && kubectl get po kafka-2 &> /dev/null
    if [ $? -eq 0 ]; then
      broker_pod_created=true
      echo "All kafka pods are created"
    else
      echo "Waiting for kafka pods to be created..."
    fi
    sleep 5
done
kubectl wait --for=condition=Ready pod/kafka-0 --timeout=300s
kubectl wait --for=condition=Ready pod/kafka-1 --timeout=300s
kubectl wait --for=condition=Ready pod/kafka-2 --timeout=300s
echo
echo
echo "-----Install other components-------"
envsubst < ./components.yaml | kubectl apply -f -
echo ">>Waiting for Kafka Connect to be ready"
connect_pod_created=false
while [ $connect_pod_created == false ]
do
    kubectl get po connect-0 &> /dev/null 
    if [ $? -eq 0 ]; then
      connect_pod_created=true
      echo "All connect pods are created"
    else
      echo "Waiting for kafka connect pods to be created..."
    fi
    sleep 5
done
echo
echo
kubectl wait --for=condition=Ready pod/connect-0 --timeout=300s 
kubectl wait --for=condition=Ready pod/schemaregistry-0 --timeout=300s 
echo
echo
kubectl cp ../certs/ca.crt connect-0:/tmp/
echo ">>Create datagen-users connector"
kubectl exec -it connect-0 -- curl --cacert /tmp/ca.crt -X POST -H "Content-Type: application/json" https://localhost:8083/connectors/ \
--data '{
  "name": "datagen-users",
  "config": {
    "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
    "quickstart": "users",
    "name": "datagen-users",
    "kafka.topic": "users",
    "max.interval": "1000",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "tasks.max": "1",
    "iterations": "1000000000",
    "key.converter.schema.registry.url": "https://schemaregistry.confluent.svc.cluster.local:8081",
    "value.converter.schema.registry.url": "https://schemaregistry:8081",
    "value.converter.schema.registry.ssl.truststore.location": "/vault/secrets/truststore.jks",
    "value.converter.schema.registry.ssl.truststore.password": "confluent"
    }
 }'
sleep 2
echo
echo ">> Check datagen-users connector status"
kubectl exec -it connect-0 -- curl --cacert /tmp/ca.crt https://localhost:8083/connectors/datagen-users/status
echo
echo
echo "------------------------"
kubectl exec -it kafka-0 -- bash -c "cat << EOF > /tmp/client.properties
security.protocol=SSL
ssl.keystore.location=/vault/secrets/keystore.jks
ssl.keystore.password=confluent
ssl.key.password=confluent
ssl.truststore.location=/vault/secrets/truststore.jks
ssl.truststore.password=confluent
EOF"
echo
echo ">> List topics"
kubectl exec -it kafka-0 -- bash -c "kafka-topics --bootstrap-server kafka.confluent.svc.cluster.local:9071 --command-config /tmp/client.properties --list"
echo "------------------------"
echo
echo
echo ">> Create postgres jdbc connector"
kubectl exec -it connect-0 -- curl --cacert /tmp/ca.crt -X POST -H "Content-Type: application/json" https://localhost:8083/connectors/ \
--data '{
  "name": "jdbc-sink",
  "config": {
    "connector.class":"io.confluent.connect.jdbc.JdbcSinkConnector",
    "tasks.max": "1",
    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
    "value.converter":"io.confluent.connect.avro.AvroConverter",
    "key.converter.schema.registry.url":"https://schemaregistry:8081",
    "value.converter.schema.registry.url":"https://schemaregistry:8081",
    "value.converter.schema.registry.ssl.truststore.location": "/vault/secrets/truststore.jks",
    "value.converter.schema.registry.ssl.truststore.password": "confluent",
    "auto.create": "true",
    "connection.url":"jdbc:postgresql://postgresql-headless:5432/demo",
    "connection.user":"postgres",
    "connection.password":"${file:/vault/secrets/database-config.txt:password}",
    "topics": "users"
    }
 }'

echo
echo ">> Check JDBC connector status"
kubectl exec -it connect-0 -- curl --cacert /tmp/ca.crt https://localhost:8083/connectors/jdbc-sink/status
echo
echo

echo "----Check postgres database for records------------------"
echo ">> Wait for records to flow to database"
sleep 10
echo
kubectl exec -it postgresql-postgresql-0 -- bash -c "export PGPASSWORD=postgrespass; psql -P pager=off -U postgres demo -c 'select * from users'"
