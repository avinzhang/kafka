# Create Cluster with PrivateLink Networking with Terraform
  * Start.sh script will create a VPC, subnets, security group, also an EC2 instance for proxy purpose within the VPC

  * Start.sh script also create a dedicated cluster with privatelink

  * start.sh script will also create the privatelink endpoint in the VPC, installs and starts a nginx proxy
  
  * Add the cluster endpoint to your hosts and have it pointing to the public IP of the proxy
    ```
    x.x.x.x lkaclkc-zmzqmy-6wr39g.ap-southeast-2.aws.glb.confluent.cloud lkc-zmzqmy-6wr39g.ap-southeast-2.aws.glb.confluent.cloud
    ```

  * You can create cluster api key, role bindings 
