# admin.hcl — broad admin without infra-destructive powers
# Catalog / Services / Nodes / Health / Prepared queries
node_prefix    "" { policy = "write" }
service_prefix "" { policy = "write" intentions = "write" }
query_prefix   "" { policy = "write" }

# Agent utility endpoints (join/leave, checks/services via agent)
agent_prefix   "" { policy = "write" }

# Sessions, KV, Events
session_prefix "" { policy = "write" }
key_prefix     "" { policy = "write" }
event_prefix   "" { policy = "write" }

# Mesh & config entries (service-defaults, proxy-defaults, gateways, etc.)
# Include this if you use Consul service mesh:
mesh = "write"

# ACL system (pick one):
# - If your “admin” should manage tokens/policies, give write:
# acl = "write"
# - If they should only read/audit ACLs, use:
acl = "read"

# Cluster-level stuff (safer defaults):
operator = "read"   # diagnostics ok, no mutating ops
# keyring = "read"  # (optional) read-only gossip key status; omit if not needed





# Full control over ACL objects, nothing else
acl = "write"
