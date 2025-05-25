# Backup Script

A versatile Bash script providing a text-based user interface (TUI) for backing up various databases and services, including MySQL/MariaDB, PostgreSQL, MongoDB, Redis, Cassandra, and Elasticsearch. The script handles logging, error reporting, and automatic cleanup of old backups based on a configurable retention policy.

---

## Table of Contents

* [Features](#features)
* [Prerequisites](#prerequisites)
* [Installation](#installation)
* [Configuration](#configuration)
* [Usage](#usage)
* [Backup Modules](#backup-modules)
* [Logging](#logging)
* [Retention Policy](#retention-policy)
* [Error Handling](#error-handling)
* [Contributing](#contributing)
* [License](#license)

---

## Features

* **Interactive TUI** via `dialog` for guided input
* **MySQL/MariaDB** dump and gzip compression
* **PostgreSQL** custom-format dump
* **MongoDB** dump via `mongodump`
* **Redis** RDB snapshot copy
* **Cassandra** snapshot via `nodetool`
* **Elasticsearch** snapshot REST API
* **Configurable** backup directory and retention period
* **Centralized logging** with timestamped messages
* **Automatic cleanup** of temporary files and old backups

---

## Prerequisites

Ensure the following commands/utilities are installed and accessible in your `$PATH`:

* `bash` (v4+)
* `dialog`
* **MySQL**: `mysql`, `mysqldump`
* **PostgreSQL**: `pg_isready`, `pg_dump`
* **MongoDB**: `mongosh`, `mongodump`
* **Redis**: `redis-cli`
* **Cassandra**: `nodetool`
* **Elasticsearch**: `curl`

---

## Installation

1. Clone or download the repository containing `backup.sh`.

2. Ensure the script is executable:

   ```bash
   chmod +x backup.sh
   ```

3. Create required directories (defaults shown):

   ```bash
   mkdir -p /var/backups/cybersir /tmp/cybersir_backup
   touch /var/log/cybersir_backup.log
   ```

4. Adjust ownership/permissions as needed:

   ```bash
   chown root:root backup.sh
   chmod 750 backup.sh
   ```

---

## Configuration

Located at the top of `backup.sh`:

| Variable         | Description                             | Default                        |
| ---------------- | --------------------------------------- | ------------------------------ |
| `BACKUP_DIR`     | Destination directory for backup output | `/var/backups/cybersir`        |
| `LOG_FILE`       | Path to the log file                    | `/var/log/cybersir_backup.log` |
| `RETENTION_DAYS` | Number of days to keep backups          | `30`                           |
| `TMP_DIR`        | Temporary working directory for errors  | `/tmp/cybersir_backup`         |

---

## Usage

Run the script interactively:

```bash
./backup.sh
```

A TUI menu will appear allowing you to choose which service to back up:

```text
 Backup :) TUI
 Select a database to back up:
 1) MySQL / MariaDB
 2) PostgreSQL
 3) MongoDB
 4) Redis
 5) Cassandra
 6) Elasticsearch
 7) Exit
```

Follow prompts to enter host, port, credentials, and database/keyspace names.

---

## Backup Modules

### MySQL / MariaDB

* Prompts for host, port, username, password, and database name
* Verifies connection before dumping
* Uses `mysqldump` piped to `gzip`
* Output file: `mysql_<db>_YYYY-MM-DD_HH-MM-SS.sql.gz`

### PostgreSQL

* Prompts for host, port, username, password, and database name
* Uses `pg_isready` to check availability
* Dumps in custom format with `pg_dump -F c`
* Output file: `postgres_<db>_YYYY-MM-DD_HH-MM-SS.dump`

### MongoDB

* Prompts for host, port, and database name
* Validates database existence via `mongosh`
* Uses `mongodump --db`
* Output directory: `mongo_<db>_YYYY-MM-DD_HH-MM-SS/`

### Redis

* Prompts for host and port
* Uses `redis-cli BGSAVE` to trigger snapshot
* Locates `dump.rdb` via `CONFIG GET dir`
* Copies to `redis_YYYY-MM-DD_HH-MM-SS.rdb`

### Cassandra

* Prompts for keyspace name
* Creates snapshot with `nodetool snapshot`
* Copies snapshots from `/var/lib/cassandra/data`
* Output directory: `cassandra_<keyspace>_YYYY-MM-DD_HH-MM-SS/`

### Elasticsearch

* Prompts for host, port, and snapshot repository name
* Creates snapshot via REST API
* Snapshot name: `snapshot_YYYY-MM-DD_HH-MM-SS`

---

## Logging

All operations, informational messages, and errors are appended to:

```
/var/log/cybersir_backup.log
```

Functions:

* `log(msg)`: Logs `[INFO]` messages
* `error(msg)`: Logs `[ERROR]` messages

Dialog boxes show user-facing notifications.

---

## Retention Policy

The script automatically deletes backup files older than `RETENTION_DAYS`. Adjust this value in the configuration section if needed.

---

## Error Handling & Cleanup

* Temporary error files in `$TMP_DIR` are cleaned up on exit or interrupt.
* Connection and dump errors are captured, displayed via dialog, and logged.

---

## Contributing

Contributions, bug reports, and feature requests are welcome. Please open an issue or submit a pull request on the project repository.

---

## License

This project is licensed under the [MIT License](LICENSE).
