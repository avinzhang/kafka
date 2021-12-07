Ansible Role: OpenLDAP Test Server
=========

This role install OpenLDAP server and put some data for test purpose.

Requirements
------------
None

Role Variables
--------------

| Name                      | Default value                         |        Requird       | Description                                                                 |
|---------------------------|---------------------------------------|----------------------|-----------------------------------------------------------------------------|
| temp_dir                  | /tmp/test-openldap-server             |         no           | Temp directory                                                              |
| ldap_http_port            | 389                                   |         no           | LDAP HTTP Port                                                              |
| ldap_https_port           | 636                                   |         no           | If ssl set true, LDAP HTTPS Port will be set                                |
| clean_all                 | true                                  |         no           | LDAP Data reset                                                             |
| ssl                       | false                                 |         no           | Enable SSL for LDAP Server                                                  |
| ssl_ca_cert               | ''                                    |         no           | CA Certificate. If ssl set true, this value must be set                     |
| ssl_cert                  | ''                                    |         no           | Server Certificate. If ssl set true, this value must be set                 |
| ssl_private_key           | ''                                    |         no           | Server Private Key. If ssl set true, this value must be set                 |


Dependencies
------------

None



Example Playbook
----------------
~~~
- name: Example Playbook
  hosts: ldap.example.com
  gather_facts: false

  roles:
    - { role: ldap }
~~~

Information
-----------
- LDAP Password: admin

- LDAP Bind DN: cn=admin,dc=example,dc=com

- LDAP Base DN: dc=example,dc=com

**LDAP Test Data**

|       Group     |      CN     |    OU    |    PW    |                  CN raw                    |
|-----------------|-------------|----------|----------|--------------------------------------------|
|  Administrators | Sue Jacobs  |  People  |  admin  | cn=Sue Jacobs,ou=People,dc=example,dc=com  | 
|  Administrators | Pete Minsky |  People  |  admin  | cn=Pete Minsky,ou=People,dc=example,dc=com | 
|  Developers     | Jooho Lee   |  People  |  admin  | cn=Jooho Lee,ou=People,dc=example,dc=com   |


Client Configuration
--------------------
The root-ca.cert.pem file will be found on ldap server vm

```
TLS_CACERTDIR /etc/openldap/cacerts
TLS_CACERT    /etc/openldap/certs/root-ca.cert.pem
TLS_REQCERT allow
```


Useful Commands
----------------
```

ldapadd -x -w admin -D "cn=admin,dc=example,dc=com" -f base.ldif

ldapsearch -v -H ldaps://ldap.example.com -D "cn=admin,dc=example,dc=com" -w "admin" -b "dc=example,dc=com" -o ldif-wrap=no   -vvvv

ldapmodify -h ldap.example.com -p 389 -D "cn=admin,dc=example,dc=com" -f user-passwd.ldif -w admin

ldapdelete -H ldaps://ldap.example.com -D "cn=admin,dc=example,dc=com" "cn=Sue Jacobs,ou=People,dc=example,dc=com" -w admin -vvv

```

