# homelab
This repository holds all the config/scripts to deploy my homelab


Accomplishement So far
    - Dell Tower Percision 7810
    - 160 GB Rab 72 cores of cpu
    - storage: 1 nvme m.2 (512gb) will be use for SNO
    - storage 2 nvme m.2 1 TB will be used for Nested VMs
    - storage 3 and 4 SATA SSD will be used for registry and later usage
    - Install Openshift 4.21 on the SNO using interactive installer
    - Install OCP Virt Operator
    - Install Local Storage Operator for the registry and created local sata registry
    - Install LVM Operator to manage the 1TB NVME to be used for the nested vms and created lvms-fast-ssd-pool storate class
    - Install nmstate operator
    - configure NAD to give bridge network for the VMS
    - create insta-config and agent-config
    - run openshift-install create image
    - Create empty dataVolume for the generated ISO
    - Upload the ISO to the Datavolume using 
    - virtctl image-upload dv nested-ocp-agent-iso \
        --namespace nested-openshift-os-images \
        --size=5Gi \
        --image-path agent.x86_64.iso \
        --storage-class lvms-fast-ssd-pool
        --insecure
    - we need nmstate operator to create a bridge interface and then create
    - create Nmstate operands
    - 
        