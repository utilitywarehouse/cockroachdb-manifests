# CockroachDB upgrade

This runbook looks to document how to orchestrate CockroachDB version updates. Please keep in mind that, whilst many
parts of this guide are universal in relation to CockroachDB, some steps are specific to deployments created via this
kustomize base.

<!-- ToC start -->
## Table of contents

   1. [Before upgrading](#before-upgrading)
      1. [Figure out what type of upgrade is to be applied](#figure-out-what-type-of-upgrade-is-to-be-applied)
      1. [Locate the appropriate tag](#locate-the-appropriate-tag)
      1. [Check cluster status](#check-cluster-status)
         1. [Verify pods are running and showing healthy](#verify-pods-are-running-and-showing-healthy)
         1. [Inspect DB Console](#inspect-db-console)
         1. [List nodes](#list-nodes)
         1. [Check the internal cluster version](#check-the-internal-cluster-version)
      1. [Notify teams](#notify-teams)
      1. [Create a manual backup](#create-a-manual-backup)
      1. [Clear init and backup jobs](#clear-init-and-backup-jobs)
   1. [Upgrade](#upgrade)
      1. [Option 1: patch version upgrade](#option-1-patch-version-upgrade)
         1. [Update manifests and apply](#update-manifests-and-apply)
      1. [Option 2: major version upgrade](#option-2-major-version-upgrade)
         1. [Review upgrade guide](#review-upgrade-guide)
         1. [Disable auto upgrade finalization](#disable-auto-upgrade-finalization)
         1. [Update manifests and apply](#update-manifests-and-apply-1)
   1. [Monitor](#monitor)
   1. [Finish](#finish)
      1. [Finalize (if required)](#finalize-if-required)
         1. [Verify](#verify)
      1. [Rollback (if required)](#rollback-if-required)
         1. [Disaster recovery](#disaster-recovery)
<!-- ToC end -->

## Before upgrading

### Figure out what type of upgrade is to be applied

When looking to upgrade to a newer version of CockroachDB, it is important to understand the nature of the upgrade.
CockroachDB does not use semantic versioning, rather, calendar-based versioning is used with the following format:

```
<2-digit-year>.<release-number>.<patch-release-number>
```

Breaking changes are typically made across `<2-digit-year>.<release-number>` increases.

For want of better terms, in this guide we will refer to "major" and "patch" version updates. When reviewing the
differences between the old and new versions of CockroachDB, if the `<2-digit-year>.<release-number>` section is
changing, this implies a major version update. If just the `<patch-release-number>` element has changed, this implies a
patch version update.

To show that by example:

- before = `v21.1.16`, after = `v21.2.0`: major
- before = `v21.1.1`, after = `v21.1.16`: patch
- before = `v21.2.7`, after = `v22.1.0`: major

### Locate the appropriate tag

Check https://github.com/utilitywarehouse/cockroachdb-manifests/tags

If the target version is new, and a tag has not yet been created, please open a PR to adjust the image tag in master.
After that has been merged, a new release can be created. Note that the tagging strategy in this repository is:

```
<cockroach-version>-<manifests-version-number>
```

That is to say, when CockroachDB `v22.1.0` is released, a tag will be created named `v22.1.0-1`. If we make further
changes to the manifests, but no CockroachDB version change is made, we may create a new tag named `v22.1.0-2`.
(Release count starts at 1, similarly to other UW repositories.)
You should typically look to use the most recent tag pertaining to the CockroachDB version you are targeting. Due to the
nature of these manifests, you should review any changes between the current and target tag. One convenient way to do 
this is via

```
https://github.com/utilitywarehouse/cockroachdb-manifests/compare/<curent-tag>...<target-tag>
```

e.g. https://github.com/utilitywarehouse/cockroachdb-manifests/compare/v21.2.1-0...v21.2.7-1

### Check cluster status

Before moving forward with the upgrade, you should first verify the cluster is in a healthy state. This can be achieved
through numerous options.

#### Verify pods are running and showing healthy

Make sure from the kubernetes side of affairs, all the pods are healthy and all underlying containers are running:

```
$ kubectl --context=<cluster> --namespace=<namespace> get pods | rg 'cockroachdb-[0-9]'
cockroachdb-0                                                     3/3     Running                      0                  16m
cockroachdb-1                                                     3/3     Running                      0                  25h
cockroachdb-2                                                     3/3     Running                      2 (14h ago)        6d20h
```

If any pods are crash looping, or containers are missing from any pods (e.g. if one were to show `2/3`), this would need
to be investigated and resolved before any upgrades are applied.

#### Inspect DB Console

The DB Console gives a decent overview of the health of nodes in a cluster, amongst other things. _TODO: link to
documentation that explains how to access the DB Console_.

Once you have the console open, check the following:

- Replication Status: there should be no under-replicated ranges indicated
- Node Status: all nodes should be displayed as live
- Nodes List: all nodes should be indicating the same version
- Jobs (in the sidebar): having jobs active during an upgrade is technically fine (unless otherwise indicated by 
CockroachDB documentation), however, it might be diligent to verify that there are no stuck jobs. If there are any long
running jobs it may be worth allowing these to compete before proceeding.

#### List nodes

You can also look to inspect the status of nodes via `cockroach node status`. This can be issued via the
`cockroachdb-client` deployment. In particular, you should look out of any nodes stuck in `decommissioning` status, as
this may block the upgrade:

```
$ kubectl --context=<cluster> --namespace=<namespace> exec deployments/cockroachdb-client -c cockroachdb-client -- cockroach node status --decommission
id      address sql_address     build   started_at      updated_at      locality        is_available    is_live gossiped_replicas       is_decommissioning      membership      is_draining
1       cockroachdb-0.cockroachdb.namespace.svc.cluster.local:26257       cockroachdb-0.cockroachdb.namespace.svc.cluster.local:26257       v21.2.7 2022-03-30 14:19:50.692222      2022-03-30 15:06:19.708401true    true    4373    false   active  false
2       cockroachdb-2.cockroachdb.namespace.svc.cluster.local:26257       cockroachdb-2.cockroachdb.namespace.svc.cluster.local:26257       v21.2.7 2022-03-30 00:02:15.486786      2022-03-30 15:06:21.227482true    true    4373    false   active  false
3       cockroachdb-1.cockroachdb.namespace.svc.cluster.local:26257       cockroachdb-1.cockroachdb.namespace.svc.cluster.local:26257       v21.2.7 2022-03-29 13:05:01.599074      2022-03-30 15:06:19.663817true    true    4373    false   active  false
```

#### Check the internal cluster version

Optionally you may wish to check that the internal cluster version matches the binary version. If it does not, this is
bad sign, and you should investigate before proceeding.

The version displayed in the DB console, etc, is typically going to be the binary version. To check the cluster version,
run the following:

```
$ kubectl --context=<cluster> --namespace=<namespace> exec deployment/cockroachdb-client -c cockroachdb-client -- cockroach sql --execute 'SHOW CLUSTER SETTING version;'
```

As an example, for a cluster running the `v21.2.7`, the above should output `21.2`.

### Notify teams

Before triggering the upgrade, you may wish to notify developers that are familiar with the target cluster. There are
a couple of reasons behind this:

- the timing of the upgrade might be sensitive for some reason
- if there are any issues relating to the upgrade, they'll have some context

Assuming there are no problems flagged, continue on.

### Create a manual backup (optional)

When moving to a new major version, whilst no issues are expected from upgrading CockroachDB, it is diligent to create a
backup before upgrading, _just in case_. If you're moving to a new patch version you may choose to omit this step,
considering the even lesser likelihood of issues and the ease at which you can rollback.

CockroachDB clusters deployed against this kustomize base are expected to use the native backup mechanism, which makes
it trivial to make ad-hoc backups. Simply use the same bucket and path (if applicable) that is targeted by the scheduled
backups:

```sql
BACKUP INTO 's3://<bucket>/<path>/ad-hoc-backup-YYYYMMDD-01/?AUTH=implicit' AS OF SYSTEM TIME '-10s';
```

You can find the path in the kubernetes-manifest by searching for `destination.url` in the relevant namespace.

This can be issued via the `cockroachdb-client` deployment using the following one-liner:

```
$ kubectl --context=<cluster> --namespace=<namespace> exec deployments/cockroachdb-client -c cockroachdb-client -- cockroach sql --execute "BACKUP TO 's3://<bucket>/<path>/ad-hoc-backup-YYYYMMDD-01/?AUTH=implicit' AS OF SYSTEM TIME '-10s';"
```

### Clear init and backup jobs

Before applying an upgrade, any existing `cockroach-init` and `cockroach-backup-init` jobs should be removed. This is
because the manifests for these jobs will start to reference the newer version, and since jobs are immutable, an error
will appear when looking to apply:

```
The Job "cockroach-init" is invalid: spec.template: Invalid value: <snip>: field is immutable
```

To clear the jobs, simply run the following:

```
$ kubectl --context=<cluster> --namespace=<namespace> delete job cockroach-init cockroach-backup-init
```

Note that the jobs will be recreated when the manifests are next applied - it is safe for both jobs to be re-run.

## Upgrade

The instructions are slightly different depending on the nature of the upgrade, so:

- for patch version upgrades, jump to [`Option 1: patch version upgrade`](#option-1-patch-version-upgrade)
- for major version upgrades, jump to [`Option 2: major version upgrade`](#option-2-major-version-upgrade)

### Option 1: patch version upgrade

Unless otherwise stated in any documentation from CockroachDB, no breaking changes or complex internal migrations are
made in patch releases. With that being the case, you can freely move up (or indeed down) patch versions as desired. All
that said, it would still be diligent to review the [release notes](https://www.cockroachlabs.com/docs/releases/index.html)
and [technical advisories](https://www.cockroachlabs.com/docs/advisories/index.html) before proceeding.

#### Update manifests and apply

Adjust the kustomize base ref to match the new target version. For example:

```diff
--- a/cluster/namespace/kustomization.yaml
+++ b/cluster/namespace/kustomization.yaml
@@ -57,7 +57,7 @@ resources:
   - 00-namespace.yaml
   - 01-auth.yaml
   - 02-network-policies.yaml
-  - github.com/utilitywarehouse/cockroachdb-manifests//base?ref=v21.2.6-0
+  - github.com/utilitywarehouse/cockroachdb-manifests//base?ref=v21.2.7-0
 
 patchesStrategicMerge:
   - cockroach.yaml
```

Then apply as normal (either by hand, or via kube-applier).

### Option 2: major version upgrade

It is important to note that you can only move 1 major version at a time. That is to say, you would be able to upgrade
from `v21.1` to `v21.2`, but you wouldn't be able to upgrade directly from `v19.2` to `v21.2`. If there is more than
one version between the current and target version, you need to upgrade one version at a time. For example, to move from
`v19.2` to `v21.2`, you'd first upgrade to `v21.1`, and then upgrade to `v21.2`.

#### Review upgrade guide

CockroachDB produce upgrade guides for each major version change. The relevant version should be reviewed before 
proceeding:

- 23.1 to 23.2: https://www.cockroachlabs.com/docs/v23.2/upgrade-cockroach-version
- 22.2 to 23.1: https://www.cockroachlabs.com/docs/v23.1/upgrade-cockroach-version.html
- 22.1 to 22.2: https://www.cockroachlabs.com/docs/v22.2/upgrade-cockroach-version.html
- 21.2 to 22.1: https://www.cockroachlabs.com/docs/v22.1/upgrade-cockroach-version.html
- 21.1 to 21.2: https://www.cockroachlabs.com/docs/v21.2/upgrade-cockroach-version.html
- 20.2 to 21.1: https://www.cockroachlabs.com/docs/v21.1/upgrade-cockroach-version.html
- 20.1 to 20.2: https://www.cockroachlabs.com/docs/v20.2/upgrade-cockroach-version.html
- 19.2 to 20.1: https://www.cockroachlabs.com/docs/v20.1/upgrade-cockroach-version
- 19.1 to 19.2: https://www.cockroachlabs.com/docs/v19.2/upgrade-cockroach-version

#### Disable auto upgrade finalization

When CockroachDB finalizes an upgrade, it applies internal migrations, amongst other things, to unlock new features
and bring the internal state in line with new expectations. Due to the nature of this, upgrade finalization is a
"no turning back" type operation.

CockroachDB defaults to automatically finalizing an upgrade once all nodes in a cluster are running the newer version.
This is undoubtedly convenient, but it also carries risks. We've had more than one incident where a cluster has been
finalized against a new version, but there have been issues appear relating to the upgrade after that point. With that
in mind, you can proceed with the default auto upgrade finalization enabled, or, you may wish to disable it (which the
CockroachDB team recommend).

To disable auto upgrade finalization, you need to tell CockroachDB that you wish to have the option to downgrade back to
the previous version (ignoring the patch element). This can be achieved by setting the
`cluster.preserve_downgrade_option` cluster setting via the `cockroachdb-client` deployment.

So for example, if you're upgrading from `v21.1.16` to `v21.2.7`, you'd execute the following:

```sql
SET CLUSTER SETTING cluster.preserve_downgrade_option = '21.1';
```

To execute this via the `cockroachdb-client` deployment, the following one-liner can be used:

```
$ kubectl --context=<cluster> --namespace=<namespace> exec deployments/cockroachdb-client -c cockroachdb-client -- cockroach sql --execute "SET CLUSTER SETTING cluster.preserve_downgrade_option = '21.1';"
```

At any point you wish to check what this value is set to, simply run:

```sql
SHOW CLUSTER SETTING cluster.preserve_downgrade_option;
```

#### Update manifests and apply

Adjust the kustomize base ref to match the target version. As a reminder, the target version can only be one increment
above the previous (excluding the patch element).

```diff
--- a/cluster/namespace/kustomization.yaml
+++ b/cluster/namespace/kustomization.yaml
@@ -57,7 +57,7 @@ resources:
   - 00-namespace.yaml
   - 01-auth.yaml
   - 02-network-policies.yaml
-  - github.com/utilitywarehouse/cockroachdb-manifests//base?ref=v21.1.16-0
+  - github.com/utilitywarehouse/cockroachdb-manifests//base?ref=v21.2.7-0
 
 patchesStrategicMerge:
   - cockroach.yaml
```

Then apply as normal (either by hand, or via kube-applier).

## Monitor

Once the updated manifests have been applied, the following behaviour is expected to be observed:

- all the pods relating to the `cockroachdb` stateful set will restart, moving to the new image tag
- the `cockroachdb-client` deployment job will restart, moving to the new image tag
- `cockroach-init` and `cockroach-backup-init` jobs will spawn - both are safe run at any point, so don't be alarmed

After the above has completed, keep an eye out for alerts.

## Finish

To finish the upgrade, you may need to finalize. If the upgrade has not gone to plan, you can look to roll it back.

### Finalize (if required)

This step is only required for major version upgrades, where auto upgrade finalization was disabled.

Once a suitable period of time has elapsed running against the new version of CockroachDB, you can look to finalize the
upgrade. The amount of time you leave the cluster in a non upgrade finalized state will vary case by case, but at 
minimum you should look to give it at least 1 day.

Before finalizing, check that the cluster is healthy (see [`Check cluster status`](#check-cluster-status))

Once you're happy that the cluster is stable, issue the following statement via the `cockroachdb-client` deployment:

```sql
RESET CLUSTER SETTING cluster.preserve_downgrade_option;
```

Unless otherwise indicated in release notes, it should _not_ be necessary to restart the nodes after executing the
above.

#### Verify

There are circumstances under which CockroachDB may decide to not move forward with finalizing the upgrade. As an
example, if there is a node stuck in "decommissioning" state, the upgrade may not complete. Whilst such circumstances
are rare and unexpected, it would be diligent to check that the cluster has finalized after resetting
`cluster.preserve_downgrade_option`.

To do so, check the output of the `version` cluster setting via the `cockroachdb-client` deployment:

```sql
SHOW CLUSTER SETTING version;
```

Note that there might be a small delay after clearing the `cluster.preserve_downgrade_option` setting before this
updates. It may also update multiple times whilst the internal state migrates.

If there is any sign that the upgrade is not finalizing correctly, you should check the job listing to see if there
are any jobs in progress;

```sql
SHOW JOBS;
```

If any jobs fail to complete, this signifies there is an issue. Unfortunately, the point of no return has likely been
hit, in which case support may be required from colleagues or the CockroachDB devs.

### Rollback (if required)

If the upgrade has undesirable results, you can look to roll it back. Note that in the case of a major version change,
this is only possible if the upgrade has not been finalized.

To roll the upgrade back, simply repeat the same steps but target the previous version. If there are issues, it is
quite possible that the cluster will not be in a healthy state; pay close attention to the DB Console, if accessible.
You may wish to confer with colleagues in deciding the best course of action to take under these circumstances.

#### Disaster recovery

If the upgrade fails in a way where rolling back is no longer viable, and the cluster cannot be made stable, the last
resort is to wipe the cluster and recover from backup (or an alternative source for the underlying data, if available).

If you wish to recover from backup, once the new cluster has been brought up, execute the following:

```sql
RESTORE FROM 's3://<bucket>/<path>/ad-hoc-backup-YYYYMMDD-01/?AUTH=implicit';
```

This should restore all databases, tables, users, etc.
