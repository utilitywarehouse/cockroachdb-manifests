# Backups

This runbook describes the backup procedure and how to restore from a backup.

## How to backup

Using the manifests in this repo you have the option of setting a backup URL using the [configuration files](../examples/config/backup-config) and the [backup script](../base/scripts.yaml). This will automatically setup the backup schedule for you and if you have setup your s3 bucket and vault injector already the backups will all happen automatically on your schedule.

## Restoring a backup

The cockroach team have a complete example of restoring from a backup [here](https://www.cockroachlabs.com/docs/stable/restore.html)
