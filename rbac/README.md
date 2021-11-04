# CP cluster with RBAC 
  * Zookeepers
    * mTls between zookeepers and brokers
    * brokers must use the same cert to connect to zookeepers
    * brokers will use sasl over mTls if both are enabled. 
