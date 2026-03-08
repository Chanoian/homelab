# Homelab — OpenShift on Bare Metal

This repository manages the full infrastructure of my homelab using GitOps with ArgoCD.
All manifests are organized under `day2/` and applied to the cluster via ArgoCD (OpenShift GitOps).

---

## Hardware

**Dell Precision Tower 7810**

| Component | Spec | Purpose |
|-----------|------|---------|
| CPU | 72 cores | Bare metal SNO + nested VMs |
| RAM | 160 GB | Bare metal SNO + nested VMs |
| NVMe 1 | 512 GB | SNO bare metal OS (RHCOS) |
| NVMe 2 | 1 TB | Nested cluster VM root disks (lvms-fast-ssd-pool) |
| SATA SSD 1 | — | Image registry (local-sata-registry) |
| SATA SSD 2 | — | Future use |
| NIC | 1x 1GbE (enp0s25) | Single interface, enslaved to OVS br-ex |

---

## Architecture

```
192.168.2.0/24
├── 192.168.2.1      Gateway (router)
├── 192.168.2.50     SNO — main.araclab.xyz (bare metal, OCP 4.21)
│   └── OpenShift Virtualization
│       ├── master-0   192.168.2.62
│       ├── master-1   192.168.2.63
│       ├── master-2   192.168.2.64
│       └── worker-0   192.168.2.65
├── 192.168.2.51     CoreDNS — Raspberry Pi (Wi-Fi)
├── 192.168.2.60     Nested API VIP  — api.nested.araclab.xyz
└── 192.168.2.61     Nested Ingress VIP — *.apps.nested.araclab.xyz
```

### SNO (Single Node OpenShift)
- **Domain:** `main.araclab.xyz`
- **OCP version:** 4.21
- **Installed via:** Interactive assisted installer (bare metal)

### Nested Cluster
- **Domain:** `nested.araclab.xyz`
- **OCP version:** 4.21
- **Topology:** 3 control planes + 1 worker running as KubeVirt VMs on the SNO
- **Installed via:** Agent-based installer (`openshift-install agent create image`)

### DNS Server
- CoreDNS running on a Raspberry Pi (Wi-Fi, 192.168.2.51)
- Handles internal resolution for both `main.araclab.xyz` and `nested.araclab.xyz`
- Forwards all other queries to `1.1.1.1` and `8.8.8.8`

---

## Operators Installed on SNO

| Operator | Purpose |
|----------|---------|
| OpenShift Virtualization | Run nested VMs |
| Kubernetes NMState | Network state management |
| LVM Storage | Manage NVMe 2 — storage class `lvms-fast-ssd-pool` |
| Local Storage Operator | Manage SATA SSD 1 — storage class `local-sata-registry` |

---

## Repository Structure

```
day2/
├── nested/
│   ├── agent-installer/   # install-config.yaml and agent-config.yaml (reference)
│   ├── networking/        # NetworkAttachmentDefinition for OVN localnet
│   └── vms/               # VirtualMachine, DataVolume, and Namespace manifests
├── operators/             # Operator subscriptions and operands
├── lvm/                   # LVMCluster manifest
├── lso/                   # Local Storage and image registry manifests
├── acme-issuer/           # Cluster certificate issuer
├── argo-apps/             # ArgoCD app-of-apps definitions
├── coredns/               # CoreDNS Corefile (deployed on Raspberry Pi)
└── day1-gitops-manual/    # Bootstrap manifests to install ArgoCD itself
```

---

## How the Nested Cluster Was Built

### Step 1 — Install SNO

Installed OpenShift 4.21 on the Dell Precision using the interactive assisted installer.
The single NIC (`enp0s25`) is managed by OVN-Kubernetes and enslaved to the OVS bridge `br-ex`.

### Step 2 — Install Operators

Via the OCP console or CLI, installed:
- OpenShift Virtualization
- LVM Storage — created `LVMCluster` pointing to NVMe 2, producing `lvms-fast-ssd-pool`
- Local Storage Operator — created `LocalVolume` on SATA SSD 1 for the image registry
- Kubernetes NMState

### Step 3 — Set Up CoreDNS on Raspberry Pi

Configured CoreDNS on the Raspberry Pi with:
- A zone for `main.araclab.xyz` pointing to the SNO node (192.168.2.50)
- A zone for `nested.araclab.xyz` pointing to the nested cluster VIPs (192.168.2.60/61)
- A wildcard rewrite for `*.apps.*.araclab.xyz`
- A global forwarder to `1.1.1.1` / `8.8.8.8` for all other lookups

