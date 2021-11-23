ui = true


storage "file" {
  path = "/opt/vault/data"
}


# HTTP listener
listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = 1
}
