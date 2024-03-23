# Backups

This runbook describes the backup procedure and how to restore from a backup.

## How to backup

Using the manifests in this repo you have the option of setting a backup URL using the [configuration files](../examples/config/backup-config) and the [backup script](../base/scripts.yaml). This will automatically setup the backup schedule for you and if you have setup your s3 bucket and [vault injector](https://github.com/utilitywarehouse/documentation/blob/master/infra/vault/vault-aws.md) already the backups will all happen automatically on your schedule.

When updating backup configs (e.g. schedule or url), existing crdb schedule might need to be dropped first. See the docs on how to [manage](https://www.cockroachlabs.com/docs/stable/manage-a-backup-schedule) or [drop](https://www.cockroachlabs.com/docs/v23.1/drop-schedules) these.
In order for the new backup schedule to get created in the db the backup job needs to run again. Deleting the (existing, but previously) completed job and rerunning kube-applier will trigger it.

## Restoring a backup

The cockroach team have a complete example of restoring from a backup [here](https://www.cockroachlabs.com/docs/stable/restore.html)

## Checking the backup ran

CockroachDB exports various Prometheus metrics, including the state of backup jobs. You can use these to alert you to the fact that a backup may not have successfully run for a period of time. 

`jobs_backup_resume_completed` is increased by the node that successfully coordinated the backup for that run, so to make sure you are looking at the backup status across the cluster you would typically write the following query, which assumes you have 1 cluster for the namespace:

```
sum by (kubernetes_namespace) (increase(jobs_backup_resume_completed{kubernetes_namespace=~"auth|auth-customer"}[14h])) == 0
```

While the backup job may have successfully run, that is not a full proof way of confirming you'll be able to restore it 😅
