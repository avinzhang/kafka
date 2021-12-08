* Deploy EC2 instances
  * edit group_vars/all
    e.g.  Setting exact_count to 5 will deploy 5 EC2 instances
  * Run playbook
  ```
  ansible-playbook -vv deploy_ec2.yaml
  ```

* List all instances 
  ```
  ansible-inventory  --graph
  ```

* List all  groups
  ```
  ansible localhost -m debug -a 'var=groups'
  ```

* Remove package from all hosts
  ```
  ansible all --become  --become-user root -u centos -m yum -a "name=confluent* state=absent"
  ansible all --become  --become-user root -u centos -m file -a "path=/etc/kafka state=absent"
  ```
