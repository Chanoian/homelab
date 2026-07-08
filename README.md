# Homelab - OpenShift Bare Metal SNO

This repository manages my homelab infrastructure with GitOps. The active design is a
single-node OpenShift cluster on bare metal, with OpenShift Virtualization kept as the
future provider for Hosted Control Plane worker VMs.

The previous design, a full nested OpenShift cluster running on OpenShift Virtualization
VMs, has been retired from the active GitOps tree and preserved under
`archive/nested-ocp-virt/`.

## Current Design

| Component | Role |
|---|---|
| Dell Precision Tower 7810 | Bare-metal Single Node OpenShift management cluster |
| Raspberry Pi | CoreDNS and lightweight support services |
| OpenShift Virtualization | Future HCP worker VM provider |
| LVM Storage | Patriot NVMe backed storage for future HCP worker VM disks |
| Local Storage Operator | SATA-backed image registry storage |
| multicluster engine | Hosted control planes / HyperShift support |

## Network

```
192.168.2.0/24
+-- 192.168.2.1    Gateway
+-- 192.168.2.50   SNO - main.araclab.xyz
+-- 192.168.2.51   CoreDNS - Raspberry Pi
```

The tower has one physical NIC, `enp0s25`, owned by OpenShift and attached to `br-ex`.
Do not modify `br-ex` with NMState or Linux bridge policies.

The current Kubernetes node name is `34-17-eb-de-51-1d`. The DNS name
`sno.main.araclab.xyz` is only a lab alias and should not be used in node selectors.

Current disk plan:

| Device | Role |
|---|---|
| `nvme0n1` Samsung 990 PRO 1TB | SNO/RHCOS OS disk |
| `nvme1n1` Patriot P300 512GB | LVM Storage target for future HCP worker VMs |
| `sda` Kingston 240GB, serial `50026B77842702D8` | Image registry candidate; wipe leftover XFS first |
| `sdb` Kingston 240GB, serial `50026B77842717DD` | Spare local storage |

For the first HCP/KubeVirt design, hosted-cluster worker VMs should use the default pod
network. They should not be attached directly to the home LAN with localnet or a custom
bridge. LAN-native VM networking can be revisited later as a separate phase.

## Future HCP Direction

The target next design is:

- SNO remains the management cluster.
- Hosted control planes run as pods on the SNO.
- Initial hosted-cluster workers can run as small KubeVirt VMs.
- Later, additional x86 bare-metal machines can be added as worker capacity.
- VM worker root disks should use dedicated storage classes/disks where possible.

This is intentionally lighter than the retired nested design because the hosted cluster
does not run its control plane as three separate VMs with its own virtualized etcd.

## Repository Layout

```
bootstrap/                  # Manual bootstrap for OpenShift GitOps
argo-apps/                  # Argo CD Application entrypoints
clusters/main/infra/        # Single infra Kustomize root reconciled by Argo
clusters/main/components/   # Component-owned operators and instances
clusters/main/cluster-config/ # Cluster-wide configuration not owned by an add-on
clusters/main/hcp/          # HCP design notes and deferred HostedCluster/NodePool manifests
coredns/                    # Raspberry Pi CoreDNS configuration
docs/                       # Active operational docs
archive/nested-ocp-virt/    # Retired full nested OCP-on-KubeVirt design
archive/obsolete-argo-apps/ # Old app definitions no longer reconciled
```

## Remote Access

Local macOS split DNS can send only `main.araclab.xyz` to the Raspberry Pi resolver:

```bash
sudo mkdir -p /etc/resolver
printf "nameserver 192.168.2.51\n" | sudo tee /etc/resolver/main.araclab.xyz
```

For remote access, use Twingate with a Connector inside the home network and Resources
for `api.main.araclab.xyz` TCP 6443, `*.apps.main.araclab.xyz` TCP 443, and optionally
`192.168.2.50` TCP 22.

## GitOps Bootstrap

Install OpenShift GitOps manually first:

```bash
oc apply -f bootstrap/argo-namespace.yaml
oc apply -f bootstrap/argocd-operator-group.yaml
oc apply -f bootstrap/argocd-sub.yaml
oc apply -f bootstrap/argocd-clusteradmin.yaml
```

Then apply the single infra Application:

```bash
oc apply -f argo-apps/infra.yaml
```

## Notes

- `clusters/main/components/lvm-storage/instance/lvmcluster.yaml` targets `nvme1n1`
  for future VM storage.
- `clusters/main/components/local-storage/registry/` contains staged registry artifacts.
  Wipe the leftover XFS signature on the first Kingston SATA disk before applying those.
- `clusters/main/components/multicluster-engine/hypershift-addon/` is staged until MCE
  creates the reserved `local-cluster` namespace.
- `install-config.yaml` files are ignored because they usually contain pull secrets.
- The archived nested design is reference material only and should not be reconciled by
  Argo CD.
