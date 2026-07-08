# NUMA and Dedicated CPU Pinning for Nested Cluster VMs

## Overview

This documents how NUMA-aware dedicated CPU pinning was configured for the nested OCP cluster VMs running on the SNO (OCP 4.21). The goal is to give each VM exclusive CPU cores and ensure CPU+memory locality on the same NUMA node.

## SNO Hardware — NUMA Topology

The Dell Precision Tower 7810 has 2 NUMA nodes:

| NUMA Node | CPUs (logical) | RAM |
|---|---|---|
| node 0 | 0-17, 36-53 (36 threads) | ~78 Gi |
| node 1 | 18-35, 54-71 (36 threads) | ~78 Gi |

Total: 72 logical CPUs (2 sockets x 18 cores x 2 threads), 157 Gi RAM.

## VM Sizing

| VM | Memory | vCPUs | Role |
|---|---|---|---|
| master-0 | 24Gi | 8 | Control plane |
| master-1 | 24Gi | 8 | Control plane |
| master-2 | 24Gi | 8 | Control plane |
| worker-0 | 32Gi | 8 | Worker |

Total: 104Gi RAM, 32 vCPUs dedicated.

**Note:** 20Gi was tested for masters but caused OOM kills. With `dedicatedCpuPlacement`, the pod gets Guaranteed QoS with a hard memory limit. The virt-launcher + QEMU overhead (~2-4Gi) must fit within that limit alongside guest memory, so 24Gi is the minimum for OCP control plane nodes.

## Step 1 — KubeletConfig

File: `clusters/main/cluster-config/kubelet/kubeletconfig.yaml`

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: KubeletConfig
metadata:
  name: set-allocatable
spec:
  machineConfigPoolSelector:
    matchLabels:
      pools.operator.machineconfiguration.openshift.io/master: ""
  kubeletConfig:
    systemReserved:
      cpu: "4000m"
      memory: 8Gi
    cpuManagerPolicy: static
    cpuManagerReconcilePeriod: 5s
    topologyManagerPolicy: single-numa-node
```

Key settings:
- `cpuManagerPolicy: static` — enables exclusive CPU allocation for Guaranteed QoS pods
- `topologyManagerPolicy: single-numa-node` — ensures all resources for a pod come from the same NUMA node
- `systemReserved` — 4 cores + 8Gi set aside for OS/kubelet/crio

**Important:** The MCP selector label changed in OCP 4.21. Use `pools.operator.machineconfiguration.openshift.io/master` instead of the old `node-role.kubernetes.io/master`. Check your MCP labels with:
```bash
oc get mcp master -o jsonpath='{.metadata.labels}'
```

Apply:
```bash
oc apply -f clusters/main/cluster-config/kubelet/kubeletconfig.yaml
```

This triggers a MachineConfig render and **node reboot**. Monitor with:
```bash
oc get mcp master -w
```

## Step 2 — Enable alignCPUs in HyperConverged

File: `clusters/main/components/virtualization/instance/hyperconverged.yaml`

Set `alignCPUs: true` under `featureGates`:
```yaml
featureGates:
  alignCPUs: true
```

This ensures KubeVirt aligns vCPU threads to physical CPU topology. Apply:
```bash
oc apply -f clusters/main/components/virtualization/instance/hyperconverged.yaml
```

No reboot required — takes effect on next VM start.

## Step 3 — Update VM Specs

File: `clusters/main/nested-cluster/vms/nested-vms.yaml`

Changes per VM:
1. Add `dedicatedCpuPlacement: true` under `domain.cpu`
2. Replace `resources.requests.memory` with `memory.guest` under `domain` (required with dedicated CPUs)

Before:
```yaml
domain:
  cpu:
    cores: 8
  resources:
    requests:
      memory: 24Gi
```

After:
```yaml
domain:
  cpu:
    cores: 8
    dedicatedCpuPlacement: true
  memory:
    guest: 20Gi
```

Apply (VMs must be stopped first):
```bash
# Stop all VMs
for vm in master-0 master-1 master-2 worker-0; do
  virtctl stop $vm -n nested-cluster
done

# Wait for VMIs to terminate
oc get vmi -n nested-cluster -w

# Apply updated specs
oc apply -f clusters/main/nested-cluster/vms/nested-vms.yaml

# VMs restart automatically (runStrategy: Always)
```

## Verification

### 1. Kubelet config is active
```bash
ssh core@192.168.2.50 "sudo grep -E 'cpuManagerPolicy|topologyManagerPolicy' /etc/kubernetes/kubelet.conf"
```
Expected: `cpuManagerPolicy: static` and `topologyManagerPolicy: single-numa-node`

### 2. CPU Manager State shows pinned CPUs
```bash
ssh core@192.168.2.50 "sudo cat /var/lib/kubelet/cpu_manager_state"
```
Should show entries with dedicated CPU sets per VM pod, and `defaultCpuSet` excluding those CPUs.

### 3. Node allocatable reflects system reserved
```bash
oc get node sno.main.araclab.xyz -o jsonpath='{.status.allocatable.cpu}'
# Should be 68 (72 total - 4 reserved)

oc get node sno.main.araclab.xyz -o jsonpath='{.status.allocatable.memory}'
# Should be ~149Gi (157Gi - 8Gi reserved)
```

### 4. VMs are running with correct memory
```bash
oc get vmi -n nested-cluster -o wide
ssh core@192.168.2.62 "free -h"
# master nodes should show ~19Gi total
```

## Known Limitations

- **NUMA node selection is not controllable** — the topology manager picks which NUMA node a VM lands on. In practice, all 4 VMs may land on the same NUMA node for CPUs, with memory spilling to the other node.
- **Hugepages would improve NUMA memory alignment** — with pre-allocated hugepages, the topology manager is forced to split VMs across NUMA nodes when one node's hugepage pool is exhausted. This is a TODO for later.

## TODO

- [ ] Add hugepages (2Mi) via MachineConfig for stricter NUMA memory alignment
- [ ] Re-evaluate VM placement after hugepages are enabled
