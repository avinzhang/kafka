#this is not automated script, just a readme file on the steps that should be performed to get it working


#SETUP external vault
#Create a VM on aws

VAULT_HOST="Vault_server"

echo "Add vault yum repo"
ssh centos@$VAULT_HOST sudo yum install -y yum-utils
ssh centos@$VAULT_HOST sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
echo "Install vault"
ssh centos@$VAULT_HOST sudo yum install vault -y
echo "Install epel"
ssh centos@$VAULT_HOST sudo yum install epel-release -y
echo "Install jq"
ssh centos@$VAULT_HOST sudo yum install jq -y

echo "Copy vault.hcl to vault host"
scp vault.hcl centos@@$VAULT_HOST:/tmp/vault.hcl
ssh centos@$VAULT_HOST sudo cp /tmp/vault.hcl /etc/vault.d/
ssh centos@$VAULT_HOST sudo chown vault:vault /etc/vault.d/vault.hcl

echo "Start vault with provided vault.hcl"
systemctl start vault

echo "Initialize vault on the vault server"
vault operator init -key-shares=1 -key-threshold=1 -format=json > /tmp/cluster-keys.json
VAULT_UNSEAL_KEY=$(cat /tmp/cluster-keys.json|jq -r ".unseal_keys_b64[]")
echo "Unseal vault"
vault operator unseal $VAULT_UNSEAL_KEY

VAULT_ROOT_TOKEN=$(cat /tmp/cluster-keys.json|jq -r ".root_token")
vault login - <<EOF
$VAULT_ROOT_TOKEN
EOF

echo "Add postgres secret to vault"
vault secrets enable -path=secret kv-v2
vault kv put secret/database/postgres password='postgrespass'

helm install vault hashicorp/vault --set "injector.externalVaultAddr=http://$VAULT_HOST:8200"

VAULT_HELM_SECRET_NAME=$(kubectl get secrets --output=json | jq -r '.items[].metadata | select(.name|startswith("vault-token-")).name')
echo $VAULT_HELM_SECRET_NAME
kubectl get secret $VAULT_HELM_SECRET_NAME --output='go-template={{ .data.token }}' | base64 --decode > /tmp/TOKEN_REVIEW_JWT
scp /tmp/TOKEN_REVIEW_JWT centos@$VAULT_HOST:/tmp/

kubectl config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.certificate-authority-data}' | base64 --decode > /tmp/KUBE_CA_CERT
scp /tmp/KUBE_CA_CERT centos@$VAULT_HOST:/tmp/

kubectl config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.server}' > /tmp/KUBE_HOST
scp /tmp/KUBE_HOST centos@$VAULT_HOST:/tmp/

vault auth enable kubernetes
vault write auth/kubernetes/config \
        token_reviewer_jwt=@/tmp/TOKEN_REVIEW_JWT \
        kubernetes_host=@/tmp/KUBE_HOST \
        kubernetes_ca_cert=@/tmp/KUBE_CA_CERT 


echo "Add vault policy"
vault policy write confluent-app-policy - <<EOF
path "secret/data/database/*" {
  capabilities = ["read", "list"]
}
EOF

vault write auth/kubernetes/role/confluent-role \
        bound_service_account_names=confluent-sa \
        bound_service_account_namespaces=confluent \
        policies=confluent-app-policy \
        ttl=24h

kubectl -n confluent create sa confluent-connect
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes -n confluent
kubectl apply -f ./zk_broker.yaml
kubectl apply -f ./components.yaml
