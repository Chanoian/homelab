# Archived Nested OCP-on-KubeVirt Design

This directory preserves the retired design where a full OpenShift cluster ran as
KubeVirt VMs on the SNO.

Archived components include:

- Agent-based installer configuration
- Nested cluster namespace
- OVN localnet NetworkAttachmentDefinition
- KubeVirt VirtualMachine manifests
- CDI DataVolumes for root disks and agent ISO clones
- Old CoreDNS records for `nested.araclab.xyz`
- NUMA and dedicated CPU pinning notes

The archived `install-config.yaml` is intentionally ignored by git because it contains
pull-secret material. Keep it local only or replace it with a redacted example before
sharing.

Do not point Argo CD at this archive. It is reference material only.
