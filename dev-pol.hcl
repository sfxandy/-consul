# Catalog read: nodes + services
node_prefix "" {
  policy = "read"
}

service_prefix "" {
  policy = "read"
}

# Services with a "service-reg" prefix: write access
service_prefix "service-reg" {
  policy = "write"
}

# KV: write access under "service-reg/"
key_prefix "service-reg/" {
  policy = "write"
