# Setup RBAC cluster
  * Use ldap playbook to setup a ldap server

  * If using self-signed certs
    * Create CA, have to comment out "regenerate_ca: false, regenerate_keystore_and_truststore: false" in the hosts yml for the first run to generate CA.
    ```
    ansible-playbook -vv -i ../rbac/hosts_self_signed_certs.yml all.yml --tags=certificate_authority
    ```
    * Install zookeeper
    ```
    ansible-playbook -vv -i ../rbac/hosts_self_signed_certs.yml all.yml --tags=zookeeper
    ```
    * Install broker
    ```
    ansible-playbook -vv -i ../rbac/hosts_self_signed_certs.yml all.yml --tags=kafka_broker
    ```
    * Install other components
    ```
    ansible-playbook -vv -i ../rbac/hosts_self_signed_certs.yml all.yml --tags=schema_registry
    ansible-playbook -vv -i ../rbac/hosts_self_signed_certs.yml all.yml --tags=kafka_connect
    ansible-playbook -vv -i ../rbac/hosts_self_signed_certs.yml all.yml --tags=ksql
    ansible-playbook -vv -i ../rbac/hosts_self_signed_certs.yml all.yml --tags=kafka_rest
    ansible-playbook -vv -i ../rbac/hosts_self_signed_certs.yml all.yml --tags=control_center
    ``` 



  * Using provided certs
    * Install cluster
      ```
      ansible-playbook -vv -i ../rbac/hosts_provided_certs.yml all.yml --tags=zookeeper
      ansible-playbook -vv -i ../rbac/hosts_provided_certs.yml all.yml --tags=kafka_broker
      ansible-playbook -vv -i ../rbac/hosts_provided_certs.yml all.yml --tags=schema_registry
      ansible-playbook -vv -i ../rbac/hosts_provided_certs.yml all.yml --tags=kafka_connect
      ansible-playbook -vv -i ../rbac/hosts_provided_certs.yml all.yml --tags=ksql
      ansible-playbook -vv -i ../rbac/hosts_provided_certs.yml all.yml --tags=kafka_rest
      ansible-playbook -vv -i ../rbac/hosts_provided_certs.yml all.yml --tags=control_center
      ```

    * Port forward C3 port to your localhost
      ```
      ssh -L localhost:9021:controlcenter.example.com:9021 centos@controlcenter.example.com
      ```

    * kafka_rest user requires permission to `_confluen-monitoring` topic
      ```
      confluent iam rolebinding create --kafka-cluster-id dzBCZ3qDS9Wa7aIwnDULPQ --principal User:restproxy --role ResourceOwner --resource Topic:_confluent-monitoring
      ```


# Install tools on the broker node
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum -y install jq curl 
    
# Setup user1 roles
    ```
    scp ../certs/ca.crt centos@kafka1.example.com:/tmp

    confluent login --url https://kafka1.example.com:8090 --ca-cert-path /tmp/ca.crt
    
    export KAFKA_CLUSTER_ID=$(curl -sik https://kafka1.example.com:8090/v1/metadata/id |grep id |jq -r ".id")

    confluent iam rolebinding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:user1 --role ClusterAdmin

    confluent iam rolebinding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:user1 --role ClusterAdmin --connect-cluster-id connect-cluster

    confluent iam rolebinding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:user1 --role ClusterAdmin --schema-registry-cluster-id schema-registry

    confluent iam rolebinding create --kafka-cluster-id $KAFKA_CLUSTER_ID --principal User:user1 --role ClusterAdmin --ksql-cluster-id ksql-server
    ```



