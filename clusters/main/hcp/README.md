# Hosted Control Planes Scaffold

This directory is reserved for the future HCP design.

Target architecture:

- The bare-metal SNO remains the management cluster.
- Hosted control planes run as pods on the SNO.
- Initial hosted-cluster workers can run as KubeVirt VMs.
- Later worker capacity can move to external x86 bare-metal hosts.
- Worker VM disks should use the Patriot P300 NVMe disk exposed through LVM Storage.

Networking rule for the first implementation:

- Use the default pod network for KubeVirt worker VMs.
- Do not attach worker VMs directly to `192.168.2.0/24`.
- Do not create localnet NADs or NMState bridge policies for `br-ex`.
- Add LAN-native worker networking only as a later, explicit phase.

No `HostedCluster`, `NodePool`, or HCP operator manifests are committed here yet. Add
those only after choosing the HCP service publishing strategy, DNS names, and worker VM
storage class.
