# 🧩 User Story
**As a** platform engineer  
**I want** to bootstrap and enable ACLs in Consul running in rootless Podman containers  
**So that** I can enforce secure, token-based access control without compromising the container-lite deployment model.

---

# ✅ Acceptance Criteria (GIVEN–WHEN–THEN Format)

## 1. ACL Bootstrap Initialization
**GIVEN** Consul server containers are running under rootless Podman  
**AND** the Consul cluster has reached a stable leader state  
**AND** the ACL system is configured but not yet bootstrapped (`"acl.enabled": true`, `"acl.default_policy": "deny"`)  
**WHEN** the operator executes  
```bash
podman exec <consul-server> consul acl bootstrap
```  
inside a Consul server container  
**THEN** a management token is generated  
**AND** the bootstrap command returns success  
**AND** the token grants full global management privileges (`operator = "write"`, unrestricted access).  

**WHEN** the bootstrap process is re-run  
**THEN** the operation is safely idempotent (either reuses or reports the existing management token without corrupting state).  

---

## 2. Token Storage and Handling
**GIVEN** the management token is generated  
**WHEN** it is persisted  
**THEN** it is stored securely outside the container filesystem (e.g., in a host-mounted secrets directory or injected via Vault, SOPS, or systemd environment files)  
**AND** the token is **not** visible in Podman logs, inspect output, or shell history.  

**WHEN** containers are restarted or replaced  
**THEN** the token remains retrievable from the designated secure storage location.  

---

## 3. Access Enforcement and Policy Validation
**GIVEN** ACLs are enabled and the bootstrap token exists  
**WHEN** an unauthenticated request is made to any Consul API or CLI endpoint  
**THEN** the request is denied with a “permission denied” response.  

**WHEN** a request is made with the management token  
**THEN** all ACL, policy, and token operations succeed.  

**WHEN** a request is made with a non-management token (e.g., an agent or service token)  
**THEN** access is restricted according to its assigned policy.  

---

## 4. System and Service Token Configuration
**GIVEN** the management token is available  
**AND** Consul client agents and service containers require access  
**WHEN** system-level tokens and policies (e.g., `agent-token`, `replication-token`, `service-token`) are created via CLI or API  
**THEN** each token has only the privileges necessary for its function  
**AND** tokens are injected into their corresponding containers through Podman environment variables or mounted configuration files  
**AND** all Consul agents successfully re-authenticate and rejoin the cluster.  

---

## 5. Automation and Documentation
**GIVEN** the ACL bootstrap and token propagation steps are scripted or containerized  
**WHEN** the bootstrap workflow runs via an automation tool (e.g., systemd service, Makefile, or shell script)  
**THEN** it completes without manual intervention  
**AND** documentation clearly outlines how to:  
- Re-bootstrap in disaster recovery situations  
- Rotate the management token  
- Redeploy containers with correct ACL tokens  

---

## 6. Validation and Observability
**GIVEN** ACLs have been enabled and tokens applied  
**WHEN** health checks and service discovery requests are executed from both servers and agents  
**THEN** Consul components report “healthy” status and expected behavior.  

**WHEN** logs and metrics are reviewed  
**THEN** ACL or token errors are visible and can be alerted on (e.g., “permission denied”, “token expired”).  

---

## 7. (Optional) Hardening & Resilience
**GIVEN** the management token exists in secure storage  
**WHEN** the token is rotated or revoked  
**THEN** updated tokens can be redeployed to containers without recreating the cluster.  

**WHEN** the cluster is rebuilt from backup or snapshots  
**THEN** the documented re-bootstrap process restores ACL functionality without manual key recovery.  
