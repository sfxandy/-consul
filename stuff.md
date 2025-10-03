# 🔧 Safe Restart & Maintenance Process for Consul Servers

## Pre-checks
1. **Confirm quorum size**  
   Consul requires a majority of servers to maintain Raft quorum.  
   - 3 servers → quorum = 2  
   - 5 servers → quorum = 3  
   - **Never take down ≥ (N − quorum + 1) servers at the same time.**

2. **Check cluster health**  
   ```bash
   consul operator raft list-peers
   ```
   - All expected peers should show up.  
   - One peer is marked `leader`.  
   - No peers should be `stale`.

   ```bash
   consul members
   ```
   - All servers should be `alive`.  
   - Confirm datacenter is consistent.

---

## Rolling maintenance steps (per server)
⚠️ **Do this one server at a time** to preserve quorum.

1. **Pick a follower (not the leader)**  
   - Find the leader with:
     ```bash
     consul operator raft list-peers
     ```
   - Restart followers first, leave the leader until last.

2. **Drain traffic from the server (optional but safer)**  
   - Mark it ineligible for leader election:  
     ```bash
     consul operator raft remove-peer <node_id>
     ```
   - Or enable maintenance mode:  
     ```bash
     consul maint -enable -reason="Server maintenance"
     ```

3. **Stop Consul agent cleanly**  
   ```bash
   systemctl stop consul
   ```

4. **Perform your work**  
   - OS patching, Consul upgrade, config changes, etc.

5. **Restart Consul agent**  
   ```bash
   systemctl start consul
   ```
   - Watch logs:
     ```bash
     journalctl -u consul -f
     ```

6. **Verify it rejoins the cluster**  
   ```bash
   consul operator raft list-peers
   consul members
   ```
   - The restarted server should show as a voter again.  
   - Leader should remain unchanged (unless intentionally rotated).

7. **Repeat for other followers**

---

## Special case: Restarting the leader
- Do this **last**.  
- When you stop the leader, the cluster should hold a new election.  
- Verify with:
  ```bash
  consul operator raft list-peers
  ```
- Restart the old leader → verify it rejoins as a follower.  

---

## Post-maintenance validation
1. **Check Autopilot state**  
   ```bash
   consul operator autopilot state
   ```
   - All servers stable, no unhealthy peers.

2. **Check Raft index progression**  
   ```bash
   consul info | grep raft
   ```
   - `commit_index` should be moving forward.

3. **Clear maintenance mode** (if enabled).

---

## ✅ TL;DR Process
- **Check quorum → Restart one follower → Verify → Repeat → Restart leader last → Verify cluster healthy.**
