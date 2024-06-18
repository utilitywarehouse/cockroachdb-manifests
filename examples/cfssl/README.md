# DEPRECATED
We have replaced `cfssl` with `cert-manager` for CockroachDB certificates. Please refer to [cert-manager examples](https://github.com/utilitywarehouse/cockroachdb-manifests/examples/cert-manager) for up-to-date manifests.

# cockroachdb-manifests

This is a Kustomization base for deploying CockroachDB to a Kubernetes cluster. The base depends on Cloudflare's
[cfssl](https://github.com/cloudflare/cfssl) as a Certificate Authority for signing certificates for
securing communication between nodes and clients.

## Deployment

To deploy a cockroachdb cluster in your namespace you will need to complete the following steps:
1. Configure and Deploy a Certificate Authority by following the [readme](./CFSSL_README.md). This will secure access for your cockroach cluster and clients.
2. Setup a `kustomization.yaml` file that will use the bases defined here with your own configuration layered over the top. There is an [examples/single-cluster](./examples/single-cluster/) folder that can be used as a starting point. By filling in the missing pieces (e.g. certs, backup config, etc) you should get a running CA and CRDB cluster with periodic backups to S3 and AWS creds injected via [vault](https://github.com/utilitywarehouse/documentation/blob/master/infra/vault/vault-aws.md) (assumes an existing vault setup).

### Single namespace - multiple CockroachDB clusters

While the preference is to have a single CockroachDB cluster per namespace, in some cases this isn't ideal. 

An example of this is in the Energy team where they have recently split into three squads but currently still share use of the `energy-platform` namespace. 

In order to deploy multiple CockroachDB clusters within a single namespace whilst avoiding naming conflicts we can make use of the `namePrefix` and/or `nameSuffix` ability of Kustomize. 
This will automagically update the names of resources within a Kustomization as well as the selectors and labels. 

One part of this that Kustomize is not able to help with is with the CockroachDB specific commands that are used to create and join nodes to the cluster. 
For this two environment variables have been added `COCKROACH_INIT_HOST` and `COCKROACH_JOIN_STRING`. 

- `COCKROACH_INIT_HOST` is used by the `init-job.yaml` manifest to initialise the first node in the cluster
- `COCKROACH_JOIN_STRING` is in the `statefulset.yaml` manifest to define which nodes will be joining the cluster. 

There are sensible defaults for these environment variables to ensure that a single cluster within a namespace can be brought up without overriding any environment variables. 


### Versioning

This repo uses tags to manage versions, these tags have two components:

  - The version of the `cockroachdb/cockroach` image the manifests are using
  - An internal version to track changes to anything besides the version of
    CockroachDB

These tags are of the form `<cockroachdb-version>-<internal-version>`, for
example: `v23.1.10-2` is the 2nd internal version of these manifests supporting
`cockroachdb/cockroachv:23.1.10`

### Configuration
The Certificate Authority is configured by a config map. This specifies the cfssl certificate authority
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
```

#### CockroachDB

You can configure `--cache` and `--max-sql-memory` cockroachdb flags via
following envvars: `CACHE` and `MAX_SQL_MEMORY`.

### Client

- The base provides a client deployment that bootstraps the Cockroach sql command.
- The client deployment is useful for debugging issues and communicating with Cockroach.
- An example command for starting a sql shell is `kubectl exec -it deployment/cockroachdb-client -c cockroachdb-client -- cockroach sql`

### Admin UI

In order to access admin UI, Port forward port 8080 on one of the cockroachdb- pods,
then navigate to https://localhost:8080/

### DB Console

CockroachDB has a DB console [user interface](https://www.cockroachlabs.com/docs/stable/ui-overview.html).
To log into the DB console you will require a database user.
This can be achieved by:
- Start a SQL shell using the client `kubectl exec -it deployment/cockroachdb-client -c cockroachdb-client -- cockroach sql`
  - You may need to change the replica count of the client (see above)
- Create a user using SQL `CREATE USER foo WITH PASSWORD 'changeme';`
- Assign admin role to the user with the SQL command `GRANT admin TO foo;`
  - This allows full access within the UI.
- Port forward any node `kubectl port-forward cockroachdb-0 8080`
- Use a browser to navigate to https://localhost:8080.
- It will warn you that the certificate is not trusted, this is expected.

### Architecture
We recommend creating one instance of CockroachDB cluster per namespace instead of creating new cluster instance
for each of applications.
Data can be separated by creating different databases, and having one, bigger cluster instead of multiple smaller ones
reduces infrastructure costs and maintenance overhead.