The Corefile lives in `coredns/Corefile` in this repo.

### Step 4 — Generate the Agent ISO

Created `install-config.yaml` and `agent-config.yaml` under `day2/nested/agent-installer/`.

Key decisions:
- `platform: none` — no cloud provider
- `networkType: OVNKubernetes`
- Static IPs assigned per host via MAC address in `agent-config.yaml`
- `rendezvousIP: 192.168.2.62` (master-0 acts as the bootstrap rendezvous host)
- DNS server set to `192.168.2.51` (Raspberry Pi CoreDNS)

```bash
openshift-install agent create image --dir day2/nested/agent-installer/
```

### Step 5 — Upload the ISO to the Cluster

Created a DataVolume for the ISO upload and used `virtctl` from a Mac to upload:

```bash
virtctl image-upload dv nested-ocp-agent-iso \
  --namespace nested-cluster \
  --size=5Gi \
  --image-path agent.x86_64.iso \
  --storage-class lvms-fast-ssd-pool \
  --upload-proxy-url https://cdi-uploadproxy-openshift-cnv.apps.main.araclab.xyz \
  --insecure
```

Each VM also gets a cloned copy of the ISO (see `iso-datavolume.yaml`).

### Step 6 — Configure VM Networking (OVN Localnet)

The challenge: the SNO has a **single NIC** (`enp0s25`) already managed by OVN-Kubernetes
and enslaved to the OVS bridge `br-ex`. VMs needed L2 access to `192.168.2.0/24` so they
could get their static IPs and reach the internet for image pulls.

**Solution: OVN localnet topology**

The OVS bridge mapping `physnet:br-ex` already exists on the node. A
`NetworkAttachmentDefinition` of type `ovn-k8s-cni-overlay` with `topology: localnet`
uses this mapping to give VMs direct L2 access to the physical network — no additional
bridges or NMState changes required.

Critical detail: the NAD `config.name` field must be `"physnet"` (matching the OVS bridge
mapping key), not the NAD resource name. The `subnets:` field must be omitted to prevent
OVN from taking over IPAM and enforcing port security.

```yaml
# day2/nested/networking/networkattachmentdef.yaml
config: |
  {
    "cniVersion": "0.3.1",
    "name": "physnet",
    "type": "ovn-k8s-cni-overlay",
    "topology": "localnet",
    "netAttachDefName": "nested-cluster/br-nested"
  }
```

> **Warning:** Never apply an NMState `NodeNetworkConfigurationPolicy` that references
> `br-ex`. Doing so removes OVN-K patch ports and breaks all cluster networking. The node
> becomes unreachable and NMState's checkpoint rollback does not reliably recover it.

### Step 7 — Create the VMs

Created `DataVolume` resources for the root disks (blank, sized per role) and
`VirtualMachine` resources with:
- MAC addresses **pinned** to match the static IP mapping in `agent-config.yaml`
- Boot order: agent ISO first, then root disk
- Interface: `bridge` binding on the localnet NAD

MAC to IP mapping:

| VM | MAC | IP |
|----|-----|----|
| master-0 | `02:7c:71:f2:81:4b` | 192.168.2.62 |
| master-1 | `02:7c:71:f2:81:4c` | 192.168.2.63 |
| master-2 | `02:7c:71:f2:81:4d` | 192.168.2.64 |
| worker-0 | `02:7c:71:f2:81:4e` | 192.168.2.65 |

### Step 8 — Boot and Install

Started all 4 VMs. The agent installer ran on each node:
- `master-0` (192.168.2.62) served as the rendezvous host
- Each node pulled the agent image from `quay.io` and registered with master-0
- The cluster installation proceeded automatically once all nodes registered

Monitor progress:
```bash
ssh core@192.168.2.62 "sudo journalctl -u agent -f"
```

---

## Key Commands

```bash
# SSH to SNO
ssh core@192.168.2.50

# VM status
oc get vmi -n nested-cluster -o wide

# VM console / VNC
virtctl console <vm-name> -n nested-cluster
virtctl vnc <vm-name> -n nested-cluster

# Check OVS bridge mapping
oc debug node/sno.main.araclab.xyz -- chroot /host \
  ovs-vsctl get Open_vSwitch . external-ids:ovn-bridge-mappings

# Check storage
oc get dv,pvc -n nested-cluster

# SSH into nested VM (once booted)
ssh core@192.168.2.62
```
