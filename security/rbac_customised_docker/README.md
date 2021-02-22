* To start everything
```
./start.sh
```

* LDAP Notes

Permission access levels from most (top) to least (bottom)
write
read
search
compare
auth
none

ACLs are evaluated on a "first match wins" basis. An ACL listed first takes precedence over ACLs mentioned later. This means that more restrictive ACLs should be listed prior to more general ones.
