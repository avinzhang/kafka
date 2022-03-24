#!/bin/bash

echo ">>Start 6 zookeepers in hierarchical mode and 6 brokers to simulate 2DC stretched setup"
docker-compose up -d 
echo
echo
for broker_node in kafka1 kafka2 kafka3 kafka4 kafka5 kafka6 
  do
    MDS_STARTED=false
    while [ $MDS_STARTED == false ]
    do
        docker-compose logs $broker_node | grep "Started NetworkTrafficServerConnector" &> /dev/null
        if [ $? -eq 0 ]; then
          MDS_STARTED=true
          echo "$broker_node is started and ready"
        else
          echo "Waiting for $broker_node to start..."
          sleep 3
        fi
    done
done
echo
echo "Create replica placement constraints"
cat << EOF > /tmp/placement-constraints.json
{
    "version": 2,
    "replicas": [
        {
            "count": 2,
            "constraints": {
                "rack": "DC-1A"
            }
         },
         {
            "count": 2,
            "constraints": {
                "rack": "DC-2A"
            }
        }
    ],
    "observers": [
        {
            "count": 1,
            "constraints": {
                "rack": "DC-1B"
            }
        },
        {
            "count": 1,
            "constraints": {
                "rack": "DC-2B"
            }
        }
    ],
    "observerPromotionPolicy":"under-min-isr"
}
EOF
echo ">>>Creat a topic"
kafka-topics --bootstrap-server localhost:1092 --create --topic test --partitions 2 --replica-placement /tmp/placement-constraints.json --config min.insync.replicas=3
echo
kafka-topics --bootstrap-server localhost:1092 --topic test --describe
echo
echo
#seq 1000000 | kafka-console-producer --broker-list localhost:4092 --topic test 
echo 


