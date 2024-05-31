# Certificates

In order to secure the communication between CRDB nodes and clients we need to generate three certificates:
- CA Certifiace - used to sign node and client certificates
- Node Certificate - used to allow nodes establishing a connection to each other
- Client Certificate - used by the init and backup jobs to connect to CRDB

All necessary manifests are in the [base](https://github.com/cert-manager/base/) directory, however, you will need to manually update
`node` Certificate manifest patch to specify the name of the namespace you are deploying CRDB to.
