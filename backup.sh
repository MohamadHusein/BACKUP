#!/bin/bash

# Configuration
BACKUP_DIR="/var/backups/cybersir"
LOG_FILE="/var/log/cybersir_backup.log"
RETENTION_DAYS=30
TMP_DIR="/tmp/cybersir_backup"

mkdir -p "$BACKUP_DIR" "$TMP_DIR"

# === Logging and Cleanup ===
log() {
  echo "$(date +'%F %T') [INFO] $1" | tee -a "$LOG_FILE"
}
error() {
  echo "$(date +'%F %T') [ERROR] $1" | tee -a "$LOG_FILE" >&2
}

cleanup() {
  # remove temp error files
  rm -f "$TMP_DIR"/*_err
}

retention_cleanup() {
  find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -print -delete >> "$LOG_FILE" 2>&1
}

trap 'cleanup; exit 1' INT TERM
trap 'cleanup' EXIT

# === Utilities ===
prompt_input() {
  dialog --title "$1" --inputbox "$2" 8 60 3>&1 1>&2 2>&3
}

prompt_pass() {
  dialog --title "$1" --insecure --passwordbox "$2" 8 60 3>&1 1>&2 2>&3
}

msg_info() {
  dialog --title "ℹ️ Info" --msgbox "$1" 10 60
}

msg_error() {
  dialog --title "❌ Error" --msgbox "$1" 10 60
}

# === Backup Functions ===
backup_mysql() {
  host=$(prompt_input "MySQL Backup" "Enter Host:") || return
  port=$(prompt_input "MySQL Backup" "Enter Port (default 3306):") || return
  port=${port:-3306}
  user=$(prompt_input "MySQL Backup" "Enter Username:") || return
  pass=$(prompt_pass "MySQL Backup" "Enter Password:") || return
  db=$(prompt_input "MySQL Backup" "Enter Database Name:") || return

  # Test connection
  MYSQL_PWD="$pass" mysql -h "$host" -P "$port" -u "$user" -e ";" 2> "$TMP_DIR/mysql_conn_err"
  if [[ $? -ne 0 ]]; then
    err=$(<"$TMP_DIR/mysql_conn_err")
    msg_error "Connection error:\n$err"
    error "MySQL conn failed: $err"
    return
  fi

  # Dump
  filename="$BACKUP_DIR/mysql_${db}_$(date +%F_%H-%M-%S).sql.gz"
  MYSQL_PWD="$pass" mysqldump -h "$host" -P "$port" -u "$user" "$db" 2> "$TMP_DIR/mysql_dump_err" | gzip > "$filename"
  if [[ $? -ne 0 ]]; then
    err=$(<"$TMP_DIR/mysql_dump_err")
    msg_error "Backup failed:\n$err"
    error "MySQL dump failed: $err"
    return
  fi

  msg_info "✅ MySQL backup saved:\n$filename"
  log "MySQL backup: $filename"
  retention_cleanup
}

backup_postgres() {
  host=$(prompt_input "PostgreSQL Backup" "Enter Host:") || return
  port=$(prompt_input "PostgreSQL Backup" "Enter Port (default 5432):") || return
  port=${port:-5432}
  user=$(prompt_input "PostgreSQL Backup" "Enter Username:") || return
  pass=$(prompt_pass "PostgreSQL Backup" "Enter Password:") || return
  db=$(prompt_input "PostgreSQL Backup" "Enter Database Name:") || return

  export PGPASSWORD="$pass"
  if ! pg_isready -h "$host" -p "$port" > /dev/null 2>&1; then
    msg_error "PostgreSQL server is not reachable."
    error "Postgres unreachable"
    return
  fi

  filename="$BACKUP_DIR/postgres_${db}_$(date +%F_%H-%M-%S).dump"
  pg_dump -h "$host" -p "$port" -U "$user" -F c "$db" > "$filename" 2> "$TMP_DIR/pg_dump_err"
  if [[ $? -ne 0 ]]; then
    err=$(<"$TMP_DIR/pg_dump_err")
    msg_error "Backup failed:\n$err"
    error "Postgres dump failed: $err"
    return
  fi

  msg_info "✅ PostgreSQL backup saved:\n$filename"
  log "Postgres backup: $filename"
  retention_cleanup
}

backup_mongodb() {
  host=$(prompt_input "MongoDB Backup" "Enter Host:") || return
  port=$(prompt_input "MongoDB Backup" "Enter Port (default 27017):") || return
  port=${port:-27017}
  db=$(prompt_input "MongoDB Backup" "Enter Database Name:") || return

  if ! mongosh --quiet --host "$host" --port "$port" --eval "db.getMongo().getDBNames().indexOf('$db') >= 0" | grep -q true; then
    msg_error "MongoDB database \"$db\" does not exist or connection failed."
    error "MongoDB auth/db failed"
    return
  fi

  filename="$BACKUP_DIR/mongo_${db}_$(date +%F_%H-%M-%S)"
  mongodump --host "$host" --port "$port" --db "$db" --out "$filename"
  msg_info "✅ MongoDB backup saved:\n$filename"
  log "MongoDB backup: $filename"
  retention_cleanup
}

backup_redis() {
  host=$(prompt_input "Redis Backup" "Enter Host (default 127.0.0.1):") || return
  host=${host:-127.0.0.1}
  port=$(prompt_input "Redis Backup" "Enter Port (default 6379):") || return
  port=${port:-6379}

  if ! redis-cli -h "$host" -p "$port" ping | grep -q PONG; then
    msg_error "Redis is not reachable."
    error "Redis unreachable"
    return
  fi

  redis-cli -h "$host" -p "$port" bgsave
  sleep 2

  dir=$(redis-cli -h "$host" -p "$port" CONFIG GET dir | awk 'NR==2')
  dump="$dir/dump.rdb"
  if [[ -f "$dump" ]]; then
    filename="$BACKUP_DIR/redis_$(date +%F_%H-%M-%S).rdb"
    cp "$dump" "$filename"
    msg_info "✅ Redis RDB backup saved:\n$filename"
    log "Redis backup: $filename"
    retention_cleanup
  else
    msg_error "Failed to locate Redis dump file."
    error "Redis dump not found"
  fi
}

backup_cassandra() {
  keyspace=$(prompt_input "Cassandra Backup" "Enter Keyspace:") || return
  filename="$BACKUP_DIR/cassandra_${keyspace}_$(date +%F_%H-%M-%S)"

  mkdir -p "$filename"
  if ! nodetool snapshot -t "${keyspace}_snap" "$keyspace"; then
    msg_error "Failed to snapshot Cassandra keyspace"
    error "Cassandra snapshot failed"
    return
  fi
  cp -r /var/lib/cassandra/data/$keyspace/*/snapshots/* "$filename" || true
  msg_info "✅ Cassandra snapshot saved:\n$filename"
  log "Cassandra backup: $filename"
  retention_cleanup
}

backup_elasticsearch() {
  host=$(prompt_input "Elasticsearch Backup" "Enter Host (default 127.0.0.1):") || return
  host=${host:-127.0.0.1}
  port=$(prompt_input "Elasticsearch Backup" "Enter Port (default 9200):") || return
  port=${port:-9200}
  repo=$(prompt_input "Elasticsearch Backup" "Enter Snapshot Repository Name:") || return
  snap="snapshot_$(date +%F_%H-%M-%S)"

  response=$(curl -s -X PUT "http://$host:$port/_snapshot/$repo/$snap?wait_for_completion=true" \
    -H 'Content-Type: application/json' -d '{}')
  if echo "$response" | grep -qE '"(accepted|successful)":true|"snapshot"'; then
    msg_info "✅ Elasticsearch snapshot \"$snap\" created"
    log "ES backup: $repo/$snap"
    retention_cleanup
  else
    msg_error "Failed to create snapshot.\n$response"
    error "ES snapshot failed: $response"
  fi
}

# === Main Menu ===
main_menu() {
  while true; do
    CHOICE=$(dialog --title " Backup :) TUI" --menu "Select a database to back up:" 18 60 10 \
      1 "MySQL / MariaDB" \
      2 "PostgreSQL" \
      3 "MongoDB" \
      4 "Redis" \
      5 "Cassandra" \
      6 "Elasticsearch" \
      7 "Exit" 3>&1 1>&2 2>&3)

    case "$CHOICE" in
      1) backup_mysql ;; 2) backup_postgres ;; 3) backup_mongodb ;; 4) backup_redis ;;
      5) backup_cassandra ;; 6) backup_elasticsearch ;; 7) clear; exit 0 ;;
    esac
  done
}

main_menu
