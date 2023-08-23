# Backups

This runbook describes the backup procedure and how to restore from a backup.

## How to backup

Using the manifests in this repo you have the option of setting a backup URL using the [configuration files](../examples/config/backup-config) and the [backup script](../base/scripts.yaml). This will automatically setup the backup schedule for you and if you have setup your s3 bucket and [vault injector](https://github.com/utilitywarehouse/documentation/blob/master/infra/vault/vault-aws.md) already the backups will all happen automatically on your schedule.

When updating backup configs (e.g. schedule or url), existing crdb schedule might need to be dropped first. See the docs on how to [manage](https://www.cockroachlabs.com/docs/stable/manage-a-backup-schedule) or [drop](https://www.cockroachlabs.com/docs/v23.1/drop-schedules) these.
In order for the new backup schedule to get created in the db the backup job needs to run again. Deleting the (existing, but previously) completed job and rerunning kube-applier will trigger it.

## Restoring a backup

The cockroach team have a complete example of restoring from a backup [here](https://www.cockroachlabs.com/docs/stable/restore.html)
