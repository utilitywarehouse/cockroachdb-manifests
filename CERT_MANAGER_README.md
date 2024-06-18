# Certificates

In order to secure the communication between CRDB nodes and clients we need to generate three certificates:
- CA Certifiace - used to sign node and client certificates
- Node Certificate - used to allow nodes establishing a connection to each other. The Node Certificate is being shared between all nodes
- Client Certificate - used by the init and backup jobs to connect to CRDB

All necessary manifests are in the [base-cert-manager](https://github.com/utilitywarehouse/cockroachdb-manifests/tree/master/base-cert-manager) directory, however, you will need to manually update
`node` Certificate manifest patch to specify the name of the namespace you are deploying CRDB to.
In case if you want to deploy more than 3 replicas of CRDB node, you will also need to update the same patch file.
