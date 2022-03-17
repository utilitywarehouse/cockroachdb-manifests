# cockroachdb-manifests

This is a Kustomization base for deploying CockroachDB to a Kubernetes cluster. The base depends on Cloudflare's
[cfssl](https://github.com/cloudflare/cfssl) as a Certificate Authority for signing certificates for
securing communication between nodes and clients.

#### CFSSL

"CFSSL is CloudFlare's PKI/TLS swiss army knife". This base requires cfssl and depends on the API server
to sign certificates and retrieve the Certificate Authority it will trust. CFSSL provide a
[docker container](https://hub.docker.com/r/cfssl/cfssl/) which can be deployed in Kubernetes.

#### Certificates

- The base relies on this [container](https://github.com/utilitywarehouse/docker-cockroach-cfssl-certs) it is used
  as an init container to sign certificates on startup.
    - The container relies on the CFSSL AuthSign endpoint and passes a CSR (Certificate Signature Request) and token.
- It uses the same container as a sidecar to refresh certificates when they are due to expire and sends a `SIGHUP` to the
  Cockroach process to inform it to reload the certificates see [docs](https://www.cockroachlabs.com/docs/stable/rotate-certificates.html)
- To send a signal to a different container they require a shared process namespace,
  see [docs](https://kubernetes.io/docs/tasks/configure-pod-container/share-process-namespace/).
    - This will require configuring kubernetes to grant the `SYS_PTRACE` capability to the container.

### Configuration
The CA is configured by a config map. This specifies the cfssl certificate authority
API endpoint and the profile used to sign client and peer certificates. These profiles must match the
cfssl configuration.
Example:
```
ca.node.profile=server
ca.client.profile=client
ca.endpoint=certificate-authority:8080
```
The auth key to sign the certificate is passed in as a secret.
Cockroach DB requires some base configuration that can be overridden. (An example is below)
- Note: `cockroach.host` and `cockroach.port` are required by the backup job.
```
cockroach.host=cockroachdb-proxy
cockroach.port=26257
cockroach.seed.hosts=cockroachdb-0.cockroachdb,cockroachdb-1.cockroachdb,cockroachdb-2.cockroachdb
cockroach.init.host=cockroachdb-0.cockroachdb
```
You may want to overwrite the config if you patch the service name for example. This can be done as shown below:
```yaml
configMapGenerator:
  - name: cockroach
    behavior: replace
    envs:
      - config/cockroach
```

### Client

- The base provides a client deployment that bootstraps the Cockroach sql command. By default the client has 0 replicas
  but can be scaled up using the replicas kustomization.
```yaml
replicas:
  - name: cockroachdb-client
    count: 1
```
- The client deployment is useful for debugging issues and communicating with Cockroach.
- An example command for starting a sql shell is `kubectl exec -it cockroachdb-client -- cockroach sql`

### DB Console

CockroachDB has a DB console [user interface](https://www.cockroachlabs.com/docs/stable/ui-overview.html).
To log into the DB console you will require a database user.
This can be achieved by:
- Shelling into the client container
- Start a SQL session with `cockroach sql`
- Create a user using SQL `CREATE USER foo WITH PASSWORD 'changeme';`
- Port forward any node `kubectl port-forward cockroachdb-0 8080`
- Use a browser to navigate to https://localhost:8080.
- It will warn you that the certificate is not trusted, this is expected. 


