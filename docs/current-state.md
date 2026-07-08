# Current Homelab State

Last updated: 2026-07-08

## Cluster

| Item | Value |
|---|---|
| Cluster type | Single Node OpenShift |
| Cluster name | `main` |
| Base domain | `araclab.xyz` |
| API | `api.main.araclab.xyz` |
| Apps wildcard | `*.apps.main.araclab.xyz` |
| SNO IP | `192.168.2.50` |
| Kubernetes node name | `34-17-eb-de-51-1d` |
| DNS server | Raspberry Pi at `192.168.2.51` |

Use the node name `34-17-eb-de-51-1d` in Kubernetes node selectors. The DNS name
`sno.main.araclab.xyz` is only an alias.

## Disk Layout

| Device | Model/serial | Role |
|---|---|---|
| `nvme0n1` | Samsung 990 PRO 1TB, `S73JNJ0W601950M` | SNO/RHCOS OS disk |
| `nvme1n1` | Patriot P300 512GB, `P300EDCB22111603199` | LVM storage target for VM disks |
| `sda` | Kingston 240GB, `50026B77842702D8` | Image registry candidate; leftover XFS must be wiped first |
| `sdb` | Kingston 240GB, `50026B77842717DD` | Spare local storage |

## DNS

The active CoreDNS file on the Raspberry Pi is `/etc/coredns/Corefile`. The repository
copy is `coredns/Corefile`.

Expected answers:

```bash
dig @192.168.2.51 api.main.araclab.xyz
dig @192.168.2.51 console-openshift-console.apps.main.araclab.xyz
```

Both should resolve to `192.168.2.50`.

## Access

Local access can use macOS split DNS through `/etc/resolver/main.araclab.xyz`.
Remote access should use Twingate Resources for the API, apps wildcard, and optional SSH.

Do not expose OpenShift API or ingress with router port forwards.
