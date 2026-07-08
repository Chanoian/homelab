# Components

Each platform add-on owns its operator install and the custom resources it manages.

Layout convention:

- `operator/`: namespace, OperatorGroup, and Subscription.
- `instance/`: operator-owned custom resources that require the CRD to exist first.
- Other folders are staged follow-up resources that are not wired into Argo until their
  prerequisites are confirmed.

Active Argo apps reconcile:

- `lvm-storage/operator`
- `lvm-storage/instance`
- `virtualization/operator`
- `virtualization/instance`
- `local-storage/operator`
- `multicluster-engine/operator`
- `multicluster-engine/instance`

Staged folders:

- `local-storage/registry`: apply after confirming and wiping the Kingston SATA disk.
- `multicluster-engine/hypershift-addon`: apply after MCE creates `local-cluster`.
