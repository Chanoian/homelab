# Homelab Project Context

## Current Direction

This repo manages a homelab running OpenShift on a Dell Precision Tower 7810.
The active design is:

- Bare-metal SNO management cluster at `main.araclab.xyz` on `192.168.2.50`
- Current Kubernetes node name: `34-17-eb-de-51-1d`
- CoreDNS on a Raspberry Pi at `192.168.2.51`
- Flat home network: `192.168.2.0/24`, gateway `192.168.2.1`
- OS disk: Samsung 990 PRO 1TB at `nvme1n1`
- Future VM storage disk: Patriot P300 512GB at `nvme0n1`
- Registry candidate: Kingston SATA serial `50026B77842702D8`
- OpenShift Virtualization stays active for future Hosted Control Plane worker VMs
- multicluster engine enables Hosted Control Planes / HyperShift support
- The old full nested OpenShift-on-KubeVirt cluster is archived, not active

GitHub repo: `https://github.com/Chanoian/homelab`

## Important Design Rules

- Do not modify `br-ex`.
- Do not add NMState policies that attach bridges to the SNO physical NIC.
- Use `34-17-eb-de-51-1d` for Kubernetes node selectors, not the DNS alias.
- For the first HCP/KubeVirt worker design, use the default pod network for worker VMs.
- Do not use localnet/L2 LAN attachment for HCP workers until the default path works.
- Keep Raspberry Pi responsibilities to DNS/bootstrap/support services, not OCP workers.
- Keep CoreDNS SNO-only until an HCP service publishing strategy is selected.
- Treat all `install-config.yaml` files as sensitive because they can contain pull secrets.

## Active GitOps Layout

| Path | Purpose |
|---|---|
| `bootstrap/` | Manual OpenShift GitOps bootstrap |
| `argo-apps/` | Argo CD Application entrypoints |
| `clusters/main/infra/` | Single infra Kustomize root reconciled by Argo |
| `clusters/main/components/` | Component-owned operators, instances, and staged follow-up resources |
| `clusters/main/cluster-config/` | Cluster-wide config not owned by an add-on component |
| `clusters/main/hcp/` | HCP design notes and deferred HostedCluster/NodePool manifests |
| `coredns/` | Raspberry Pi CoreDNS config |

## Current Storage Plan

| Device | Role |
|---|---|
| `nvme1n1` Samsung 990 PRO 1TB | SNO/RHCOS OS disk |
| `nvme0n1` Patriot P300 512GB | LVM Storage target for future HCP worker VMs |
| `sda` Kingston 240GB, serial `50026B77842702D8` | Image registry candidate; wipe leftover XFS first |
| `sdb` Kingston 240GB, serial `50026B77842717DD` | Spare |

The active LVMCluster operand must only target `/dev/nvme0n1`. Do not let LVM Storage
auto-consume all free disks.

## Remote Access

Twingate Resources in use/planned:

- `api.main.araclab.xyz` on TCP 6443
- `*.apps.main.araclab.xyz` on TCP 443
- `192.168.2.50` on TCP 22 for SSH, optional and restricted

## Archived Layout

The retired nested cluster design lives under `archive/nested-ocp-virt/`.
It contains the old agent installer config, localnet NAD, DataVolumes, KubeVirt VMs,
CoreDNS snapshot, and NUMA/CPU-pinning notes.

The archived design ran:

- 3 virtualized OpenShift control-plane nodes
- 1 virtualized worker node
- Agent-based installer ISO and cloned ISO PVCs
- OVN localnet attachment to the home LAN

That design was too heavy for the single tower and put unnecessary pressure on local
storage. Do not restore it into active Argo paths unless explicitly requested.

## Future HCP Direction

Preferred next step:

- Create one hosted cluster with one small KubeVirt worker node pool.
- Keep worker VMs on the default pod network.
- Use dedicated local storage for worker VM root disks where possible.
- Add external x86 hardware later for non-virtualized workers.

Do not add HostedCluster or NodePool manifests until the service publishing strategy,
storage class, and DNS names are selected.

## Useful Commands

```bash
oc get applications -n openshift-gitops
oc get pods -n openshift-cnv
oc get sc
oc get mcp
```
