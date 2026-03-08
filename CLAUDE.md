# Homelab Project Context

## Overview
This repo manages a homelab running OpenShift on a Dell Precision Tower 7810 (160GB RAM).
All infrastructure is managed via GitOps with ArgoCD (OpenShift GitOps operator).
GitHub repo: https://github.com/Chanoian/homelab

## Architecture
- **Bare metal SNO:** OCP 4.21 at `main.araclab.xyz` (192.168.2.50)
- **Nested multi-node cluster:** OCP 4.21 on OpenShift Virtualization at `nested.araclab.xyz`
  - 3 control planes + 1 worker running as VMs on OpenShift Virt
  - Installed using agent-based installer (`openshift-install agent create image`)
- **CoreDNS:** Raspberry Pi at 192.168.2.51
- **Gateway:** 192.168.2.1
- **Subnet:** 192.168.2.0/24 (flat, no VLAN)

## Nested Cluster — IP Allocation

| Role | FQDN | IP |
|---|---|---|
| API VIP | api.nested.araclab.xyz | 192.168.2.60 |
| Ingress VIP | *.apps.nested.araclab.xyz | 192.168.2.61 |
| Control Plane 1 | cp1.nested.araclab.xyz | 192.168.2.62 |
| Control Plane 2 | cp2.nested.araclab.xyz | 192.168.2.63 |
| Control Plane 3 | cp3.nested.araclab.xyz | 192.168.2.64 |
| Worker 1 | worker1.nested.araclab.xyz | 192.168.2.65 |

## Nested Cluster — VM Resources

| VM | RAM | vCPUs | Root Disk | Storage Class |
|---|---|---|---|---|
| master-0 | 24Gi | 8 | 120Gi | lvms-fast-ssd-pool |
| master-1 | 24Gi | 8 | 120Gi | lvms-fast-ssd-pool |
| master-2 | 24Gi | 8 | 120Gi | lvms-fast-ssd-pool |
| worker-0 | 32Gi | 8 | 200Gi | lvms-fast-ssd-pool |

## Networking — CRITICAL DETAILS

### Single NIC Setup
- Physical NIC: `enp0s25` attached to OVS bridge `br-ex`
- OVS bridge mapping: `physnet:br-ex` (already configured)
- VMs use **OVN localnet topology** to get L2 access to 192.168.2.0/24
- NetworkAttachmentDefinition: `localnet-physnet` in namespace `nested-cluster`
- The NAD config `name` field MUST be `"physnet"` (matching the OVS bridge mapping key), NOT the NAD resource name
- There is also a `br-lab` Linux bridge on the node but it is UNUSED and has nothing attached
- NMState operator is installed on the SNO

### VM Interface
- Interface name inside VMs: `enp1s0` (confirmed via guest agent)
- VMs use bridge binding on the localnet NAD
- VMs are configured with localnet ONLY (no pod network / masquerade)

### MAC Address Issue — CURRENT PROBLEM
The agent ISO was generated with these MACs in agent-config.yaml:
- master-0: 02:7c:71:f2:81:4b
- master-1: 02:7c:71:f2:81:4c
- master-2: 02:7c:71:f2:81:4d
- worker-0: 02:7c:71:f2:81:4e

But when VMs were recreated in the `nested-cluster` namespace, KubeVirt assigned NEW random MACs.
The VM specs do NOT have macAddress pinned, so the agent ISO static IP config doesn't match.
**FIX NEEDED:** Pin the MACs in the VM specs to match the agent ISO: 02:7c:71:f2:81:4b through 4e.
This requires: stop VMs → update VM specs with macAddress field → restart VMs.

## Storage

| Device | Size | Purpose | Storage Class |
|---|---|---|---|
| NVMe1 | 512 GB | SNO bare metal OS (RHCOS) | — |
| NVMe2 | 1 TB | Nested cluster VM disks | lvms-fast-ssd-pool (default) |
| SATA SSD #1 | TBD | Image registry (main cluster) | local-sata-registry |
| SATA SSD #2 | TBD | Future use | — |

