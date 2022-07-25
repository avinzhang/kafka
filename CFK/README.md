# Create kubernetes cluster 
  * EKS
    * Install brew tap for eksctl
    ```
    brew install weaveworks/tap/eksctl
    ```
    * Install eksctl command
    ```
    brew install eksctl
    ```
    * Setup aws API key
    ```
    aws configure
    ```
    * Create cluster with eksctl, the provisioning process will take a while
    ```
     eksctl create cluster \
     --version 1.22 \
     --name avin-eks \
     --region ap-southeast-2 \
     --nodegroup-name eks-ng \
     --node-type t3.xlarge \
     --nodes 0 \
     --nodes-min 0 \
     --nodes-max 12 \
     --ssh-access \
     --ssh-public-key ~/.ssh/id_rsa.pub \
     --managed \
     --node-private-networking \
     --zones ap-southeast-2a,ap-southeast-2b,ap-southeast-2c \
     --verbose 3 \
     --tags owner_email=$OWNER_EMAIL
    ```
    * Delete the cluster
    ```
    eksctl delete cluster --name avin-eks
    ```
    * Scale down nodegroup to 0
    ```
    eksctl scale nodegroup --cluster=avin-eks --nodes=0 --nodes-min=0 --name=eks-ng
    ```
    * Write credential to kubeconfig
    ```
    eksctl utils write-kubeconfig --cluster=avin-eks
    ```

  * AKS
    * Install azure cli
    ```
    brew install azure-cli
    ```
    * Authenticate with azure cli
    ```
    az login
    ```
    * Create an resource group
    ```
    az group create --name avingroup --location australiaeast
    ```
    * Create your AKS cluster
    ```
    az aks create --resource-group avingroup --name avin-aks-cluster --node-count 6 --kubernetes-version 1.19.9
    ```
    * Setup kube config for your cluster
    ```
    az aks get-credentials --name avin-aks-cluster --resource-group avingroup
    ```
    * Delete cluster
    ```
    az aks delete --name avin-aks-cluster --resource-group avingroup
    ```

  * GKE 
    * Install gcloud cli
    ```
    brew install --cask google-cloud-sdk
    ```
    * setup authentication to GCP
    ```
    gcloud auth login
    ```
    * Create cluster
    ```
    gcloud container clusters create avin-gke-cluster \
      --zone australia-southeast1-a \
      --node-locations australia-southeast1-a,australia-southeast1-b,australia-southeast1-c \
      --cluster-version 1.18 \
      --num-nodes=2 \
      --enable-autoscaling \
      --min-nodes 2 --max-nodes 12 \
      --scopes=service-control,service-management,compute-rw,storage-ro,cloud-platform,logging-write,monitoring-write,pubsub,datastore,"https://www.googleapis.com/auth/ndev.clouddns.readwrite"
    ```

    * Delete cluster
    ```
    gcloud container clusters delete avin-gke-cluster --zone australia-southeast1-a --quiet
    ```


# Remove a cluster from kubeconfig
  * remove user
  ```
  kubectl config unset <users.xxxx>
  ```
  * remove cluster
  ```
  kubectl config delete-cluster xxxxx
  ```
  * remove context
  ```
  kubectl config delete-context xxxx
  ```
# Rename context
  * Rename context name
  ```
  kubectl config rename-context oldname newname
  ```

# Install a specific version of CFK
  * Latest version from helm repo
  ```
  helm search repo confluentinc/confluent-for-kubernetes
  ```
  * All available versions
  ```
  helm search repo -l confluentinc/confluent-for-kubernetes
  ```
  * Install a specific version of CFK
  ```
  helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes --version="0.304.2"
  ```

# Useful commands
  * Get nodes with region and zones
  ```
  kubectl get node --label-columns failure-domain.beta.kubernetes.io/region,failure-domain.beta.kubernetes.io/zone
  ```
  * Get all CRD version
  ```
  kubectl get crd -o=jsonpath="{range .items[*]}{.metadata.name}{'|| \tcontroller-gen.kubebuilder.io/version\t ||'}{.metadata.annotations.controller-gen\.kubebuilder\.io/version}{\"\n\"}{end}" | grep -i confluent
  ```
