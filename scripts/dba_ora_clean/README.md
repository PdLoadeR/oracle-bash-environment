# DBA Oracle Cleanup Framework (v2.7)

## Overview

`dba_ora_clean.sh` is a production-grade Oracle server cleanup framework designed for enterprise database environments.

The framework was rewritten from the original cleanup utility to provide:

- Safe execution by default
- Preflight validation mode
- Scoped execution by cleanup category
- Oracle environment auto-discovery
- ADRCI-based diagnostic cleanup
- Database audit cleanup
- OEM agent cleanup
- Filesystem cleanup
- Locking and timeout protection
- Detailed operational logging

The entire solution is contained in a single portable Bash script.

---

# Key Features

## Safety First

The framework uses multiple layers of protection:

- Preflight mode is the default
- File locking prevents concurrent execution
- ADRCI timeouts
- SQLPlus timeouts
- Filesystem scan timeouts
- Database OPEN state validation
- Active Oracle Home filtering
- Explicit ADRCI error detection
- Optional stop-on-error behavior

---

# Cleanup Components

## 1. Filesystem Cleanup

### Oracle Home Audit Files

```text
$ORACLE_HOME/rdbms/audit/*.aud
```

Retention:

```text
2 days
```

### Oracle Home Trace Files

```text
$ORACLE_HOME/rdbms/log/*.trc
```

Retention:

```text
32 days
```

### Database Audit Files (AUDIT_FILE_DEST)

The framework does NOT assume:

```text
$ORACLE_BASE/admin/<SID>/adump
```

Instead it dynamically queries:

```sql
select value
from v$parameter
where name='audit_file_dest';
```

This supports:

- SID != DB_NAME
- DB_UNIQUE_NAME conventions
- Custom audit directories
- Future Oracle deployments

Retention:

```text
2 days
```

### CRS EVM Logs

```text
$ORACLE_BASE/crsdata/<hostname>/evm/evmlog*
```

Retention:

```text
32 days
```

### Listener XML Alert Files

```text
$ORACLE_BASE/diag/tnslsnr/<hostname>
```

Retention:

```text
2 days
```

### Script Execution Logs

Retention:

```text
14 days
```

---

## 2. ADRCI Cleanup

ADRCI manages diagnostic repository content.

Retention:

```text
32 days
```

### Allowed ADR Families

```text
diag/rdbms/*
diag/asm/*
diag/tnslsnr/*
diag/crs/*
diag/clients/*
diag/kfod/*
```

### Excluded ADR Families

```text
diag/asmcmd/*
diag/asmtool/*
diag/orapwd/*
```

### Schema Migration

Disabled by default.

Can be enabled explicitly:

```bash
./dba_ora_clean.sh \
  --apply \
  --only adr \
  --allow-adr-schema-migration
```

---

## 3. OEM Agent Cleanup

Removes:

```text
heapdump*.phd
Snap*.trc
core*.dmp
javacore*.txt
*.log.*
incdir_*
```

Retention:

```text
14 days
```

---

## 4. Database Cleanup

### Traditional Audit Trail

Target:

```sql
SYS.AUD$
```

Retention:

```text
365 days
```

Deletes occur in batches of:

```text
10,000 rows
```

### Scheduler Log Cleanup

Target:

```sql
DBMS_SCHEDULER.PURGE_LOG
```

### Unified Audit Cleanup

Target:

```sql
DBMS_AUDIT_MGMT
```

Retention:

```text
365 days
```

---

# Active Oracle Home Selection (v2.5+)

The framework only processes Oracle Homes that satisfy ALL of the following:

1. Running PMON process exists
2. Matching uncommented entry exists in `/etc/oratab`
3. Oracle Home exists on disk

This prevents processing unrelated homes such as:

- GoldenGate homes
- Inactive APEX homes
- Decommissioned homes
- Stale OOP patching homes

The script reports:

```text
Registered Oracle homes from /etc/oratab
Active Oracle homes selected for cleanup
```

---

# Execution Modes

## Preflight (Default)

No files removed.
No database changes.
No ADR changes.

```bash
./dba_ora_clean.sh --preflight
```

---

## Full Cleanup

```bash
./dba_ora_clean.sh --apply
```

---

# Scope-Based Execution

## Filesystem Only

```bash
./dba_ora_clean.sh --preflight --only filesystem
./dba_ora_clean.sh --apply --only filesystem
```

## OEM Only

```bash
./dba_ora_clean.sh --preflight --only oem
./dba_ora_clean.sh --apply --only oem
```

## ADR Only

```bash
./dba_ora_clean.sh --preflight --only adr
./dba_ora_clean.sh --apply --only adr
```

## Database Only

```bash
./dba_ora_clean.sh --preflight --only database
./dba_ora_clean.sh --apply --only database
```

---

# Validation Workflow

Recommended process for any production deployment.

## Step 1

Validate syntax:

```bash
bash -n dba_ora_clean.sh
```

## Step 2

Review full plan:

```bash
./dba_ora_clean.sh --preflight
```

## Step 3

Validate individual phases:

```bash
./dba_ora_clean.sh --preflight --only filesystem
./dba_ora_clean.sh --preflight --only oem
./dba_ora_clean.sh --preflight --only adr
./dba_ora_clean.sh --preflight --only database
```

## Step 4 - Option 1

Apply phases individually.

```bash
./dba_ora_clean.sh --apply --only filesystem
./dba_ora_clean.sh --apply --only oem
./dba_ora_clean.sh --apply --only adr
./dba_ora_clean.sh --apply --only database
```

## Step 4 - Option 2

Run complete cleanup.

```bash
./dba_ora_clean.sh --apply
```

---

# Logging

Default location:

```text
../log
```

Example:

```text
ora_clean_server01.20260924_120000.log
```

Custom location:

```bash
./dba_ora_clean.sh \
    --preflight \
    --log-dir /u01/admin/cleanup_logs
```

---

# Known Behaviors

### Root-Owned ADR Homes

Can generate:

```text
DIA-48191
Permission denied
```

These are reported and processing continues.

### DIA-49803

Schema mismatch.

Reported and skipped unless:

```bash
--allow-adr-schema-migration
```

is specified.

### Stale ADR Homes

ADRCI may discover homes whose databases are no longer running.

This is expected and often desirable because old diagnostic data still needs cleanup.

---

# Version History

| Version | Major Change |
|----------|-------------|
| 2.0 | Safety rewrite, locking, preflight, timeouts |
| 2.1 | SID handling fixes |
| 2.2 | Explicit ADRCI environment handling |
| 2.3 | ADRCI semantic error detection and DB prechecks |
| 2.4 | AUD$ retention fix using NUMTODSINTERVAL |
| 2.5 | Active Oracle Home filtering and ADR allowlist |
| 2.6 | Restored filesystem cleanup items |
| 2.7 | AUDIT_FILE_DEST discovery via V$PARAMETER |

---

# Author

Parsa Bahrami

Original v1 framework was based on historical cleanup implementations from:

- Wayne Sharp
- Muthu Venguidassalame
- M. Ali
