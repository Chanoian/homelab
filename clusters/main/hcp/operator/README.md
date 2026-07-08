# HCP Operator

Hosted control planes are enabled through the multicluster engine Operator.

The active MCE subscription is rendered from:

- `clusters/main/components/multicluster-engine/operator/`

The active `MultiClusterEngine` operand is reconciled from:

- `clusters/main/components/multicluster-engine/instance/`

The `hypershift-addon` manifest is staged and should be applied only after MCE has
created the reserved `local-cluster` namespace:

- `clusters/main/components/multicluster-engine/hypershift-addon/`

Do not add `HostedCluster` or `NodePool` manifests until the service publishing
strategy, DNS names, and worker VM storage class are selected.
