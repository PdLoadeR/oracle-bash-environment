# DBA Oracle Cleanup Framework

Production-oriented Oracle database server housekeeping with safe preflight validation, scoped execution, structured logging, timeout protection, and automated Oracle environment discovery.

Current release: **v2.8.1**

## Overview

`dba_ora_clean.sh` is a single-file Bash framework for cleaning Oracle database servers without requiring companion configuration files or libraries.

The framework supports:

- Active Oracle Home filesystem cleanup
- Database operating-system audit cleanup using the actual `AUDIT_FILE_DEST`
- CRS EVM log cleanup
- Listener XML alert cleanup
- ADRCI-managed diagnostic cleanup
- OEM Agent cleanup
- Traditional audit trail cleanup
- Scheduler log cleanup
- Unified Audit Trail cleanup
- Preflight and apply modes
- Phase-specific execution
- Plain-text file logging with screen-only status colors

## Safety model

The script is designed to favor safety and reviewability over aggressive cleanup.

Key safeguards include:

- Preflight is the default mode
- No cleanup occurs unless `--apply` is supplied
- A non-blocking lock prevents overlapping executions
- Filesystem, ADRCI, and SQLPlus operations use timeouts
- Filesystem operations validate paths before deletion
- Filesystem searches stay on the current filesystem with `find -xdev`
- ADR-managed content is purged through ADRCI rather than direct deletion
- ADRCI output is inspected for semantic failures such as `DIA-`, `ORA-`, `SP2-`, Linux errors, and permission errors
- Database cleanup requires a successful local connection and `OPEN` instance status
- Automatic ADR schema migration is disabled unless explicitly requested
- Cleanup failures are recorded while remaining targets continue unless `--stop-on-error` is supplied

## Requirements

Run the script as the Oracle software owner on a Linux host with:

- Bash
- `/etc/oratab`
- SQLPlus in each active database Oracle Home
- ADRCI in an active database or Grid Oracle Home
- Standard utilities including `awk`, `find`, `flock`, `grep`, `ps`, `stat`, `timeout`, and `xargs`

The executing account must have permission to access the selected files and connect locally to each database using:

```bash
sqlplus -s -L '/ as sysdba'
```

## Installation

Copy the script to the desired operational directory and make it executable:

```bash
chmod 750 dba_ora_clean.sh
```

Validate the Bash syntax before the first run:

```bash
bash -n dba_ora_clean.sh
```

## Usage

```bash
./dba_ora_clean.sh [--preflight | --apply] [OPTIONS]
```

Display the built-in help:

```bash
./dba_ora_clean.sh --help
```

### Execution modes

#### Preflight

Preflight reports planned work without deleting files, purging ADR content, or changing database data.

```bash
./dba_ora_clean.sh --preflight
```

Preflight is the default, so this is equivalent:

```bash
./dba_ora_clean.sh
```

#### Apply

Run all cleanup phases:

```bash
./dba_ora_clean.sh --apply
```

## Scope-specific execution

### Filesystem only

Preflight:

```bash
./dba_ora_clean.sh --preflight --only filesystem
```

Apply:

```bash
./dba_ora_clean.sh --apply --only filesystem
```

### OEM only

Preflight:

```bash
./dba_ora_clean.sh --preflight --only oem
```

Apply:

```bash
./dba_ora_clean.sh --apply --only oem
```

### ADR only

Preflight:

```bash
./dba_ora_clean.sh --preflight --only adr
```

Apply:

```bash
./dba_ora_clean.sh --apply --only adr
```

### Database only

Preflight:

```bash
./dba_ora_clean.sh --preflight --only database
```

Apply:

```bash
./dba_ora_clean.sh --apply --only database
```

## Additional options

### Stop on first error

By default, the script records a failure and continues with the remaining targets.

```bash
./dba_ora_clean.sh --apply --stop-on-error
```

### Custom log directory

```bash
./dba_ora_clean.sh \
    --preflight \
    --log-dir /u01/app/oracle/admin/cleanup_logs
```

### Allow ADR schema migration

ADRCI schema migration is disabled by default. Enable it only when intentionally handling `DIA-49803`:

```bash
./dba_ora_clean.sh \
    --apply \
    --only adr \
    --allow-adr-schema-migration
```

### Disable screen colors

```bash
NO_COLOR=1 ./dba_ora_clean.sh --preflight
```

Colors are automatically disabled when output is not attached to an interactive terminal.

## Active Oracle Home selection

Filesystem cleanup and ADR base discovery operate only on Oracle Homes that meet all three conditions:

1. A running database or ASM PMON process exists.
2. The detected SID has a matching uncommented entry in `/etc/oratab`.
3. The referenced Oracle Home exists on the filesystem.

The script logs both inventories:

```text
Registered Oracle homes from /etc/oratab: ...
Active Oracle homes selected for cleanup: ...
```

This avoids processing unrelated or inactive software homes, including standalone GoldenGate homes, while preserving valid database and Grid homes.

## SID discovery