### Storage Classes
- `lvms-fast-ssd-pool` (default) — LVM Storage on NVMe2, WaitForFirstConsumer
- `local-sata-registry` — Local Storage on SATA SSD #1, WaitForFirstConsumer
- DataVolumes with `WaitForFirstConsumer` need annotation `cdi.kubevirt.io/storage.bind.immediate.requested: "true"` for upload or immediate binding

## Namespaces

| Namespace | Purpose |
|---|---|
| `nested-cluster` | VMs, root disks, NAD, agent ISO PVC — all nested cluster runtime resources |
| `nested-openshift-os-images` | OLD namespace, was used before migration. Should be cleaned up. |

## Installed Operators on SNO
- OpenShift Virtualization (openshift-cnv)
- Kubernetes NMState Operator (4.21)
- LVM Storage (lvms-fast-ssd-pool)
- Local Storage Operator (local-sata-registry)
- OpenShift GitOps — NOT YET INSTALLED

## Agent-Based Installer Config

### install-config.yaml
- baseDomain: araclab.xyz
- metadata.name: nested
- networking: OVNKubernetes
- clusterNetwork: 10.128.0.0/14, hostPrefix 23
- serviceNetwork: 172.30.0.0/16
- machineNetwork: 192.168.2.0/24
- 3 control plane replicas, 1 worker replica
- platform: none
- Needs pull secret and SSH public key

### agent-config.yaml
- rendezvousIP: 192.168.2.62
- Interface name: enp1s0 on all hosts
- DNS server: 192.168.2.51
- Gateway: 192.168.2.1
- Static IPs mapped by MAC address (see MAC Address Issue above)

## Current State (as of conversation)

### What's Working
- SNO is healthy and running OCP 4.21
- OpenShift Virt is installed and functional
- NAD `localnet-physnet` created in `nested-cluster` namespace
- 4 VMs running in `nested-cluster` namespace
- Agent ISO uploaded to `nested-cluster` namespace via virtctl
- Root disks created on lvms-fast-ssd-pool
- VMs boot from agent ISO and reach DHCP

### What's NOT Working
- VMs get DHCP IPs instead of static IPs (MAC mismatch)
- Agent installer can't reach quay.io (likely DNS/routing issue due to wrong IPs)
- MAC addresses in VM specs are not pinned to match agent ISO config

### Next Steps (in order)
1. **Pin MAC addresses in VM specs** — add macAddress field matching agent ISO config
2. **Stop VMs, apply updated specs, restart** — VMs should get correct static IPs
3. **Verify static IPs** — ping 192.168.2.62-65
4. **Monitor agent installer progress** — should pull images from quay and install
5. **Add CoreDNS records** for nested.araclab.xyz if not already done
6. **Install OpenShift GitOps** on SNO
7. **Set up ArgoCD app-of-apps** to manage all manifests from this repo
8. **Configure image registry** on SATA SSD #1

## Key Commands
```bash
# Access SNO node
ssh core@192.168.2.50

# Check nested cluster VMs
oc get vms -n nested-cluster
oc get vmi -n nested-cluster -o wide

# VM console access
virtctl console <vm-name> -n nested-cluster
virtctl vnc <vm-name> -n nested-cluster

# Check networking
oc get net-attach-def -n nested-cluster
oc debug node/sno.main.araclab.xyz -- chroot /host ovs-vsctl get Open_vSwitch . external-ids:ovn-bridge-mappings

# Check storage
oc get dv -n nested-cluster
oc get pvc -n nested-cluster
oc get sc

# Agent installer logs (once VMs are booting correctly)
# SSH into a node and run:
journalctl -u agent -f

# ArgoCD (once installed)
oc get applications -n openshift-gitops
```

## CDI Upload Notes
- `virtctl image-upload` from Mac works (used to upload agent ISO)
- Upload proxy route: https://cdi-uploadproxy-openshift-cnv.apps.main.araclab.xyz
- Uploading from the SNO node via curl had connection reset issues
- For WaitForFirstConsumer PVCs, add annotation: `cdi.kubevirt.io/storage.bind.immediate.requested: "true"`

## User's Environment
- Working from macOS
- Has oc and virtctl on Mac
- Can SSH to SNO: ssh core@192.168.2.50
- api.main.araclab.xyz is reachable from outside home network
- Sometimes working remotely (can't reach VM DHCP IPs directly, only via *.apps.main.araclab.xyz routes)