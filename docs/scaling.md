# Adding or removing CockroachDB nodes

This runbook looks to document how to orchestrate adding, removing, re-adding, and replacing CockroachDB nodes. This is
specifically written with this kustomize base in mind, however many parts are agnostic to how CockroachDB is deployed.

<!-- ToC start -->
## Table of Contents

   1. [Before applying changes](#before-applying-changes)
      1. [Check cluster health](#check-cluster-health)
         1. [Verify pods are running and showing healthy](#verify-pods-are-running-and-showing-healthy)
         1. [Inspect DB Console](#inspect-db-console)
      1. [Review zone configurations](#review-zone-configurations)
   1. [Apply changes](#apply-changes)
      1. [Option 1: adding nodes](#option-1-adding-nodes)
         1. [Increase replica count](#increase-replica-count)
         1. [Review join flag (optional)](#review-join-flag-optional)
         1. [Increase replication factor (optional)](#increase-replication-factor-optional)
      1. [Option 2: removing nodes](#option-2-removing-nodes)
         1. [Decommission](#decommission)
         1. [Decrease replica count](#decrease-replica-count)
         1. [Remove orphaned PVCs](#remove-orphaned-pvcs)
         1. [Decrease replication factor (optional)](#decrease-replication-factor-optional)
      1. [Option 3: re-adding nodes](#option-3-re-adding-nodes)
         1. [Non-decommissioned nodes](#non-decommissioned-nodes)
         1. [Decommissioned nodes](#decommissioned-nodes)
      1. [Option 4: replacing nodes](#option-4-replacing-nodes)
         1. [Scale up (if necessary)](#scale-up-if-necessary)
         1. [Stop the problematic node](#stop-the-problematic-node)
         1. [Decommission the problematic node](#decommission-the-problematic-node)
         1. [Remove the PVC](#remove-the-pvc)
         1. [Re-apply manifests](#re-apply-manifests)
   1. [After applying changes](#after-applying-changes)
      1. [Re-check cluster health](#re-check-cluster-health)
<!-- ToC end -->

## Before applying changes

If the number of nodes is being changed under normal circumstances (i.e. not in reaction to issues resulting from a
prior change to the replica count), the cluster should be checked first to ensure it is in a healthy state.

### Check cluster health

#### Verify pods are running and showing healthy

Make sure from the kubernetes side of affairs, all the pods are healthy and all underlying containers are running:

```
$ kubectl --context=<cluster> --namespace=<namespace> get pods | rg 'cockroachdb-[0-9]'
cockroachdb-0                                                     3/3     Running                      0                  16m
cockroachdb-1                                                     3/3     Running                      0                  25h
cockroachdb-2                                                     3/3     Running                      2 (14h ago)        6d20h
```

If any pods are crash looping, or containers are missing from any pods (e.g. if one were to show `2/3`), this would need
to be investigated and resolved before any nodes are introduced or removed from the cluster.

#### Inspect DB Console

The DB Console gives a decent overview of the health of nodes in a cluster, amongst other things. _TODO: link to
documentation that explains how to access the DB Console_.

Once you have the console open, check the following:

- Replication Status: there should be no under-replicated ranges indicated
- Node Status: all nodes should be displayed as live
- Nodes List: all nodes should be indicating the same version

### Review zone configurations

If you're adding or removing nodes, you may need to tweak the replication factor in relation to the various zone. This
is discussed later on, but for now, it's worth grabbing a copy of the zone configurations.

To view the configuration, execute the following:

```sql
SHOW ZONE CONFIGURATIONS;
```

To execute this via the `cockroachdb-client` deployment, the following one-liner can be used:

```
$ kubectl --context=<cluster> --namespace=<namespace> exec deployments/cockroachdb-client -c cockroachdb-client -- cockroach sql --execute "SHOW ZONE CONFIGURATIONS;"
target  raw_config_sql
RANGE default   "ALTER RANGE default CONFIGURE ZONE USING
        range_min_bytes = 16777216,
        range_max_bytes = 67108864,
        gc.ttlseconds = 90000,
        num_replicas = 3,
        constraints = '[]',
        lease_preferences = '[]'"
DATABASE system "ALTER DATABASE system CONFIGURE ZONE USING
        range_min_bytes = 16777216,
        range_max_bytes = 67108864,
        gc.ttlseconds = 90000,
        num_replicas = 5,
        constraints = '[]',
        lease_preferences = '[]'"
TABLE system.public.jobs        "ALTER TABLE system.public.jobs CONFIGURE ZONE USING
        range_min_bytes = 16777216,
        range_max_bytes = 67108864,
        gc.ttlseconds = 600,
        num_replicas = 5,
        constraints = '[]',
        lease_preferences = '[]'"
RANGE meta      "ALTER RANGE meta CONFIGURE ZONE USING
        range_min_bytes = 16777216,
        range_max_bytes = 67108864,
        gc.ttlseconds = 3600,
        num_replicas = 5,
        constraints = '[]',
        lease_preferences = '[]'"
RANGE system    "ALTER RANGE system CONFIGURE ZONE USING
        range_min_bytes = 16777216,
        range_max_bytes = 67108864,
        gc.ttlseconds = 90000,
        num_replicas = 5,
        constraints = '[]',
        lease_preferences = '[]'"
RANGE liveness  "ALTER RANGE liveness CONFIGURE ZONE USING
        range_min_bytes = 16777216,
        range_max_bytes = 67108864,
        gc.ttlseconds = 600,
        num_replicas = 5,
        constraints = '[]',
        lease_preferences = '[]'"
TABLE system.public.replication_constraint_stats        "ALTER TABLE system.public.replication_constraint_stats CONFIGURE ZONE USING
        gc.ttlseconds = 600"
TABLE system.public.replication_stats   "ALTER TABLE system.public.replication_stats CONFIGURE ZONE USING
        gc.ttlseconds = 600"
```

The `num_replicas` setting indicates the replication factor for a given zone.

## Apply changes

The instructions depend on the nature of the change. So,

- for adding nodes, jump to [`Option 1: adding nodes`](#option-1-adding-nodes)
- for removing nodes, jump to [`Option 2: removing nodes`](#option-2-removing-nodes)
- for re-adding nodes, jump to [`Option 3: re-adding nodes`](#option-3-re-adding-nodes)
- for replacing nodes, jump to [`Option 4: replacing nodes`](#option-4-replacing-nodes)

### Option 1: adding nodes

#### Increase replica count

This kustomize base defaults to 3 replicas. If you wish, you can increase the replica count. To achieve this, simply
set the replicas count to the target value via the kustomize
[`replicas` directive](https://github.com/kubernetes-sigs/kustomize/blob/master/examples/replicas.md)

```diff
--- a/cluster/namespace/kustomization.yaml
+++ b/cluster/namespace/kustomization.yaml
@@ -201,5 +201,9 @@ resources:
   - 01-auth.yaml
   - 02-network-policies.yaml
   - github.com/utilitywarehouse/cockroachdb-manifests//base?ref=v21.2.8-0
 
+replicas:
+  - name: cockroachdb
+    count: 5
+
 patchesStrategicMerge:
   - cockroach.yaml
```

Apply via whatever normal route would be used. The kubernetes scheduler will then look to provision the additional pvcs,
pods, etc, to satisfy the target count.

#### Review join flag (optional)

The [`--join`](https://github.com/utilitywarehouse/cockroachdb-manifests/blob/795a82920d5977d7c07ace1ba73969f3e39d4411/base/statefulset.yaml#L83)
flag currently hardcodes the default initial 3 nodes of the cluster. This may change at some stage to make it more
configurable, but please note that it is _not_ necessary to set all nodes in the cluster into the `--join` flag value.
In fact, the CockroachDB team
[actively recommend against including nodes beyond the first 3 to 5](https://www.cockroachlabs.com/docs/stable/cockroach-start.html):

> --join, -j 
> 
> The host addresses that connect nodes to the cluster and distribute the rest of the node addresses. These can be IP addresses or DNS aliases of nodes.
>
> When starting a cluster in a single region, specify the addresses of 3-5 initial nodes. When starting a cluster in multiple regions, specify more than 1 address per region, and select nodes that are spread across failure domains. Then run the cockroach init command against any of these nodes to complete cluster startup. See the example below for more details.
>
> Use the same --join list for all nodes to ensure that the cluster can stabilize. Do not list every node in the cluster, because this increases the time for a new cluster to stabilize. Note that these are best practices; it is not required to restart an existing node to update its --join flag.
> 
> cockroach start must be run with the --join flag. To start a single-node cluster, use cockroach start-single-node instead.

So, if you're for example scaling from 3 to 5, the `--join` flag can be left alone.

#### Increase replication factor (optional)

Increasing the count of nodes in a CockroachDB cluster _does not automatically result in any change to the
[replication factor](https://www.cockroachlabs.com/docs/stable/architecture/replication-layer.html)_. The replication
factor dictates the requested storage count of ranges across the nodes. If the requested count exceeds the number of
nodes, generally speaking the number of nodes becomes the target replica count. In other words
`target_replica_count = min(num_nodes, zone_num_replicas)`.

The default zone configuration for system related data (i.e. data used by CockroachDB internals) sets `num_replicas` to
5, whilst the default for user related data sets it to 3. That ultimately means that if you scale to 5 nodes, the
clusters ability to survive a loss of 2 nodes may not be greatly improved, as ranges relating to user defined data may
become unavailable. Whether this is an issue depends on the reasoning behind modifying the number of nodes:

- if the increase was looking to try to improve performance in certain areas, or scale as data grows, you may feel
  satisfied to leave the replication factor alone
- if the increase was looking to try to improve availability, then you may wish to increase the replication factor

If your circumstances do meet the needs to adjust replica count, you should decide the value to set based on the number
of node failures you wish to be able to survive. This is ideally based on the following formula, though CockroachDB will
likely accept any value and act appropriately.

```
number of node failures to tolerate = (replication factor - 1) / 2
```

So for example:
- with a replication factor of 3, 1 node outage can be survived
- with a replication factor of 5, 2 node outages can be survived
- with a replication factor of 7, 3 node outages can be survived
- .. and so on.

Since CockroachDB will always respect the number of nodes in the cluster, if you wish to always have a replication
factor that always matches the number of nodes, you can set the value to some arbitrary high value (e.g. 1000).

Once you have decided on the target count, at minimum you'll want to adjust the `default` zone:

```sql
ALTER RANGE default CONFIGURE ZONE USING num_replicas = <target>;
```

Other zones may require adjustments depending on their current values and your desired target. Note that this setting
will be lost if the cluster is ever re-built, so you may wish to document or create an init type job that forces the
setting.

### Option 2: removing nodes

If there are surplus nodes in a CockroachDB cluster (either by original intent or by accident), or you have nodes in an
irreparable state, those nodes can be
[decommissioned](https://www.cockroachlabs.com/docs/stable/node-shutdown.html?filters=decommission).

Please be aware that if you reduce the kubernetes side replica count without explicitly decommissioning the nodes,
you run a real risk of ranges becoming unavailable and a resulting cluster outage. Should such circumstances occur, the
best option is to [re-add those nodes](#option-3-re-adding-nodes), wait for the cluster to become healthy again, and
then apply the following steps as normal.

#### Decommission

First, locate the IDs of the nodes you wish to decommission. When scaling a statefulset down, kubernetes will always
remove pods from the tail end of the set to achieve the target replica count. So for example, a 5 node CockroachDB
cluster may have the following pods:

- `cockroachdb-0`
- `cockroachdb-1`
- `cockroachdb-2`
- `cockroachdb-3`
- `cockroachdb-4`

And after scaling to 3, we'd expect there to be the following pods:

- `cockroachdb-0`
- `cockroachdb-1`
- `cockroachdb-2`

So `cockroachdb-3` and `cockroachdb-4` will have been removed.

Given the parameters you're dealing with, first determine which pods are expected to be removed when the replica count
is dropped. Then determine which CockroachDB node ID is assigned to nodes running on those pods - this can be achieved
by either inspecting the DB console, or by running `cockroach node status` in the `cockroachdb-client` deployment:

```
$ kubectl --context=<cluster> --namespace=<namespace> exec deployments/cockroachdb-client -c cockroachdb-client -- cockroach node status
id      address sql_address     build   started_at      updated_at      locality        is_available    is_live
1       cockroachdb-0.cockroachdb.namespace.svc.cluster.local:26257       cockroachdb-0.cockroachdb.namespace.svc.cluster.local:26257       v21.1.12        2022-03-28 13:07:45.605608      2022-04-07 13:22:38.441553                true    true
2       cockroachdb-2.cockroachdb.namespace.svc.cluster.local:26257       cockroachdb-2.cockroachdb.namespace.svc.cluster.local:26257       v21.1.12        2022-03-28 10:10:42.439315      2022-04-07 13:22:36.03664         true    true
3       cockroachdb-1.cockroachdb.namespace.svc.cluster.local:26257       cockroachdb-1.cockroachdb.namespace.svc.cluster.local:26257       v21.1.12        2022-03-28 14:31:19.07911       2022-04-07 13:22:38.883085                true    true
4       cockroachdb-4.cockroachdb.namespace.svc.cluster.local:26257       cockroachdb-4.cockroachdb.namespace.svc.cluster.local:26257       v21.1.12        2022-03-28 16:23:27.421104      2022-04-07 13:22:35.658349                true    true
5       cockroachdb-3.cockroachdb.namespace.svc.cluster.local:26257       cockroachdb-3.cockroachdb.namespace.svc.cluster.local:26257       v21.1.12        2022-03-28 12:33:26.462544      2022-04-07 13:22:35.790106                true    true
```

Sticking with the example where we're scaling from 5 to 3, we'd want to determine the node IDs for `cockroachdb-3` and
`cockroachdb-4`. Based on the above output, the node ID for `cockroachdb-3` is 5, and the node ID for `cockroachdb-4`
is 4. For the avoidance of any doubt: the numeric value on the end of each pods name and related hostname have zero
bearing on the ID used by CockroachDB. Always locate the node ID via the DB console or `cockroach node status`.

Once you have determined the IDs of the nodes that require decommissioning, you can tell the cluster to decommission
those nodes. Ideally this is done one at time. Each respective node can be decommissioned via
`cockroach node decommission <node-id>`. This can be executed via the `cockroachdb-client` deployment:

```
$ kubectl --context=<cluster> --namespace=<namespace> exec deployments/cockroachdb-client -c cockroachdb-client -- cockroach node decommission <node-id>
```

The output of the command should give an indication of progress. If at any point during or after you wish to check the
status of the various nodes, you can run `cockroach node status --decommission`; the `membership` for the node being
decommissioned should ultimately update to `decommissioned` once the process has completed. You can also observe changes
from the DB console:

- the replica count against the decommissioning node should fall at time goes on
- the node should ultimately show as decommissioned once the process has completed

Once the node is observed to be decommissioned, check the cluster is still showing healthy.

If there are further nodes to decommission, simply repeat this step which each respective node ID.

#### Decrease replica count

Once the target nodes have been decommissioned, the kubernetes side replica count can be reduced to match the desired
number. So if you are decreasing from 5 to 3, the nodes relating to `cockroachdb-3` and `cockroachdb-4` are expected to
be decommissioned by this stage. The replica count can then be changed as follows:

To achieve this, simply
set the replicas count to the target value via the kustomize
[`replicas` directive](https://github.com/kubernetes-sigs/kustomize/blob/master/examples/replicas.md)

```diff
--- a/cluster/namespace/kustomization.yaml
+++ b/cluster/namespace/kustomization.yaml
@@ -201,5 +201,9 @@ resources:
   - 01-auth.yaml
   - 02-network-policies.yaml
   - github.com/utilitywarehouse/cockroachdb-manifests//base?ref=v21.2.8-0
 
replicas:
  - name: cockroachdb
-   count: 5
+   count: 3

 patchesStrategicMerge:
   - cockroach.yaml
```

(or in this instance the replicas direct can be removed entirely, as the default is 3). The kubernetes side change
should be applied as normal.

#### Remove orphaned PVCs

When scaling a statefulset down, kubernetes does not by default remove the PVCs associated with removed pods. This is
a useful property in a number of settings. However, with CockroachDB, once a node is decommissioned, it is permanently
in that state and cannot be recovered. With that in mind, it is diligent to remove any associated PVCs to avoid any
future confusion should you wish to scale up again. To delete the PVCs, simply remove those associated with the now
removed pods:

```
$ kubectl --context=<cluster> --namespace=<namespace> delete pvc datadir-<pod-name>
```

With the prior example where `cockroachdb-3` and `cockroachdb-4` have been removed, this would end up looking like:

```
$ kubectl --context=<cluster> --namespace=<namespace> delete pvc datadir-cockroachdb-3
$ kubectl --context=<cluster> --namespace=<namespace> delete pvc datadir-cockroachdb-4
```

#### Decrease replication factor (optional)

If the replication factor has been previously increased whilst adding nodes (see
[Increase replication factor (optional)](#increase-replication-factor-optional)), you _may_ wish to now decrease it.
CockroachDB is happy to operate with a higher requested replica count than can be achieved via the number of nodes in
the cluster, so the replication factor only needs to be decreased if you want it to be a value that is lower than the
node count.

For example, if you are running a 7 node cluster with a replication factor of 7, and then reduce the node count to 5, if
you're happy with 5 replicas being stored, then there is nothing to do - however, if you now wanted to operate with 3 
replicas being stored, you'd need to adjust the replication factor.

Refer to [Increase replication factor (optional)](#increase-replication-factor-optional) for instructions on changing
value.

### Option 3: re-adding nodes

If nodes have been taken offline, it _may_ be possible to bring them back into action.

#### Non-decommissioned nodes

If you've accidentally scaled a cluster down without decommissioning nodes, you may be facing issues due to unavailable
ranges. To re-add nodes in such circumstances, simply increase the replica count again:

```diff
--- a/cluster/namespace/kustomization.yaml
+++ b/cluster/namespace/kustomization.yaml
@@ -201,5 +201,9 @@ resources:
   - 01-auth.yaml
   - 02-network-policies.yaml
   - github.com/utilitywarehouse/cockroachdb-manifests//base?ref=v21.2.8-0
 
replicas:
  - name: cockroachdb
-   count: 3
+   count: 5

 patchesStrategicMerge:
   - cockroach.yaml
```

Apply as normal, and hopefully the cluster will become healthy again. Assuming you still wish to scale down to the 
a lower replica count, [follow the process documented above](#option-2-removing-nodes).

#### Decommissioned nodes

CockroachDB does support
[recommissioning nodes](https://www.cockroachlabs.com/docs/v21.2/node-shutdown?filters=decommission#recommission-nodes),
but only if the node is in _decommissioning_ state. Once a node is decommissioned, it is permanently in that state and
cannot be recommissioned. With that in mind, if any PVCs are still around covering pods that would come into existence
after increasing the kubernetes side replica count, these need to be removed.

Once you have verified no PVCs will be claimed when scaling up, [add the desired nodes as normal](#option-1-adding-nodes).

### Option 4: replacing nodes

There are very occasional circumstances where a node may need to be replaced. Almost always this is because of a node
getting into some corrupted state due to a bug.

#### Scale up (if necessary)

When replacing a problematic node, the node will first off need decommissioning. When taking the replication count into
consideration, it is important to note that CockroachDB to does not treat a decommissioning node as contributing to
target value. So if `num_replicas` is set to 5 for a given zone, with 5 nodes in the cluster, it is permitted to reduce
down to 4 nodes; CockroachDB will simply look to have 4 replicas stored. The exception to this rule is when operating a
3 node cluster - CockroachDB generally does not want to let you reduce to 2 nodes - as a CockroachDB employee puts it:

> What you WILL have trouble with, is decommissioning from a 3 node cluster to a 2 node cluster. It's like when Ant-Man
> enters the Quantum Realm - the rules start to change when things get small.

With that in mind, if you're operating with a 3 node cluster, you at minimum need to add 1 additional node before
proceeding. Nodes can be added via the [normal process](#option-1-adding-nodes). You _may_ be able to get away with
leaving the node in decommissioning state, continuing the process, then attempt to decommission again once the
replacement node is action; your mileage may vary, and this is generally not recommended. 

#### Stop the problematic node

The node that requires replacement may be crash looping or otherwise misbehaving depending on the nature of the problem.
It is worth stopping it not only to avoid this causing any potential problems whilst decommissioning, but also to make
it simpler to remove the underlying PVC.

One of the easiest options to achieve this is to temporarily remove the underlying statefulset with the orphan flag set:
this ensures that the pods remain active, but also means that any pods that are stopped do not come back up.

```
$ kubectl --context=<cluster> --namespace=<namespace> delete sts --cascade=orphan cockroachdb
```

Once this is done, delete the pod that requires replacement:

```
$ kubectl --context=<cluster> --namespace=<namespace> delete pod <pod-name>
```

#### Decommission the problematic node

The node should be decommissioned in a similar fashion to the process applied when
[scaling a cluster down to fewer nodes](#decommission):

- locate the CockroachDB node ID relating to the problematic node via `cockroach node status` or the DB console
- run `cockroach node decommission <node-id>` via the `cockroachdb-client` deployment
- wait for the decommissioning process to finish

#### Remove the PVC

Once the node has been confirmed to be decommissioned, you can delete the underlying PVC:

```
$ kubectl --context=<cluster> --namespace=<namespace> delete pvc datadir-<pod-name>
```

#### Re-apply manifests

After the PVC has been cleared, you can re-apply the manifests as normal (if kube-applier is in use, just hit "Force
apply run" on relevant namespace). This will re-create the statefulset, at which point kubernetes will notice the
missing pod and underlying PVC, and provision them.

## After applying changes

### Re-check cluster health

Whether you're adding, removing, re-adding, or replacing nodes, you should always check on the state of the cluster
after making modifications. The same steps [taken before applying changes](#check-cluster-health) can be applied after -
in particular make sure there are no under-replicated ranges being reported.