Running instances are discovered from PMON process command names. This supports environments where `ORACLE_SID`, `DB_NAME`, and `DB_UNIQUE_NAME` do not use identical values.

The discovered SID is matched case-insensitively against `/etc/oratab` to resolve the exact SID spelling and Oracle Home.

## Cleanup coverage and retention

| Area | Target | Default retention |
|---|---|---:|
| Oracle Home audit | `$ORACLE_HOME/rdbms/audit/*.aud` | 2 days |
| Database OS audit | Files under the queried `AUDIT_FILE_DEST` | 2 days |
| Oracle Home traces | `$ORACLE_HOME/rdbms/log/*.trc` | 32 days |
| CRS EVM logs | `$ORACLE_BASE/crsdata/<hostname>/evm/evmlog*` | 32 days |
| Listener XML files | `$ORACLE_BASE/diag/tnslsnr/<hostname>/**/*.xml` | 2 days |
| ADR content | Approved ADR home families through ADRCI | 32 days |
| OEM Agent files | Dumps, archived logs, and incidents | 14 days |
| Script logs | `ora_clean_*` in the selected log directory | 14 days |
| Traditional audit | `SYS.AUD$` | 365 days |
| Unified audit | Unified Audit Trail | 365 days |
| Scheduler logs | Job and window logs | 0 days |

Retention values are defined near the beginning of the script and can be reviewed before deployment.

## Filesystem cleanup

### Oracle Home audit and trace files

For each active Oracle Home, the filesystem phase scans:

```text
$ORACLE_HOME/rdbms/audit/*.aud
$ORACLE_HOME/rdbms/log/*.trc
```

### Database `AUDIT_FILE_DEST`

The script does not construct the adump path from `ORACLE_SID`.

For each running non-ASM database, it connects locally and queries:

```sql
SELECT TRIM(value)
  FROM v$parameter
 WHERE name = 'audit_file_dest';
```

The returned path must be absolute before the filesystem cleanup engine will process it. This supports environments where the audit directory follows `DB_NAME`, `DB_UNIQUE_NAME`, or a custom naming convention.

### CRS EVM logs

The script scans the EVM directory beneath each unique active Oracle Base:

```text
$ORACLE_BASE/crsdata/<hostname>/evm
```

### Listener XML files

The script recursively scans XML files beneath:

```text
$ORACLE_BASE/diag/tnslsnr/<hostname>
```

### Filesystem deletion behavior

The filesystem engine:

- Validates each target directory
- Uses `find -xdev`
- Applies a timeout to each scan
- Calculates candidate count and byte total
- Reports the plan in both preflight and apply modes
- Removes files in batches of 1,000
- Removes matching directories in batches of 100

## ADRCI cleanup

ADRCI is selected from an active database or Grid Oracle Home. ADR bases are derived only from active Oracle Homes, preventing invalid bases from unrelated product homes.

### Approved ADR home families

```text
diag/rdbms/*
diag/asm/*
diag/tnslsnr/*
diag/crs/*
diag/clients/*
diag/kfod/*
```

### ADR families discovered but skipped

Examples include:

```text
diag/asmcmd/*
diag/asmtool/*
diag/orapwd/*
```

The allowlist is based on the ADR home family, not on database-name patterns. Valid custom database names remain eligible under `diag/rdbms`.

### ADR semantic error detection

An ADRCI process can return a successful operating-system exit code while printing an ADR error. The script treats output containing the following patterns as a failed operation:

```text
DIA-
ORA-
SP2-
Linux-* Error:
Permission denied
```

### Root-owned ADR homes

When the script runs as the Oracle software owner, root-owned ADR homes can produce permission errors such as:

```text
DIA-48191
Permission denied
```

These failures are logged. Processing continues unless `--stop-on-error` is enabled.

## OEM Agent cleanup

OEM Agent homes are discovered from `/etc/oragchomelist`.

The OEM phase scans:

```text
heapdump*.phd
Snap*.trc
core*.dmp
javacore*.txt
*.log.*
incdir_*
```

Missing OEM Agent paths are reported and skipped safely.

## Database cleanup

Database cleanup excludes ASM and management database instances. Each remaining database must pass a SQLPlus precheck and report `OPEN` before cleanup begins.

### Traditional audit trail

The script removes rows older than the configured retention from:

```sql
SYS.AUD$
```

Deletion is performed in batches of 10,000 rows with a commit after each batch.

### Scheduler logs

The script calls:

```sql
DBMS_SCHEDULER.PURGE_LOG
```

for job and window logs.

### Unified Audit Trail

The script uses:

```sql
DBMS_AUDIT_MGMT.SET_LAST_ARCHIVE_TIMESTAMP
DBMS_AUDIT_MGMT.CLEAN_AUDIT_TRAIL
```

with the configured database audit retention.

## Logging

### Log file

The default log directory is:

```text
../log
```

relative to the script directory.

Log filenames follow this pattern:

```text
ora_clean_<hostname>.<timestamp>_<pid>.log
```

