# PVC resize

This runbook looks to document how to deal with increasing the size of PVCs associated with CockroachDB deployments in
kubernetes. For the purposes of this guide we will be discussing and providing examples in relation to this specific
kustomize base, but the equivalent process can be applied for any statefulset.

<!-- ToC start -->
## Table of Contents

   1. [Prepare changes](#prepare-changes)
      1. [Determine where PVC size is defined](#determine-where-pvc-size-is-defined)
      1. [Raise a PR increasing the PVC size](#raise-a-pr-increasing-the-pvc-size)
         1. [With an existing overlay](#with-an-existing-overlay)
         1. [Without an existing overlay](#without-an-existing-overlay)
      1. [Disable kube-applier](#disable-kube-applier)
   1. [Apply changes](#apply-changes)
      1. [Edit PVCs](#edit-pvcs)
      1. [Delete statefulset](#delete-statefulset)
      1. [Merge your PR](#merge-your-pr)
      1. [Apply manifests](#apply-manifests)
<!-- ToC end -->

## Prepare changes

### Determine where PVC size is defined

This first step is to figure our what is dictating the size of the existing PVCs. This kustomize base currently
[defaults to 10GB](https://github.com/utilitywarehouse/cockroachdb-manifests/blob/795a82920d5977d7c07ace1ba73969f3e39d4411/base/statefulset.yaml#L196),
for the PVC size. You can view the current size of the PVCs by executing the following:

```
$ kubectl --context=<cluster> --namespace=<namespace> get pvc | grep '^datadir-cockroachdb'
datadir-cockroachdb-0                     Bound    pvc-ce911399-2c65-4e87-9eb8-54e430552d1e   100Gi      RWO            netapp-ontap-san-ext4   348d
datadir-cockroachdb-1                     Bound    pvc-00bc70ad-aba2-4501-be6b-036e56b1a574   100Gi      RWO            netapp-ontap-san-ext4   348d
datadir-cockroachdb-2                     Bound    pvc-b0a99819-0fd3-45ca-b4d2-60c621196ece   100Gi      RWO            netapp-ontap-san-ext4   348d
```

If the size is greater than 10GB it is almost certainly the case that an overlay is in use.

### Raise a PR increasing the PVC size

A PR should be raised to the kubernetes-manifests repository. The PR is expected to be modifying the requested
storage size in the `volumeClaimTemplates` section of the `cockroachdb` statefulset.

#### With an existing overlay

If you already have an overlay that patches the PVC size, simply adjust the value:

```diff
--- a/cluster/namespace/cockroachdb.yaml
+++ b/cluster/namespace/cockroachdb.yaml
@@ -11,4 +11,4 @@ spec:
           - "ReadWriteOnce"
         resources:
           requests:
-            storage: 100Gi
+            storage: 120Gi
```

#### Without an existing overlay

In the `kustomize.yaml` that imports this base, apply the following type of change, setting the
`volumeClaimTemplates[0].spec.resources.requests.storage` value as desired:

```diff
--- /dev/null
+++ b/cluster/namespace/cockroachdb.yaml
@@ -0,0 +1,14 @@
+apiVersion: apps/v1
+kind: StatefulSet
+metadata:
+  name: cockroachdb
+spec:
+  volumeClaimTemplates:
+    - metadata:
+        name: datadir
+      spec:
+        accessModes:
+          - "ReadWriteOnce"
+        resources:
+          requests:
+            storage: 100Gi
--- a/cluster/namespace/kustomization.yaml
+++ b/cluster/namespace/kustomization.yaml
@@ -200,3 +200,6 @@ resources:
   - 01-auth.yaml
   - 02-network-policies.yaml
   - github.com/utilitywarehouse/cockroachdb-manifests//base?ref=v21.2.8-0
+
+patchesStrategicMerge:
+  - cockroachdb.yaml
```

### Disable kube-applier

If your namespace has kube-applier in use, you may wish to disable it temporarily whilst you make changes.
Alternatively, you can put it into dry-run mode.

## Apply changes

The `volumeClaimTemplates` section of a statefulset is immutable. Due to that, simply merging the changes prepared above
will result in an error on apply. To work around this we must edit the underlying PVCs by hand, and then do some
trickery to get the statefulset change applied.

### Edit PVCs

First, list out the PVCs:

```
$ kubectl --context=<cluster> --namespace=<namespace> get pvc | grep '^datadir-cockroachdb'
datadir-cockroachdb-0                     Bound    pvc-ce911399-2c65-4e87-9eb8-54e430552d1e   100Gi      RWO            netapp-ontap-san-ext4   348d
datadir-cockroachdb-1                     Bound    pvc-00bc70ad-aba2-4501-be6b-036e56b1a574   100Gi      RWO            netapp-ontap-san-ext4   348d
datadir-cockroachdb-2                     Bound    pvc-b0a99819-0fd3-45ca-b4d2-60c621196ece   100Gi      RWO            netapp-ontap-san-ext4   348d
```

Starting with `datadir-cockroachdb-0`, edit the PVC:

```
$ kubectl --context=<cluster> --namespace=<namespace> edit pvc datadir-cockroachdb-0
```

(this will open the yaml representation of the PVC in your `$EDITOR`)

Locate the following section:

```yaml
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: netapp-ontap-san-ext4
  volumeMode: Filesystem
  volumeName: pvc-ce911399-2c65-4e87-9eb8-54e430552d1e
```

and modify the `storage` value to match the change in your PR:

```diff
--- a/...
+++ b/...
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
-     storage: 100Gi
+     storage: 120Gi
  storageClassName: netapp-ontap-san-ext4
  volumeMode: Filesystem
  volumeName: pvc-ce911399-2c65-4e87-9eb8-54e430552d1e
```

Finally, exit your `$EDITOR`.

To view the progress of the resize, you can describe the PVC:

```
$ kubectl --context=<cluster> --namespace=<namespace> describe pvc datadir-cockroachdb-0 
Name:          datadir-cockroachdb-0
Namespace:     <namespace>
StorageClass:  netapp-ontap-san-ext4
Status:        Bound
Volume:        pvc-ce911399-2c65-4e87-9eb8-54e430552d1e
Labels:        app=cockroachdb
Annotations:   pv.kubernetes.io/bind-completed: yes
               pv.kubernetes.io/bound-by-controller: yes
               volume.beta.kubernetes.io/storage-provisioner: csi.trident.netapp.io
Finalizers:    [kubernetes.io/pvc-protection]
Capacity:      100Gi
Access Modes:  RWO
VolumeMode:    Filesystem
Used By:       cockroachdb-0
Conditions:
  Type                      Status  LastProbeTime                     LastTransitionTime                Reason  Message
  ----                      ------  -----------------                 ------------------                ------  -------
  FileSystemResizePending   True    Mon, 01 Jan 0001 00:00:00 +0000   Wed, 13 Apr 2022 16:58:03 +0100           Waiting for user to (re-)start a pod to finish file system resize of volume on node.
Events:
  Type     Reason                    Age   From                                    Message
  ----     ------                    ----  ----                                    -------
  Normal   Resizing                  21s   external-resizer csi.trident.netapp.io  External resizer is resizing volume pvc-ce911399-2c65-4e87-9eb8-54e430552d1e
  Warning  ExternalExpanding         21s   volume_expand                           Ignoring the PVC: didn't find a plugin capable of expanding the volume; waiting for an external controller to process this PVC.
  Normal   FileSystemResizeRequired  21s   external-resizer csi.trident.netapp.io  Require file system resize of volume on node
```

Note that the information made available may vary depending on the environment.

After a short while you should hopefully find that the PVC is showing with an increased size:

```
$ kubectl --context=<cluster> --namespace=<namespace> get pvc | grep '^datadir-cockroachdb'
datadir-cockroachdb-0                     Bound    pvc-ce911399-2c65-4e87-9eb8-54e430552d1e   120Gi      RWO            netapp-ontap-san-ext4   348d
datadir-cockroachdb-1                     Bound    pvc-00bc70ad-aba2-4501-be6b-036e56b1a574   100Gi      RWO            netapp-ontap-san-ext4   348d
datadir-cockroachdb-2                     Bound    pvc-b0a99819-0fd3-45ca-b4d2-60c621196ece   100Gi      RWO            netapp-ontap-san-ext4   348d
```

Repeat this step for the remaining PVCs, until all are showing with the expected size:

```
$ kubectl --context=<cluster> --namespace=<namespace> get pvc | grep '^datadir-cockroachdb'
datadir-cockroachdb-0                     Bound    pvc-ce911399-2c65-4e87-9eb8-54e430552d1e   120Gi      RWO            netapp-ontap-san-ext4   348d
datadir-cockroachdb-1                     Bound    pvc-00bc70ad-aba2-4501-be6b-036e56b1a574   120Gi      RWO            netapp-ontap-san-ext4   348d
datadir-cockroachdb-2                     Bound    pvc-b0a99819-0fd3-45ca-b4d2-60c621196ece   120Gi      RWO            netapp-ontap-san-ext4   348d
```

### Delete statefulset

Deleting and re-applying the statefulset is currently the simplest workaround to deal with the problems associated with
`volumeClaimTemplates` being immutable. When deleting the statefulset, it is important to tell kubernetes to orphan
the pods, etc - failing to do some will mean the kubernetes scheduler will scale down the entire cluster.

Delete the statefulset using the following:

```
$ kubectl --context=<cluster> --namespace=<namespace> delete sts --cascade=orphan cockroachdb                 
statefulset.apps "cockroachdb" deleted
```

### Merge your PR

Merge the PR containing the change that updates the `volumeClaimTemplates` value against the `cockroachdb` statefulset.

### Apply manifests

If you have disabled kube-applier, you can now re-enable it. In doing so, it may apply automatically - or failing that,
the `Force apply run` button can be clicked in the relevant UI to force it to apply.

If kube-applier is not in use, apply the changes as you normally would.

Pod restarts might be required for the PVC resizes to finalise. After applying, the `cockroachdb` pods may automatically
restart (this is currently the observed behaviour in merit). If for some reason they do not restart, you can force the
statefulset to roll by executing the following:

```
$ kubectl --context=<cluster> --namespace=<namespace> rollout restart sts cockroachdb                 
statefulset.apps/cockroachdb restarted
```
