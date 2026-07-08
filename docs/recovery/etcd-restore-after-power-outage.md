# Recovering SNO etcd After Power Outage

**Date:** 2026-03-12
**Cluster:** SNO (`main.araclab.xyz`)
**Root Cause:** Unclean shutdown from power outage

> Current install note: the SNO OS disk is the Samsung 990 PRO at `nvme1n1`. Older
> recovery notes might mention `nvme0n1`; verify with `lsblk` before running repairs.

## Symptoms

- Node was pingable but OpenShift API (port 6443) not responding
- `xfs_repair` was needed to mount `/sysroot`
- After filesystem repair, kubelet started but etcd crash-looped (200+ restarts)
- kube-apiserver couldn't connect to etcd on port 2379 (TLS handshake failures)
- etcd logs showed: `"failed to publish local member to cluster through raft"` with repeated timeouts
- etcd WAL file marked as `.wal.broken`

## Recovery Steps

### 1. Fix XFS Filesystem

From emergency shell (physical console required):

```bash
xfs_repair /dev/nvme1n1p4
# If it says filesystem is mounted:
xfs_repair -L /dev/nvme1n1p4   # WARNING: zeros the journal log
reboot -f
```

### 2. Diagnose etcd

```bash
ssh core@192.168.2.50

# Check etcd status
sudo crictl ps -a --name "^etcd$"

# Check etcd logs
CONT=$(sudo crictl ps -a --name "^etcd$" -q | head -1)
sudo crictl logs $CONT 2>&1 | tail -30

# Check if API server can reach etcd
curl -sk https://localhost:6443/readyz

# Check etcd port - high Recv-Q means etcd is stuck
ss -tlnp | grep 2379
```

### 3. Create Backup Material

OpenShift's `cluster-restore.sh` needs two files:
1. An etcd snapshot (`.db`)
2. A static pod resources tarball

Since we had no proper backup, we used the raw etcd bbolt database:

```bash
sudo mkdir -p /home/core/backup

# Copy the etcd db file as a snapshot
sudo cp /var/lib/etcd/member/snap/db /home/core/backup/snapshot_$(date +%F).db

# Create static pod resources tarball (path inside tar must be "static-pod-resources/")
sudo tar czf /home/core/backup/static_kuberesources_$(date +%F).tar.gz \
  -C /etc/kubernetes static-pod-resources/
```

### 4. Run cluster-restore.sh

```bash
sudo /usr/local/bin/cluster-restore.sh /home/core/backup
```

If the script hangs waiting for etcd container to stop:

```bash
# From another terminal
sudo crictl stopp <pod-id> && sudo crictl rmp <pod-id>
```

### 5. Fix "snapshot missing hash" Error

The raw db file doesn't have a hash like a proper `etcdctl snapshot save` output.
Edit the restore pod manifest to add `--skip-hash-check`:

```bash
sudo sed -i 's|snapshot restore "${SNAPSHOT_FILE}"|snapshot restore "${SNAPSHOT_FILE}" --skip-hash-check|' \
  /etc/kubernetes/manifests/etcd-pod.yaml
```

### 6. Ensure /var/lib/etcd is Empty

The restore pod checks that `/var/lib/etcd` is completely empty before restoring:

```bash
sudo rm -rf /var/lib/etcd/*
sudo systemctl restart kubelet
```

### 7. Move Restored Data

The restore pod creates data in `/var/lib/etcd/restore-<uuid>/member/`.
It should auto-move it to `/var/lib/etcd/member/`, but if it doesn't:

```bash
sudo mv /var/lib/etcd/restore-*/member /var/lib/etcd/member
sudo rm -rf /var/lib/etcd/restore-*
```

### 8. Get Working Kubeconfig

After restore, the old kubeconfig may be rejected. Get a fresh one from the node:

```bash
ssh core@192.168.2.50 \
  "sudo cat /etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/lb-ext.kubeconfig" \
  2>/dev/null | grep -v "WARNING\|vulnerable\|upgraded\|openssh" > kubeconfig-sno
```

### 9. Wait for Stabilization

After restore, the cluster needs 5-15 minutes to fully reconcile.
Cluster operators will show errors/progressing during this time.

## Key Files on the Node

| Path | Purpose |
|---|---|
| `/var/lib/etcd/member/` | etcd data directory |
| `/var/lib/etcd/member/wal/` | Write-ahead log |
| `/var/lib/etcd/member/snap/db` | bbolt database |
| `/var/lib/etcd-backup/` | Backup location used by restore script |
| `/etc/kubernetes/manifests/etcd-pod.yaml` | etcd static pod manifest |
| `/usr/local/bin/cluster-backup.sh` | Creates etcd backup |
| `/usr/local/bin/cluster-restore.sh` | Restores etcd from backup |

## Prevention

- **Get a UPS** - even a small one ($50-80) prevents unclean shutdowns
- **Run regular backups:**
  ```bash
  sudo /usr/local/bin/cluster-backup.sh /home/core/etcd-backup-$(date +%F)
  ```
- Consider a cron job for automated etcd backups

## Lessons Learned

1. Always take etcd backups - without one, recovery is much harder
2. The raw `snap/db` file can be used as a snapshot but needs `--skip-hash-check`
3. `cluster-restore.sh` expects `/var/lib/etcd` to be completely empty
4. The static pod resources tarball path must be `static-pod-resources/` (not `etc/kubernetes/static-pod-resources/`)
5. After restore, old kubeconfigs may not work - get a fresh one from the node
6. Don't move the WAL directory manually - it changes etcd's initialization state