File logs are always plain text and never contain ANSI color sequences.

### Structured command output

SQLPlus and ADRCI output is normalized into the same aligned format as framework messages:

```text
[2026-09-24 15:31:20] OUTPUT    [ADRCI] DIA-48191: user missing read or write permission
[2026-09-24 15:31:22] OUTPUT    [SQL SH1PRD PRECHECK] OPEN
[2026-09-24 15:31:22] OUTPUT    [SQL SH1PRD] AUDIT_ROWS_DELETED=0
```

Blank SQLPlus and ADRCI lines are omitted.

### Screen-only tag colors in v2.8.1

When running interactively, only the status tag is colored. The timestamp and message remain in the terminal's default color.

| Tag | Screen color |
|---|---|
| `START` | Light blue |
| `SUCCESS` | Light green |
| `WARNING` | Yellow |
| `FAILED` | Light red |
| `TIMEOUT` | Light red |
| `INFO` | Default terminal color |
| `PLAN` | Default terminal color |
| `OUTPUT` | Default terminal color |
| `SUMMARY` | Default terminal color |

The ANSI reset is written immediately after the padded tag field, so the remaining message is not colored.

## Summary and return code

Every run ends with summary lines for:

- Script version, mode, scope, and return code
- Filesystem candidate files, directories, and bytes
- ADR discovered, successful, failed, timed-out, and skipped totals
- Database successful, failed, timed-out, and skipped totals
- Log file location

Any recorded failure sets the final return code to a nonzero value.

## Recommended validation workflow

### 1. Validate syntax

```bash
bash -n dba_ora_clean.sh
```

### 2. Review help

```bash
./dba_ora_clean.sh --help
```

### 3. Run a full preflight

```bash
./dba_ora_clean.sh --preflight
```

### 4. Validate each phase independently

```bash
./dba_ora_clean.sh --preflight --only filesystem
./dba_ora_clean.sh --preflight --only oem
./dba_ora_clean.sh --preflight --only adr
./dba_ora_clean.sh --preflight --only database
```

### 5. Apply each phase independently - Option 1

```bash
./dba_ora_clean.sh --apply --only filesystem
./dba_ora_clean.sh --apply --only oem
./dba_ora_clean.sh --apply --only adr
./dba_ora_clean.sh --apply --only database
```

### 5. Run the complete cleanup - Option 2

```bash
./dba_ora_clean.sh --apply
```

### 6. Review the plain-text log

Confirm that:

- The expected active Oracle Homes were selected
- `AUDIT_FILE_DEST` was resolved correctly for each database
- ADR bases were not duplicated
- SQL and ADRCI output is aligned
- The log contains no ANSI escape sequences
- Summary totals match the operations performed

## Troubleshooting

### Audit directory is skipped

Confirm the database is running and the following query returns an absolute path:

```sql
SELECT value
  FROM v$parameter
 WHERE name = 'audit_file_dest';
```

### ADR permission errors

Review ownership and permissions for the reported ADR home. Root-owned ADR homes may not be purgeable by the Oracle software owner.

### Running SID is excluded

Confirm that:

- A PMON process exists
- The SID has an uncommented `/etc/oratab` entry
- The Oracle Home in `/etc/oratab` exists

### Screen has no colors

Colors appear only when standard output is attached to an interactive terminal. Also confirm that `NO_COLOR` is not set and `TERM` is not `dumb`.

### Disable colors manually

```bash
NO_COLOR=1 ./dba_ora_clean.sh --preflight
```

## Version history

| Version | Major change |
|---|---|
| 1.0 | Initial release |
| 1.0.1 | Batched removal behavior |
| 1.0.2 | Database alert-log rotation disabled |
| 1.1 | ADR Home cleanup introduced |
| 1.1.1 | ADRCI schema mismatch handling introduced |
| 2.0 | Safety rewrite with preflight, locking, timeouts, and scoped execution |
| 2.1 | Oracle environment loading and case-insensitive SID resolution corrected |
| 2.2 | Explicit Oracle Home and Oracle Base environment for ADRCI |
| 2.3 | ADRCI semantic error detection and exact database prechecks |
| 2.4 | `SYS.AUD$` retention arithmetic corrected with `NUMTODSINTERVAL` |
| 2.5 | Active Oracle Home filtering and ADR family allowlist |
| 2.6 | Database OS audit, CRS EVM, and listener XML filesystem cleanup restored |
| 2.7 | Database audit path resolved from `V$PARAMETER.AUDIT_FILE_DEST` |
| 2.8 | SQL and ADRCI output aligned; screen-only status colors added |
| 2.8.1 | Color limited to the status tag; informational tags use the default terminal color |

## Author and credits

**Author:** Parsa Bahrami

The original v1.0 implementation was based on historical cleanup scripts by:

- Wayne Sharp
- Muthu Venguidassalame
- M. Ali

## Operational warning

Always run preflight and review the selected Oracle Homes, resolved audit destinations, ADR bases, candidate counts, and log location before using `--apply` on a production server.
