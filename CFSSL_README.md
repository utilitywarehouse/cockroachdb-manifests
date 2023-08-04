# CFSSL

"CFSSL is CloudFlare's PKI/TLS swiss army knife". This base requires cfssl and depends on the API server
to sign certificates and retrieve the Certificate Authority it will trust. CFSSL provide a
[docker container](https://hub.docker.com/r/cfssl/cfssl/) which can be deployed in Kubernetes.

## Certificates

- The base relies on [docker-cockroach-cfssl-certs](https://github.com/utilitywarehouse/docker-cockroach-cfssl-certs).
It is executed via an init container, acquiring certificates on pod start.
- The container relies on the CFSSL AuthSign endpoint and passes a CSR (Certificate Signature Request) and token.
- It uses the same container as a sidecar to refresh certificates when they are due to expire and sends a `SIGHUP` to the
  Cockroach process to inform it to reload the certificates see [docs](https://www.cockroachlabs.com/docs/stable/rotate-certificates.html)
- To send a signal to a different container they require a shared process namespace,
  see [docs](https://kubernetes.io/docs/tasks/configure-pod-container/share-process-namespace/).
  - This will require configuring kubernetes to grant the `SYS_PTRACE` capability to the container.
  - See [this](https://github.com/utilitywarehouse/kubernetes-manifests/pull/75092) PR for example (yes, access is given per namespace).

### Generating Certificates

To configure the certificate authority you will need to generate a hex encoded access key, a self signed CA certificate and key for it and store these in kubernetes as secrets. To generate a certificate first create a json file with your configuration (changing the values as necessary):

``` json
{
  "CN": "Utility Warehouse CA",
  "key": {
    "algo": "ecdsa",
    "size": 521
  },
  "ca": {
    "expiry": "17520h"
  }
}
```
Note that this will expire in 2 years

then run the `cfssl` command to generate certificates, `cfssl gencert -initca <your-config-file>.json | cfssljson -bare ca`. The command will generate 3 files `ca.pem`, `ca-key.pem` and `ca.csr`. You will not need the `cs.csr` file to configure cockroach.

finally you can generate a hex encoded access key with
``` shell
hexdump -n 16 -e '4/4 "%08X" 1 "\n"' /dev/random
```

### Generate new certificate
When CA certificate is about to expire you can generate new certificate using
the same key by running the following command.

`cfssl gencert -ca-key=ca-key.pem -initca ca-csr.json | cfssljson -bare ca`

Here `ca-csr.json` is the same file as before and `ca-key.pem` is the old
generated key. You can then delete the `ca-certs` secret and recreate it
with the same command as before.

Without requiring the `ca-csr.json`, you can renew the certificate with
`cfssl gencert -renewca -ca ca-certs-ca.pem -ca-key ca-certs-ca-key.pem | cfssljson -bare ca`

Once the secret is updated you should restart the pods of the CA service
to make them use the new certificate. Afterwards, you should restart all 
services that use certificates signed by this CA, so that they can fetch
the new CA certificate. As we are using the same key the certificates signed
by the CA will appear to be signed by both the old CA certificate and the new one.
