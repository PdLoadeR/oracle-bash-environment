# ora_utils

**Bash functions for managing Oracle Databases on Linux.**

`ora_utils` is a single file you source into the shell of the Oracle software owner. It adds 50 commands that answer the day-to-day questions of a DBA across *every* database on the host at once - what is running from which home, how full is everything, are the backups recent, is Data Guard in sync, is this host ready for the next patch - and prints the answer as a clean table (or CSV / JSON / raw output for scripts and Ansible).

```text
$ lsoh
  +-----------------+--------------------------------------------+---------------+-----------+--------------------------+
  |  NAME           |  LOCATION                                  |  VERSION      |  TYPE     |  STATUS                  |
  +-----------------+--------------------------------------------+---------------+-----------+--------------------------+
  |  OraGI19Home1   |  /u01/app/19.32.0/grid                     |  19.32.0.0.0  |  GRID     |  ACTIVE (CRS)            |
  |  OraDB19Home2   |  /u01/app/oracle/product/19.31.0/dbhome_1  |  19.31.0.0.0  |  DBMS EE  |  ACTIVE (1 DB)           |
  |  OraDB19Home3   |  /u01/app/oracle/product/19.32.0/dbhome_1  |  19.32.0.0.0  |  DBMS EE  |  ACTIVE (2 DBs)          |
  |  OraDB23Home1   |  /u01/app/oracle/product/23.26.1/dbhome_1  |  23.26.1.0.0  |  DBMS EE  |  ACTIVE (1 DB)           |
  |  agent13c1      |  /u01/app/oracle/agent/agent_13.5.0.0.0    |  13.5.0.0.0   |  AGNT     |  INSTALLED               |
  |  OraGG21cHome1  |  /u01/app/ogg/ogg21c                       |  21.17.0.0.0  |  OGG MA   |  ACTIVE (2 deployments)  |
  +-----------------+--------------------------------------------+---------------+-----------+--------------------------+
```

> All host names, database names, users, paths and values in this README are fictitious examples.

## Table of contents

- [Highlights](#highlights)
- [Requirements and compatibility](#requirements-and-compatibility)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Conventions shared by all functions](#conventions-shared-by-all-functions)
- [Environment variables](#environment-variables)
- [Function reference](#function-reference)
  - [Getting help](#getting-help)
  - [Inventory and environment](#inventory-and-environment)
  - [Database status and health](#database-status-and-health)
  - [Sessions and performance](#sessions-and-performance)
  - [Users, configuration and compliance](#users-configuration-and-compliance)
  - [Data Guard](#data-guard)
  - [Patching and upgrades](#patching-and-upgrades)
  - [Running SQL on every database](#running-sql-on-every-database)
  - [Host, OS and filesystems](#host-os-and-filesystems)
  - [Oracle Enterprise Manager agent](#oracle-enterprise-manager-agent)
  - [Clusterware / Oracle Restart](#clusterware--oracle-restart)
  - [Utilities](#utilities)
- [Aliases](#aliases)
- [Bash utility functions](#bash-utility-functions)
- [About the examples](#about-the-examples)
- [Author](#author)

## Highlights

- **One command, every database.** Functions discover the running instances from their PMON processes and take each `ORACLE_HOME` from the running binary, so the right home is used even during out-of-place patching when oratab already points to the new home. Databases in oratab that are down are reported too.
- **Your shell stays untouched.** Every Oracle command runs in an isolated subshell: `ORACLE_SID`, `ORACLE_HOME`, `PATH` and `LD_LIBRARY_PATH` of your session never change (except with `setdb`, whose job is to set them).
- **Same options everywhere.** `--csv`, `--json`, `--raw`, `--no-header`, `--grep`, `--grep-v`, `--no-color` and `--help` work the same way in every reporting function.
- **Script and Ansible friendly.** Consistent return codes (0 OK, 1 error, 2 something found), JSON output and the check IDs of `dbprecheck` / `oscheck`.
- **Multitenant, RAC and Data Guard aware.** CDB$ROOT and every PDB, RAC instance names, mounted standbys.
- **19c and 26ai, RHEL / Oracle Linux 8, 9 and 10.** Release-specific rules and OS certification checks.
- **Safe by default.** Anything that changes something (`dbsqlall` DML/DDL, `dbpurge`, `emblackout`, `lsemtgt --apply`, `lsmenu --kill`) is a dry run or asks you to type `YES`.

## Requirements and compatibility

| Item | Supported |
|---|---|
| Shell | bash 4.2 or later |
| Operating system | Red Hat Enterprise Linux / Oracle Linux 8, 9 and 10 (7 works for most functions) |
| Oracle Database | 19c and 26ai (23ai), single instance, RAC, Oracle Restart, Data Guard, multitenant and non-CDB |
| Tools | GNU coreutils, awk, sed, grep; `python3` (lsautoupg), `openssl` / `keytool` (lscert); Oracle tools from the homes (`sqlplus`, `opatch`, `srvctl`, `dgmgrl`, `adrci`, `orapki`, `emctl`, `emcli`) |
| User | The Oracle software owner (needs `/ as sysdba` and read access to `/proc/<pid>/exe` of the Oracle processes) |
| Optional licenses | `dbash` and `dbgrowth` use AWR/ASH (Oracle Diagnostics Pack); they skip databases where `CONTROL_MANAGEMENT_PACK_ACCESS` does not include DIAGNOSTIC unless `--force` is used |

## Installation

```bash
# 1. Copy the file to the Oracle software owner's home directory
cp ora_utils ~/ora_utils

# 2. Source it from ~/.bashrc
cat >> ~/.bashrc <<'EOF'
if [[ -f "$HOME/ora_utils" ]]; then
    . "$HOME/ora_utils"
fi
EOF

# 3. Load it in the current session
. ~/ora_utils
```

The file refuses to run when executed directly (`./ora_utils`) - it must be sourced. It is safe to source more than once.

## Quick start

```bash
dbahelp                  # every function with a one-line description
dbahelp lsoh             # help of one function (same as: lsoh --help)
lsoh                     # Oracle homes and what runs from them
dbsummary                # one line per database
dbspace --alerts         # tablespaces / FRA that need attention
dbprecheck --summary     # GO / NO-GO before patching
```

## Conventions shared by all functions

### Output formats

Every reporting function prints a table by default and accepts one of `--csv`, `--json` or `--raw`. `--no-header` removes the header line (table and CSV).

**Table (default)**

```text
$ lsoh --type grid
  +----------------+-------------------------+---------------+--------+----------------+
  |  NAME          |  LOCATION               |  VERSION      |  TYPE  |  STATUS        |
  +----------------+-------------------------+---------------+--------+----------------+
  |  OraGI19Home1  |  /u01/app/19.32.0/grid  |  19.32.0.0.0  |  GRID  |  ACTIVE (CRS)  |
  +----------------+-------------------------+---------------+--------+----------------+
```

**CSV**

```text
$ lsoh --type grid --csv
NAME,LOCATION,VERSION,TYPE,STATUS
OraGI19Home1,/u01/app/19.32.0/grid,19.32.0.0.0,GRID,ACTIVE (CRS)
```

**JSON**

```text
$ lsoh --type grid --json
[
  {"NAME":"OraGI19Home1","LOCATION":"/u01/app/19.32.0/grid","VERSION":"19.32.0.0.0","TYPE":"GRID","STATUS":"ACTIVE (CRS)"}
]
```

**Raw: tab-separated, no header**

```text
$ lsoh --type grid --raw
OraGI19Home1	/u01/app/19.32.0/grid	19.32.0.0.0	GRID	ACTIVE (CRS)
```

**Table without the header**

```text
$ lsoh --type db --no-header
  +----------------+--------------------------------------------+---------------+-----------+------------------+
  |  OraDB19Home2  |  /u01/app/oracle/product/19.31.0/dbhome_1  |  19.31.0.0.0  |  DBMS EE  |  ACTIVE (1 DB)   |
  |  OraDB19Home3  |  /u01/app/oracle/product/19.32.0/dbhome_1  |  19.32.0.0.0  |  DBMS EE  |  ACTIVE (2 DBs)  |
  |  OraDB23Home1  |  /u01/app/oracle/product/23.26.1/dbhome_1  |  23.26.1.0.0  |  DBMS EE  |  ACTIVE (1 DB)   |
  +----------------+--------------------------------------------+---------------+-----------+------------------+
```

**Include rows matching a case-insensitive regex**

```text
$ lsoh --grep '19\.3'
  +----------------+--------------------------------------------+---------------+-----------+------------------+
  |  NAME          |  LOCATION                                  |  VERSION      |  TYPE     |  STATUS          |
  +----------------+--------------------------------------------+---------------+-----------+------------------+
  |  OraGI19Home1  |  /u01/app/19.32.0/grid                     |  19.32.0.0.0  |  GRID     |  ACTIVE (CRS)    |
  |  OraDB19Home2  |  /u01/app/oracle/product/19.31.0/dbhome_1  |  19.31.0.0.0  |  DBMS EE  |  ACTIVE (1 DB)   |
  |  OraDB19Home3  |  /u01/app/oracle/product/19.32.0/dbhome_1  |  19.32.0.0.0  |  DBMS EE  |  ACTIVE (2 DBs)  |
  +----------------+--------------------------------------------+---------------+-----------+------------------+
```

**Exclude rows matching a regex (`--grep -v` works too)**

```text
$ lsoh --grep-v 'grid|agnt|ogg'
  +----------------+--------------------------------------------+---------------+-----------+------------------+
  |  NAME          |  LOCATION                                  |  VERSION      |  TYPE     |  STATUS          |
  +----------------+--------------------------------------------+---------------+-----------+------------------+
  |  OraDB19Home2  |  /u01/app/oracle/product/19.31.0/dbhome_1  |  19.31.0.0.0  |  DBMS EE  |  ACTIVE (1 DB)   |
  |  OraDB19Home3  |  /u01/app/oracle/product/19.32.0/dbhome_1  |  19.32.0.0.0  |  DBMS EE  |  ACTIVE (2 DBs)  |
  |  OraDB23Home1  |  /u01/app/oracle/product/23.26.1/dbhome_1  |  23.26.1.0.0  |  DBMS EE  |  ACTIVE (1 DB)   |
  +----------------+--------------------------------------------+---------------+-----------+------------------+
```

Long values are wrapped inside the table cell where it helps readability (`dbparam`, `dbrmancfg`, the column names of `dbmemory`). CSV, JSON and raw output are never wrapped.

### Filtering

| Option | Meaning |
|---|---|
| `--grep PATTERN` | Keep rows matching a case-insensitive extended regex |
| `--grep-v PATTERN` / `--grep -v PATTERN` | Drop rows matching the regex |
| `--db REGEX` | (database functions) Only query SIDs matching the regex - faster than `--grep` because the other databases are not queried at all |

### Status colors

In table output on a terminal, only the status cell is colored: **red** for CRIT, FAIL, ERROR, DOWN, NO-GO, EXPIRED, MISMATCH, MISSING; **yellow** for WARN, PENDING, LOCKED, UNKNOWN and anything `(ignored)`; **green** for OK, PASS, GO, MATCH, ACTIVE. Use `--no-color` or set `NO_COLOR=1` to disable colors. Redirected output and CSV / JSON / raw are never colored.

### Return codes

| Code | Meaning |
|---|---|
| 0 | Success - nothing CRIT / FAIL / NO-GO found |
| 1 | Error - invalid option, nothing to query, tool not found ... |
| 2 | Something was found - CRIT row, NO-GO, MISMATCH, blocking sessions, errors in the alert log ... (see each function's help) |

**Return code 2 = at least one CRIT**

```text
$ dbspace --alerts >/dev/null; echo "rc=$?"
rc=0
```

**Return code 0 = everything OK / WARN**

```text
$ lsasm --grep RECO >/dev/null; echo "rc=$?"
rc=0
```

**Return code 1 = error (bad option, nothing to query ...)**

```text
$ dbspace --bogus; echo "rc=$?"
ERROR: Unknown option: --bogus (see dbspace --help)
rc=1
```

### Safety

| Function | Protection |
|---|---|
| `dbsqlall` | DML, DDL, GRANT, PL/SQL, SHUTDOWN ... require typing `YES` (or `--yes`); refused without a terminal; `--dry-run` |
| `dbpurge` | Dry run unless `--execute`; asks for `YES`; never purges alert logs |
| `emblackout` | `--reason` and `--duration` are mandatory, duration capped at 72 hours; asks for `YES`; `--dry-run` |
| `lsemtgt --apply` | Shows every `emcli` command first and asks for `YES` |
| `lsmenu --kill` | Asks for `YES`; only orphaned menus (never parent shells or menus with an active session); SIGTERM before SIGKILL |
| `dbblock --kill-sql` | Only prints the KILL SESSION statements |
| `dbstats --flush` | The only write in the health functions - opt-in |

## Environment variables

All are optional - the defaults work on a standard installation.

| Variable | Used by | Purpose |
|---|---|---|
| `DBA_ORATAB` | all | Path to oratab (default `/etc/oratab`, then `/var/opt/oracle/oratab`) |
| `DBA_ORAINST_LOC` | lsoh, lspatches | Path to `oraInst.loc` (default `/etc/oraInst.loc`) |
| `DBA_FUNCTIONS_FILE` | dbahelp | Path of the ora_utils file (auto-detected) |
| `DBA_AGENT_INST` | lsagent, emblackout, lsemtgt, lsdbhome, lscert | OEM agent instance directory when it is not auto-detected |
| `DBA_EMCLI` | lsemtgt | Path to `emcli` (default: `emcli` in PATH) |
| `DBA_AUTOUPG_LOG_DIR` | lsautoupg | AutoUpgrade log directory |
| `DBA_DG_PROPS` | dbdgcheck | Default broker property list |
| `DBA_CERT_PATHS` | lscert | Extra directories / files to search (colon separated) |
| `DBA_WALLET_PWD` | lscert | Wallet / keystore password for unattended single-store runs |
| `DBA_OS_RELEASE_FILE` | oscheck, dbprecheck | What-if: os-release file for the certification checks |
| `DBA_KERNEL` | oscheck, dbprecheck | What-if: kernel release for the certification checks |
| `NO_COLOR` | all | Disable colors (same as `--no-color`) |

## Function reference

**Getting help**

| Function | Description |
|---|---|
| [`dbahelp`](#dbahelp) | Lists the functions in ora_utils with a one-line description, or shows the help of one function. |

**Inventory and environment**

| Function | Description |
|---|---|
| [`lsoh`](#lsoh) | Lists every Oracle home registered in the central inventory with its type, version and whether anything is actually running from it. |
| [`lspatches`](#lspatches) | Shows the patch level of every database and Grid home in one table, based on `opatch lspatches`. |
| [`lslsnr`](#lslsnr) | Lists all listeners on the host: CRS / Oracle Restart managed, SCAN and standalone. |
| [`lsdbhome`](#lsdbhome) | Shows, for every database, the ORACLE_HOME known to each layer - the quickest way to spot drift after out-of-place patching. |
| [`setdb`](#setdb) | Sets the Oracle environment of the current shell for a database or ASM instance, from a menu or by SID / number. |

**Database status and health**

| Function | Description |
|---|---|
| [`dbsummary`](#dbsummary) | One-row-per-database inventory of the host: role, open mode, release, RU, CDB/PDBs, size, log mode and flashback. |
| [`dbuptime`](#dbuptime) | Startup time and uptime of every instance, plus the previous startup from AWR. |
| [`dbmemory`](#dbmemory) | Memory parameters and current memory usage of every running instance, with a TOTAL row. |
| [`dbhpaloc`](#dbhpaloc) | HugePages allocation of every running instance, read from the latest Huge Pages section of its alert log. |
| [`dbspace`](#dbspace) | Tablespace, TEMP, UNDO and FRA usage of every running database and every open container, relative to the autoextend maximum. |
| [`lsasm`](#lsasm) | ASM diskgroup usage including the space that is really usable after mirroring, or the list of ASM disks. |
| [`dbbkp`](#dbbkp) | Latest RMAN backups recorded in each database's control file, with an age-based status. |
| [`dbarch`](#dbarch) | Archive log generation per database (or per hour) and FRA usage. |
| [`dbredo`](#dbredo) | Online and standby redo log configuration and log switch rate per database. |
| [`dbstats`](#dbstats) | Optimizer statistics health: the automatic stats job and stale or missing table statistics per schema and container. |
| [`dbtde`](#dbtde) | Transparent Data Encryption keystore status per container. |
| [`dbgrowth`](#dbgrowth) | Tablespace growth from AWR history with a forecast of the days left until each tablespace is full. |
| [`dbalert`](#dbalert) | ORA- errors (or any pattern) from the alert log of every database within a time window. |
| [`dbincident`](#dbincident) | ADR incidents (ORA-600, ORA-7445, ORA-4031 ...) of every database, with an option to package one for an Oracle SR. |

**Sessions and performance**

| Function | Description |
|---|---|
| [`dbcpu`](#dbcpu) | CPU used by each database, measured over a sampling interval. |
| [`dbsess`](#dbsess) | Sessions of every database: active session detail or a per-database summary against the limits. |
| [`dbblock`](#dbblock) | Blocking chains across all databases: every root blocker followed by the sessions waiting on it. |
| [`dbash`](#dbash) | "What is the database doing right now?" - top wait events and top SQL from Active Session History. |
| [`dblongops`](#dblongops) | Long-running operations with progress and time remaining (RMAN, scans, index builds, Data Pump ...). |
| [`dbconn`](#dbconn) | User sessions grouped per database and container - who has to be notified or drained before patching. |

**Users, configuration and compliance**

| Function | Description |
|---|---|
| [`dbusers`](#dbusers) | Account health: locked, expired, soon-to-expire and default-password accounts in the ASM password file, every CDB and every PDB. |
| [`dbparam`](#dbparam) | Compares init parameters side by side across all running databases (and optionally their PDBs). |
| [`dbjobs`](#dbjobs) | Scheduler job runs that did not succeed, broken scheduler jobs and broken DBMS_JOB jobs. |
| [`dbrmancfg`](#dbrmancfg) | RMAN persistent configuration side by side for every database. |
| [`dbfeatures`](#dbfeatures) | Feature usage from `DBA_FEATURE_USAGE_STATISTICS`, mapped to the option or management pack that usually licenses it. |
| [`dbservices`](#dbservices) | Application services: how Clusterware / Oracle Restart is configured to run them versus where they run now. |

**Data Guard**

| Function | Description |
|---|---|
| [`dbdglag`](#dbdglag) | Data Guard broker status and transport / apply lag of every member, as a table. |
| [`dbdgcheck`](#dbdgcheck) | Data Guard broker health per member: switchover / failover readiness, protection mode, FSFO and key properties. |

**Patching and upgrades**

| Function | Description |
|---|---|
| [`dbdatapatch`](#dbdatapatch) | Answers "is this database fully patched?" - compares the RU/OJVM/Datapump patches in the running home with what datapatch applied in every container. |
| [`ohdiff`](#ohdiff) | Compares the patches of two Oracle homes - typically the old and new home of an out-of-place patch. |
| [`dbprecheck`](#dbprecheck) | Pre-patch / pre-upgrade GO / NO-GO checks per database, per container and for the host - built to be used by people and by Ansible. |
| [`lsautoupg`](#lsautoupg) | Progress of AutoUpgrade jobs on the host. |

**Running SQL on every database**

| Function | Description |
|---|---|
| [`dbsqlall`](#dbsqlall) | Runs a SQL statement, PL/SQL block or SQL file on every running database (or a filtered set, or every PDB). |

**Host, OS and filesystems**

| Function | Description |
|---|---|
| [`oscheck`](#oscheck) | Checks the host against Oracle's Linux requirements for the releases in use (19c and/or 26ai), including certification of every home. |
| [`lsfs`](#lsfs) | Usage of the filesystems holding Oracle homes, bases, Grid, agent and custom paths, or the largest housekeeping directories. |
| [`dbpurge`](#dbpurge) | Purges old ADR diagnostic data of every ADR home on the host - dry run by default. |
| [`lscert`](#lscert) | Certificate expiry for every kind of store a DBA meets: Oracle / OWM wallets (auto-login and password), PKCS#12, Java keystores and PEM/DER files. |

**Oracle Enterprise Manager agent**

| Function | Description |
|---|---|
| [`lsagent`](#lsagent) | OEM agent health in one row: state, targets, uploads, pending files, heartbeat and blackouts. |
| [`emblackout`](#emblackout) | Lists, starts and stops OEM agent-side blackouts with a standard name, a mandatory reason and a duration. |
| [`lsemtgt`](#lsemtgt) | Compares the targets registered with the local OEM agent with the homes really in use, and can fix them through EMCLI. |

**Clusterware / Oracle Restart**

| Function | Description |
|---|---|
| [`lscrs`](#lscrs) | Clusterware or Oracle Restart resources whose STATE does not match the TARGET. |

**Utilities**

| Function | Description |
|---|---|
| [`passgen`](#passgen) | Generates strong random passwords. |
| [`wclip`](#wclip) | Copies stdin to the Windows clipboard through a modified PuTTY / KiTTY (ANSI printer pass-through). |
| [`lsmenu`](#lsmenu) | Finds `/bin/sh ./menu` processes left behind by closed sessions (no terminal, or parent exited) and optionally kills them. |

## Getting help

### dbahelp

Lists the functions in ora_utils with a one-line description, or shows the help of one function.

**Features**

- Reads the `# DESC:` line above each function, so new functions appear automatically
- `--full` also lists functions without a description (internal `_` helpers are always hidden)
- `dbahelp <function>` runs `<function> --help`
- Supports all common output options (`--csv`, `--json`, `--raw`, `--grep` ...)

**Usage**

```text
dbahelp [--full] [--csv|--json|--raw] [--no-header] [--grep PATTERN] [--grep-v PATTERN]
dbahelp <function_name>
```

**Examples**

**List only the functions whose name starts with `ls`**

```text
$ dbahelp --grep '^ls'
  +-------------+--------------------------------------------------------------------------------------------------------------------------------------------+
  |  COMMAND    |  DESCRIPTION                                                                                                                               |
  +-------------+--------------------------------------------------------------------------------------------------------------------------------------------+
  |  lsagent    |  OEM agent status - state, uploads, pending files, heartbeat and blackouts                                                                 |
  |  lsasm      |  ASM diskgroup usage including usable space after mirroring (and optional disk list)                                                       |
  |  lsautoupg  |  Progress of AutoUpgrade jobs on this host (status.json + latest job log line)                                                             |
  |  lscert     |  Certificate expiry for Oracle/OWM wallets (auto-login and password), PKCS#12, Java keystores (OGG/OHS) and PEM/DER files                  |
  |  lscrs      |  Clusterware / Oracle Restart resources whose STATE does not match the TARGET (filtered crsctl stat res)                                   |
  |  lsdbhome   |  Running vs oratab vs CRS vs OEM ORACLE_HOME for every database (out-of-place patching drift)                                              |
  |  lsemtgt    |  OEM agent targets (DB, listener, ASM, HAS, cluster, Oracle home) vs the homes really in use - detect stale properties after OOP patching  |
  |  lsfs       |  Usage of filesystems holding Oracle homes, bases, /stage, /dump and other custom paths (with --top consumers)                             |
  |  lslsnr     |  List listeners (CRS-managed, SCAN and standalone) with filtering                                                                          |
  |  lsmenu     |  Identify and optionally kill orphaned 'menu' processes                                                                                    |
  |  lsoh       |  List Oracle homes with type, version and usage status (ACTIVE/CONFIGURED/INSTALLED)                                                       |
  |  lspatches  |  Display Oracle patch levels across homes                                                                                                  |
  +-------------+--------------------------------------------------------------------------------------------------------------------------------------------+
```

**Same list as CSV**

```text
$ dbahelp --csv --grep 'pass|clip'
COMMAND,DESCRIPTION
dbusers,"Locked, expired, soon-to-expire and default-password accounts (CDB, every PDB and the ASM password file)"
lscert,"Certificate expiry for Oracle/OWM wallets (auto-login and password), PKCS#12, Java keystores (OGG/OHS) and PEM/DER files"
passgen,Random Password Generator
wclip,Copy stdin into the Windows clipboard (modified PuTTY or KiTTY with printer passthrough)
```

**Show the help of one function (same as `lsoh --help`)**

```bash
dbahelp lsoh
```

<details>
<summary>Full <code>dbahelp --help</code></summary>

```text
Usage:
  dbahelp [--full] [--csv|--json|--raw] [--no-header] [--grep PATTERN] [--grep-v PATTERN]
  dbahelp <function_name>

Behavior:
  dbahelp
      Show functions that have a '# DESC:' line directly above them.
  dbahelp --full
      Show ALL functions in the file (except _internal helpers).
      Functions without '# DESC:' have an empty DESCRIPTION.
  dbahelp <function_name>
      Run: <function_name> --help

Notes:
  - To include a function in the default output, add
        # DESC: description text
    immediately above the function definition.
  - Function definitions are only recognized at column 0, with or
    without the 'function' keyword and with or without '()'.
```

</details>

[Back to the function list](#function-reference)

## Inventory and environment

### lsoh

Lists every Oracle home registered in the central inventory with its type, version and whether anything is actually running from it.

**Features**

- Types: `DBMS EE/SE2`, `GRID`, `AGNT` (OEM agent), `CLNT`, `OHS`, `OCMN`, `OGG MA`, `OGG CA`
- Full versions via `oraversion -compositeVersion` (DB, Grid, client) or `adminclient --version` (OGG Microservices)
- STATUS: `ACTIVE (N DBs)` counted from the running PMON binaries (correct during out-of-place patching), `ACTIVE (N deployments)` for OGG MA, `ACTIVE (CRS)` for the active Grid home, `CONFIGURED` (in oratab but down) or `INSTALLED` (unused)
- `--full` adds DETAIL (SIDs / OGG deployments using the home) and ROOH (read-only Oracle home)
- `--size` adds the size of each home (opt-in because it runs `du`)
- Filters: `--type`, `--status`, `--column`, plus the common `--grep` / `--grep-v`
- Homes flagged `REMOVED="T"` (detached) in the inventory are skipped

**Usage**

```text
lsoh [--full] [--size] [--type TYPE] [--status REGEX] [--column COL]
     [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**All Oracle homes in the central inventory with their usage status**

```text
$ lsoh
  +-----------------+--------------------------------------------+---------------+-----------+--------------------------+
  |  NAME           |  LOCATION                                  |  VERSION      |  TYPE     |  STATUS                  |
  +-----------------+--------------------------------------------+---------------+-----------+--------------------------+
  |  OraGI19Home1   |  /u01/app/19.32.0/grid                     |  19.32.0.0.0  |  GRID     |  ACTIVE (CRS)            |
  |  OraDB19Home2   |  /u01/app/oracle/product/19.31.0/dbhome_1  |  19.31.0.0.0  |  DBMS EE  |  ACTIVE (1 DB)           |
  |  OraDB19Home3   |  /u01/app/oracle/product/19.32.0/dbhome_1  |  19.32.0.0.0  |  DBMS EE  |  ACTIVE (2 DBs)          |
  |  OraDB23Home1   |  /u01/app/oracle/product/23.26.1/dbhome_1  |  23.26.1.0.0  |  DBMS EE  |  ACTIVE (1 DB)           |
  |  agent13c1      |  /u01/app/oracle/agent/agent_13.5.0.0.0    |  13.5.0.0.0   |  AGNT     |  INSTALLED               |
  |  OraGG21cHome1  |  /u01/app/ogg/ogg21c                       |  21.17.0.0.0  |  OGG MA   |  ACTIVE (2 deployments)  |
  +-----------------+--------------------------------------------+---------------+-----------+--------------------------+
```

**Add the DETAIL (SIDs / OGG deployments using the home) and ROOH columns**

```text
$ lsoh --full
  +-----------------+--------------------------------------------+---------------+-----------+--------------------------+--------------------+--------+
  |  NAME           |  LOCATION                                  |  VERSION      |  TYPE     |  STATUS                  |  DETAIL            |  ROOH  |
  +-----------------+--------------------------------------------+---------------+-----------+--------------------------+--------------------+--------+
  |  OraGI19Home1   |  /u01/app/19.32.0/grid                     |  19.32.0.0.0  |  GRID     |  ACTIVE (CRS)            |  +ASM              |  -     |
  |  OraDB19Home2   |  /u01/app/oracle/product/19.31.0/dbhome_1  |  19.31.0.0.0  |  DBMS EE  |  ACTIVE (1 DB)           |  HRPRD             |  NO    |
  |  OraDB19Home3   |  /u01/app/oracle/product/19.32.0/dbhome_1  |  19.32.0.0.0  |  DBMS EE  |  ACTIVE (2 DBs)          |  CRMSTBY,FINPRD    |  NO    |
  |  OraDB23Home1   |  /u01/app/oracle/product/23.26.1/dbhome_1  |  23.26.1.0.0  |  DBMS EE  |  ACTIVE (1 DB)           |  AIDEV             |  NO    |
  |  agent13c1      |  /u01/app/oracle/agent/agent_13.5.0.0.0    |  13.5.0.0.0   |  AGNT     |  INSTALLED               |  -                 |  -     |
  |  OraGG21cHome1  |  /u01/app/ogg/ogg21c                       |  21.17.0.0.0  |  OGG MA   |  ACTIVE (2 deployments)  |  depl_fin,depl_hr  |  -     |
  +-----------------+--------------------------------------------+---------------+-----------+--------------------------+--------------------+--------+
```

**Script-friendly: one database home location per line**

```text
$ lsoh --type db --column location --raw
/u01/app/oracle/product/19.31.0/dbhome_1
/u01/app/oracle/product/19.32.0/dbhome_1
/u01/app/oracle/product/23.26.1/dbhome_1
```

**GoldenGate homes as JSON**

```text
$ lsoh --type ogg --json
[
  {"NAME":"OraGG21cHome1","LOCATION":"/u01/app/ogg/ogg21c","VERSION":"21.17.0.0.0","TYPE":"OGG MA","STATUS":"ACTIVE (2 deployments)"}
]
```

**Clean-up candidates after out-of-place patching (homes nothing runs from)**

```text
$ lsoh --type db --status installed
  +--------+------------+-----------+--------+----------+
  |  NAME  |  LOCATION  |  VERSION  |  TYPE  |  STATUS  |
  +--------+------------+-----------+--------+----------+
```

**Add the size of each home (runs `du`, so it is opt-in)**

```text
$ lsoh --size --type db
Measuring Oracle home sizes - please wait...
  +----------------+--------------------------------------------+---------------+-----------+------------------+-----------+
  |  NAME          |  LOCATION                                  |  VERSION      |  TYPE     |  STATUS          |  SIZE_GB  |
  +----------------+--------------------------------------------+---------------+-----------+------------------+-----------+
  |  OraDB19Home2  |  /u01/app/oracle/product/19.31.0/dbhome_1  |  19.31.0.0.0  |  DBMS EE  |  ACTIVE (1 DB)   |  0.0      |
  |  OraDB19Home3  |  /u01/app/oracle/product/19.32.0/dbhome_1  |  19.32.0.0.0  |  DBMS EE  |  ACTIVE (2 DBs)  |  0.0      |
  |  OraDB23Home1  |  /u01/app/oracle/product/23.26.1/dbhome_1  |  23.26.1.0.0  |  DBMS EE  |  ACTIVE (1 DB)   |  0.0      |
  +----------------+--------------------------------------------+---------------+-----------+------------------+-----------+
```

<details>
<summary>Full <code>lsoh --help</code></summary>

```text
Usage: lsoh [options]

Lists the Oracle homes registered in the central inventory (oraInst.loc -> inventory.xml).

Default columns: NAME, LOCATION, VERSION, TYPE, STATUS
--full adds    : DETAIL, ROOH
--size adds    : SIZE_GB

TYPE   DBMS EE / DBMS SE2 / ..., GRID, AGNT, CLNT, OHS, OCMN, OGG MA, OGG CA
STATUS
  DBMS     ACTIVE (N DBs)         N database instances run from this home (from the running
                                  PMON binary, so out-of-place patching is counted correctly)
           ACTIVE (N processes)   no database, but other processes (e.g. a listener) run from it
           CONFIGURED (N in oratab, down)  oratab references it but nothing runs from it
           INSTALLED              not used
  GRID     ACTIVE (CRS)           the active Clusterware / Oracle Restart home
           ACTIVE (N processes) / INSTALLED
  OGG MA   ACTIVE (N deployments) adminsrvr processes running from this home
           ACTIVE (ServiceManager only) / INSTALLED
  others   ACTIVE (N processes) / INSTALLED
DETAIL     SIDs (DBMS/GRID) or deployment names (OGG MA) using the home
ROOH       YES = read-only Oracle home (orabasehome differs from the home), NO, or '-'
SIZE_GB    du of the home (slow - only with --size or --column size)

Options:
  --full              Add DETAIL and ROOH columns
  --size              Add SIZE_GB (runs du on every home, limited to 5 minutes in total)
  --type TYPE         Filter by TYPE (see below)
  --status REGEX      Filter by STATUS (case-insensitive regex), e.g. installed, active
  --column COL        Show only one column: name|location|version|type|status|detail|rooh|size
  --csv|--json|--raw  Output format (default: table)
  --grep PATTERN      Include only rows matching PATTERN (case-insensitive regex)
  --grep -v PATTERN   Exclude rows matching PATTERN (same as --grep-v)
  --no-header         Suppress header row (table/csv only)
  --no-color          Do not color the STATUS column
  -h, --help          Show this help

TYPE values:
  db | dbms        Database homes        grid            Grid homes
  ogg              GoldenGate homes      agent | agnt    OEM agent homes
  client | clnt    Oracle client homes   ohs             Oracle HTTP Server homes
  ocmn             Oracle common homes   <regex>         Any regex matched against TYPE

Notes:
  - Homes flagged REMOVED="T" (detached) in the central inventory are not listed.
  - Process detection needs read access to /proc/<pid>/exe (run as the software owner).
  - OGG deployment names are taken from the adminsrvr command line (--deployment /
    --deploymentName) or its OGG_ETC_HOME environment; 'unnamed' when not found.
  - --raw with --column prints one value per line; --no-header has no effect on --json/--raw.

Examples:
  lsoh
  lsoh --full
  lsoh --type db --status installed        (clean-up candidates after patching)
  lsoh --type ogg --full
  lsoh --size --csv
  lsoh --column location --raw
```

</details>

[Back to the function list](#function-reference)

### lspatches

Shows the patch level of every database and Grid home in one table, based on `opatch lspatches`.

**Features**

- Columns: HOME, Java, JDK, OJVM, Database RU, Datapump; `--full` adds TOMCAT, OCW, ACFS, DBWLM
- Homes are discovered with `lsoh` (DBMS and GRID), falling back to oratab - or pass homes as arguments
- `opatch` runs in parallel (`--parallel N`, default 4) without job-control noise
- A failing `opatch` is shown as `ERROR (opatch rc=N)` instead of empty columns
- `--column` to print one column only (e.g. `--column database --raw` for scripts)

**Usage**

```text
lspatches [--short|--full] [--column COL] [--parallel N] [ORACLE_HOME ...]
          [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Patch levels of every database and Grid home (opatch runs in parallel)**

```text
$ lspatches
Found 4 Oracle homes, running lspatches in parallel - please wait...
  +--------------------------------------------+-------------+-------------------+-------------------------------+-------------------------------+--------------------------+
  |  HOME                                      |  Java       |  JDK              |  OJVM                         |  Database                     |  Datapump                |
  +--------------------------------------------+-------------+-------------------+-------------------------------+-------------------------------+--------------------------+
  |  /u01/app/19.32.0/grid                     |  1.8.0_503  |  19.0.0.0.260818  |  n/a                          |  19.32.0.0.260721 (39472050)  |  n/a                     |
  |  /u01/app/oracle/product/19.31.0/dbhome_1  |  1.8.0_503  |  19.0.0.0.260415  |  19.31.0.0.260415 (38900113)  |  19.31.0.0.260415 (38871002)  |  19.31.0.0.0 (38955210)  |
  |  /u01/app/oracle/product/19.32.0/dbhome_1  |  1.8.0_503  |  19.0.0.0.260818  |  19.32.0.0.260721 (39222882)  |  19.32.0.0.260721 (39472050)  |  19.32.0.0.0 (39388555)  |
  |  /u01/app/oracle/product/23.26.1/dbhome_1  |  11.0.29    |  n/a              |  23.26.1.0.0 (39103002)       |  23.26.1.0.0 (39103001)       |  n/a                     |
  +--------------------------------------------+-------------+-------------------+-------------------------------+-------------------------------+--------------------------+
```

**All patch columns, including OCW, ACFS, DBWLM and TOMCAT**

```text
$ lspatches --full
Found 4 Oracle homes, running lspatches in parallel - please wait...
  +--------------------------------------------+-------------+-------------------+-------------------------------+-------------------------------+--------------------------+-------------------------+--------------------------+--------------------------+-------------------------+
  |  HOME                                      |  Java       |  JDK              |  OJVM                         |  Database                     |  Datapump                |  TOMCAT                 |  OCW                     |  ACFS                    |  DBWLM                  |
  +--------------------------------------------+-------------+-------------------+-------------------------------+-------------------------------+--------------------------+-------------------------+--------------------------+--------------------------+-------------------------+
  |  /u01/app/19.32.0/grid                     |  1.8.0_503  |  19.0.0.0.260818  |  n/a                          |  19.32.0.0.260721 (39472050)  |  n/a                     |  19.0.0.0.0 (39467030)  |  19.32.0.0.0 (39467003)  |  19.32.0.0.0 (39467010)  |  19.0.0.0.0 (39467020)  |
  |  /u01/app/oracle/product/19.31.0/dbhome_1  |  1.8.0_503  |  19.0.0.0.260415  |  19.31.0.0.260415 (38900113)  |  19.31.0.0.260415 (38871002)  |  19.31.0.0.0 (38955210)  |  n/a                    |  19.31.0.0.0 (38877001)  |  n/a                     |  n/a                    |
  |  /u01/app/oracle/product/19.32.0/dbhome_1  |  1.8.0_503  |  19.0.0.0.260818  |  19.32.0.0.260721 (39222882)  |  19.32.0.0.260721 (39472050)  |  19.32.0.0.0 (39388555)  |  n/a                    |  19.32.0.0.0 (39467003)  |  n/a                     |  n/a                    |
  |  /u01/app/oracle/product/23.26.1/dbhome_1  |  11.0.29    |  n/a              |  23.26.1.0.0 (39103002)       |  23.26.1.0.0 (39103001)       |  n/a                     |  n/a                    |  n/a                     |  n/a                     |  n/a                    |
  +--------------------------------------------+-------------+-------------------+-------------------------------+-------------------------------+--------------------------+-------------------------+--------------------------+--------------------------+-------------------------+
```

**Only the Database Release Update, one line per home**

```text
$ lspatches --column database --raw
Found 4 Oracle homes, running lspatches in parallel - please wait...
19.32.0.0.260721 (39472050)
19.31.0.0.260415 (38871002)
19.32.0.0.260721 (39472050)
23.26.1.0.0 (39103001)
```

**One specific home as CSV**

```text
$ lspatches --csv /u01/app/oracle/product/19.32.0/dbhome_1
Found 1 Oracle home(s), running lspatches - please wait...
HOME,Java,JDK,OJVM,Database,Datapump
/u01/app/oracle/product/19.32.0/dbhome_1,1.8.0_503,19.0.0.0.260818,19.32.0.0.260721 (39222882),19.32.0.0.260721 (39472050),19.32.0.0.0 (39388555)
```

<details>
<summary>Full <code>lspatches --help</code></summary>

```text
Usage: lspatches [options] [ORACLE_HOME ...]

Patch detail modes:
  --short                      Show default patch columns (default)
  --full                       Show all supported patch columns

Output modes:
  --csv                        Output in CSV format
  --json                       Output in JSON format
  --raw                        Script-friendly raw output (tab separated, no header)
  --no-header                  Suppress header row (table/csv only)

Filtering:
  --grep PATTERN               Include only rows matching PATTERN (case-insensitive regex)
  --grep -v PATTERN            Exclude rows matching PATTERN (case-insensitive regex)
  --grep-v PATTERN             Same as: --grep -v PATTERN
  --column COL                 Show only one column

Performance:
  --parallel N                 Number of 'opatch lspatches' run concurrently (default: 4).
                               Use --parallel 1 to run them one at a time.

Column values:
  home | oracle_home, java, jdk, ojvm, database | db, datapump | dp,
  tomcat, ocw, acfs, dbwlm  (tomcat/ocw/acfs/dbwlm require --full)

Notes:
  - If no ORACLE_HOME values are given, DB and Grid homes are discovered with lsoh,
    falling back to oratab.
  - If opatch fails for a home, the Database column shows ERROR (opatch rc=N).
  - Database = 'Database Release Update'; any other '... Release Update' line (other
    wording in newer releases such as 26ai) is used when that is not found.

Examples:
  lspatches
  lspatches --full
  lspatches --csv
  lspatches --grep 19.31
  lspatches --column database
  lspatches --column home --raw
  lspatches --full --column ocw
  lspatches /u01/app/oracle/product/19.31.0/dbhome_1
```

</details>

[Back to the function list](#function-reference)

### lslsnr

Lists all listeners on the host: CRS / Oracle Restart managed, SCAN and standalone.

**Features**

- Grid home read from `/etc/oracle/olr.loc` (works with `+ASM`, `+ASM1` ...)
- Ports from `srvctl config listener` (TCP and TCPS), standalone listener ports from `lsnrctl status`
- STATUS (enabled/disabled in CRS) and RUNNING (yes/no) are separate columns
- Standalone `tnslsnr` processes that are not registered in CRS are detected from the process list
- Filters: `--status enabled|disabled`, `--column`, `--grep` / `--grep-v`

**Usage**

```text
lslsnr [--status enabled|disabled] [--column COL]
       [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**CRS-managed, SCAN and standalone listeners**

```text
$ lslsnr
  +-----------------+--------------+--------------------------------------------+-----------------+------------+-----------+
  |  LISTENER_NAME  |  TYPE        |  ORACLE_HOME                               |  LISTENER_PORT  |  STATUS    |  RUNNING  |
  +-----------------+--------------+--------------------------------------------+-----------------+------------+-----------+
  |  LISTENER       |  LOCAL       |  /u01/app/19.32.0/grid                     |  1521           |  enabled   |  yes      |
  |  LISTENER_DG    |  LOCAL       |  /u01/app/19.32.0/grid                     |  1522;2484      |  disabled  |  no       |
  |  LISTENER_HR    |  STANDALONE  |  /u01/app/oracle/product/19.31.0/dbhome_1  |  1531           |  n/a       |  yes      |
  +-----------------+--------------+--------------------------------------------+-----------------+------------+-----------+
```

**Names of the enabled listeners only**

```text
$ lslsnr --status enabled --column name --raw
LISTENER
```

**Exclude standalone listeners, CSV output**

```text
$ lslsnr --grep -v STANDALONE --csv
LISTENER_NAME,TYPE,ORACLE_HOME,LISTENER_PORT,STATUS,RUNNING
LISTENER,LOCAL,/u01/app/19.32.0/grid,1521,enabled,yes
LISTENER_DG,LOCAL,/u01/app/19.32.0/grid,1522;2484,disabled,no
```

<details>
<summary>Full <code>lslsnr --help</code></summary>

```text
Usage: lslsnr [options]

Lists listeners on this host:
  LOCAL       CRS/HAS-managed listeners       (srvctl config/status listener)
  SCAN        SCAN listeners on RAC clusters  (srvctl config/status scan_listener)
  STANDALONE  Running tnslsnr processes not registered in CRS (port from lsnrctl status)

Columns:
  LISTENER_NAME, TYPE, ORACLE_HOME, LISTENER_PORT,
  STATUS  (srvctl enabled/disabled - configuration, NOT whether it is running)
  RUNNING (yes/no from srvctl status; standalone listeners are always 'yes')

Options:
  --csv | --json | --raw        Output format (default: table)
  --grep PATTERN                Include only rows matching PATTERN (case-insensitive regex)
  --grep -v PATTERN | --grep-v  Exclude rows matching PATTERN
  --column COL                  Show only one column: name|type|home|port|status|running
  --status STATUS               Filter by srvctl status: enabled|disabled
  --no-header                   Suppress header row (table/csv only)
  -h, --help                    Show this help

Notes:
  - The Grid home is read from /etc/oracle/olr.loc (works with +ASM1, +ASM2 ...).
  - Multiple ports are shown as a semicolon-separated list.

Examples:
  lslsnr
  lslsnr --csv
  lslsnr --grep -v SCAN
  lslsnr --column port
  lslsnr --status enabled --column name --raw
```

</details>

[Back to the function list](#function-reference)

### lsdbhome

Shows, for every database, the ORACLE_HOME known to each layer - the quickest way to spot drift after out-of-place patching.

**Features**

- RUNNING_HOME from `/proc/<pmon pid>/exe`, ORATAB_HOME, CRS_HOME (`srvctl config database`), OEM_HOME (agent `targets.xml`)
- STATUS `MATCH` when all known values agree, `MISMATCH` otherwise (`-` = not known by that layer)
- `--short` shows only the last two path components
- Return code 2 when a MISMATCH is found

**Usage**

```text
lsdbhome [--short] [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**ORACLE_HOME known to each layer for every database (out-of-place patching drift)**

```text
$ lsdbhome
  +-----------+---------+--------------------------------------------+--------------------------------------------+--------------------------------------------+--------------------------------------------+------------+
  |  SID      |  STATE  |  RUNNING_HOME                              |  ORATAB_HOME                               |  CRS_HOME                                  |  OEM_HOME                                  |  STATUS    |
  +-----------+---------+--------------------------------------------+--------------------------------------------+--------------------------------------------+--------------------------------------------+------------+
  |  AIDEV    |  UP     |  /u01/app/oracle/product/23.26.1/dbhome_1  |  /u01/app/oracle/product/23.26.1/dbhome_1  |  -                                         |  /u01/app/oracle/product/19.32.0/dbhome_1  |  MISMATCH  |
  |  CRMSTBY  |  UP     |  /u01/app/oracle/product/19.32.0/dbhome_1  |  /u01/app/oracle/product/19.32.0/dbhome_1  |  /u01/app/oracle/product/19.32.0/dbhome_1  |  -                                         |  MATCH     |
  |  DWTST    |  DOWN   |  -                                         |  /u01/app/oracle/product/19.32.0/dbhome_1  |  -                                         |  -                                         |  MATCH     |
  |  FINPRD   |  UP     |  /u01/app/oracle/product/19.32.0/dbhome_1  |  /u01/app/oracle/product/19.32.0/dbhome_1  |  /u01/app/oracle/product/19.32.0/dbhome_1  |  /u01/app/oracle/product/19.32.0/dbhome_1  |  MATCH     |
  |  HRPRD    |  UP     |  /u01/app/oracle/product/19.31.0/dbhome_1  |  /u01/app/oracle/product/19.32.0/dbhome_1  |  /u01/app/oracle/product/19.31.0/dbhome_1  |  /u01/app/oracle/product/19.31.0/dbhome_1  |  MISMATCH  |
  +-----------+---------+--------------------------------------------+--------------------------------------------+--------------------------------------------+--------------------------------------------+------------+
```

**Only the databases that need attention, with shortened paths**

```text
$ lsdbhome --short --grep MISMATCH
  +---------+---------+------------------------+------------------------+------------------------+------------------------+------------+
  |  SID    |  STATE  |  RUNNING_HOME          |  ORATAB_HOME           |  CRS_HOME              |  OEM_HOME              |  STATUS    |
  +---------+---------+------------------------+------------------------+------------------------+------------------------+------------+
  |  AIDEV  |  UP     |  .../23.26.1/dbhome_1  |  .../23.26.1/dbhome_1  |  -                     |  .../19.32.0/dbhome_1  |  MISMATCH  |
  |  HRPRD  |  UP     |  .../19.31.0/dbhome_1  |  .../19.32.0/dbhome_1  |  .../19.31.0/dbhome_1  |  .../19.31.0/dbhome_1  |  MISMATCH  |
  +---------+---------+------------------------+------------------------+------------------------+------------------------+------------+
```

<details>
<summary>Full <code>lsdbhome --help</code></summary>

```text
Usage: lsdbhome [--short] [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

For every database instance on the host, shows the ORACLE_HOME known to each layer:
  RUNNING_HOME   home of the running PMON binary (/proc/<pid>/exe)
  ORATAB_HOME    /etc/oratab
  CRS_HOME       srvctl config database (Oracle Restart / RAC registration)
  OEM_HOME       OracleHome property of the oracle_database target in the local
                 agent's targets.xml (<agent_inst>/sysman/emd/targets.xml)
  STATUS         MATCH when all known values agree, MISMATCH otherwise
                 ('-' = not known by that layer; not counted as a mismatch)

After out-of-place patching all four should point to the new home; any
MISMATCH shows what still needs to be updated (oratab, srvctl modify database -oraclehome,
or the OEM target property).

Options:
  --short        Show only the last two path components of each home
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Notes:
  - Set DBA_AGENT_INST=/path/to/agent_inst if the agent is not running or not auto-detected.

Return code: 0 = all MATCH, 2 = at least one MISMATCH

Examples:
  lsdbhome
  lsdbhome --short
  lsdbhome --grep MISMATCH
```

</details>

[Back to the function list](#function-reference)

### setdb

Sets the Oracle environment of the current shell for a database or ASM instance, from a menu or by SID / number.

**Features**

- Menu lists `+ASM` first, then every database sorted by SID, with ROLE and STATUS (e.g. `PRIMARY / READ WRITE`, `PHYSICAL STANDBY / MOUNTED`)
- Sets `ORACLE_SID`, `ORACLE_HOME`, `ORACLE_BASE`, `PATH`, `LD_LIBRARY_PATH` and `ADR_HOME` (so the `cda` alias works)
- Removes the previous home from `PATH` / `LD_LIBRARY_PATH` first
- For running instances the home comes from the running binary - correct during out-of-place patching (a NOTE is printed when oratab differs)
- Warns when `TWO_TASK` is set
- Named `setdb` so the Linux `setsid` command is not hidden

**Usage**

```text
setdb [SID|NUMBER]
```

**Examples**

**Interactive menu: ASM first, then the databases sorted by SID with role and status**

```text
$ setdb
  +------+-----------+---------+--------------------+--------------+--------------------------------------------+
  |  NO  |  SID      |  STATE  |  ROLE              |  STATUS      |  ORACLE_HOME                               |
  +------+-----------+---------+--------------------+--------------+--------------------------------------------+
  |  1   |  +ASM     |  UP     |  ASM               |  STARTED     |  /u01/app/19.32.0/grid                     |
  |  2   |  AIDEV    |  UP     |  PRIMARY           |  READ WRITE  |  /u01/app/oracle/product/23.26.1/dbhome_1  |
  |  3   |  CRMSTBY  |  UP     |  PHYSICAL STANDBY  |  MOUNTED     |  /u01/app/oracle/product/19.32.0/dbhome_1  |
  |  4   |  DWTST    |  DOWN   |  -                 |  -           |  /u01/app/oracle/product/19.32.0/dbhome_1  |
  |  5   |  FINPRD   |  UP     |  PRIMARY           |  READ WRITE  |  /u01/app/oracle/product/19.32.0/dbhome_1  |
  |  6   |  HRPRD    |  UP     |  PRIMARY           |  READ WRITE  |  /u01/app/oracle/product/19.31.0/dbhome_1  |
  +------+-----------+---------+--------------------+--------------+--------------------------------------------+
Select number or SID: 4
ORACLE_SID  = DWTST   (DOWN)
ORACLE_HOME = /u01/app/oracle/product/19.32.0/dbhome_1
ORACLE_BASE = /u01/app/oracle
ADR_HOME    = /u01/app/oracle/diag/rdbms/dwtst/DWTST
```

**Set the environment directly. The NOTE shows out-of-place patching in progress**

```text
$ setdb HRPRD
ORACLE_SID  = HRPRD   (UP)
ORACLE_HOME = /u01/app/oracle/product/19.31.0/dbhome_1
ORACLE_BASE = /u01/app/oracle
ADR_HOME    = /u01/app/oracle/diag/rdbms/hrprd/HRPRD
NOTE: oratab points to /u01/app/oracle/product/19.32.0/dbhome_1 - using the RUNNING home above (out-of-place patching in progress?)
```

<details>
<summary>Full <code>setdb --help</code></summary>

```text
Usage: setdb [SID|NUMBER]

Sets the Oracle environment of the CURRENT shell for one database or ASM instance:
  ORACLE_SID, ORACLE_HOME, ORACLE_BASE, PATH, LD_LIBRARY_PATH, ADR_HOME
(the previous ORACLE_HOME is removed from PATH / LD_LIBRARY_PATH first).

Without an argument a numbered menu is shown: the ASM instance first (when running),
then every database sorted by SID. For running instances the menu also shows the
database ROLE (PRIMARY / PHYSICAL STANDBY / ...) and the STATUS (READ WRITE, MOUNTED,
READ ONLY WITH APPLY, STARTED, ...); DOWN oratab databases are listed too.
For RUNNING instances the ORACLE_HOME is taken from the
running binary, so it is correct during out-of-place patching even when oratab
already points to the new home (a NOTE is printed when they differ).

ADR_HOME is set to the instance's diag directory, so the 'cda' alias works.

Examples:
  setdb             (menu)
  setdb PRD1
  setdb 2
  setdb +ASM1

Note: named setdb (not setsid) so the Linux 'setsid' command is not hidden.
```

</details>

[Back to the function list](#function-reference)

## Database status and health

### dbsummary

One-row-per-database inventory of the host: role, open mode, release, RU, CDB/PDBs, size, log mode and flashback.

**Features**

- Running instances and DOWN oratab databases
- VERSION from `VERSION_FULL` (26ai reports `23.0.0.0.0` in `VERSION`)
- RU = the latest Release Update successfully applied by datapatch
- SIZE_GB works on mounted standbys (datafiles + tempfiles)
- `--full` adds DB_UNIQUE_NAME, VERSION, FORCE_LOG, CHARSET and ORACLE_HOME

**Usage**

```text
dbsummary [--full] [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
          [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**One-row inventory of every database on the host (running and down)**

```text
$ dbsummary
  +-----------+-----------+--------------------+--------------+--------------------+-------+--------+-----------+----------------+-------------+----------+
  |  SID      |  DB_NAME  |  ROLE              |  OPEN_MODE   |  RU                |  CDB  |  PDBS  |  SIZE_GB  |  LOG_MODE      |  FLASHBACK  |  STATUS  |
  +-----------+-----------+--------------------+--------------+--------------------+-------+--------+-----------+----------------+-------------+----------+
  |  AIDEV    |  AIDEV    |  PRIMARY           |  READ WRITE  |  23.26.1.0.0       |  YES  |  1     |  88.4     |  NOARCHIVELOG  |  NO         |  UP      |
  |  CRMSTBY  |  CRMPRD   |  PHYSICAL STANDBY  |  MOUNTED     |                    |  YES  |  1     |  956.0    |  ARCHIVELOG    |  YES        |  UP      |
  |  DWTST    |           |                    |              |                    |       |        |           |                |             |  DOWN    |
  |  FINPRD   |  FINPRD   |  PRIMARY           |  READ WRITE  |  19.32.0.0.260721  |  YES  |  2     |  1843.6   |  ARCHIVELOG    |  YES        |  UP      |
  |  HRPRD    |  HRPRD    |  PRIMARY           |  READ WRITE  |  19.31.0.0.260415  |  NO   |  -     |  412.3    |  ARCHIVELOG    |  NO         |  UP      |
  +-----------+-----------+--------------------+--------------+--------------------+-------+--------+-----------+----------------+-------------+----------+
```

**All columns as CSV**

```text
$ dbsummary --full --csv
SID,DB_NAME,DB_UNIQUE_NAME,ROLE,OPEN_MODE,VERSION,RU,CDB,PDBS,SIZE_GB,LOG_MODE,FORCE_LOG,FLASHBACK,CHARSET,STATUS,ORACLE_HOME
AIDEV,AIDEV,AIDEV,PRIMARY,READ WRITE,23.26.1.0.0,23.26.1.0.0,YES,1,88.4,NOARCHIVELOG,NO,NO,AL32UTF8,UP,/u01/app/oracle/product/23.26.1/dbhome_1
CRMSTBY,CRMPRD,CRMPRD_B,PHYSICAL STANDBY,MOUNTED,19.32.0.0.0,,YES,1,956.0,ARCHIVELOG,YES,YES,,UP,/u01/app/oracle/product/19.32.0/dbhome_1
DWTST,,,,,,,,,,,,,,DOWN,/u01/app/oracle/product/19.32.0/dbhome_1
FINPRD,FINPRD,FINPRD_A,PRIMARY,READ WRITE,19.32.0.0.0,19.32.0.0.260721,YES,2,1843.6,ARCHIVELOG,YES,YES,AL32UTF8,UP,/u01/app/oracle/product/19.32.0/dbhome_1
HRPRD,HRPRD,HRPRD,PRIMARY,READ WRITE,19.31.0.0.0,19.31.0.0.260415,NO,-,412.3,ARCHIVELOG,NO,NO,WE8MSWIN1252,UP,/u01/app/oracle/product/19.31.0/dbhome_1
```

<details>
<summary>Full <code>dbsummary --help</code></summary>

```text
Usage: dbsummary [--full] [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
                 [--csv|--json|--raw] [--no-header] [--no-color]

One row per database on the host (running instances + DOWN oratab entries).

Default columns:
  SID, DB_NAME, ROLE, OPEN_MODE, RU, CDB, PDBS, SIZE_GB, LOG_MODE, FLASHBACK, STATUS
--full adds:
  DB_UNIQUE_NAME, VERSION, FORCE_LOG, CHARSET, ORACLE_HOME

Column notes:
  VERSION   Full release (V$INSTANCE.VERSION_FULL), e.g. 19.32.0.0.0 or 23.26.1.0.0
            (26ai reports VERSION 23.0.0.0.0 - VERSION_FULL shows the real release)
  RU        Latest Release Update successfully applied by datapatch (dba_registry_sqlpatch)
  PDBS      Number of PDBs (PDB$SEED excluded)
  SIZE_GB   Datafiles + tempfiles (works on MOUNTED standbys too)
  RU and CHARSET need an OPEN database; they are blank on MOUNTED standbys.

Options:
  --full               Show all columns
  --db REGEX           Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v    Filter output rows (case-insensitive regex)
  --csv|--json|--raw   Output format (default: table)
  --no-header          Suppress header row (table/csv only)
  --no-color           Do not color status values

Examples:
  dbsummary
  dbsummary --full --csv
  dbsummary --grep STANDBY
```

</details>

[Back to the function list](#function-reference)

### dbuptime

Startup time and uptime of every instance, plus the previous startup from AWR.

**Features**

- Includes DOWN oratab databases and mounted standbys
- PREV_START = latest AWR-recorded startup before the current one (open databases)
- `--full` adds DB_UNIQUE_NAME, instance number/name and ORACLE_HOME

**Usage**

```text
dbuptime [--grep PATTERN] [--grep-v PATTERN] [--full] [--csv|--json|--raw] [--no-header]
```

**Examples**

**Startup time, uptime and previous startup of every instance**

```text
$ dbuptime
  +-----------+-----------+---------------+-------------+--------------+--------------------+----------+-----------------------+--------------+-----------------------+
  |  SID      |  DB_NAME  |  INSTANCE_ID  |  HOST_NAME  |  OPEN_MODE   |  DATABASE_ROLE     |  STATUS  |  CURRENT_START        |  UPTIME      |  PREV_START           |
  +-----------+-----------+---------------+-------------+--------------+--------------------+----------+-----------------------+--------------+-----------------------+
  |  AIDEV    |  AIDEV    |  1            |  dbhost01   |  READ WRITE  |  PRIMARY           |  UP      |  2026-11-16 04:14:17  |  9d 2h 17m   |  2026-08-16 04:14:17  |
  |  CRMSTBY  |  CRMPRD   |  1            |  dbhost01   |  MOUNTED     |  PHYSICAL STANDBY  |  UP      |  2026-10-15 04:14:17  |  41d 2h 17m  |                       |
  |  DWTST    |           |               |             |              |                    |  DOWN    |                       |              |                       |
  |  FINPRD   |  FINPRD   |  1            |  dbhost01   |  READ WRITE  |  PRIMARY           |  UP      |  2026-10-15 04:14:17  |  41d 2h 17m  |  2026-07-15 04:14:17  |
  |  HRPRD    |  HRPRD    |  1            |  dbhost01   |  READ WRITE  |  PRIMARY           |  UP      |  2026-11-22 04:14:17  |  3d 2h 17m   |  2026-08-22 04:14:17  |
  +-----------+-----------+---------------+-------------+--------------+--------------------+----------+-----------------------+--------------+-----------------------+
```

**All columns for SIDs starting with FIN or HR**

```text
$ dbuptime --full --grep '^(FIN|HR)'
  +----------+-----------+------------------+---------------+-------------------+-----------------+-------------+--------------+-----------------+----------+-----------------------+--------------+-----------------------+--------------------------------------------+
  |  SID     |  DB_NAME  |  DB_UNIQUE_NAME  |  INSTANCE_ID  |  INSTANCE_NUMBER  |  INSTANCE_NAME  |  HOST_NAME  |  OPEN_MODE   |  DATABASE_ROLE  |  STATUS  |  CURRENT_START        |  UPTIME      |  PREV_START           |  ORACLE_HOME                               |
  +----------+-----------+------------------+---------------+-------------------+-----------------+-------------+--------------+-----------------+----------+-----------------------+--------------+-----------------------+--------------------------------------------+
  |  FINPRD  |  FINPRD   |  FINPRD_A        |  1            |  1                |  FINPRD         |  dbhost01   |  READ WRITE  |  PRIMARY        |  UP      |  2026-10-15 04:14:18  |  41d 2h 17m  |  2026-07-15 04:14:18  |  /u01/app/oracle/product/19.32.0/dbhome_1  |
  |  HRPRD   |  HRPRD    |  HRPRD           |  1            |  1                |  HRPRD          |  dbhost01   |  READ WRITE  |  PRIMARY        |  UP      |  2026-11-22 04:14:18  |  3d 2h 17m   |  2026-08-22 04:14:18  |  /u01/app/oracle/product/19.31.0/dbhome_1  |
  +----------+-----------+------------------+---------------+-------------------+-----------------+-------------+--------------+-----------------+----------+-----------------------+--------------+-----------------------+--------------------------------------------+
```

**JSON output**

```text
$ dbuptime --json --grep HRPRD
[
  {"SID":"HRPRD","DB_NAME":"HRPRD","INSTANCE_ID":"1","HOST_NAME":"dbhost01","OPEN_MODE":"READ WRITE","DATABASE_ROLE":"PRIMARY","STATUS":"UP","CURRENT_START":"2026-11-22 04:14:18","UPTIME":"3d 2h 17m","PREV_START":"2026-08-22 04:14:18"}
]
```

<details>
<summary>Full <code>dbuptime --help</code></summary>

```text
Usage: dbuptime [--grep PATTERN] [--grep-v PATTERN] [--full] [--csv|--json|--raw] [--no-header]

Shows startup time and uptime of every database instance on the host.
Running instances come from PMON (ORACLE_HOME from the running binary);
oratab database entries with no running instance are shown as DOWN.

Options:
  --grep PATTERN     Include only SIDs matching PATTERN (case-insensitive regex)
  --grep-v PATTERN   Exclude SIDs matching PATTERN
  --full             Show all columns
  --csv|--json|--raw Output format (default: table)
  --no-header        Suppress header row (table/csv only)
  -h, --help         Show help

Default columns:
  SID, DB_NAME, INSTANCE_ID, HOST_NAME, OPEN_MODE,
  DATABASE_ROLE, STATUS, CURRENT_START, UPTIME, PREV_START

Full columns:
  SID, DB_NAME, DB_UNIQUE_NAME, INSTANCE_ID, INSTANCE_NUMBER,
  INSTANCE_NAME, HOST_NAME, OPEN_MODE, DATABASE_ROLE, STATUS,
  CURRENT_START, UPTIME, PREV_START, ORACLE_HOME

Notes:
  - Mounted standbys are fully reported; PREV_START needs an OPEN database
    (AWR history) and is blank otherwise.
  - PREV_START is the latest AWR-recorded startup before the current one.

Examples:
  dbuptime
  dbuptime --grep em
  dbuptime --full --csv
  dbuptime --grep '^PRD'
```

</details>

[Back to the function list](#function-reference)

### dbmemory

Memory parameters and current memory usage of every running instance, with a TOTAL row.

**Features**

- Memory mode (AMM / ASMM / MANUAL), SGA and PGA targets and limits
- Current usage: SGA_CUR_GB, SHARED_POOL_CUR_GB, DB_CACHE_CUR_GB (`v$sga_dynamic_components`), PGA_ALLOC_GB, PGA_MAX_ALLOC_GB (`v$pgastat`)
- Column selection with `--columns`, `--cgrep` and `--cgrep-v`; `--summary` for the TOTAL row only
- Long column names wrap at `_` in table mode to keep the table narrow (never in CSV/JSON/raw)

**Usage**

```text
dbmemory [--csv|--json|--raw] [--no-header] [--summary] [--grep PATTERN] [--grep-v PATTERN]
         [--cgrep PATTERN] [--cgrep-v PATTERN] [--columns COL1,COL2,...]
```

**Examples**

**Memory settings and current usage (column names wrap at `_` in table mode)**

```text
$ dbmemory
  +-----------+-------------+-----------+---------------+-------------+---------------+------------+--------------+---------------+----------------+----------------+----------------+-------------+-------------+------------+
  |  DB_NAME  |  INSTANCE_  |  STATUS   |  MEMORY_MODE  |  MEMORY_    |  SGA_TARGET_  |  SGA_MAX_  |  SGA_CUR_GB  |  PGA_TARGET_  |  PGA_LIMIT_GB  |  PGA_ALLOC_GB  |  SHARED_POOL_  |  DB_CACHE_  |  PROCESSES  |  SESSIONS  |
  |           |  NAME       |           |               |  TARGET_GB  |  GB           |  SIZE_GB   |              |  GB           |                |                |  CUR_GB        |  CUR_GB     |             |            |
  +-----------+-------------+-----------+---------------+-------------+---------------+------------+--------------+---------------+----------------+----------------+----------------+-------------+-------------+------------+
  |  AIDEV    |  AIDEV      |  OPEN     |  AMM          |  4.00       |  0.00         |  0.00      |  2.62        |  0.00         |  0.00          |  0.40          |  0.81          |  1.32       |  400        |  624       |
  |  CRMPRD   |  CRMSTBY    |  MOUNTED  |  ASMM         |  0.00       |  12.00        |  12.00     |  12.00       |  4.00         |  8.00          |  0.62          |  1.88          |  9.21       |  1000       |  1528      |
  |  FINPRD   |  FINPRD     |  OPEN     |  ASMM         |  0.00       |  16.00        |  16.00     |  16.00       |  6.00         |  12.00         |  4.81          |  3.25          |  10.52      |  1500       |  2272      |
  |  HRPRD    |  HRPRD      |  OPEN     |  ASMM         |  0.00       |  6.00         |  6.00      |  6.00        |  2.00         |  4.00          |  1.12          |  1.20          |  4.31       |  600        |  924       |
  |  TOTAL    |             |           |               |  4          |  34           |  34        |  36.62       |  12           |  24            |  6.95          |  7.14          |  25.36      |  3500       |  5348      |
  +-----------+-------------+-----------+---------------+-------------+---------------+------------+--------------+---------------+----------------+----------------+----------------+-------------+-------------+------------+
```

**Only the TOTAL row**

```text
$ dbmemory --summary
  +-----------+-------------+----------+---------------+-------------+---------------+------------+--------------+---------------+----------------+----------------+----------------+-------------+-------------+------------+
  |  DB_NAME  |  INSTANCE_  |  STATUS  |  MEMORY_MODE  |  MEMORY_    |  SGA_TARGET_  |  SGA_MAX_  |  SGA_CUR_GB  |  PGA_TARGET_  |  PGA_LIMIT_GB  |  PGA_ALLOC_GB  |  SHARED_POOL_  |  DB_CACHE_  |  PROCESSES  |  SESSIONS  |
  |           |  NAME       |          |               |  TARGET_GB  |  GB           |  SIZE_GB   |              |  GB           |                |                |  CUR_GB        |  CUR_GB     |             |            |
  +-----------+-------------+----------+---------------+-------------+---------------+------------+--------------+---------------+----------------+----------------+----------------+-------------+-------------+------------+
  |  TOTAL    |             |          |               |  4          |  34           |  34        |  36.62       |  12           |  24            |  6.95          |  7.14          |  25.36      |  3500       |  5348      |
  +-----------+-------------+----------+---------------+-------------+---------------+------------+--------------+---------------+----------------+----------------+----------------+-------------+-------------+------------+
```

**Selected columns only**

```text
$ dbmemory --columns SGA_TARGET_GB,SGA_CUR_GB,PGA_TARGET_GB,PGA_ALLOC_GB
  +-----------+-------------+---------------+--------------+---------------+----------------+
  |  DB_NAME  |  INSTANCE_  |  SGA_TARGET_  |  SGA_CUR_GB  |  PGA_TARGET_  |  PGA_ALLOC_GB  |
  |           |  NAME       |  GB           |              |  GB           |                |
  +-----------+-------------+---------------+--------------+---------------+----------------+
  |  AIDEV    |  AIDEV      |  0.00         |  2.62        |  0.00         |  0.40          |
  |  CRMPRD   |  CRMSTBY    |  12.00        |  12.00       |  4.00         |  0.62          |
  |  FINPRD   |  FINPRD     |  16.00        |  16.00       |  6.00         |  4.81          |
  |  HRPRD    |  HRPRD      |  6.00         |  6.00        |  2.00         |  1.12          |
  |  TOTAL    |             |  34           |  36.62       |  12           |  6.95          |
  +-----------+-------------+---------------+--------------+---------------+----------------+
```

**Only the PGA columns, CSV (names are never wrapped in CSV)**

```text
$ dbmemory --cgrep PGA --csv
DB_NAME,INSTANCE_NAME,PGA_TARGET_GB,PGA_LIMIT_GB,PGA_ALLOC_GB
AIDEV,AIDEV,0.00,0.00,0.40
CRMPRD,CRMSTBY,4.00,8.00,0.62
FINPRD,FINPRD,6.00,12.00,4.81
HRPRD,HRPRD,2.00,4.00,1.12
TOTAL,,12,24,6.95
```

<details>
<summary>Full <code>dbmemory --help</code></summary>

```text
Usage:
  dbmemory [--csv|--json|--raw] [--no-header] [--summary] [--grep PATTERN] [--grep-v PATTERN]
           [--cgrep PATTERN] [--cgrep-v PATTERN] [--columns COL1,COL2,...]

Description:
  Shows Oracle memory settings (parameters) and current usage for all running
  DB instances on this server, plus a TOTAL row.

  Parameter columns (configured values; under ASMM, SHARED_POOL_GB and DB_CACHE_GB
  are MINIMUMS, not current sizes):
    MEMORY_TARGET_GB, MEMORY_MAX_TARGET_GB, SGA_TARGET_GB, SGA_MAX_SIZE_GB,
    PGA_TARGET_GB, PGA_LIMIT_GB, SHARED_POOL_GB, DB_CACHE_GB, LARGE_POOL_GB,
    JAVA_POOL_GB, STREAMS_POOL_GB, RESULT_CACHE_MB, PROCESSES, SESSIONS
  Current usage columns:
    SGA_CUR_GB            Current SGA size (v$sga)
    SHARED_POOL_CUR_GB    Current shared pool (v$sga_dynamic_components)
    DB_CACHE_CUR_GB       Current default buffer cache (v$sga_dynamic_components)
    PGA_ALLOC_GB          Total PGA allocated now (v$pgastat)
    PGA_MAX_ALLOC_GB      Maximum PGA allocated since startup (v$pgastat)

Options:
  --csv / --json / --raw    Output format (default: table)
  --no-header               Suppress header row (table/csv only)
  --summary                 Show only the TOTAL row (header kept)
  --grep PATTERN            Include rows where DB_NAME or INSTANCE_NAME matches PATTERN
  --grep-v PATTERN          Exclude rows where DB_NAME or INSTANCE_NAME matches PATTERN
  --cgrep PATTERN           Include only columns whose name matches PATTERN
  --cgrep-v PATTERN         Exclude columns whose name matches PATTERN
  --columns COL1,COL2,...   Show only the selected columns
  DB_NAME and INSTANCE_NAME are always kept as the leading columns.

  In table mode long column names are wrapped at '_' (e.g. SHARED_POOL_ / CUR_GB) to keep
  the table narrow. CSV / JSON / raw output always uses the full names on one line.

Available columns:
  DB_NAME INSTANCE_NAME HOST_NAME STATUS DATABASE_ROLE OPEN_MODE MEMORY_MODE
  MEMORY_TARGET_GB MEMORY_MAX_TARGET_GB SGA_TARGET_GB SGA_MAX_SIZE_GB SGA_CUR_GB
  PGA_TARGET_GB PGA_LIMIT_GB PGA_ALLOC_GB PGA_MAX_ALLOC_GB
  SHARED_POOL_GB SHARED_POOL_CUR_GB DB_CACHE_GB DB_CACHE_CUR_GB
  LARGE_POOL_GB JAVA_POOL_GB STREAMS_POOL_GB RESULT_CACHE_MB PROCESSES SESSIONS

Examples:
  dbmemory
  dbmemory --summary
  dbmemory --grep prod
  dbmemory --cgrep GB --cgrep-v MAX
  dbmemory --columns SGA_TARGET_GB,SGA_CUR_GB,PGA_TARGET_GB,PGA_ALLOC_GB
```

</details>

[Back to the function list](#function-reference)

### dbhpaloc

HugePages allocation of every running instance, read from the latest Huge Pages section of its alert log.

**Features**

- One row per page size (2 MB and 1 GB pages)
- Alert logs are read backwards, so very large logs are fast
- OK when expected = allocated without errors, FAIL otherwise; ERROR when no section is found
- Ends with the host totals from `/proc/meminfo`, the pages expected by all instances, the headroom and the Transparent HugePages setting
- `--status`, `--sort COLUMN[:desc]`, `--summary`

**Usage**

```text
dbhpaloc [--grep PATTERN] [--grep-v PATTERN] [--status ok|fail|error]
         [--sort COLUMN[:desc]] [--summary] [--csv|--json|--raw] [--no-header]
```

**Examples**

**HugePages allocation of each instance from its alert log, plus the host totals**

```text
$ dbhpaloc
  +------------+------------+-------------+------------+-------------+--------------+----------+-----------------------------------------+
  |  INSTANCE  |  PAGESIZE  |  AVAILABLE  |  EXPECTED  |  ALLOCATED  |  %ALLOCATED  |  STATUS  |  ERROR                                  |
  +------------+------------+-------------+------------+-------------+--------------+----------+-----------------------------------------+
  |  AIDEV     |  -         |  -          |  -         |  -          |  -           |  ERROR   |  No HugePages entry found in alert log  |
  |  HRPRD     |  2048K     |  3290       |  3073      |  1536       |  50.0%       |  FAIL    |  ORA-27125                              |
  |  CRMSTBY   |  2048K     |  12286      |  6145      |  6145       |  100.0%      |  OK      |  NONE                                   |
  |  FINPRD    |  2048K     |  20480      |  8193      |  8193       |  100.0%      |  OK      |  NONE                                   |
  +------------+------------+-------------+------------+-------------+--------------+----------+-----------------------------------------+

System HugePages
----------------
Total Pages        : 0
Free Pages         : 0
Reserved           : 0
Surplus            : 0
Page Size          : 2048 kB
Expected by DBs    : 17411  (sum of EXPECTED for rows shown above, default page size)
Headroom           : -17411 pages
Transparent HP     : always   <-- Oracle recommends: never
```

**Add a summary and sort by allocated pages**

```text
$ dbhpaloc --summary --sort allocated:desc
  +------------+------------+-------------+------------+-------------+--------------+----------+-----------------------------------------+
  |  INSTANCE  |  PAGESIZE  |  AVAILABLE  |  EXPECTED  |  ALLOCATED  |  %ALLOCATED  |  STATUS  |  ERROR                                  |
  +------------+------------+-------------+------------+-------------+--------------+----------+-----------------------------------------+
  |  FINPRD    |  2048K     |  20480      |  8193      |  8193       |  100.0%      |  OK      |  NONE                                   |
  |  CRMSTBY   |  2048K     |  12286      |  6145      |  6145       |  100.0%      |  OK      |  NONE                                   |
  |  HRPRD     |  2048K     |  3290       |  3073      |  1536       |  50.0%       |  FAIL    |  ORA-27125                              |
  |  AIDEV     |  -         |  -          |  -         |  -          |  -           |  ERROR   |  No HugePages entry found in alert log  |
  +------------+------------+-------------+------------+-------------+--------------+----------+-----------------------------------------+

Summary
-------
Rows Checked       : 4
OK                 : 2
FAIL               : 1
ERROR              : 1
Average Allocation : 83.3% (excluding ERROR rows)

System HugePages
----------------
Total Pages        : 0
Free Pages         : 0
Reserved           : 0
Surplus            : 0
Page Size          : 2048 kB
Expected by DBs    : 17411  (sum of EXPECTED for rows shown above, default page size)
Headroom           : -17411 pages
Transparent HP     : always   <-- Oracle recommends: never
```

**Only the instances that did not get all their HugePages**

```text
$ dbhpaloc --status fail --csv
INSTANCE,PAGESIZE,AVAILABLE,EXPECTED,ALLOCATED,%ALLOCATED,STATUS,ERROR
HRPRD,2048K,3290,3073,1536,50.0,FAIL,ORA-27125
```

<details>
<summary>Full <code>dbhpaloc --help</code></summary>

```text
Usage:
  dbhpaloc [--grep PATTERN] [--grep-v PATTERN] [--status ok|fail|error]
           [--sort COLUMN[:desc]] [--summary] [--csv|--json|--raw] [--no-header]

Description:
  Displays HugePages allocation for all running Oracle databases, based on the
  latest "Huge Pages Information" section in each database alert log
  (read from the end of the file, so large alert logs are fast).
  One row per huge page size found (2048K and/or 1048576K = 1GB pages).

Filter Options:
  --grep <pattern>       Include only instances matching pattern
  --grep-v <pattern>     Exclude instances matching pattern
  --status <status>      ok, fail, error

Sort Columns (append :desc for descending):
  instance | db | dbname | database     Instance name
  %allocated | pct (default)             Allocation percentage
  expected                               Expected pages
  allocated                              Allocated pages
  status                                 OK / FAIL / ERROR

Output Options:
  --summary              Summary after the table (ERROR rows are excluded from the average)
  --csv / --json / --raw Output the instance table only

The table view always ends with system HugePages (/proc/meminfo), the total
pages expected by the running instances, and the Transparent HugePages setting.

Examples:
  dbhpaloc
  dbhpaloc --status fail
  dbhpaloc --grep awm --status fail
  dbhpaloc --sort allocated:desc
  dbhpaloc --summary
```

</details>

[Back to the function list](#function-reference)

### dbspace

Tablespace, TEMP, UNDO and FRA usage of every running database and every open container, relative to the autoextend maximum.

**Features**

- PERMANENT = allocated - free; UNDO = ACTIVE + UNEXPIRED extents; TEMP = segments in use now; FRA = used - reclaimable
- PCT_USED is relative to MAX_GB (autoextend maximum), the real "how full can it get" number
- BIGFILE column (YES / NO)
- WARN / CRIT thresholds (`--warn`, `--crit`), `--alerts` for problem rows only
- Mounted standbys report the FRA only
- Return code 2 when a CRIT row exists

**Usage**

```text
dbspace [--warn PCT] [--crit PCT] [--alerts] [--no-fra] [--no-temp] [--db REGEX]
        [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Tablespace, TEMP, UNDO and FRA usage for every container (autoextend-aware)**

```text
$ dbspace
  +-----------+-------------+----------------+-------------+-----------+-----------+------------+-----------+------------+---------------------+
  |  SID      |  CONTAINER  |  TABLESPACE    |  TYPE       |  BIGFILE  |  USED_GB  |  ALLOC_GB  |  MAX_GB   |  PCT_USED  |  STATUS             |
  +-----------+-------------+----------------+-------------+-----------+-----------+------------+-----------+------------+---------------------+
  |  AIDEV    |  AIPDB1     |  USERS         |  PERMANENT  |  NO       |  40.00    |  42.00     |  64.00    |  62.5      |  OK                 |
  |  AIDEV    |  CDB$ROOT   |  SYSTEM        |  PERMANENT  |  NO       |  1.30     |  1.40      |  32.00    |  4.1       |  OK                 |
  |  CRMSTBY  |  -          |  FRA:+RECO     |  FRA        |  -        |  188.00   |  400.00    |  400.00   |  47.0      |  OK                 |
  |  CRMSTBY  |  -          |  (dictionary)  |  -          |  -        |  -        |  -         |  -        |  -         |  SKIPPED (MOUNTED)  |
  |  FINPRD   |  -          |  FRA:+RECO     |  FRA        |  -        |  412.40   |  500.00    |  500.00   |  82.5      |  OK                 |
  |  FINPRD   |  CDB$ROOT   |  SYSAUX        |  PERMANENT  |  NO       |  3.10     |  3.50      |  32.00    |  9.7       |  OK                 |
  |  FINPRD   |  CDB$ROOT   |  SYSTEM        |  PERMANENT  |  NO       |  1.42     |  1.50      |  32.00    |  4.4       |  OK                 |
  |  FINPRD   |  CDB$ROOT   |  UNDOTBS1      |  UNDO       |  NO       |  0.80     |  4.00      |  32.00    |  2.5       |  OK                 |
  |  FINPRD   |  CDB$ROOT   |  TEMP          |  TEMPORARY  |  NO       |  0.10     |  2.00      |  32.00    |  0.3       |  OK                 |
  |  FINPRD   |  FINPDB1    |  FIN_DATA      |  PERMANENT  |  YES      |  1210.00  |  1240.00   |  1280.00  |  94.5      |  WARN               |
  |  FINPRD   |  FINPDB1    |  FIN_INDEX     |  PERMANENT  |  NO       |  255.10   |  260.00    |  288.00   |  88.6      |  WARN               |
  |  FINPRD   |  FINPDB1    |  TEMP          |  TEMPORARY  |  NO       |  12.40    |  16.00     |  32.00    |  38.8      |  OK                 |
  |  FINPRD   |  FINPDB1    |  USERS         |  PERMANENT  |  NO       |  0.20     |  0.50      |  32.00    |  0.6       |  OK                 |
  |  FINPRD   |  FINPDB2    |  FIN_ARCH      |  PERMANENT  |  YES      |  190.00   |  200.00    |  1024.00  |  18.6      |  OK                 |
  |  HRPRD    |  -          |  HR_DATA       |  PERMANENT  |  NO       |  260.30   |  270.00    |  320.00   |  81.3      |  OK                 |
  |  HRPRD    |  -          |  FRA:+RECO     |  FRA        |  -        |  61.20    |  200.00    |  200.00   |  30.6      |  OK                 |
  |  HRPRD    |  -          |  SYSAUX        |  PERMANENT  |  NO       |  2.40     |  2.60      |  32.00    |  7.5       |  OK                 |
  |  HRPRD    |  -          |  SYSTEM        |  PERMANENT  |  NO       |  1.10     |  1.20      |  32.00    |  3.4       |  OK                 |
  |  HRPRD    |  -          |  TEMP          |  TEMPORARY  |  NO       |  0.50     |  8.00      |  32.00    |  1.6       |  OK                 |
  +-----------+-------------+----------------+-------------+-----------+-----------+------------+-----------+------------+---------------------+
```

**Only WARN / CRIT rows**

```text
$ dbspace --alerts
  +----------+-------------+--------------+-------------+-----------+-----------+------------+-----------+------------+----------+
  |  SID     |  CONTAINER  |  TABLESPACE  |  TYPE       |  BIGFILE  |  USED_GB  |  ALLOC_GB  |  MAX_GB   |  PCT_USED  |  STATUS  |
  +----------+-------------+--------------+-------------+-----------+-----------+------------+-----------+------------+----------+
  |  FINPRD  |  FINPDB1    |  FIN_DATA    |  PERMANENT  |  YES      |  1210.00  |  1240.00   |  1280.00  |  94.5      |  WARN    |
  |  FINPRD  |  FINPDB1    |  FIN_INDEX   |  PERMANENT  |  NO       |  255.10   |  260.00    |  288.00   |  88.6      |  WARN    |
  +----------+-------------+--------------+-------------+-----------+-----------+------------+-----------+------------+----------+
```

**Custom thresholds, one database, no FRA row, CSV**

```text
$ dbspace --warn 80 --crit 90 --no-fra --db HRPRD --csv
SID,CONTAINER,TABLESPACE,TYPE,BIGFILE,USED_GB,ALLOC_GB,MAX_GB,PCT_USED,STATUS
HRPRD,-,HR_DATA,PERMANENT,NO,260.30,270.00,320.00,81.3,WARN
HRPRD,-,SYSAUX,PERMANENT,NO,2.40,2.60,32.00,7.5,OK
HRPRD,-,SYSTEM,PERMANENT,NO,1.10,1.20,32.00,3.4,OK
HRPRD,-,TEMP,TEMPORARY,NO,0.50,8.00,32.00,1.6,OK
```

**Bigfile tablespaces only, without the header**

```text
$ dbspace --grep '[|]YES[|]' --no-header
  +----------+-------------+--------------+-------------+-----------+-----------+------------+-----------+------------+----------+
  |  FINPRD  |  FINPDB1    |  FIN_DATA    |  PERMANENT  |  YES      |  1210.00  |  1240.00   |  1280.00  |  94.5      |  WARN    |
  |  FINPRD  |  FINPDB2    |  FIN_ARCH    |  PERMANENT  |  YES      |  190.00   |  200.00    |  1024.00  |  18.6      |  OK      |
  +----------+-------------+--------------+-------------+-----------+-----------+------------+-----------+------------+----------+
```

<details>
<summary>Full <code>dbspace --help</code></summary>

```text
Usage: dbspace [--warn PCT] [--crit PCT] [--alerts] [--no-fra] [--no-temp] [--db REGEX]
               [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Space usage for every running database, every OPEN container (CDB root + PDBs).

Rows:
  PERMANENT  used = allocated - free
  UNDO       used = ACTIVE + UNEXPIRED undo extents (EXPIRED space is reusable)
  TEMPORARY  used = segments in use right now (v$tempseg_usage)
  FRA        used = space_used - space_reclaimable (v$recovery_file_dest)

BIGFILE is YES for bigfile tablespaces (one datafile up to 32 TB with 8K blocks) and NO
for regular (smallfile) tablespaces; '-' for the FRA row.

PCT_USED is relative to MAX_GB: the autoextend maximum (or the allocated size
for files without autoextend). This is the real "how full can it get" number.

Options:
  --warn PCT     WARN threshold (default: 85)
  --crit PCT     CRIT threshold (default: 95)
  --alerts       Only show rows that are WARN or CRIT
  --no-fra       Skip the FRA row
  --no-temp      Skip TEMPORARY tablespaces
  --db REGEX     Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Notes:
  - MOUNTED standbys only report the FRA (dictionary views need an OPEN database).
  - Only OPEN PDBs are reported (CDB_* views).

Return code: 0 = all OK/WARN, 1 = error, 2 = at least one CRIT

Examples:
  dbspace
  dbspace --alerts
  dbspace --db PRD --grep -v TEMPORARY
  dbspace --warn 80 --crit 90 --csv
  dbspace --grep '[|]YES[|]'            (bigfile tablespaces only)
```

</details>

[Back to the function list](#function-reference)

### lsasm

ASM diskgroup usage including the space that is really usable after mirroring, or the list of ASM disks.

**Features**

- USABLE_FREE_GB = `USABLE_FILE_MB` (space for new files while still able to restore redundancy)
- PCT_USED based on usable space; CRIT when usable free space is negative
- WARN when a disk is offline or the diskgroup is not mounted
- `--disks` lists path, state, mode, header status, failgroup and size of every disk
- Connects to the local ASM instance as SYSASM (falls back to SYSDBA)

**Usage**

```text
lsasm [--disks] [--warn PCT] [--crit PCT] [--grep PATTERN] [--grep-v PATTERN]
      [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**ASM diskgroups with raw and usable (after mirroring) space**

```text
$ lsasm
  +-------------+-----------+----------+------------+-----------+-------------------+------------------+------------+-----------+----------+
  |  DISKGROUP  |  STATE    |  TYPE    |  TOTAL_GB  |  FREE_GB  |  USABLE_TOTAL_GB  |  USABLE_FREE_GB  |  PCT_USED  |  OFFLINE  |  STATUS  |
  +-------------+-----------+----------+------------+-----------+-------------------+------------------+------------+-----------+----------+
  |  DATA       |  MOUNTED  |  NORMAL  |  2048.00   |  500.00   |  896.00           |  122.00          |  86.4      |  0        |  WARN    |
  |  RECO       |  MOUNTED  |  NORMAL  |  2048.00   |  1224.00  |  896.00           |  484.00          |  46.0      |  0        |  OK      |
  |  OCR        |  MOUNTED  |  EXTERN  |  30.00     |  28.71    |  30.00            |  28.71           |  4.3       |  0        |  OK      |
  +-------------+-----------+----------+------------+-----------+-------------------+------------------+------------+-----------+----------+
```

**ASM disks instead of diskgroups**

```text
$ lsasm --disks
  +-------------+-------------+--------------------------------+----------+----------+-------------+-------------+------------+-----------+
  |  DISKGROUP  |  DISK       |  PATH                          |  STATE   |  MODE    |  HEADER     |  FAILGROUP  |  TOTAL_GB  |  FREE_GB  |
  +-------------+-------------+--------------------------------+----------+----------+-------------+-------------+------------+-----------+
  |  DATA       |  DATA_0000  |  /dev/oracleasm/disks/DATA01   |  NORMAL  |  ONLINE  |  MEMBER     |  FG1        |  1024.00   |  201.50   |
  |  DATA       |  DATA_0001  |  /dev/oracleasm/disks/DATA02   |  NORMAL  |  ONLINE  |  MEMBER     |  FG2        |  1024.00   |  201.50   |
  |  RECO       |  RECO_0000  |  /dev/oracleasm/disks/RECO01   |  NORMAL  |  ONLINE  |  MEMBER     |  FG1        |  1024.00   |  612.00   |
  |  RECO       |  RECO_0001  |  /dev/oracleasm/disks/RECO02   |  NORMAL  |  ONLINE  |  MEMBER     |  FG2        |  1024.00   |  612.00   |
  |  -          |  -          |  /dev/oracleasm/disks/SPARE01  |  NORMAL  |  ONLINE  |  CANDIDATE  |  -          |  1024.00   |  1024.00  |
  +-------------+-------------+--------------------------------+----------+----------+-------------+-------------+------------+-----------+
```

**Custom thresholds, hide the OCR diskgroup**

```text
$ lsasm --warn 70 --crit 85 --grep -v OCR
  +-------------+-----------+----------+------------+-----------+-------------------+------------------+------------+-----------+----------+
  |  DISKGROUP  |  STATE    |  TYPE    |  TOTAL_GB  |  FREE_GB  |  USABLE_TOTAL_GB  |  USABLE_FREE_GB  |  PCT_USED  |  OFFLINE  |  STATUS  |
  +-------------+-----------+----------+------------+-----------+-------------------+------------------+------------+-----------+----------+
  |  DATA       |  MOUNTED  |  NORMAL  |  2048.00   |  500.00   |  896.00           |  122.00          |  86.4      |  0        |  CRIT    |
  |  RECO       |  MOUNTED  |  NORMAL  |  2048.00   |  1224.00  |  896.00           |  484.00          |  46.0      |  0        |  OK      |
  +-------------+-----------+----------+------------+-----------+-------------------+------------------+------------+-----------+----------+
```

<details>
<summary>Full <code>lsasm --help</code></summary>

```text
Usage: lsasm [--disks] [--warn PCT] [--crit PCT] [--grep PATTERN] [--grep-v PATTERN]
             [--csv|--json|--raw] [--no-header] [--no-color]

ASM diskgroup usage from the local ASM instance (v$asm_diskgroup).

Columns:
  TOTAL_GB / FREE_GB        Raw capacity (all mirror copies counted)
  USABLE_TOTAL_GB           (TOTAL - REQUIRED_MIRROR_FREE) / redundancy factor
  USABLE_FREE_GB            USABLE_FILE_MB: space you can really use for new files
                            while still being able to restore redundancy after a disk failure
  PCT_USED                  1 - USABLE_FREE / USABLE_TOTAL
  OFFLINE                   Number of offline disks
  STATUS                    OK / WARN / CRIT by PCT_USED; CRIT if USABLE_FREE < 0;
                            WARN if any disk is offline or the group is not MOUNTED

  Redundancy factor: EXTERN = 1, NORMAL/FLEX/EXTEND = 2, HIGH = 3

Options:
  --disks          List ASM disks instead (path, state, mode, header status, size)
  --warn PCT       WARN threshold (default: 80)
  --crit PCT       CRIT threshold (default: 90)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Notes:
  - Connects to the local ASM instance (+ASM / +ASM1 ...) from the Grid home as SYSASM,
    falling back to SYSDBA. The OS user must be in the ASM admin/dba group.

Return code: 0 = all OK/WARN, 1 = error, 2 = at least one CRIT

Examples:
  lsasm
  lsasm --disks
  lsasm --grep DATA --csv
```

</details>

[Back to the function list](#function-reference)

### dbbkp

Latest RMAN backups recorded in each database's control file, with an age-based status.

**Features**

- LAST_FULL (full or level 0), LAST_INCR (level 1+), LAST_ARCH and their age in hours
- Status of the last RMAN job and the number of failed jobs in the last 24 hours
- CRIT when no DB backup exists or it is older than `--db-hours` (default 26); WARN for old archivelog backups or failed jobs
- Return code 2 when a CRIT row exists

**Usage**

```text
dbbkp [--db-hours N] [--arch-hours N] [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
      [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Latest RMAN backups of every database with an age-based status**

```text
$ dbbkp
  +-----------+--------------------+----------------+--------------------+--------------------+--------------------+------------+--------------+-------------+--------------+-----------------------------------+
  |  SID      |  ROLE              |  LOG_MODE      |  LAST_FULL         |  LAST_INCR         |  LAST_ARCH         |  DB_AGE_H  |  ARCH_AGE_H  |  LAST_JOB   |  FAILED_24H  |  STATUS                           |
  +-----------+--------------------+----------------+--------------------+--------------------+--------------------+------------+--------------+-------------+--------------+-----------------------------------+
  |  AIDEV    |  PRIMARY           |  NOARCHIVELOG  |  -                 |  -                 |  -                 |  -         |  -           |  -          |  0           |  CRIT (no DB backup found)        |
  |  CRMSTBY  |  PHYSICAL STANDBY  |  ARCHIVELOG    |  2026-11-24 04:31  |  2026-11-24 20:31  |  2026-11-25 05:51  |  10.0      |  0.7         |  COMPLETED  |  0           |  OK                               |
  |  FINPRD   |  PRIMARY           |  ARCHIVELOG    |  2026-11-20 03:31  |  2026-11-24 21:31  |  2026-11-25 05:11  |  9.0       |  1.3         |  COMPLETED  |  0           |  OK                               |
  |  HRPRD    |  PRIMARY           |  ARCHIVELOG    |  2026-11-22 02:31  |  -                 |  2026-11-24 23:31  |  76.0      |  7.0         |  FAILED     |  2           |  CRIT (DB backup older than 26h)  |
  +-----------+--------------------+----------------+--------------------+--------------------+--------------------+------------+--------------+-------------+--------------+-----------------------------------+
```

**Weekly full backups, stricter archivelog backups**

```text
$ dbbkp --db-hours 170 --arch-hours 2 --grep -v AIDEV
  +-----------+--------------------+--------------+--------------------+--------------------+--------------------+------------+--------------+-------------+--------------+------------------------------------------+
  |  SID      |  ROLE              |  LOG_MODE    |  LAST_FULL         |  LAST_INCR         |  LAST_ARCH         |  DB_AGE_H  |  ARCH_AGE_H  |  LAST_JOB   |  FAILED_24H  |  STATUS                                  |
  +-----------+--------------------+--------------+--------------------+--------------------+--------------------+------------+--------------+-------------+--------------+------------------------------------------+
  |  CRMSTBY  |  PHYSICAL STANDBY  |  ARCHIVELOG  |  2026-11-24 04:31  |  2026-11-24 20:31  |  2026-11-25 05:51  |  10.0      |  0.7         |  COMPLETED  |  0           |  OK                                      |
  |  FINPRD   |  PRIMARY           |  ARCHIVELOG  |  2026-11-20 03:31  |  2026-11-24 21:31  |  2026-11-25 05:11  |  9.0       |  1.3         |  COMPLETED  |  0           |  OK                                      |
  |  HRPRD    |  PRIMARY           |  ARCHIVELOG  |  2026-11-22 02:31  |  -                 |  2026-11-24 23:31  |  76.0      |  7.0         |  FAILED     |  2           |  WARN (archivelog backup older than 2h)  |
  +-----------+--------------------+--------------+--------------------+--------------------+--------------------+------------+--------------+-------------+--------------+------------------------------------------+
```

**JSON for one database**

```text
$ dbbkp --json --db FINPRD
[
  {"SID":"FINPRD","ROLE":"PRIMARY","LOG_MODE":"ARCHIVELOG","LAST_FULL":"2026-11-20 03:31","LAST_INCR":"2026-11-24 21:31","LAST_ARCH":"2026-11-25 05:11","DB_AGE_H":"9.0","ARCH_AGE_H":"1.3","LAST_JOB":"COMPLETED","FAILED_24H":"0","STATUS":"OK"}
]
```

<details>
<summary>Full <code>dbbkp --help</code></summary>

```text
Usage: dbbkp [--db-hours N] [--arch-hours N] [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
             [--csv|--json|--raw] [--no-header] [--no-color]

Latest RMAN backups recorded in the control file of every running database.

Columns:
  LAST_FULL       Latest FULL or INCREMENTAL LEVEL 0 backup set
  LAST_INCR       Latest INCREMENTAL LEVEL 1+ backup set
  LAST_ARCH       Latest ARCHIVELOG backup set
  DB_AGE_H        Hours since the newest of LAST_FULL / LAST_INCR
  ARCH_AGE_H      Hours since LAST_ARCH
  LAST_JOB        Status of the most recent RMAN job (v$rman_backup_job_details)
  FAILED_24H      Number of FAILED / COMPLETED WITH ERRORS jobs in the last 24 hours
  STATUS          CRIT  - no DB backup, or DB_AGE_H > --db-hours
                  WARN  - ARCHIVELOG mode and ARCH_AGE_H > --arch-hours (or none),
                          or failed RMAN jobs in the last 24 hours
                  OK    - otherwise

Options:
  --db-hours N     Maximum age of the latest DB backup (default: 26)
  --arch-hours N   Maximum age of the latest archivelog backup (default: 4)
  --db REGEX       Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Notes:
  - Backups taken on a standby are recorded in the standby control file, so the
    primary may show CRIT when backups only run on the standby (and vice versa).
  - Backups not made by RMAN (storage snapshots) are not visible here.

Return code: 0 = all OK/WARN, 1 = error, 2 = at least one CRIT

Examples:
  dbbkp
  dbbkp --db-hours 170          (weekly full backups)
  dbbkp --grep CRIT
```

</details>

[Back to the function list](#function-reference)

### dbarch

Archive log generation per database (or per hour) and FRA usage.

**Features**

- Each archived log is counted once, even with several archive destinations
- Summary: switches, GB, average GB/hour, the peak hour and FRA usage with WARN / CRIT
- `--hourly`: one row per hour with a `#` bar scaled to the busiest hour
- `--hours N` look-back window (up to 31 days)

**Usage**

```text
dbarch [--hours N] [--hourly] [--warn PCT] [--crit PCT] [--db REGEX]
       [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Archive log generation per database over the last 24 hours, with FRA usage**

```text
$ dbarch
  +-----------+----------------+------------+----------+-------------------+--------------------+-----------+-----------+----------+
  |  SID      |  LOG_MODE      |  SWITCHES  |  GB      |  AVG_GB_PER_HOUR  |  PEAK_HOUR         |  PEAK_GB  |  FRA_PCT  |  STATUS  |
  +-----------+----------------+------------+----------+-------------------+--------------------+-----------+-----------+----------+
  |  AIDEV    |  NOARCHIVELOG  |  0         |  0.00    |  0.00             |  -                 |  -        |  no FRA   |  OK      |
  |  CRMSTBY  |  ARCHIVELOG    |  58        |  58.00   |  2.42             |  2026-11-24 17:00  |  6.00     |  47.0     |  OK      |
  |  FINPRD   |  ARCHIVELOG    |  125       |  122.50  |  5.10             |  2026-11-24 17:00  |  17.64    |  82.5     |  WARN    |
  |  HRPRD    |  ARCHIVELOG    |  26        |  13.00   |  0.54             |  2026-11-24 13:00  |  1.00     |  30.6     |  OK      |
  +-----------+----------------+------------+----------+-------------------+--------------------+-----------+-----------+----------+
```

**Hour-by-hour heatmap for one database**

```text
$ dbarch --hourly --db FINPRD
  +----------+--------------------+------------+---------+--------------------------------------------+
  |  SID     |  HOUR              |  SWITCHES  |  GB     |  BAR                                       |
  +----------+--------------------+------------+---------+--------------------------------------------+
  |  FINPRD  |  2026-11-24 07:00  |  4         |  3.92   |  #########                                 |
  |  FINPRD  |  2026-11-24 08:00  |  4         |  3.92   |  #########                                 |
  |  FINPRD  |  2026-11-24 09:00  |  5         |  4.90   |  ###########                               |
  |  FINPRD  |  2026-11-24 10:00  |  3         |  2.94   |  #######                                   |
  |  FINPRD  |  2026-11-24 11:00  |  2         |  1.96   |  ####                                      |
  |  FINPRD  |  2026-11-24 12:00  |  2         |  1.96   |  ####                                      |
  |  FINPRD  |  2026-11-24 13:00  |  2         |  1.96   |  ####                                      |
  |  FINPRD  |  2026-11-24 14:00  |  3         |  2.94   |  #######                                   |
  |  FINPRD  |  2026-11-24 15:00  |  6         |  5.88   |  #############                             |
  |  FINPRD  |  2026-11-24 16:00  |  14        |  13.72  |  ###############################           |
  |  FINPRD  |  2026-11-24 17:00  |  18        |  17.64  |  ########################################  |
  |  FINPRD  |  2026-11-24 18:00  |  9         |  8.82   |  ####################                      |
  |  FINPRD  |  2026-11-24 19:00  |  5         |  4.90   |  ###########                               |
  |  FINPRD  |  2026-11-24 20:00  |  4         |  3.92   |  #########                                 |
  |  FINPRD  |  2026-11-24 21:00  |  4         |  3.92   |  #########                                 |
  |  FINPRD  |  2026-11-24 22:00  |  5         |  4.90   |  ###########                               |
  |  FINPRD  |  2026-11-24 23:00  |  6         |  5.88   |  #############                             |
  |  FINPRD  |  2026-11-25 00:00  |  4         |  3.92   |  #########                                 |
  |  FINPRD  |  2026-11-25 01:00  |  3         |  2.94   |  #######                                   |
  |  FINPRD  |  2026-11-25 02:00  |  3         |  2.94   |  #######                                   |
  |  FINPRD  |  2026-11-25 03:00  |  4         |  3.92   |  #########                                 |
  |  FINPRD  |  2026-11-25 04:00  |  6         |  5.88   |  #############                             |
  |  FINPRD  |  2026-11-25 05:00  |  5         |  4.90   |  ###########                               |
  |  FINPRD  |  2026-11-25 06:00  |  4         |  3.92   |  #########                                 |
  +----------+--------------------+------------+---------+--------------------------------------------+
```

**Last 7 days, CSV**

```text
$ dbarch --hours 168 --csv
SID,LOG_MODE,SWITCHES,GB,AVG_GB_PER_HOUR,PEAK_HOUR,PEAK_GB,FRA_PCT,STATUS
AIDEV,NOARCHIVELOG,0,0.00,0.00,-,-,no FRA,OK
CRMSTBY,ARCHIVELOG,58,58.00,0.35,2026-11-24 17:00,6.00,47.0,OK
FINPRD,ARCHIVELOG,125,122.50,0.73,2026-11-24 17:00,17.64,82.5,WARN
HRPRD,ARCHIVELOG,26,13.00,0.08,2026-11-24 13:00,1.00,30.6,OK
```

<details>
<summary>Full <code>dbarch --help</code></summary>

```text
Usage: dbarch [--hours N] [--hourly] [--warn PCT] [--crit PCT] [--db REGEX]
              [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Archive log generation from v$archived_log (each log counted once, even with
several archive destinations) and FRA usage.

Default (one row per database):
  SID, LOG_MODE, SWITCHES, GB, AVG_GB_PER_HOUR, PEAK_HOUR, PEAK_GB, FRA_PCT, STATUS
  STATUS is based on FRA_PCT (--warn / --crit).

--hourly (one row per database and hour, table view adds a bar chart):
  SID, HOUR, SWITCHES, GB, BAR   ('#' scaled to the busiest hour of that database)

Options:
  --hours N      Look-back window in hours (default: 24, max: 744)
  --hourly       Per-hour breakdown
  --warn PCT     FRA WARN threshold (default: 80)
  --crit PCT     FRA CRIT threshold (default: 90)
  --db REGEX     Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Examples:
  dbarch
  dbarch --hourly --db PRD
  dbarch --hours 168 --csv
```

</details>

[Back to the function list](#function-reference)

### dbredo

Online and standby redo log configuration and log switch rate per database.

**Features**

- Groups, size, minimum members per group, standby redo log groups and size, switches in 24h and the busiest hour
- WARN for more than `--max-switches` per hour (default 12), single-member groups, too few or too small standby logs, INVALID/STALE members
- `--detail` lists every group and member

**Usage**

```text
dbredo [--detail] [--max-switches N] [--db REGEX]
       [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Redo groups, members, standby redo logs and switch rate per database**

```text
$ dbredo
  +-----------+----------+----------+-----------+---------------+--------------+---------------+----------------+----------------+----------------------------------+
  |  DB       |  THREAD  |  GROUPS  |  SIZE_MB  |  MIN_MEMBERS  |  SRL_GROUPS  |  SRL_SIZE_MB  |  SWITCHES_24H  |  MAX_PER_HOUR  |  STATUS                          |
  +-----------+----------+----------+-----------+---------------+--------------+---------------+----------------+----------------+----------------------------------+
  |  AIDEV    |  1       |  3       |  200      |  1            |  0           |  -            |  4             |  1             |  WARN (single-member group(s))   |
  |  CRMSTBY  |  1       |  3       |  1024     |  2            |  2           |  1024         |  46            |  6             |  WARN (too few standby logs)     |
  |  FINPRD   |  1       |  3       |  2048     |  2            |  4           |  2048         |  103           |  18            |  WARN (18 switches in one hour)  |
  |  HRPRD    |  1       |  3       |  512      |  1            |  0           |  -            |  28            |  2             |  WARN (single-member group(s))   |
  +-----------+----------+----------+-----------+---------------+--------------+---------------+----------------+----------------+----------------------------------+
```

**One row per group and member**

```text
$ dbredo --detail --db HRPRD
  +---------+----------+---------+----------+-----------+------------+------------+---------------------------------------+-----------------+
  |  DB     |  THREAD  |  GROUP  |  TYPE    |  SIZE_MB  |  STATUS    |  ARCHIVED  |  MEMBER                               |  MEMBER_STATUS  |
  +---------+----------+---------+----------+-----------+------------+------------+---------------------------------------+-----------------+
  |  HRPRD  |  1       |  1      |  ONLINE  |  512      |  CURRENT   |  YES       |  +DATA/HRPRD/ONLINELOG/group_1.270.1  |  OK             |
  |  HRPRD  |  1       |  2      |  ONLINE  |  512      |  INACTIVE  |  YES       |  +DATA/HRPRD/ONLINELOG/group_2.270.1  |  OK             |
  |  HRPRD  |  1       |  3      |  ONLINE  |  512      |  INACTIVE  |  YES       |  +DATA/HRPRD/ONLINELOG/group_3.270.1  |  OK             |
  +---------+----------+---------+----------+-----------+------------+------------+---------------------------------------+-----------------+
```

**Raise the log switch threshold**

```text
$ dbredo --max-switches 20 --db FINPRD
  +----------+----------+----------+-----------+---------------+--------------+---------------+----------------+----------------+----------+
  |  DB      |  THREAD  |  GROUPS  |  SIZE_MB  |  MIN_MEMBERS  |  SRL_GROUPS  |  SRL_SIZE_MB  |  SWITCHES_24H  |  MAX_PER_HOUR  |  STATUS  |
  +----------+----------+----------+-----------+---------------+--------------+---------------+----------------+----------------+----------+
  |  FINPRD  |  1       |  3       |  2048     |  2            |  4           |  2048         |  103           |  18            |  OK      |
  +----------+----------+----------+-----------+---------------+--------------+---------------+----------------+----------------+----------+
```

<details>
<summary>Full <code>dbredo --help</code></summary>

```text
Usage: dbredo [--detail] [--max-switches N] [--db REGEX]
              [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Summary (default) - one row per database and redo thread:
  DB, THREAD, GROUPS, SIZE_MB, MIN_MEMBERS, SRL_GROUPS, SRL_SIZE_MB, SWITCHES_24H,
  MAX_PER_HOUR, STATUS
  STATUS WARN when:
    - MAX_PER_HOUR > --max-switches (default 12, i.e. a switch every 5 minutes or more
      often; Oracle's common guideline is about 3-4 switches per hour at peak)
    - a group has fewer than 2 members (no multiplexing)
    - standby redo logs exist but are fewer than GROUPS + 1 per thread, or smaller than
      the online logs (Data Guard best practice)
    - any member is INVALID / STALE (see --detail)

--detail - one row per log group and member:
  DB, THREAD, GROUP, TYPE (ONLINE/STANDBY), SIZE_MB, STATUS, ARCHIVED, MEMBER, MEMBER_STATUS

Options:
  --detail          Per group / member rows
  --max-switches N  WARN threshold for the busiest hour in the last 24h (default: 12)
  --db REGEX        Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Examples:
  dbredo
  dbredo --detail --db PRD
```

</details>

[Back to the function list](#function-reference)

### dbstats

Optimizer statistics health: the automatic stats job and stale or missing table statistics per schema and container.

**Features**

- AUTO STATS JOB row per container: CRIT when disabled, WARN without a successful run in `--job-days`
- One row per non Oracle-maintained schema with TOTAL / STALE / MISSING / LOCKED tables
- `--flush` refreshes the DML monitoring info first (opt-in, it is a write)
- Only schemas with problems are shown unless `--all`

**Usage**

```text
dbstats [--all] [--flush] [--job-days N] [--db REGEX]
        [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Automatic stats job status and schemas with stale or missing statistics**

```text
$ dbstats
  +-----------+------------+-------------------+---------+---------+-----------+----------+--------------------+---------------------+
  |  DB       |  CON       |  ITEM             |  TOTAL  |  STALE  |  MISSING  |  LOCKED  |  LAST_RUN          |  STATUS             |
  +-----------+------------+-------------------+---------+---------+-----------+----------+--------------------+---------------------+
  |  AIDEV    |  CDB$ROOT  |  AUTO STATS JOB   |  -      |  -      |  -        |  -       |  2026-11-24 23:31  |  OK                 |
  |  AIDEV    |  AIPDB1    |  AUTO STATS JOB   |  -      |  -      |  -        |  -       |  2026-11-24 23:31  |  OK                 |
  |  CRMSTBY  |  -         |  -                |  -      |  -      |  -        |  -       |  -                 |  SKIPPED (MOUNTED)  |
  |  FINPRD   |  CDB$ROOT  |  AUTO STATS JOB   |  -      |  -      |  -        |  -       |  2026-11-24 23:31  |  OK                 |
  |  FINPRD   |  FINPDB1   |  AUTO STATS JOB   |  -      |  -      |  -        |  -       |  2026-11-24 23:31  |  OK                 |
  |  FINPRD   |  FINPDB2   |  AUTO STATS JOB   |  -      |  -      |  -        |  -       |  2026-11-24 23:31  |  OK                 |
  |  FINPRD   |  FINPDB1   |  SCHEMA FIN       |  412    |  37     |  5        |  0       |  2026-11-24 23:31  |  WARN               |
  |  FINPRD   |  FINPDB2   |  SCHEMA REPORTER  |  21     |  4      |  0        |  0       |  2026-11-24 23:31  |  WARN               |
  |  HRPRD    |  -         |  AUTO STATS JOB   |  -      |  -      |  -        |  -       |  2026-11-24 23:31  |  CRIT (disabled)    |
  |  HRPRD    |  -         |  SCHEMA HR        |  140    |  12     |  1        |  0       |  2026-11-24 06:31  |  WARN               |
  +-----------+------------+-------------------+---------+---------+-----------+----------+--------------------+---------------------+
```

**Every schema, also the healthy ones**

```text
$ dbstats --all --db HRPRD
  +---------+-------+------------------+---------+---------+-----------+----------+--------------------+-------------------+
  |  DB     |  CON  |  ITEM            |  TOTAL  |  STALE  |  MISSING  |  LOCKED  |  LAST_RUN          |  STATUS           |
  +---------+-------+------------------+---------+---------+-----------+----------+--------------------+-------------------+
  |  HRPRD  |  -    |  AUTO STATS JOB  |  -      |  -      |  -        |  -       |  2026-11-24 23:31  |  CRIT (disabled)  |
  |  HRPRD  |  -    |  SCHEMA HR       |  140    |  12     |  1        |  0       |  2026-11-24 06:31  |  WARN             |
  +---------+-------+------------------+---------+---------+-----------+----------+--------------------+-------------------+
```

<details>
<summary>Full <code>dbstats --help</code></summary>

```text
Usage: dbstats [--all] [--flush] [--job-days N] [--db REGEX]
               [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Optimizer statistics health for every running database and every OPEN container.

Rows:
  AUTO STATS JOB   'auto optimizer stats collection' autotask: ENABLED/DISABLED and the
                   last SUCCEEDED run (DBA_AUTOTASK_CLIENT / DBA_AUTOTASK_JOB_HISTORY)
                   STATUS CRIT if disabled, WARN if no successful run in --job-days days
  SCHEMA <owner>   tables of non Oracle-maintained schemas (DBA_TAB_STATISTICS):
                   TOTAL, STALE (STALE_STATS = YES), MISSING (never analyzed), LOCKED
                   STATUS WARN if any table is stale or missing statistics
  By default only schemas with stale or missing statistics are listed (--all: every schema).

Columns: DB, CON, ITEM, TOTAL, STALE, MISSING, LOCKED, LAST_RUN, STATUS

Options:
  --all          List every schema, also the healthy ones
  --flush        Run DBMS_STATS.FLUSH_DATABASE_MONITORING_INFO first, so STALE_STATS
                 reflects the latest DML (otherwise up to ~15 minutes old). Harmless,
                 but it is a write - therefore opt-in.
  --job-days N   WARN when the last successful auto stats run is older (default: 2)
  --db REGEX     Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Notes:
  - Dictionary and fixed-object statistics are checked by dbprecheck (stats_dict / stats_fixed).
  - MOUNTED standbys are skipped.

Examples:
  dbstats
  dbstats --all --db PRD
  dbstats --flush --grep APP
```

</details>

[Back to the function list](#function-reference)

### dbtde

Transparent Data Encryption keystore status per container.

**Features**

- Keystore configuration (`wallet_root`, `tde_configuration`), location, status, wallet type, keystore mode, backup state
- Number of encrypted tablespaces per container
- CRIT when the keystore is closed while encrypted tablespaces exist; WARN for no master key, no backup or a password keystore (manual open after restart)

**Usage**

```text
dbtde [--db REGEX] [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**TDE keystore status per container**

```text
$ dbtde
  +-----------+------------+--------------------------------------------------------------------------+------------+--------------------------------------+-----------------+---------------+-----------------+-------------+----------+--------------------------------------------------------+
  |  DB       |  CON       |  KEYSTORE                                                                |  WRL_TYPE  |  LOCATION                            |  KS_STATUS      |  WALLET_TYPE  |  KEYSTORE_MODE  |  BACKED_UP  |  ENC_TS  |  STATUS                                                |
  +-----------+------------+--------------------------------------------------------------------------+------------+--------------------------------------+-----------------+---------------+-----------------+-------------+----------+--------------------------------------------------------+
  |  AIDEV    |  CDB$ROOT  |  /u01/app/oracle/admin/AIDEV/wallet_root / KEYSTORE_CONFIGURATION=FILE   |  FILE      |  -                                   |  NOT_AVAILABLE  |  UNKNOWN      |  NONE           |  UNDEFINED  |  0       |  -                                                     |
  |  CRMSTBY  |  CDB$ROOT  |  /u01/app/oracle/admin/CRMPRD/wallet_root / KEYSTORE_CONFIGURATION=FILE  |  FILE      |  -                                   |  CLOSED         |  UNKNOWN      |  NONE           |  UNDEFINED  |  0       |  -                                                     |
  |  CRMSTBY  |  CRMPDB1   |  /u01/app/oracle/admin/CRMPRD/wallet_root / KEYSTORE_CONFIGURATION=FILE  |  FILE      |  -                                   |  CLOSED         |  UNKNOWN      |  UNITED         |  UNDEFINED  |  3       |  CRIT (encrypted tablespaces, keystore CLOSED)         |
  |  FINPRD   |  CDB$ROOT  |  /u01/app/oracle/admin/FINPRD/wallet_root / KEYSTORE_CONFIGURATION=FILE  |  FILE      |  -                                   |  OPEN           |  AUTOLOGIN    |  NONE           |  YES        |  0       |  OK                                                    |
  |  FINPRD   |  FINPDB1   |  /u01/app/oracle/admin/FINPRD/wallet_root / KEYSTORE_CONFIGURATION=FILE  |  FILE      |  -                                   |  OPEN           |  AUTOLOGIN    |  UNITED         |  YES        |  4       |  OK                                                    |
  |  FINPRD   |  FINPDB2   |  /u01/app/oracle/admin/FINPRD/wallet_root / KEYSTORE_CONFIGURATION=FILE  |  FILE      |  -                                   |  OPEN           |  AUTOLOGIN    |  UNITED         |  NO         |  1       |  WARN (keystore not backed up)                         |
  |  HRPRD    |  -         |  - / -                                                                   |  FILE      |  /u01/app/oracle/admin/HRPRD/wallet  |  OPEN           |  PASSWORD     |  NONE           |  YES        |  2       |  WARN (password keystore - manual open after restart)  |
  +-----------+------------+--------------------------------------------------------------------------+------------+--------------------------------------+-----------------+---------------+-----------------+-------------+----------+--------------------------------------------------------+
```

**Only the containers that need attention**

```text
$ dbtde --grep 'CRIT|WARN' --csv
DB,CON,KEYSTORE,WRL_TYPE,LOCATION,KS_STATUS,WALLET_TYPE,KEYSTORE_MODE,BACKED_UP,ENC_TS,STATUS
CRMSTBY,CRMPDB1,/u01/app/oracle/admin/CRMPRD/wallet_root / KEYSTORE_CONFIGURATION=FILE,FILE,-,CLOSED,UNKNOWN,UNITED,UNDEFINED,3,"CRIT (encrypted tablespaces, keystore CLOSED)"
FINPRD,FINPDB2,/u01/app/oracle/admin/FINPRD/wallet_root / KEYSTORE_CONFIGURATION=FILE,FILE,-,OPEN,AUTOLOGIN,UNITED,NO,1,WARN (keystore not backed up)
HRPRD,-,- / -,FILE,/u01/app/oracle/admin/HRPRD/wallet,OPEN,PASSWORD,NONE,YES,2,WARN (password keystore - manual open after restart)
```

<details>
<summary>Full <code>dbtde --help</code></summary>

```text
Usage: dbtde [--db REGEX] [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Transparent Data Encryption keystore status (GV$ENCRYPTION_WALLET) per container.

Columns: DB, CON, KEYSTORE, WRL_TYPE, LOCATION, KS_STATUS, WALLET_TYPE, KEYSTORE_MODE,
         BACKED_UP, ENC_TS, STATUS
  KEYSTORE   wallet_root / tde_configuration parameters (or sqlnet.ora ENCRYPTION_WALLET_LOCATION)
  ENC_TS     number of encrypted tablespaces in the container
  STATUS     CRIT  keystore CLOSED / NOT_AVAILABLE while encrypted tablespaces exist
             WARN  OPEN_NO_MASTER_KEY, keystore not backed up, or PASSWORD wallet (instance
                   restart needs a manual ADMINISTER KEY MANAGEMENT ... OPEN)
             OK    open with a master key (or TDE not used: '-')

Options:
  --db REGEX     Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Notes:
  - Certificate expiry of the TDE wallet is not relevant (TDE keys do not expire);
    for TLS wallets use lscert.

Return code: 0 = no CRIT, 2 = at least one CRIT, 1 = error

Examples:
  dbtde
  dbtde --grep -v OK
```

</details>

[Back to the function list](#function-reference)

### dbgrowth

Tablespace growth from AWR history with a forecast of the days left until each tablespace is full.

**Features**

- Growth over `--days` (default 30) from `DBA_HIST_TBSPC_SPACE_USAGE`, GB per day and DAYS_TO_FULL against the autoextend maximum
- A TOTAL row per database
- WARN / CRIT on DAYS_TO_FULL (`--warn 90`, `--crit 30` days by default)
- Requires the Diagnostics Pack - databases without it are skipped unless `--force`

**Usage**

```text
dbgrowth [--days N] [--warn DAYS] [--crit DAYS] [--all] [--force] [--db REGEX]
         [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Growth over the last 30 days with a days-until-full forecast**

```text
$ dbgrowth
  +-----------+------------+--------------------+-----------+-----------+-------------+--------------+----------------+--------------------------------------------------------+
  |  DB       |  CON       |  TABLESPACE        |  USED_GB  |  MAX_GB   |  GROWTH_GB  |  GB_PER_DAY  |  DAYS_TO_FULL  |  STATUS                                                |
  +-----------+------------+--------------------+-----------+-----------+-------------+--------------+----------------+--------------------------------------------------------+
  |  AIDEV    |  AIPDB1    |  USERS             |  40.00    |  64.00    |  4.00       |  0.133       |  180           |  OK                                                    |
  |  AIDEV    |  -         |  TOTAL             |  40.00    |  64.00    |  4.00       |  0.133       |  180           |  OK                                                    |
  |  CRMSTBY  |  -         |  (no AWR history)  |  -        |  -        |  -          |  -           |  -             |  UNKNOWN                                               |
  |  FINPRD   |  FINPDB1   |  FIN_DATA          |  1210.00  |  1280.00  |  96.00      |  3.200       |  22            |  CRIT                                                  |
  |  FINPRD   |  FINPDB1   |  FIN_INDEX         |  255.10   |  288.00   |  14.20      |  0.473       |  70            |  WARN                                                  |
  |  FINPRD   |  FINPDB2   |  FIN_ARCH          |  190.00   |  1024.00  |  30.00      |  1.000       |  834           |  OK                                                    |
  |  FINPRD   |  CDB$ROOT  |  SYSAUX            |  3.10     |  32.00    |  0.20       |  0.007       |  4129          |  OK                                                    |
  |  FINPRD   |  -         |  TOTAL             |  1658.40  |  2656.00  |  140.40     |  4.680       |  213           |  OK                                                    |
  |  HRPRD    |  -         |  -                 |  -        |  -        |  -          |  -           |  -             |  SKIPPED (Diagnostics Pack not enabled - use --force)  |
  +-----------+------------+--------------------+-----------+-----------+-------------+--------------+----------------+--------------------------------------------------------+
```

**Also tablespaces that are not growing**

```text
$ dbgrowth --all --db FINPRD
  +----------+------------+--------------+-----------+-----------+-------------+--------------+----------------+----------+
  |  DB      |  CON       |  TABLESPACE  |  USED_GB  |  MAX_GB   |  GROWTH_GB  |  GB_PER_DAY  |  DAYS_TO_FULL  |  STATUS  |
  +----------+------------+--------------+-----------+-----------+-------------+--------------+----------------+----------+
  |  FINPRD  |  FINPDB1   |  FIN_DATA    |  1210.00  |  1280.00  |  96.00      |  3.200       |  22            |  CRIT    |
  |  FINPRD  |  FINPDB1   |  FIN_INDEX   |  255.10   |  288.00   |  14.20      |  0.473       |  70            |  WARN    |
  |  FINPRD  |  FINPDB2   |  FIN_ARCH    |  190.00   |  1024.00  |  30.00      |  1.000       |  834           |  OK      |
  |  FINPRD  |  CDB$ROOT  |  SYSAUX      |  3.10     |  32.00    |  0.20       |  0.007       |  4129          |  OK      |
  |  FINPRD  |  FINPDB1   |  USERS       |  0.20     |  32.00    |  0.00       |  0.000       |  -             |  OK      |
  |  FINPRD  |  -         |  TOTAL       |  1658.40  |  2656.00  |  140.40     |  4.680       |  213           |  OK      |
  +----------+------------+--------------+-----------+-----------+-------------+--------------+----------------+----------+
```

**90-day window, custom thresholds, totals only**

```text
$ dbgrowth --days 90 --warn 120 --crit 45 --grep TOTAL
  +----------+-------+--------------+-----------+-----------+-------------+--------------+----------------+----------+
  |  DB      |  CON  |  TABLESPACE  |  USED_GB  |  MAX_GB   |  GROWTH_GB  |  GB_PER_DAY  |  DAYS_TO_FULL  |  STATUS  |
  +----------+-------+--------------+-----------+-----------+-------------+--------------+----------------+----------+
  |  AIDEV   |  -    |  TOTAL       |  40.00    |  64.00    |  4.00       |  0.133       |  180           |  OK      |
  |  FINPRD  |  -    |  TOTAL       |  1658.40  |  2656.00  |  140.40     |  4.680       |  213           |  OK      |
  +----------+-------+--------------+-----------+-----------+-------------+--------------+----------------+----------+
```

<details>
<summary>Full <code>dbgrowth --help</code></summary>

```text
Usage: dbgrowth [--days N] [--warn DAYS] [--crit DAYS] [--all] [--force] [--db REGEX]
                [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Tablespace growth over the last N days from AWR (DBA_HIST_TBSPC_SPACE_USAGE) and a
forecast of the days left until each tablespace is full at the current growth rate.

Columns: DB, CON, TABLESPACE, USED_GB, MAX_GB, GROWTH_GB, GB_PER_DAY, DAYS_TO_FULL, STATUS
  MAX_GB         autoextend maximum (TABLESPACE_MAXSIZE)
  GROWTH_GB      used space now minus used space at the start of the window
  DAYS_TO_FULL   (MAX_GB - USED_GB) / GB_PER_DAY ('-' when not growing)
  STATUS         CRIT when DAYS_TO_FULL <= --crit, WARN when <= --warn, else OK
  A TOTAL row per database sums all tablespaces.

Options:
  --days N       History window in days (default: 30; limited by the AWR retention)
  --warn DAYS    WARN threshold for DAYS_TO_FULL (default: 90)
  --crit DAYS    CRIT threshold for DAYS_TO_FULL (default: 30)
  --all          Also list tablespaces that are not growing (hidden by default)
  --force        Run even when CONTROL_MANAGEMENT_PACK_ACCESS does not include DIAGNOSTIC
  --db REGEX     Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Notes:
  - Licensing: AWR history is part of the Oracle Diagnostics Pack.
  - In a CDB, PDB tablespaces appear when AWR snapshots include them (CDB-level
    snapshots capture tablespace usage for the open PDBs).
  - TEMP and UNDO are excluded (their usage is not growth).

Return code: 0 = all OK/WARN, 2 = at least one CRIT, 1 = error

Examples:
  dbgrowth
  dbgrowth --days 90 --all
  dbgrowth --grep TOTAL
```

</details>

[Back to the function list](#function-reference)

### dbalert

ORA- errors (or any pattern) from the alert log of every database within a time window.

**Features**

- Running and DOWN databases; the alert log is read backwards so only the window is processed
- Understands both alert log timestamp formats (12.2+ ISO and the older format)
- Summary per database and error code (count, first, last, sample) or `--detail` (one row per line)
- `--since 30m|2h|7d`, `--pattern REGEX`, `--max N`
- Return code 2 when errors are found

**Usage**

```text
dbalert [--since 24h] [--detail] [--pattern REGEX] [--max N] [--db REGEX]
        [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**ORA- errors of the last 24 hours, one row per database and error code**

```text
$ dbalert
  +-----------+-------------+---------+-----------------------+-----------------------+----------------------------------------------------------------------------------------------------------------------------------------------+
  |  DB       |  CODE       |  COUNT  |  FIRST                |  LAST                 |  SAMPLE                                                                                                                                      |
  +-----------+-------------+---------+-----------------------+-----------------------+----------------------------------------------------------------------------------------------------------------------------------------------+
  |  CRMSTBY  |  ORA-16191  |  1      |  2026-11-24 23:25:28  |  2026-11-24 23:25:28  |  ORA-16191: Primary log shipping client not logged on standby                                                                                |
  |  FINPRD   |  ORA-00060  |  1      |  2026-11-25 01:25:28  |  2026-11-25 01:25:28  |  ORA-00060: Deadlock detected. See Note 60.1 at My Oracle Support for Troubleshooting ORA-60 Errors. More info in file FINPRD_ora_8812.trc.  |
  |  FINPRD   |  ORA-01555  |  1      |  2026-11-25 02:25:28  |  2026-11-25 02:25:28  |  ORA-01555: snapshot too old: rollback segment number 4 with name "_SYSSMU4_1158493212$" too small                                           |
  |  FINPRD   |  ORA-00600  |  1      |  2026-11-25 04:25:28  |  2026-11-25 04:25:28  |  ORA-00600: internal error code, arguments: [kcbz_check_objd_typ_3], [0], [0], [1], [], [], [], [], [], [], [], []                           |
  |  FINPRD   |  ORA-03136  |  1      |  2026-11-25 05:55:28  |  2026-11-25 05:55:28  |  ORA-03136: inbound connection timed out                                                                                                     |
  +-----------+-------------+---------+-----------------------+-----------------------+----------------------------------------------------------------------------------------------------------------------------------------------+
```

**One row per error line in the last 6 hours**

```text
$ dbalert --since 6h --detail
  +----------+-----------------------+-------------+----------------------------------------------------------------------------------------------------------------------------------------------+
  |  DB      |  TIME                 |  CODE       |  MESSAGE                                                                                                                                     |
  +----------+-----------------------+-------------+----------------------------------------------------------------------------------------------------------------------------------------------+
  |  FINPRD  |  2026-11-25 01:25:28  |  ORA-00060  |  ORA-00060: Deadlock detected. See Note 60.1 at My Oracle Support for Troubleshooting ORA-60 Errors. More info in file FINPRD_ora_8812.trc.  |
  |  FINPRD  |  2026-11-25 02:25:28  |  ORA-01555  |  ORA-01555: snapshot too old: rollback segment number 4 with name "_SYSSMU4_1158493212$" too small                                           |
  |  FINPRD  |  2026-11-25 04:25:28  |  ORA-00600  |  ORA-00600: internal error code, arguments: [kcbz_check_objd_typ_3], [0], [0], [1], [], [], [], [], [], [], [], []                           |
  |  FINPRD  |  2026-11-25 05:55:28  |  ORA-03136  |  ORA-03136: inbound connection timed out                                                                                                     |
  +----------+-----------------------+-------------+----------------------------------------------------------------------------------------------------------------------------------------------+
```

**Last 7 days without the noisy ORA-03136**

```text
$ dbalert --since 7d --grep-v 'ORA-03136'
  +-----------+-------------+---------+-----------------------+-----------------------+----------------------------------------------------------------------------------------------------------------------------------------------+
  |  DB       |  CODE       |  COUNT  |  FIRST                |  LAST                 |  SAMPLE                                                                                                                                      |
  +-----------+-------------+---------+-----------------------+-----------------------+----------------------------------------------------------------------------------------------------------------------------------------------+
  |  CRMSTBY  |  ORA-16191  |  1      |  2026-11-24 23:25:28  |  2026-11-24 23:25:28  |  ORA-16191: Primary log shipping client not logged on standby                                                                                |
  |  FINPRD   |  ORA-00060  |  1      |  2026-11-25 01:25:28  |  2026-11-25 01:25:28  |  ORA-00060: Deadlock detected. See Note 60.1 at My Oracle Support for Troubleshooting ORA-60 Errors. More info in file FINPRD_ora_8812.trc.  |
  |  FINPRD   |  ORA-01555  |  1      |  2026-11-25 02:25:28  |  2026-11-25 02:25:28  |  ORA-01555: snapshot too old: rollback segment number 4 with name "_SYSSMU4_1158493212$" too small                                           |
  |  FINPRD   |  ORA-00600  |  1      |  2026-11-25 04:25:28  |  2026-11-25 04:25:28  |  ORA-00600: internal error code, arguments: [kcbz_check_objd_typ_3], [0], [0], [1], [], [], [], [], [], [], [], []                           |
  |  HRPRD    |  ORA-27125  |  1      |  2026-11-22 06:27:29  |  2026-11-22 06:27:29  |  2048K            3290            3073            1536        ORA-27125                                                                      |
  +-----------+-------------+---------+-----------------------+-----------------------+----------------------------------------------------------------------------------------------------------------------------------------------+
```

**Custom pattern on a database that is down**

```text
$ dbalert --since 7d --pattern 'ORA-[0-9]+|Shutting down' --db DWTST --detail
  +---------+-----------------------+-----------------+---------------------------------------------+
  |  DB     |  TIME                 |  CODE           |  MESSAGE                                    |
  +---------+-----------------------+-----------------+---------------------------------------------+
  |  DWTST  |  2026-11-19 06:28:34  |  Shutting down  |  Shutting down ORACLE instance (immediate)  |
  +---------+-----------------------+-----------------+---------------------------------------------+
```

<details>
<summary>Full <code>dbalert --help</code></summary>

```text
Usage: dbalert [--since 24h] [--detail] [--pattern REGEX] [--max N] [--db REGEX]
               [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Scans the alert log of every database on the host (running instances and DOWN
oratab entries) for errors logged within the time window. The file is read
backwards, so only the requested window is processed even for very large logs.

Summary (default): DB, CODE, COUNT, FIRST, LAST, SAMPLE   (one row per DB and error code)
--detail:          DB, TIME, CODE, MESSAGE                (one row per error line)

Options:
  --since DUR       Window: 30m, 2h, 1d, ... (plain number = hours; default: 24h)
  --detail          One row per error line instead of a summary
  --pattern REGEX   Error pattern (extended regex, default: 'ORA-[0-9]+').
                    Example: 'ORA-[0-9]+|TNS-[0-9]+|Checkpoint not complete'
  --max N           Detail: maximum lines per database, newest kept (default: 200)
  --db REGEX        Only scan SIDs matching REGEX (case-insensitive)
  --grep / --grep-v Filter output rows, e.g.  --grep-v 'ORA-(3136|609)'
  --csv|--json|--raw, --no-header, --no-color

Notes:
  - Both alert log timestamp formats are understood (12.2+ ISO and the older
    'Wed Nov 13 10:00:00 2026' format). Times are compared in the server's local time.

Return code: 0 = no errors in window, 2 = errors found, 1 = problem reading logs

Examples:
  dbalert
  dbalert --since 2h --detail
  dbalert --since 7d --grep ORA-00600
  dbalert --pattern 'ORA-[0-9]+|Checkpoint not complete' --grep-v 'ORA-3136'
```

</details>

[Back to the function list](#function-reference)

### dbincident

ADR incidents (ORA-600, ORA-7445, ORA-4031 ...) of every database, with an option to package one for an Oracle SR.

**Features**

- Reads `adrci show incident` of each database's ADR home
- `--days N` window (default 7)
- `--package ID --db SID` creates an IPS zip with `adrci ips pack` (asks for confirmation, `--dir` for the target)

**Usage**

```text
dbincident [--days N] [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
           [--csv|--json|--raw] [--no-header] [--no-color]
dbincident --package INCIDENT_ID --db SID [--dir DIR] [--yes]
```

**Examples**

**ADR incidents of the last 7 days**

```text
$ dbincident
  +----------+---------------+-----------------------------------+-----------------------+------------------------------+
  |  DB      |  INCIDENT_ID  |  PROBLEM_KEY                      |  CREATE_TIME          |  ADR_HOME                    |
  +----------+---------------+-----------------------------------+-----------------------+------------------------------+
  |  FINPRD  |  48211        |  ORA 600 [kcbz_check_objd_typ_3]  |  2026-11-23 06:31:39  |  diag/rdbms/finprd_a/FINPRD  |
  |  FINPRD  |  48177        |  ORA 7445 [qkxrPXformUnm]         |  2026-11-20 06:31:39  |  diag/rdbms/finprd_a/FINPRD  |
  +----------+---------------+-----------------------------------+-----------------------+------------------------------+
```

**Longer window, one error**

```text
$ dbincident --days 60 --grep 'ORA 4031'
  +----------+---------------+---------------+-----------------------+------------------------------+
  |  DB      |  INCIDENT_ID  |  PROBLEM_KEY  |  CREATE_TIME          |  ADR_HOME                    |
  +----------+---------------+---------------+-----------------------+------------------------------+
  |  FINPRD  |  40001        |  ORA 4031     |  2026-10-16 06:31:39  |  diag/rdbms/finprd_a/FINPRD  |
  +----------+---------------+---------------+-----------------------+------------------------------+
```

**Create an IPS package for an Oracle SR**

```text
$ dbincident --package 48211 --db FINPRD --yes --dir /u01/app/oracle/ips_packages
Database : FINPRD
ADR home : /u01/app/oracle/diag/rdbms/finprd_a/FINPRD
Incident : 48211
Target   : /u01/app/oracle/ips_packages  (46G free)
Generated package 1 in file /u01/app/oracle/ips_packages/ORA600kcb_20261125101500_COM_1.zip, mode complete
```

<details>
<summary>Full <code>dbincident --help</code></summary>

```text
Usage: dbincident [--days N] [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
                  [--csv|--json|--raw] [--no-header] [--no-color]
       dbincident --package INCIDENT_ID --db SID [--dir DIR] [--yes]

Lists the critical-error incidents recorded in the ADR of every database on the host
(adrci 'show incident'), e.g. ORA-00600, ORA-07445, ORA-04031.

Columns: DB, INCIDENT_ID, PROBLEM_KEY, CREATE_TIME, ADR_HOME

Packaging for an Oracle SR:
  --package ID   Create an IPS zip for incident ID (adrci 'ips pack incident ID in DIR').
                 Needs --db to select the database. Asks for confirmation (or --yes).
  --dir DIR      Target directory for the package (default: $ORACLE_BASE/ips_packages,
                 created when missing). Check the free space first - packages can be large.

Options:
  --days N       Only incidents created in the last N days (default: 7)
  --db REGEX     Only SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Return code: 0 = no incidents, 2 = incidents found, 1 = error

Examples:
  dbincident
  dbincident --days 30 --grep 'ORA 600'
  dbincident --package 123456 --db PRD1
```

</details>

[Back to the function list](#function-reference)

## Sessions and performance

### dbcpu

CPU used by each database, measured over a sampling interval.

**Features**

- OS_CPU%: utime+stime of every background AND foreground process of the instance, read twice from `/proc/<pid>/stat` (a current value, unlike the lifetime average of `ps %CPU`)
- HOST_CPU% = OS_CPU% / number of CPUs; DB_CPU/sec = Oracle's `CPU Usage Per Sec` (60-second group) in cores
- Shows `STATUS:MOUNTED`, `STATUS:DOWN` ... for instances that cannot report the metric
- `--sort 1|2`, `--interval N`, `--explain` / `--fullexplain` (how to read the numbers)

**Usage**

```text
dbcpu [--sort 1|2] [--interval SECONDS] [--explain|--fullexplain]
      [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header]
```

**Examples**

**CPU used by every instance, sampled over 2 seconds**

```text
$ dbcpu
  +-----------+---------+-----------+-------------+------------------+
  |  DB_NAME  |  PROCS  |  OS_CPU%  |  HOST_CPU%  |  DB_CPU/sec      |
  +-----------+---------+-----------+-------------+------------------+
  |  FINPRD   |  4      |  48.0     |  48.0       |  2.84            |
  |  HRPRD    |  2      |  12.0     |  12.0       |  0.41            |
  |  AIDEV    |  1      |  0.0      |  0.0        |  0.07            |
  |  CRMSTBY  |  1      |  0.0      |  0.0        |  STATUS:MOUNTED  |
  |  DWTST    |  0      |  0.0      |  0.0        |  STATUS:DOWN     |
  +-----------+---------+-----------+-------------+------------------+

Sampled over 2s on 1 CPUs. Run 'dbcpu --explain' or 'dbcpu --fullexplain' for how to read these numbers.
```

**Sort by Oracle's own DB CPU metric and sample for 5 seconds**

```text
$ dbcpu --sort 2 --interval 5
  +-----------+---------+-----------+-------------+------------------+
  |  DB_NAME  |  PROCS  |  OS_CPU%  |  HOST_CPU%  |  DB_CPU/sec      |
  +-----------+---------+-----------+-------------+------------------+
  |  FINPRD   |  4      |  44.0     |  44.0       |  2.84            |
  |  HRPRD    |  2      |  12.2     |  12.2       |  0.41            |
  |  AIDEV    |  1      |  0.0      |  0.0        |  0.07            |
  |  CRMSTBY  |  1      |  0.0      |  0.0        |  STATUS:MOUNTED  |
  |  DWTST    |  0      |  0.0      |  0.0        |  STATUS:DOWN     |
  +-----------+---------+-----------+-------------+------------------+

Sampled over 5s on 1 CPUs. Run 'dbcpu --explain' or 'dbcpu --fullexplain' for how to read these numbers.
```

**Add a short explanation of the metrics**

```text
$ dbcpu --explain
  +-----------+---------+-----------+-------------+------------------+
  |  DB_NAME  |  PROCS  |  OS_CPU%  |  HOST_CPU%  |  DB_CPU/sec      |
  +-----------+---------+-----------+-------------+------------------+
  |  FINPRD   |  4      |  48.0     |  48.0       |  2.84            |
  |  HRPRD    |  2      |  11.5     |  11.5       |  0.41            |
  |  AIDEV    |  1      |  0.0      |  0.0        |  0.07            |
  |  CRMSTBY  |  1      |  0.0      |  0.0        |  STATUS:MOUNTED  |
  |  DWTST    |  0      |  0.0      |  0.0        |  STATUS:DOWN     |
  +-----------+---------+-----------+-------------+------------------+
------------------------------------------------------------------------------
DBCPU Metric Explanation
------------------------------------------------------------------------------
  OS_CPU%     = CPU used by all background AND foreground (dedicated server)
                processes of the instance during the sampling interval,
                from /proc/<pid>/stat. 100% = one core.
  HOST_CPU%   = OS_CPU% / number of CPUs on the host.
  DB_CPU/sec  = Oracle's own CPU consumption from v$sysmetric
                ('CPU Usage Per Sec', 60-second group) in cores.

  STATUS:DOWN means the instance could not be queried.
  STATUS:STARTED / STATUS:MOUNTED means it is reachable but not OPEN.

  OS_CPU% / 100 and DB_CPU/sec are both in "cores", so they are roughly
  comparable, but OS_CPU% is the last few seconds and DB_CPU/sec is the
  last minute, and DB_CPU/sec excludes some background CPU.
------------------------------------------------------------------------------
Tip: Run 'dbcpu --fullexplain' for full details.
```

<details>
<summary>Full <code>dbcpu --help</code></summary>

```text
Usage: dbcpu [--sort 1|2] [--interval SECONDS] [--explain|--fullexplain]
             [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header]

Description:
  Displays CPU utilization for all Oracle databases on the server.

  OS_CPU%      CPU used by ALL processes of the instance (background ora_*_SID and
               foreground oracleSID server processes) measured over the sampling
               interval from /proc/<pid>/stat. 100% = one full CPU core.
  HOST_CPU%    OS_CPU% divided by the number of CPUs on the host.
  PROCS        Number of Oracle processes found for the instance.
  DB_CPU/sec   Oracle "CPU Usage Per Sec" from v$sysmetric (60-second group),
               converted from centiseconds to CPU-seconds per second (= cores).
               STATUS:DOWN     - instance could not be queried / not running
               STATUS:STARTED  - instance reachable but not OPEN
               STATUS:MOUNTED

Options:
  --sort 1            Sort by OS_CPU% descending (default)
  --sort 2            Sort by DB_CPU/sec descending
  --interval N        Sampling interval in seconds, 1-60 (default: 2)
  --explain           Short explanation of the metrics
  --fullexplain       Detailed explanation and troubleshooting workflow
  --grep / --grep-v   Filter by DB name (case-insensitive regex)
  -h, --help          Show this help message

Examples:
  dbcpu
  dbcpu --sort 2
  dbcpu --interval 5
  dbcpu --fullexplain
```

</details>

[Back to the function list](#function-reference)

### dbsess

Sessions of every database: active session detail or a per-database summary against the limits.

**Features**

- Detail: container, SID/serial, user, SQL_ID, wait event (or ON CPU), seconds in call, blocker, machine, program
- `--summary`: sessions and processes against their limits with WARN / CRIT
- `--all` includes inactive sessions, `--min-secs` filters long calls

**Usage**

```text
dbsess [--summary] [--all] [--min-secs N] [--db REGEX]
       [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Active user sessions of every database**

```text
$ dbsess
  +----------+-----------+--------------+-------------+----------+-----------------+---------------------------------+--------+-----------+--------------+----------------------------------+
  |  DB      |  CON      |  SESSION     |  USERNAME   |  STATUS  |  SQL_ID         |  EVENT                          |  SECS  |  BLOCKER  |  MACHINE     |  PROGRAM                         |
  +----------+-----------+--------------+-------------+----------+-----------------+---------------------------------+--------+-----------+--------------+----------------------------------+
  |  FINPRD  |  FINPDB1  |  1123,40211  |  APP_FIN    |  ACTIVE  |  7v3k2p9qhs2w1  |  db file sequential read        |  412   |  -        |  appsrv01    |  JDBC Thin Client                |
  |  FINPRD  |  FINPDB1  |  1450,11873  |  APP_FIN    |  ACTIVE  |  0w2mxfk7c8q3n  |  enq: TX - row lock contention  |  186   |  1:2210   |  appsrv02    |  JDBC Thin Client                |
  |  FINPRD  |  FINPDB1  |  987,3301    |  BATCH_FIN  |  ACTIVE  |  4cr8d1t6s0mfa  |  ON CPU                         |  95    |  -        |  batchsrv01  |  sqlplus@batchsrv01 (TNS V1-V3)  |
  |  FINPRD  |  FINPDB2  |  302,551     |  REPORTER   |  ACTIVE  |  9h1zq2bs7tk4x  |  direct path read               |  41    |  -        |  bisrv01     |  Toad.exe                        |
  +----------+-----------+--------------+-------------+----------+-----------------+---------------------------------+--------+-----------+--------------+----------------------------------+
```

**Session and process usage against the limits**

```text
$ dbsess --summary
  +-----------+------------+--------------+------------+----------+-----------+-------------+--------------+------------+----------+
  |  DB       |  SESSIONS  |  SESS_LIMIT  |  SESS_PCT  |  ACTIVE  |  BLOCKED  |  PROCESSES  |  PROC_LIMIT  |  PROC_PCT  |  STATUS  |
  +-----------+------------+--------------+------------+----------+-----------+-------------+--------------+------------+----------+
  |  AIDEV    |  41        |  624         |  6.6       |  1       |  0        |  38         |  400         |  9.5       |  OK      |
  |  CRMSTBY  |  58        |  1528        |  3.8       |  0       |  0        |  62         |  1000        |  6.2       |  OK      |
  |  FINPRD   |  1874      |  2272        |  82.5      |  46      |  3        |  1612       |  1500        |  107.5     |  CRIT    |
  |  HRPRD    |  212       |  924         |  22.9      |  4       |  0        |  198        |  600         |  33.0      |  OK      |
  +-----------+------------+--------------+------------+----------+-----------+-------------+--------------+------------+----------+
```

**Only sessions in the current call for 2 minutes or more**

```text
$ dbsess --min-secs 120
  +----------+-----------+--------------+-------------+----------+-----------------+---------------------------------+--------+-----------+--------------+----------------------------------+
  |  DB      |  CON      |  SESSION     |  USERNAME   |  STATUS  |  SQL_ID         |  EVENT                          |  SECS  |  BLOCKER  |  MACHINE     |  PROGRAM                         |
  +----------+-----------+--------------+-------------+----------+-----------------+---------------------------------+--------+-----------+--------------+----------------------------------+
  |  FINPRD  |  FINPDB1  |  1123,40211  |  APP_FIN    |  ACTIVE  |  7v3k2p9qhs2w1  |  db file sequential read        |  412   |  -        |  appsrv01    |  JDBC Thin Client                |
  |  FINPRD  |  FINPDB1  |  1450,11873  |  APP_FIN    |  ACTIVE  |  0w2mxfk7c8q3n  |  enq: TX - row lock contention  |  186   |  1:2210   |  appsrv02    |  JDBC Thin Client                |
  |  FINPRD  |  FINPDB1  |  987,3301    |  BATCH_FIN  |  ACTIVE  |  4cr8d1t6s0mfa  |  ON CPU                         |  95    |  -        |  batchsrv01  |  sqlplus@batchsrv01 (TNS V1-V3)  |
  |  FINPRD  |  FINPDB2  |  302,551     |  REPORTER   |  ACTIVE  |  9h1zq2bs7tk4x  |  direct path read               |  41    |  -        |  bisrv01     |  Toad.exe                        |
  +----------+-----------+--------------+-------------+----------+-----------------+---------------------------------+--------+-----------+--------------+----------------------------------+
```

**Include INACTIVE sessions, only one application server**

```text
$ dbsess --all --grep appsrv02
  +----------+-----------+--------------+------------+------------+-----------------+---------------------------------+--------+-----------+------------+--------------------+
  |  DB      |  CON      |  SESSION     |  USERNAME  |  STATUS    |  SQL_ID         |  EVENT                          |  SECS  |  BLOCKER  |  MACHINE   |  PROGRAM           |
  +----------+-----------+--------------+------------+------------+-----------------+---------------------------------+--------+-----------+------------+--------------------+
  |  FINPRD  |  FINPDB1  |  1450,11873  |  APP_FIN   |  ACTIVE    |  0w2mxfk7c8q3n  |  enq: TX - row lock contention  |  186   |  1:2210   |  appsrv02  |  JDBC Thin Client  |
  |  FINPRD  |  FINPDB1  |  2210,6152   |  APP_FIN   |  INACTIVE  |  -              |  SQL*Net message from client    |  1903  |  -        |  appsrv02  |  JDBC Thin Client  |
  +----------+-----------+--------------+------------+------------+-----------------+---------------------------------+--------+-----------+------------+--------------------+
```

<details>
<summary>Full <code>dbsess --help</code></summary>

```text
Usage: dbsess [--summary] [--all] [--min-secs N] [--db REGEX]
              [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Detail (default): ACTIVE user sessions of every running database (your own session excluded).
  DB, CON, SESSION (sid,serial#), USERNAME, STATUS, SQL_ID, EVENT ('ON CPU' when not waiting),
  SECS (seconds in the current call), BLOCKER (inst:sid), MACHINE, PROGRAM

--summary: one row per database
  DB, SESSIONS, SESS_LIMIT, SESS_PCT, ACTIVE, BLOCKED, PROCESSES, PROC_LIMIT, PROC_PCT, STATUS
  STATUS is the worse of SESS_PCT / PROC_PCT against --warn / --crit.

Options:
  --summary       Per-database counts and limits
  --all           Detail: include INACTIVE sessions
  --min-secs N    Detail: only sessions in the current call for at least N seconds
  --warn PCT      Summary WARN threshold for session/process usage (default: 80)
  --crit PCT      Summary CRIT threshold (default: 90)
  --db REGEX      Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Examples:
  dbsess
  dbsess --min-secs 60
  dbsess --grep APPUSER --all
  dbsess --summary
```

</details>

[Back to the function list](#function-reference)

### dbblock

Blocking chains across all databases: every root blocker followed by the sessions waiting on it.

**Features**

- RAC-aware (`gv$session`), sessions shown as `inst:sid,serial#`
- Wait time and time in the current call for every waiter
- `--kill-sql` prints `ALTER SYSTEM KILL SESSION` statements for the root blockers - nothing is executed
- Return code 2 when blocking is found

**Usage**

```text
dbblock [--kill-sql] [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
        [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Blocking chains: root blocker followed by its waiters**

```text
$ dbblock
  +----------+----------------+----------------+------------+------------+-----------------+---------------------------------+-------------+------------------+------------+--------------------+
  |  DB      |  ROLE          |  SESSION       |  USERNAME  |  STATUS    |  SQL_ID         |  EVENT                          |  WAIT_SECS  |  LAST_CALL_SECS  |  MACHINE   |  PROGRAM           |
  +----------+----------------+----------------+------------+------------+-----------------+---------------------------------+-------------+------------------+------------+--------------------+
  |  FINPRD  |  BLOCKER       |  1:2210,6152   |  APP_FIN   |  INACTIVE  |  -              |  SQL*Net message from client    |  0          |  1903            |  appsrv02  |  JDBC Thin Client  |
  |  FINPRD  |  `> WAITER     |  1:1450,11873  |  APP_FIN   |  ACTIVE    |  0w2mxfk7c8q3n  |  enq: TX - row lock contention  |  186        |  186             |  appsrv02  |  JDBC Thin Client  |
  |  FINPRD  |  `---> WAITER  |  1:1502,9001   |  APP_FIN   |  ACTIVE    |  0w2mxfk7c8q3n  |  enq: TX - row lock contention  |  74         |  74              |  appsrv01  |  JDBC Thin Client  |
  +----------+----------------+----------------+------------+------------+-----------------+---------------------------------+-------------+------------------+------------+--------------------+
```

**Also print the KILL SESSION statements for the root blockers (nothing is executed)**

```text
$ dbblock --kill-sql
  +----------+----------------+----------------+------------+------------+-----------------+---------------------------------+-------------+------------------+------------+--------------------+
  |  DB      |  ROLE          |  SESSION       |  USERNAME  |  STATUS    |  SQL_ID         |  EVENT                          |  WAIT_SECS  |  LAST_CALL_SECS  |  MACHINE   |  PROGRAM           |
  +----------+----------------+----------------+------------+------------+-----------------+---------------------------------+-------------+------------------+------------+--------------------+
  |  FINPRD  |  BLOCKER       |  1:2210,6152   |  APP_FIN   |  INACTIVE  |  -              |  SQL*Net message from client    |  0          |  1903            |  appsrv02  |  JDBC Thin Client  |
  |  FINPRD  |  `> WAITER     |  1:1450,11873  |  APP_FIN   |  ACTIVE    |  0w2mxfk7c8q3n  |  enq: TX - row lock contention  |  186        |  186             |  appsrv02  |  JDBC Thin Client  |
  |  FINPRD  |  `---> WAITER  |  1:1502,9001   |  APP_FIN   |  ACTIVE    |  0w2mxfk7c8q3n  |  enq: TX - row lock contention  |  74         |  74              |  appsrv01  |  JDBC Thin Client  |
  +----------+----------------+----------------+------------+------------+-----------------+---------------------------------+-------------+------------------+------------+--------------------+

-- Review before running (connect to the database shown in each comment):
-- FINPRD: blocker 1:2210,6152
ALTER SYSTEM KILL SESSION '2210,6152,@1' IMMEDIATE;
```

<details>
<summary>Full <code>dbblock --help</code></summary>

```text
Usage: dbblock [--kill-sql] [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
               [--csv|--json|--raw] [--no-header] [--no-color]

Blocking chains from gv$session (RAC-aware): every root blocker followed by the
sessions waiting on it ('`->' marks the level in the chain).

Columns:
  DB, ROLE (BLOCKER / WAITER), SESSION (inst:sid,serial#), USERNAME, STATUS, SQL_ID,
  EVENT, WAIT_SECS, LAST_CALL_SECS, MACHINE, PROGRAM

Options:
  --kill-sql     Also print ALTER SYSTEM KILL SESSION statements for the root blockers.
                 Nothing is executed - review and run them yourself.
  --db REGEX     Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Return code: 0 = no blocking, 2 = blocking found, 1 = error

Examples:
  dbblock
  dbblock --kill-sql
```

</details>

[Back to the function list](#function-reference)

### dbash

"What is the database doing right now?" - top wait events and top SQL from Active Session History.

**Features**

- LOAD row with average active sessions against the CPU count
- Top wait events (ON CPU included) and top SQL_IDs with container, main event and the start of the SQL text
- `--minutes N`, `--top N`, `--by event|sql|both`
- Requires the Diagnostics Pack - databases without it are skipped unless `--force`

**Usage**

```text
dbash [--minutes N] [--top N] [--by event|sql|both] [--force] [--db REGEX]
      [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Load, top wait events and top SQL of the last 15 minutes**

```text
$ dbash
  +-----------+---------+--------------------------------------+------------------------------------------------------------------------------------------------------+-----------+---------+--------+
  |  DB       |  TYPE   |  ITEM                                |  DETAIL                                                                                              |  SAMPLES  |  PCT    |  AAS   |
  +-----------+---------+--------------------------------------+------------------------------------------------------------------------------------------------------+-----------+---------+--------+
  |  AIDEV    |  LOAD   |  total (15m)                         |  OK (cpu_count 2)                                                                                    |  96       |  100.0  |  0.11  |
  |  AIDEV    |  EVENT  |  ON CPU                              |  -                                                                                                   |  60       |  62.5   |  0.07  |
  |  AIDEV    |  EVENT  |  db file sequential read             |  -                                                                                                   |  36       |  37.5   |  0.04  |
  |  AIDEV    |  SQL    |  1p8z0q4mvh7cd                       |  AIPDB1 / ON CPU / select embedding from docs where id = :1                                          |  40       |  50.0   |  0.04  |
  |  CRMSTBY  |  LOAD   |  total (15m)                         |  OK (cpu_count 16)                                                                                   |  180      |  100.0  |  0.20  |
  |  CRMSTBY  |  EVENT  |  ON CPU                              |  -                                                                                                   |  74       |  41.1   |  0.08  |
  |  CRMSTBY  |  EVENT  |  parallel recovery read buffer free  |  -                                                                                                   |  61       |  33.9   |  0.07  |
  |  CRMSTBY  |  EVENT  |  recovery apply pending              |  -                                                                                                   |  45       |  25.0   |  0.05  |
  |  FINPRD   |  LOAD   |  total (15m)                         |  OK (cpu_count 16)                                                                                   |  5130     |  100.0  |  5.70  |
  |  FINPRD   |  EVENT  |  ON CPU                              |  -                                                                                                   |  2410     |  47.0   |  2.68  |
  |  FINPRD   |  EVENT  |  db file sequential read             |  -                                                                                                   |  1180     |  23.0   |  1.31  |
  |  FINPRD   |  EVENT  |  enq: TX - row lock contention       |  -                                                                                                   |  720      |  14.0   |  0.80  |
  |  FINPRD   |  EVENT  |  log file sync                       |  -                                                                                                   |  410      |  8.0    |  0.46  |
  |  FINPRD   |  EVENT  |  direct path read                    |  -                                                                                                   |  230      |  4.5    |  0.26  |
  |  FINPRD   |  SQL    |  7v3k2p9qhs2w1                       |  FINPDB1 / db file sequential read / select h.acct_id, sum(h.amount) from gl_history h where         |  1410     |  31.2   |  1.57  |
  |  FINPRD   |  SQL    |  0w2mxfk7c8q3n                       |  FINPDB1 / enq: TX - row lock contention / update gl_balance set amount = amount + :1 where acct_id  |  702      |  15.5   |  0.78  |
  |  FINPRD   |  SQL    |  4cr8d1t6s0mfa                       |  FINPDB1 / ON CPU / begin fin_pkg.post_journal(:1, :2); end;                                         |  611      |  13.5   |  0.68  |
  |  HRPRD    |  LOAD   |  -                                   |  SKIPPED (Diagnostics Pack not enabled - use --force)                                                |  -        |  -      |  -     |
  +-----------+---------+--------------------------------------+------------------------------------------------------------------------------------------------------+-----------+---------+--------+
```

**Top 3 SQL_IDs of one database**

```text
$ dbash --db FINPRD --by sql --top 3
  +----------+--------+-----------------+------------------------------------------------------------------------------------------------------+-----------+---------+--------+
  |  DB      |  TYPE  |  ITEM           |  DETAIL                                                                                              |  SAMPLES  |  PCT    |  AAS   |
  +----------+--------+-----------------+------------------------------------------------------------------------------------------------------+-----------+---------+--------+
  |  FINPRD  |  LOAD  |  total (15m)    |  OK (cpu_count 16)                                                                                   |  5130     |  100.0  |  5.70  |
  |  FINPRD  |  SQL   |  7v3k2p9qhs2w1  |  FINPDB1 / db file sequential read / select h.acct_id, sum(h.amount) from gl_history h where         |  1410     |  31.2   |  1.57  |
  |  FINPRD  |  SQL   |  0w2mxfk7c8q3n  |  FINPDB1 / enq: TX - row lock contention / update gl_balance set amount = amount + :1 where acct_id  |  702      |  15.5   |  0.78  |
  |  FINPRD  |  SQL   |  4cr8d1t6s0mfa  |  FINPDB1 / ON CPU / begin fin_pkg.post_journal(:1, :2); end;                                         |  611      |  13.5   |  0.68  |
  +----------+--------+-----------------+------------------------------------------------------------------------------------------------------+-----------+---------+--------+
```

**Only the wait events of the last 5 minutes**

```text
$ dbash --minutes 5 --by event --db FINPRD
  +----------+---------+---------------------------------+-----------------------+-----------+---------+---------+
  |  DB      |  TYPE   |  ITEM                           |  DETAIL               |  SAMPLES  |  PCT    |  AAS    |
  +----------+---------+---------------------------------+-----------------------+-----------+---------+---------+
  |  FINPRD  |  LOAD   |  total (5m)                     |  WARN (cpu_count 16)  |  5130     |  100.0  |  17.10  |
  |  FINPRD  |  EVENT  |  ON CPU                         |  -                    |  2410     |  47.0   |  8.03   |
  |  FINPRD  |  EVENT  |  db file sequential read        |  -                    |  1180     |  23.0   |  3.93   |
  |  FINPRD  |  EVENT  |  enq: TX - row lock contention  |  -                    |  720      |  14.0   |  2.40   |
  |  FINPRD  |  EVENT  |  log file sync                  |  -                    |  410      |  8.0    |  1.37   |
  |  FINPRD  |  EVENT  |  direct path read               |  -                    |  230      |  4.5    |  0.77   |
  +----------+---------+---------------------------------+-----------------------+-----------+---------+---------+
```

<details>
<summary>Full <code>dbash --help</code></summary>

```text
Usage: dbash [--minutes N] [--top N] [--by event|sql|both] [--force] [--db REGEX]
             [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

"What is the database doing right now?" - from GV$ACTIVE_SESSION_HISTORY (one-second
samples kept in memory) over the last N minutes, for every running database.

Columns: DB, TYPE, ITEM, DETAIL, SAMPLES, PCT, AAS
  TYPE    LOAD   one row per database: total average active sessions vs CPU count
          EVENT  top wait events ('ON CPU' = sessions running on CPU)
          SQL    top SQL_IDs (DETAIL = container, top event and the start of the SQL text)
  AAS     average active sessions = SAMPLES / seconds in the window
  LOAD STATUS (in DETAIL): OK, WARN when AAS > CPU count (sessions queue for CPU or wait)

Options:
  --minutes N     Window in minutes (default: 15, max: 1440)
  --top N         Rows per type (default: 5)
  --by TYPE       event, sql or both (default)
  --force         Run even when CONTROL_MANAGEMENT_PACK_ACCESS does not include DIAGNOSTIC
  --db REGEX      Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Licensing: ASH is part of the Oracle Diagnostics Pack. Databases whose
CONTROL_MANAGEMENT_PACK_ACCESS does not include DIAGNOSTIC are SKIPPED unless --force.

Examples:
  dbash
  dbash --minutes 5 --by sql --top 10
  dbash --db PRD --csv
```

</details>

[Back to the function list](#function-reference)

### dblongops

Long-running operations with progress and time remaining (RMAN, scans, index builds, Data Pump ...).

**Features**

- From `gv$session_longops`: operation, target, % done, elapsed, remaining, SQL_ID
- `--all` also shows operations that finished in the last hour

**Usage**

```text
dblongops [--all] [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
          [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Operations in progress with % done and time remaining**

```text
$ dblongops
  +----------+-----------+----------------+-------------+-------------------------------------+------------------+------------+-----------+-------------+-----------------+-----------+
  |  DB      |  CON      |  SESSION       |  USERNAME   |  OPNAME                             |  TARGET          |  PCT_DONE  |  ELAPSED  |  REMAINING  |  SQL_ID         |  STATUS   |
  +----------+-----------+----------------+-------------+-------------------------------------+------------------+------------+-----------+-------------+-----------------+-----------+
  |  FINPRD  |  -        |  1:1987,33021  |  SYS        |  RMAN: incremental datafile backup  |  Set Count       |  62.4      |  1h 12m   |  0h 43m     |  -              |  RUNNING  |
  |  FINPRD  |  FINPDB1  |  1:987,3301    |  BATCH_FIN  |  Table Scan                         |  FIN.GL_HISTORY  |  38.0      |  0h 21m   |  0h 34m     |  4cr8d1t6s0mfa  |  RUNNING  |
  +----------+-----------+----------------+-------------+-------------------------------------+------------------+------------+-----------+-------------+-----------------+-----------+
```

**Include operations that finished in the last hour**

```text
$ dblongops --all --grep FINPDB1
  +----------+-----------+--------------+-------------+------------------------+----------------------+------------+-----------+-------------+-----------------+-----------+
  |  DB      |  CON      |  SESSION     |  USERNAME   |  OPNAME                |  TARGET              |  PCT_DONE  |  ELAPSED  |  REMAINING  |  SQL_ID         |  STATUS   |
  +----------+-----------+--------------+-------------+------------------------+----------------------+------------+-----------+-------------+-----------------+-----------+
  |  FINPRD  |  FINPDB1  |  1:987,3301  |  BATCH_FIN  |  Table Scan            |  FIN.GL_HISTORY      |  38.0      |  0h 21m   |  0h 34m     |  4cr8d1t6s0mfa  |  RUNNING  |
  |  FINPRD  |  FINPDB1  |  1:1120,404  |  FIN        |  Index Fast Full Scan  |  FIN.GL_HISTORY_IX1  |  100.0     |  0h 6m    |  0h 0m      |  8sd02k1mzq5vx  |  DONE     |
  +----------+-----------+--------------+-------------+------------------------+----------------------+------------+-----------+-------------+-----------------+-----------+
```

<details>
<summary>Full <code>dblongops --help</code></summary>

```text
Usage: dblongops [--all] [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
                 [--csv|--json|--raw] [--no-header] [--no-color]

Operations Oracle tracks in GV$SESSION_LONGOPS (RMAN backup/restore, index creation,
table scans, hash joins, Data Pump, stats gathering ...) for every running database.

Columns: DB, CON, SESSION (inst:sid,serial#), USERNAME, OPNAME, TARGET, PCT_DONE,
         ELAPSED, REMAINING, SQL_ID, STATUS
  STATUS  RUNNING (not finished) or DONE (finished, only with --all)

Options:
  --all          Also show operations that finished in the last hour
  --db REGEX     Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Examples:
  dblongops
  dblongops --grep RMAN
  dblongops --all --db PRD
```

</details>

[Back to the function list](#function-reference)

### dbconn

User sessions grouped per database and container - who has to be notified or drained before patching.

**Features**

- Group by any combination of user, machine, program and service (`--by`)
- Session count, active sessions, oldest and newest logon
- Oracle-maintained accounts are hidden unless `--all`

**Usage**

```text
dbconn [--by user,machine,program,service] [--all] [--db REGEX]
       [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**User sessions grouped by user, machine and program**

```text
$ dbconn
  +----------+-----------+-------------+--------------+----------------------------------+------------+----------+--------------------+--------------------+
  |  DB      |  CON      |  USERNAME   |  MACHINE     |  PROGRAM                         |  SESSIONS  |  ACTIVE  |  OLDEST_LOGON      |  NEWEST_LOGON      |
  +----------+-----------+-------------+--------------+----------------------------------+------------+----------+--------------------+--------------------+
  |  FINPRD  |  FINPDB1  |  APP_FIN    |  appsrv01    |  JDBC Thin Client                |  612       |  22      |  2026-11-07 06:31  |  2026-11-25 06:29  |
  |  FINPRD  |  FINPDB1  |  APP_FIN    |  appsrv02    |  JDBC Thin Client                |  598       |  19      |  2026-11-07 06:31  |  2026-11-25 06:30  |
  |  FINPRD  |  FINPDB2  |  REPORTER   |  bisrv01     |  Toad.exe                        |  14        |  1       |  2026-11-24 06:31  |  2026-11-25 04:31  |
  |  FINPRD  |  FINPDB2  |  ETL_USER   |  etlsrv01    |  python3                         |  8         |  0       |  2026-11-24 21:31  |  2026-11-25 03:31  |
  |  FINPRD  |  FINPDB1  |  BATCH_FIN  |  batchsrv01  |  sqlplus@batchsrv01 (TNS V1-V3)  |  6         |  2       |  2026-11-25 01:31  |  2026-11-25 05:31  |
  |  HRPRD   |  -        |  HR_APP     |  hrapp01     |  w3wp.exe                        |  120       |  3       |  2026-11-22 06:31  |  2026-11-25 06:26  |
  +----------+-----------+-------------+--------------+----------------------------------+------------+----------+--------------------+--------------------+
```

**Group by client machine only - who to notify before patching**

```text
$ dbconn --by machine
  +----------+-----------+--------------+------------+----------+--------------------+--------------------+
  |  DB      |  CON      |  MACHINE     |  SESSIONS  |  ACTIVE  |  OLDEST_LOGON      |  NEWEST_LOGON      |
  +----------+-----------+--------------+------------+----------+--------------------+--------------------+
  |  FINPRD  |  FINPDB1  |  appsrv01    |  612       |  22      |  2026-11-07 06:31  |  2026-11-25 06:29  |
  |  FINPRD  |  FINPDB1  |  appsrv02    |  598       |  19      |  2026-11-07 06:31  |  2026-11-25 06:30  |
  |  FINPRD  |  FINPDB2  |  bisrv01     |  14        |  1       |  2026-11-24 06:31  |  2026-11-25 04:31  |
  |  FINPRD  |  FINPDB2  |  etlsrv01    |  8         |  0       |  2026-11-24 21:31  |  2026-11-25 03:31  |
  |  FINPRD  |  FINPDB1  |  batchsrv01  |  6         |  2       |  2026-11-25 01:31  |  2026-11-25 05:31  |
  |  HRPRD   |  -        |  hrapp01     |  120       |  3       |  2026-11-22 06:31  |  2026-11-25 06:26  |
  +----------+-----------+--------------+------------+----------+--------------------+--------------------+
```

**Group by service and user, CSV**

```text
$ dbconn --by service,user --db FINPRD --csv
DB,CON,SERVICE,USERNAME,SESSIONS,ACTIVE,OLDEST_LOGON,NEWEST_LOGON
FINPRD,FINPDB1,FIN_OLTP,APP_FIN,1210,41,2026-11-07 06:31,2026-11-25 06:29
FINPRD,FINPDB2,FIN_RPT,REPORTER,14,1,2026-11-24 06:31,2026-11-25 04:31
FINPRD,FINPDB2,FIN_BATCH,ETL_USER,8,0,2026-11-24 21:31,2026-11-25 03:31
FINPRD,FINPDB1,FIN_BATCH,BATCH_FIN,6,2,2026-11-25 01:31,2026-11-25 05:31
```

<details>
<summary>Full <code>dbconn --help</code></summary>

```text
Usage: dbconn [--by user,machine,program,service] [--all] [--db REGEX]
              [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

User sessions (GV$SESSION, TYPE = USER) grouped per database and container - the list of
applications that need notice or draining before patching, and the first place to look
during a connection storm.

Columns: DB, CON, <grouping columns>, SESSIONS, ACTIVE, OLDEST_LOGON, NEWEST_LOGON

Options:
  --by LIST      Grouping columns, comma separated: user, machine, program, service
                 (default: user,machine,program)
  --all          Include background-like users (SYS, SYSTEM, DBSNMP, oracle-maintained
                 accounts); hidden by default
  --db REGEX     Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Examples:
  dbconn
  dbconn --by machine
  dbconn --by service,user --db PRD
  dbconn --grep -v 'sqlplus'
```

</details>

[Back to the function list](#function-reference)

## Users, configuration and compliance

### dbusers

Account health: locked, expired, soon-to-expire and default-password accounts in the ASM password file, every CDB and every PDB.

**Features**

- ASM password-file users are listed first; a missing ASMSNMP is reported
- CDB common users and PDB local users, default passwords checked per container
- CRIT: locked by failed logins, expired, default password, expiring today, locked watch-list account (DBSNMP by default)
- WARN: grace period, locked, expiring within `--days`; closed PDBs are reported
- `--watch` adds accounts to always show (e.g. monitoring or OGG users)

**Usage**

```text
dbusers [--days N] [--all] [--watch USER1,USER2] [--no-asm] [--db REGEX]
        [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Accounts that need attention (ASM password file first, then every database and PDB)**

```text
$ dbusers
  +-----------+------------+--------------+------------------+---------------+-------------+--------------------+-------------------------+---------------------------------------+
  |  DB       |  CON       |  USERNAME    |  ACCOUNT_STATUS  |  EXPIRY_DATE  |  DAYS_LEFT  |  LOCK_DATE         |  PROFILE                |  STATUS                               |
  +-----------+------------+--------------+------------------+---------------+-------------+--------------------+-------------------------+---------------------------------------+
  |  +ASM     |  -         |  ASMSNMP     |  OPEN            |  2027-01-26   |  62         |  -                 |  SYSDBA                 |  OK                                   |
  |  +ASM     |  -         |  SYS         |  OPEN            |  -            |  -          |  -                 |  SYSASM,SYSDBA,SYSOPER  |  OK                                   |
  |  AIDEV    |  CDB$ROOT  |  DBSNMP      |  OPEN            |  -            |  -          |  -                 |  DEFAULT                |  OK                                   |
  |  CRMSTBY  |  -         |  -           |  -               |  -            |  -          |  -                 |  -                      |  SKIPPED (MOUNTED)                    |
  |  FINPRD   |  CDB$ROOT  |  C##MONITOR  |  OPEN            |  2026-12-04   |  9          |  -                 |  C##MON_PROF            |  WARN (expires in 9 days)             |
  |  FINPRD   |  CDB$ROOT  |  DBSNMP      |  LOCKED          |  2027-01-12   |  48         |  2026-11-23 06:31  |  DEFAULT                |  CRIT (watch-list account locked)     |
  |  FINPRD   |  CDB$ROOT  |  SCOTT       |  OPEN            |  -            |  -          |  -                 |  DEFAULT                |  CRIT (default password)              |
  |  FINPRD   |  FINPDB1   |  BATCH_FIN   |  LOCKED(TIMED)   |  -            |  -          |  2026-11-25 04:31  |  APP_PROFILE            |  CRIT (locked by failed logins)       |
  |  FINPRD   |  FINPDB1   |  DEMO        |  OPEN            |  -            |  -          |  -                 |  DEFAULT                |  CRIT (default password)              |
  |  FINPRD   |  FINPDB1   |  RPT_USER    |  EXPIRED(GRACE)  |  2026-11-29   |  4          |  -                 |  DEFAULT                |  WARN (password in grace period)      |
  |  FINPRD   |  FINPDB2   |  OLD_ETL     |  EXPIRED         |  2026-11-13   |  -12        |  -                 |  DEFAULT                |  CRIT (password expired)              |
  |  FINPRD   |  FINPDB3   |  -           |  -               |  -            |  -          |  -                 |  -                      |  WARN (PDB is MOUNTED - not checked)  |
  |  HRPRD    |  -         |  DBSNMP      |  OPEN            |  2027-06-13   |  200        |  -                 |  DEFAULT                |  OK                                   |
  |  HRPRD    |  -         |  HR_APP      |  OPEN            |  2026-12-06   |  11         |  -                 |  DEFAULT                |  WARN (expires in 11 days)            |
  +-----------+------------+--------------+------------------+---------------+-------------+--------------------+-------------------------+---------------------------------------+
```

**Every checked account of one database**

```text
$ dbusers --all --no-asm --db HRPRD
  +---------+-------+------------+------------------+---------------+-------------+-------------+-----------+-----------------------------+
  |  DB     |  CON  |  USERNAME  |  ACCOUNT_STATUS  |  EXPIRY_DATE  |  DAYS_LEFT  |  LOCK_DATE  |  PROFILE  |  STATUS                     |
  +---------+-------+------------+------------------+---------------+-------------+-------------+-----------+-----------------------------+
  |  HRPRD  |  -    |  DBSNMP    |  OPEN            |  2027-06-13   |  200        |  -          |  DEFAULT  |  OK                         |
  |  HRPRD  |  -    |  HR_APP    |  OPEN            |  2026-12-06   |  11         |  -          |  DEFAULT  |  WARN (expires in 11 days)  |
  +---------+-------+------------+------------------+---------------+-------------+-------------+-----------+-----------------------------+
```

**30-day expiry window and an extra watch-list account**

```text
$ dbusers --days 30 --watch C##MONITOR --grep CDB
  +----------+------------+--------------+------------------+---------------+-------------+--------------------+---------------+------------------------------------+
  |  DB      |  CON       |  USERNAME    |  ACCOUNT_STATUS  |  EXPIRY_DATE  |  DAYS_LEFT  |  LOCK_DATE         |  PROFILE      |  STATUS                            |
  +----------+------------+--------------+------------------+---------------+-------------+--------------------+---------------+------------------------------------+
  |  AIDEV   |  CDB$ROOT  |  DBSNMP      |  OPEN            |  -            |  -          |  -                 |  DEFAULT      |  OK                                |
  |  FINPRD  |  CDB$ROOT  |  C##MONITOR  |  OPEN            |  2026-12-04   |  9          |  -                 |  C##MON_PROF  |  WARN (expires in 9 days)          |
  |  FINPRD  |  CDB$ROOT  |  DBSNMP      |  LOCKED          |  2027-01-12   |  48         |  2026-11-23 06:31  |  DEFAULT      |  CRIT (watch-list account locked)  |
  |  FINPRD  |  CDB$ROOT  |  SCOTT       |  OPEN            |  -            |  -          |  -                 |  DEFAULT      |  CRIT (default password)           |
  +----------+------------+--------------+------------------+---------------+-------------+--------------------+---------------+------------------------------------+
```

<details>
<summary>Full <code>dbusers --help</code></summary>

```text
Usage: dbusers [--days N] [--all] [--watch USER1,USER2] [--no-asm] [--db REGEX]
               [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Account health for:
  - the local ASM instance (users in the ASM password file, v$pwfile_users) - listed FIRST
  - every running database: CDB$ROOT (common users) and every OPEN PDB (local and
    common users as seen inside the PDB), or the non-CDB itself
By default only accounts that need attention are shown, plus the watch-list accounts.

STATUS rules (first match wins):
  CRIT  account status LOCKED(TIMED)        (locked by failed logins)
  WARN  account status EXPIRED(GRACE)       (in the grace period)
  CRIT  account status EXPIRED
  CRIT  OPEN account with a default password (CDB_USERS_WITH_DEFPWD, per container)
  WARN  account status LOCKED                (CRIT for watch-list accounts)
  CRIT  OPEN and the password expires today or has passed its expiry date
  WARN  OPEN and the password expires within --days
  OK    otherwise
ASM:
  WARN  ASMSNMP (OEM monitoring of ASM) is not in the ASM password file
  The rules above are applied when the ASM version reports ACCOUNT_STATUS (12.2+).
Containers:
  WARN  a PDB that is not OPEN (its users cannot be checked)

Accounts checked: all non Oracle-maintained users + the watch list
(default watch list: DBSNMP; ASMSNMP is always watched in ASM).

Options:
  --days N          Expiry warning window in days (default: 14)
  --all             Show every checked account, including OK ones
  --watch U1,U2     Add accounts to the watch list (always shown), e.g. C##MONITOR,OGG_ADMIN
  --no-asm          Skip the ASM password file
  --db REGEX        Only query SIDs matching REGEX (case-insensitive; ASM is always checked
                    unless --no-asm)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Notes:
  - PROFILE shows the profile for database users and the administrative privileges
    (SYSASM, SYSDBA, ...) for ASM password file users.
  - MOUNTED standbys are skipped (dictionary views need an OPEN database).

Return code: 0 = nothing CRIT, 2 = at least one CRIT, 1 = error

Examples:
  dbusers
  dbusers --days 30 --watch C##OGG_ADMIN
  dbusers --all --grep APP_
  dbusers --all --grep '^\+ASM'
```

</details>

[Back to the function list](#function-reference)

### dbparam

Compares init parameters side by side across all running databases (and optionally their PDBs).

**Features**

- Select by exact name, SQL LIKE pattern, `--nondefault` or `--hidden` (set underscore parameters)
- SAME column: MATCH / DIFF; `--diff` shows only the differences
- `--pdbs` / `--pdb REGEX` add one column per open PDB
- Long values (control_files, log_archive_dest_n ...) wrap at spaces in table mode (`--width`)

**Usage**

```text
dbparam [PARAM|PATTERN ...] [--nondefault] [--hidden] [--diff] [--pdbs | --pdb REGEX]
        [--width N] [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
        [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Compare parameters across all databases**

```text
$ dbparam processes sessions open_cursors
  +----------------+---------+-----------+----------+---------+--------+
  |  PARAMETER     |  AIDEV  |  CRMSTBY  |  FINPRD  |  HRPRD  |  SAME  |
  +----------------+---------+-----------+----------+---------+--------+
  |  open_cursors  |  300    |  1000     |  1000    |  300    |  DIFF  |
  |  processes     |  400    |  1000     |  1500    |  600    |  DIFF  |
  |  sessions      |  624    |  1528     |  2272    |  924    |  DIFF  |
  +----------------+---------+-----------+----------+---------+--------+
```

**Long values wrap at spaces in table mode**

```text
$ dbparam control_files 'log_archive_dest_%'
  +----------------------+--------------------------------------------------+-----------------------------------------------------+------------------------------------------------------+---------------------------------------------------+--------+
  |  PARAMETER           |  AIDEV                                           |  CRMSTBY                                            |  FINPRD                                              |  HRPRD                                            |  SAME  |
  +----------------------+--------------------------------------------------+-----------------------------------------------------+------------------------------------------------------+---------------------------------------------------+--------+
  |  control_files       |  +DATA/AIDEV/CONTROLFILE/current.301.1170000404  |  +DATA/CRMPRD_B/CONTROLFILE/current.288.1160000303  |  +DATA/FINPRD_A/CONTROLFILE/current.261.1159000101,  |  +DATA/HRPRD/CONTROLFILE/current.270.1149000202,  |  DIFF  |
  |                      |                                                  |                                                     |  +RECO/FINPRD_A/CONTROLFILE/current.256.1159000101   |  +RECO/HRPRD/CONTROLFILE/current.260.1149000202   |        |
  |  log_archive_dest_1  |  -                                               |  LOCATION=USE_DB_RECOVERY_FILE_DEST                 |  LOCATION=USE_DB_RECOVERY_FILE_DEST                  |  LOCATION=USE_DB_RECOVERY_FILE_DEST               |  DIFF  |
  |                      |                                                  |  VALID_FOR=(ALL_LOGFILES,ALL_ROLES)                 |  VALID_FOR=(ALL_LOGFILES,ALL_ROLES)                  |                                                   |        |
  |                      |                                                  |  DB_UNIQUE_NAME=CRMPRD_B                            |  DB_UNIQUE_NAME=FINPRD_A                             |                                                   |        |
  +----------------------+--------------------------------------------------+-----------------------------------------------------+------------------------------------------------------+---------------------------------------------------+--------+
```

**Add one column per open PDB**

```text
$ dbparam open_cursors processes --pdbs --db FINPRD
  +----------------+----------+------------------+------------------+---------+
  |  PARAMETER     |  FINPRD  |  FINPRD/FINPDB1  |  FINPRD/FINPDB2  |  SAME   |
  +----------------+----------+------------------+------------------+---------+
  |  open_cursors  |  1000    |  2000            |  1000            |  DIFF   |
  |  processes     |  1500    |  1500            |  1500            |  MATCH  |
  +----------------+----------+------------------+------------------+---------+
```

**Every underscore parameter that is set**

```text
$ dbparam --hidden
  +-----------------------------+---------+-----------+--------------------------+--------------+--------+
  |  PARAMETER                  |  AIDEV  |  CRMSTBY  |  FINPRD                  |  HRPRD       |  SAME  |
  +-----------------------------+---------+-----------+--------------------------+--------------+--------+
  |  _fix_control               |  -      |  -        |  20107874:0, 22174392:1  |  20107874:0  |  DIFF  |
  |  _optimizer_adaptive_plans  |  -      |  -        |  FALSE                   |  -           |  DIFF  |
  +-----------------------------+---------+-----------+--------------------------+--------------+--------+
```

**Only differences, CSV (never wrapped)**

```text
$ dbparam processes sessions --diff --csv
PARAMETER,AIDEV,CRMSTBY,FINPRD,HRPRD,SAME
processes,400,1000,1500,600,DIFF
sessions,624,1528,2272,924,DIFF
```

<details>
<summary>Full <code>dbparam --help</code></summary>

```text
Usage: dbparam [PARAM|PATTERN ...] [--nondefault] [--hidden] [--diff] [--pdbs | --pdb REGEX]
               [--width N] [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
               [--csv|--json|--raw] [--no-header] [--no-color]

Shows parameters side by side: one row per parameter, one column per database
(and per PDB with --pdbs), plus SAME = MATCH / DIFF.
Values come from v$system_parameter (display_value).

Selecting parameters (at least one is required):
  PARAM            Exact name, e.g. processes sga_target
  PATTERN          SQL LIKE pattern, e.g. 'pga%'  'db_%size'
  --nondefault     Every parameter explicitly set (isdefault = FALSE)
  --hidden         Every underscore (_) parameter that is set

Options:
  --diff           Only show parameters whose values differ between the columns
  --pdbs           Add one column per OPEN PDB, named SID/PDB (value seen inside the PDB,
                   i.e. the PDB's own setting or the value inherited from CDB$ROOT)
  --pdb REGEX      Like --pdbs, but only PDBs whose name matches REGEX
  --width N        Table mode only: wrap values longer than N characters at spaces
                   (default: 40, 0 = no wrapping). CSV/JSON/raw output is never wrapped.
  --db REGEX       Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Notes:
  - '-' means the parameter is not set / not present in that database or PDB.
  - The SID column of a CDB shows the CDB$ROOT value.
  - Non-CDBs simply have no SID/PDB columns.

Examples:
  dbparam processes sessions sga_target pga_aggregate_target
  dbparam 'pga%' 'sga%'
  dbparam control_files 'log_archive_dest_%'
  dbparam --nondefault --diff
  dbparam --hidden --pdbs
  dbparam open_cursors --pdb '^APP'
```

</details>

[Back to the function list](#function-reference)

### dbjobs

Scheduler job runs that did not succeed, broken scheduler jobs and broken DBMS_JOB jobs.

**Features**

- Detail per run (status, time, error number, additional info) or `--summary` per job
- `--hours N` window (default 24)
- Return code 2 when failures are found

**Usage**

```text
dbjobs [--hours N] [--summary] [--db REGEX]
       [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Failed and broken scheduler jobs of the last 24 hours**

```text
$ dbjobs
  +-----------+------------+----------+-------------------------+---------------------+--------------------+----------+-----------------------------------------------------------------+
  |  DB       |  CON       |  OWNER   |  JOB_NAME               |  STATUS             |  LOG_DATE          |  ERROR#  |  DETAIL                                                         |
  +-----------+------------+----------+-------------------------+---------------------+--------------------+----------+-----------------------------------------------------------------+
  |  CRMSTBY  |  -         |  -       |  -                      |  SKIPPED (MOUNTED)  |  -                 |  -       |  -                                                              |
  |  FINPRD   |  FINPDB1   |  FIN     |  GL_NIGHTLY_LOAD        |  FAILED             |  2026-11-25 00:31  |  1013    |  ORA-01013: user requested cancel of current operation          |
  |  FINPRD   |  FINPDB1   |  FIN     |  GL_NIGHTLY_LOAD        |  FAILED             |  2026-11-24 00:31  |  1013    |  ORA-01013: user requested cancel of current operation          |
  |  FINPRD   |  CDB$ROOT  |  SYS     |  ORA$AT_OS_OPT_SY_8812  |  STOPPED            |  2026-11-25 02:31  |  0       |  REASON="Stop job called because associated window was closed"  |
  |  FINPRD   |  FINPDB2   |  ARCH    |  PURGE_AUDIT            |  BROKEN             |  2026-11-22 06:31  |  -       |  failure_count=16                                               |
  |  FINPRD   |  -         |  LEGACY  |  DBMS_JOB 42            |  BROKEN             |  2026-11-05 06:31  |  -       |  failures=16                                                    |
  +-----------+------------+----------+-------------------------+---------------------+--------------------+----------+-----------------------------------------------------------------+
```

**One row per job with the failure count**

```text
$ dbjobs --summary
  +-----------+------------+----------+-------------------------+---------------------+--------------------+---------------+
  |  DB       |  CON       |  OWNER   |  JOB_NAME               |  FAILURES           |  LAST_FAILURE      |  LAST_ERROR#  |
  +-----------+------------+----------+-------------------------+---------------------+--------------------+---------------+
  |  CRMSTBY  |  -         |  -       |  -                      |  SKIPPED (MOUNTED)  |  -                 |  -            |
  |  FINPRD   |  FINPDB1   |  FIN     |  GL_NIGHTLY_LOAD        |  2                  |  2026-11-25 00:31  |  1013         |
  |  FINPRD   |  CDB$ROOT  |  SYS     |  ORA$AT_OS_OPT_SY_8812  |  1                  |  2026-11-25 02:31  |  0            |
  |  FINPRD   |  FINPDB2   |  ARCH    |  PURGE_AUDIT            |  1                  |  2026-11-22 06:31  |  -            |
  |  FINPRD   |  -         |  LEGACY  |  DBMS_JOB 42            |  1                  |  2026-11-05 06:31  |  -            |
  +-----------+------------+----------+-------------------------+---------------------+--------------------+---------------+
```

**Last 7 days without the automatic maintenance jobs**

```text
$ dbjobs --hours 168 --grep-v 'ORA[$]AT_'
  +-----------+-----------+----------+-------------------+---------------------+--------------------+----------+---------------------------------------------------------+
  |  DB       |  CON      |  OWNER   |  JOB_NAME         |  STATUS             |  LOG_DATE          |  ERROR#  |  DETAIL                                                 |
  +-----------+-----------+----------+-------------------+---------------------+--------------------+----------+---------------------------------------------------------+
  |  CRMSTBY  |  -        |  -       |  -                |  SKIPPED (MOUNTED)  |  -                 |  -       |  -                                                      |
  |  FINPRD   |  FINPDB1  |  FIN     |  GL_NIGHTLY_LOAD  |  FAILED             |  2026-11-25 00:31  |  1013    |  ORA-01013: user requested cancel of current operation  |
  |  FINPRD   |  FINPDB1  |  FIN     |  GL_NIGHTLY_LOAD  |  FAILED             |  2026-11-24 00:31  |  1013    |  ORA-01013: user requested cancel of current operation  |
  |  FINPRD   |  FINPDB2  |  ARCH    |  PURGE_AUDIT      |  BROKEN             |  2026-11-22 06:31  |  -       |  failure_count=16                                       |
  |  FINPRD   |  -        |  LEGACY  |  DBMS_JOB 42      |  BROKEN             |  2026-11-05 06:31  |  -       |  failures=16                                            |
  +-----------+-----------+----------+-------------------+---------------------+--------------------+----------+---------------------------------------------------------+
```

<details>
<summary>Full <code>dbjobs --help</code></summary>

```text
Usage: dbjobs [--hours N] [--summary] [--db REGEX]
              [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Scheduler job runs that did not succeed (CDB_SCHEDULER_JOB_RUN_DETAILS) within
the window, plus jobs currently BROKEN (scheduler) and broken DBMS_JOB jobs.

Detail (default): DB, CON, OWNER, JOB_NAME, STATUS, LOG_DATE, ERROR#, DETAIL
--summary:        DB, CON, OWNER, JOB_NAME, FAILURES, LAST_FAILURE, LAST_ERROR#

Options:
  --hours N      Look-back window in hours (default: 24)
  --summary      One row per job with the failure count
  --db REGEX     Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v  Filter rows, e.g. --grep-v 'ORA\$AT_'  (hide automatic maintenance jobs)
  --csv|--json|--raw, --no-header, --no-color

Return code: 0 = none found, 2 = failures found, 1 = error

Examples:
  dbjobs
  dbjobs --hours 168 --summary
  dbjobs --grep-v 'ORA\$AT_'
```

</details>

[Back to the function list](#function-reference)

### dbrmancfg

RMAN persistent configuration side by side for every database.

**Features**

- Every `V$RMAN_CONFIGURATION` setting, plus block change tracking and `CONTROL_FILE_RECORD_KEEP_TIME`
- `(default)` when a setting is not configured; MATCH / DIFF per row, `--diff` for differences only
- Long values wrap in table mode (`--width`)

**Usage**

```text
dbrmancfg [--diff] [--width N] [--db REGEX]
          [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**RMAN configuration side by side**

```text
$ dbrmancfg
  +---------------------------------+-------------+-------------------------------------------+-------------------------------------------+-------------------------------------+--------+
  |  SETTING                        |  AIDEV      |  CRMSTBY                                  |  FINPRD                                   |  HRPRD                              |  SAME  |
  +---------------------------------+-------------+-------------------------------------------+-------------------------------------------+-------------------------------------+--------+
  |  ARCHIVELOG DELETION POLICY     |  (default)  |  TO APPLIED ON ALL STANDBY                |  TO APPLIED ON ALL STANDBY BACKED UP 1    |  (default)                          |  DIFF  |
  |                                 |             |                                           |  TIMES TO DEVICE TYPE SBT_TAPE            |                                     |        |
  |  BLOCK CHANGE TRACKING          |  DISABLED   |  ENABLED                                  |  ENABLED                                  |  DISABLED                           |  DIFF  |
  |  CHANNEL                        |  (default)  |  DEVICE TYPE 'SBT_TAPE' PARMS             |  DEVICE TYPE 'SBT_TAPE' PARMS             |  (default)                          |  DIFF  |
  |                                 |             |  'SBT_LIBRARY=/opt/backup/lib/libobk.so'  |  'SBT_LIBRARY=/opt/backup/lib/libobk.so'  |                                     |        |
  |  COMPRESSION ALGORITHM          |  (default)  |  (default)                                |  'MEDIUM' AS OF RELEASE 'DEFAULT'         |  (default)                          |  DIFF  |
  |                                 |             |                                           |  OPTIMIZE FOR LOAD TRUE                   |                                     |        |
  |  CONTROLFILE AUTOBACKUP         |  (default)  |  ON                                       |  ON                                       |  ON                                 |  DIFF  |
  |  CONTROL_FILE_RECORD_KEEP_TIME  |  7          |  30                                       |  30                                       |  30                                 |  DIFF  |
  |  DEVICE TYPE                    |  (default)  |  SBT_TAPE PARALLELISM 4 BACKUP TYPE TO    |  SBT_TAPE PARALLELISM 4 BACKUP TYPE TO    |  DISK PARALLELISM 2 BACKUP TYPE TO  |  DIFF  |
  |                                 |             |  BACKUPSET                                |  BACKUPSET                                |  COMPRESSED BACKUPSET               |        |
  |  RETENTION POLICY               |  (default)  |  TO RECOVERY WINDOW OF 14 DAYS            |  TO RECOVERY WINDOW OF 14 DAYS            |  TO RECOVERY WINDOW OF 7 DAYS       |  DIFF  |
  +---------------------------------+-------------+-------------------------------------------+-------------------------------------------+-------------------------------------+--------+
```

**Only some settings**

```text
$ dbrmancfg --diff --grep 'RETENTION|TRACKING'
  +-------------------------+-------------+---------------------------------+---------------------------------+--------------------------------+--------+
  |  SETTING                |  AIDEV      |  CRMSTBY                        |  FINPRD                         |  HRPRD                         |  SAME  |
  +-------------------------+-------------+---------------------------------+---------------------------------+--------------------------------+--------+
  |  BLOCK CHANGE TRACKING  |  DISABLED   |  ENABLED                        |  ENABLED                        |  DISABLED                      |  DIFF  |
  |  RETENTION POLICY       |  (default)  |  TO RECOVERY WINDOW OF 14 DAYS  |  TO RECOVERY WINDOW OF 14 DAYS  |  TO RECOVERY WINDOW OF 7 DAYS  |  DIFF  |
  +-------------------------+-------------+---------------------------------+---------------------------------+--------------------------------+--------+
```

**CSV output**

```text
$ dbrmancfg --csv --grep 'RETENTION'
SETTING,AIDEV,CRMSTBY,FINPRD,HRPRD,SAME
RETENTION POLICY,(default),TO RECOVERY WINDOW OF 14 DAYS,TO RECOVERY WINDOW OF 14 DAYS,TO RECOVERY WINDOW OF 7 DAYS,DIFF
```

<details>
<summary>Full <code>dbrmancfg --help</code></summary>

```text
Usage: dbrmancfg [--diff] [--width N] [--db REGEX]
                 [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

RMAN persistent configuration of every running database side by side, one row per
setting, one column per database, plus SAME = MATCH / DIFF.

Rows:
  Every setting in V$RMAN_CONFIGURATION (RETENTION POLICY, CONTROLFILE AUTOBACKUP,
  DEVICE TYPE, CHANNEL, COMPRESSION ALGORITHM, ENCRYPTION ..., ARCHIVELOG DELETION POLICY,
  SNAPSHOT CONTROLFILE NAME ...). '(default)' = not configured (RMAN default applies).
  BLOCK CHANGE TRACKING   ENABLED / DISABLED (V$BLOCK_CHANGE_TRACKING)
  CONTROL_FILE_RECORD_KEEP_TIME   parameter value (days of backup history in the control file)

Options:
  --diff         Only settings that differ between the databases
  --width N      Table mode only: wrap values longer than N characters (default 40, 0 = off)
  --db REGEX     Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Examples:
  dbrmancfg
  dbrmancfg --diff
  dbrmancfg --grep 'RETENTION|DELETION'
```

</details>

[Back to the function list](#function-reference)

### dbfeatures

Feature usage from `DBA_FEATURE_USAGE_STATISTICS`, mapped to the option or management pack that usually licenses it.

**Features**

- Latest version row per feature: currently used, detected usages, first/last usage, last sample
- Mapping to Diagnostics / Tuning Pack, Partitioning, Advanced Compression, Advanced Security, Active Data Guard, In-Memory, RAC, Multitenant (more than 3 PDBs) ...
- `--current` for features in use now, `--all` for unmapped features too
- An indicator for license reviews, not a licensing determination (confirm with MOS Doc ID 1317265.1)

**Usage**

```text
dbfeatures [--all] [--current] [--db REGEX]
           [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Used features mapped to the option or pack that usually licenses them**

```text
$ dbfeatures
  +-----------+------------------------+---------------------------------+------------------+-------------------+---------------+--------------+---------------------+
  |  DB       |  OPTION_PACK           |  FEATURE                        |  CURRENTLY_USED  |  DETECTED_USAGES  |  FIRST_USAGE  |  LAST_USAGE  |  LAST_SAMPLE        |
  +-----------+------------------------+---------------------------------+------------------+-------------------+---------------+--------------+---------------------+
  |  AIDEV    |  Database In-Memory    |  In-Memory Column Store         |  TRUE            |  4                |  2026-10-26   |  2026-11-23  |  2026-11-22         |
  |  CRMSTBY  |  -                     |  -                              |  -               |  -                |  -            |  -           |  SKIPPED (MOUNTED)  |
  |  FINPRD   |  Diagnostics Pack      |  AWR Report                     |  TRUE            |  128              |  2024-03-01   |  2026-11-24  |  2026-11-22         |
  |  FINPRD   |  Diagnostics Pack      |  Automatic Workload Repository  |  TRUE            |  412              |  2024-01-10   |  2026-11-24  |  2026-11-22         |
  |  FINPRD   |  Partitioning          |  Partitioning (user)            |  TRUE            |  96               |  2024-01-10   |  2026-11-24  |  2026-11-22         |
  |  FINPRD   |  Tuning Pack           |  Real-Time SQL Monitoring       |  TRUE            |  33               |  2025-02-11   |  2026-11-17  |  2026-11-22         |
  |  FINPRD   |  Advanced Security     |  Transparent Data Encryption    |  TRUE            |  96               |  2024-01-10   |  2026-11-24  |  2026-11-22         |
  |  FINPRD   |  Advanced Compression  |  OLTP Table Compression         |  FALSE           |  2                |  2025-06-01   |  2025-06-02  |  2026-11-22         |
  |  HRPRD    |  Diagnostics Pack      |  AWR Report                     |  FALSE           |  3                |  2025-09-12   |  2025-09-12  |  2026-11-22         |
  +-----------+------------------------+---------------------------------+------------------+-------------------+---------------+--------------+---------------------+
Indicator only - confirm with MOS Doc ID 1317265.1 (options_packs_usage_statistics.sql) before any licensing decision.
```

**Features currently in use, including unmapped ones**

```text
$ dbfeatures --all --current --db FINPRD
  +----------+---------------------+----------------------------------------------------------+------------------+-------------------+---------------+--------------+---------------+
  |  DB      |  OPTION_PACK        |  FEATURE                                                 |  CURRENTLY_USED  |  DETECTED_USAGES  |  FIRST_USAGE  |  LAST_USAGE  |  LAST_SAMPLE  |
  +----------+---------------------+----------------------------------------------------------+------------------+-------------------+---------------+--------------+---------------+
  |  FINPRD  |  Diagnostics Pack   |  AWR Report                                              |  TRUE            |  128              |  2024-03-01   |  2026-11-24  |  2026-11-22   |
  |  FINPRD  |  Diagnostics Pack   |  Automatic Workload Repository                           |  TRUE            |  412              |  2024-01-10   |  2026-11-24  |  2026-11-22   |
  |  FINPRD  |  Partitioning       |  Partitioning (user)                                     |  TRUE            |  96               |  2024-01-10   |  2026-11-24  |  2026-11-22   |
  |  FINPRD  |  Tuning Pack        |  Real-Time SQL Monitoring                                |  TRUE            |  33               |  2025-02-11   |  2026-11-17  |  2026-11-22   |
  |  FINPRD  |  Advanced Security  |  Transparent Data Encryption                             |  TRUE            |  96               |  2024-01-10   |  2026-11-24  |  2026-11-22   |
  |  FINPRD  |  -                  |  Backup BASIC Compression                                |  TRUE            |  90               |  2024-01-10   |  2026-11-24  |  2026-11-22   |
  |  FINPRD  |  -                  |  Automatic Maintenance - Optimizer Statistics Gathering  |  TRUE            |  99               |  2024-01-10   |  2026-11-24  |  2026-11-22   |
  +----------+---------------------+----------------------------------------------------------+------------------+-------------------+---------------+--------------+---------------+
Indicator only - confirm with MOS Doc ID 1317265.1 (options_packs_usage_statistics.sql) before any licensing decision.
```

<details>
<summary>Full <code>dbfeatures --help</code></summary>

```text
Usage: dbfeatures [--all] [--current] [--db REGEX]
                  [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Feature usage recorded by the database (DBA_FEATURE_USAGE_STATISTICS, latest version
row per feature, DETECTED_USAGES > 0), mapped to the Oracle option or management pack
that usually licenses it.

Columns: DB, OPTION_PACK, FEATURE, CURRENTLY_USED, DETECTED_USAGES, FIRST_USAGE,
         LAST_USAGE, LAST_SAMPLE
  OPTION_PACK  Diagnostics Pack, Tuning Pack, Partitioning, Advanced Compression,
               Advanced Security, Active Data Guard, Database In-Memory, RAC,
               Real Application Testing, Label Security, Database Vault, OLAP,
               Multitenant ... ('-' = not mapped, shown with --all)

Options:
  --all          Also list used features that are not mapped to an option or pack
  --current      Only features with CURRENTLY_USED = TRUE
  --db REGEX     Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

IMPORTANT - this is an indicator, not a licensing determination:
  - Usage statistics are sampled weekly; some features are recorded although they were
    only used by Oracle-internal or default jobs.
  - The mapping above is simplified. For a review use Oracle's official script from
    My Oracle Support Doc ID 1317265.1 (options_packs_usage_statistics.sql) and your
    Oracle license agreement / LMS contact.
  - Reading the usage view itself needs no extra license.

Examples:
  dbfeatures
  dbfeatures --current
  dbfeatures --grep 'Compression|Diagnostics' --csv
```

</details>

[Back to the function list](#function-reference)

### dbservices

Application services: how Clusterware / Oracle Restart is configured to run them versus where they run now.

**Features**

- Configuration from `srvctl config service` (role, PDB, preferred and available instances)
- Running instances from `GV$ACTIVE_SERVICES`
- OK, WARN (relocated / not on all preferred instances), DOWN, `OK (role)` for role-based services, `RUNNING (not in CRS)`
- `--issues` for problem rows only; return code 2 when DOWN or WARN exist

**Usage**

```text
dbservices [--issues] [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
           [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Configured (srvctl) vs running (GV$ACTIVE_SERVICES) services**

```text
$ dbservices
  +----------+-------------+-----------+--------------------+-------------+-------------+--------------+------------------------------+
  |  DB      |  SERVICE    |  PDB      |  ROLE              |  PREFERRED  |  AVAILABLE  |  RUNNING_ON  |  STATUS                      |
  +----------+-------------+-----------+--------------------+-------------+-------------+--------------+------------------------------+
  |  FINPRD  |  fin_adhoc  |  FINPDB2  |  -                 |  -          |  -          |  FINPRD      |  RUNNING (not in CRS)        |
  |  FINPRD  |  fin_batch  |  FINPDB1  |  PRIMARY           |  FINPRD     |  -          |  FINPRD      |  OK                          |
  |  FINPRD  |  fin_oltp   |  FINPDB1  |  PRIMARY           |  FINPRD     |  -          |  FINPRD      |  OK                          |
  |  FINPRD  |  fin_ro     |  FINPDB1  |  PHYSICAL_STANDBY  |  FINPRD     |  -          |  -           |  OK (role PHYSICAL_STANDBY)  |
  |  FINPRD  |  fin_rpt    |  FINPDB2  |  PRIMARY           |  FINPRD     |  -          |  -           |  DOWN                        |
  |  HRPRD   |  hr_app     |  -        |  -                 |  -          |  -          |  HRPRD       |  RUNNING (not in CRS)        |
  +----------+-------------+-----------+--------------------+-------------+-------------+--------------+------------------------------+
```

**Only services that are down, relocated or not in CRS**

```text
$ dbservices --issues
  +----------+-----------+-----------+-----------+-------------+-------------+--------------+----------+
  |  DB      |  SERVICE  |  PDB      |  ROLE     |  PREFERRED  |  AVAILABLE  |  RUNNING_ON  |  STATUS  |
  +----------+-----------+-----------+-----------+-------------+-------------+--------------+----------+
  |  FINPRD  |  fin_rpt  |  FINPDB2  |  PRIMARY  |  FINPRD     |  -          |  -           |  DOWN    |
  +----------+-----------+-----------+-----------+-------------+-------------+--------------+----------+
```

<details>
<summary>Full <code>dbservices --help</code></summary>

```text
Usage: dbservices [--issues] [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
                  [--csv|--json|--raw] [--no-header] [--no-color]

Application services of every running database: the configuration in Clusterware /
Oracle Restart (srvctl config service) compared with where each service is running now
(GV$ACTIVE_SERVICES). Use it before and after rolling / out-of-place patching to see
which services must be relocated or restarted.

Columns: DB, SERVICE, PDB, ROLE, PREFERRED, AVAILABLE, RUNNING_ON, STATUS
  ROLE        service role from srvctl (PRIMARY, PHYSICAL_STANDBY ...)
  RUNNING_ON  instance(s) the service is active on
  STATUS      OK          running on all preferred instances
              WARN        running on an available (non-preferred) instance - relocated -
                          or only on some preferred instances
              DOWN        not running although its role matches the database role
              OK (role)   not running because its role does not match the database role
              RUNNING (not in CRS)  created with DBMS_SERVICE / SERVICE_NAMES only

Internal services (SYS$*, the default DB_UNIQUE_NAME / PDB services, XDB) are hidden.

Options:
  --issues       Only rows that are not OK
  --db REGEX     Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Return code: 0 = all OK, 2 = DOWN or WARN found, 1 = error

Examples:
  dbservices
  dbservices --issues
```

</details>

[Back to the function list](#function-reference)

## Data Guard

### dbdglag

Data Guard broker status and transport / apply lag of every member, as a table.

**Features**

- One database (`dbdglag SID`, RAC instance names accepted) or `--all`
- LAG_STATUS OK / WARN / CRIT from the larger of the two lags (`--warn 300`, `--crit 1800` seconds by default)
- Databases without a broker configuration show `NO_BROKER` instead of an error
- Return code 2 when a member is CRIT

**Usage**

```text
dbdglag [--db] <ORACLE_SID> | --all
        [--warn SECONDS] [--crit SECONDS]
        [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header]
```

**Examples**

**Broker status and lag of every member of every configuration**

```text
$ dbdglag --all
  +-----------+--------------------+-----------------+------------+-----------------------------+------------------------+------------------------+--------------+
  |  SID      |  DB_ROLE           |  CONFIG_STATUS  |  MEMBER    |  MEMBER_ROLE                |  TRANSPORT_LAG         |  APPLY_LAG             |  LAG_STATUS  |
  +-----------+--------------------+-----------------+------------+-----------------------------+------------------------+------------------------+--------------+
  |  AIDEV    |  PRIMARY           |  NO_BROKER      |  -         |  -                          |  -                     |  -                     |  -           |
  |  CRMSTBY  |  PHYSICAL STANDBY  |  SUCCESS        |  CRMPRD_A  |  Primary database           |  -                     |  -                     |  PRIMARY     |
  |  CRMSTBY  |  PHYSICAL STANDBY  |  SUCCESS        |  CRMPRD_B  |  Physical standby database  |  0 seconds             |  3 seconds             |  OK          |
  |  FINPRD   |  PRIMARY           |  WARNING        |  FINPRD_A  |  Primary database           |  -                     |  -                     |  PRIMARY     |
  |  FINPRD   |  PRIMARY           |  WARNING        |  FINPRD_B  |  Physical standby database  |  0 seconds             |  12 seconds            |  OK          |
  |  FINPRD   |  PRIMARY           |  WARNING        |  FINPRD_C  |  Physical standby database  |  4 minutes 10 seconds  |  38 minutes 2 seconds  |  CRIT        |
  |  HRPRD    |  PRIMARY           |  NO_BROKER      |  -         |  -                          |  -                     |  -                     |  -           |
  +-----------+--------------------+-----------------+------------+-----------------------------+------------------------+------------------------+--------------+
```

**One database, custom thresholds**

```text
$ dbdglag FINPRD --warn 60 --crit 1800
  +----------+-----------+-----------------+------------+-----------------------------+------------------------+------------------------+--------------+
  |  SID     |  DB_ROLE  |  CONFIG_STATUS  |  MEMBER    |  MEMBER_ROLE                |  TRANSPORT_LAG         |  APPLY_LAG             |  LAG_STATUS  |
  +----------+-----------+-----------------+------------+-----------------------------+------------------------+------------------------+--------------+
  |  FINPRD  |  PRIMARY  |  WARNING        |  FINPRD_A  |  Primary database           |  -                     |  -                     |  PRIMARY     |
  |  FINPRD  |  PRIMARY  |  WARNING        |  FINPRD_B  |  Physical standby database  |  0 seconds             |  12 seconds            |  OK          |
  |  FINPRD  |  PRIMARY  |  WARNING        |  FINPRD_C  |  Physical standby database  |  4 minutes 10 seconds  |  38 minutes 2 seconds  |  CRIT        |
  +----------+-----------+-----------------+------------+-----------------------------+------------------------+------------------------+--------------+
```

**CSV without the databases that have no broker configuration**

```text
$ dbdglag --all --csv --grep -v NO_BROKER
SID,DB_ROLE,CONFIG_STATUS,MEMBER,MEMBER_ROLE,TRANSPORT_LAG,APPLY_LAG,LAG_STATUS
CRMSTBY,PHYSICAL STANDBY,SUCCESS,CRMPRD_A,Primary database,-,-,PRIMARY
CRMSTBY,PHYSICAL STANDBY,SUCCESS,CRMPRD_B,Physical standby database,0 seconds,3 seconds,OK
FINPRD,PRIMARY,WARNING,FINPRD_A,Primary database,-,-,PRIMARY
FINPRD,PRIMARY,WARNING,FINPRD_B,Physical standby database,0 seconds,12 seconds,OK
FINPRD,PRIMARY,WARNING,FINPRD_C,Physical standby database,4 minutes 10 seconds,38 minutes 2 seconds,CRIT
```

<details>
<summary>Full <code>dbdglag --help</code></summary>

```text

Usage: dbdglag [--db] <ORACLE_SID> | --all
               [--warn SECONDS] [--crit SECONDS]
               [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header]

Description:
  Shows the Data Guard Broker configuration status and the transport/apply lag
  of every standby member, as a table (one row per member).

Options:
  --db <ORACLE_SID>   Check one database (RAC: DB name or instance name)
  <ORACLE_SID>        Same as --db
  --all               Check all running databases on the host
  --warn SECONDS      Lag threshold for WARN (default: 300)
  --crit SECONDS      Lag threshold for CRIT (default: 1800)
  --grep / --grep-v   Filter rows (case-insensitive regex)
  -h, --help          Show help

Columns:
  SID, DB_ROLE, CONFIG_STATUS, MEMBER, MEMBER_ROLE, TRANSPORT_LAG, APPLY_LAG, LAG_STATUS
  LAG_STATUS: OK / WARN / CRIT from the larger of the two lags; PRIMARY for the
  primary member; UNKNOWN when the lag could not be determined.
  CONFIG_STATUS NO_BROKER means the database has no broker configuration (not an error).

Return code:
  0 = all OK/WARN, 1 = an error occurred, 2 = at least one member is CRIT

Examples:
  dbdglag --db PRDDB
  dbdglag PRDDB1
  dbdglag --all
  dbdglag --all --warn 60 --crit 600 --csv
```

</details>

[Back to the function list](#function-reference)

### dbdgcheck

Data Guard broker health per member: switchover / failover readiness, protection mode, FSFO and key properties.

**Features**

- `VALIDATE DATABASE` for every standby (Ready for Switchover / Failover)
- Broker properties from `SHOW DATABASE VERBOSE` - confirm that a property policy really took effect
- Property list with `--props` or `DBA_DG_PROPS`
- WARN when the configuration is in WARNING or a standby is not ready for switchover; CRIT for configuration ERROR

**Usage**

```text
dbdgcheck [--props P1,P2,...] [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
          [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Switchover / failover readiness and key broker properties per member**

```text
$ dbdgcheck
  +-----------+------------+--------------------+------------------+------------+--------------+-------------------------+--------------+-------------+--------------+---------------------+-------------------------+-------------------------+--------------------------------+
  |  DB       |  MEMBER    |  ROLE              |  PROTECTION      |  FSFO      |  SWITCHOVER  |  FAILOVER               |  LogXptMode  |  DelayMins  |  NetTimeout  |  ApplyLagThreshold  |  TransportLagThreshold  |  StandbyFileManagement  |  STATUS                        |
  +-----------+------------+--------------------+------------------+------------+--------------+-------------------------+--------------+-------------+--------------+---------------------+-------------------------+-------------------------+--------------------------------+
  |  AIDEV    |  -         |  -                 |  -               |  -         |  -           |  -                      |  -           |  -          |  -           |  -                  |  -                      |  -                      |  NO_BROKER                     |
  |  CRMSTBY  |  CRMPRD_A  |  Primary           |  MaxPerformance  |  Disabled  |  -           |  -                      |  ASYNC       |  0          |  30          |  30                 |  30                     |  AUTO                   |  OK                            |
  |  CRMSTBY  |  CRMPRD_B  |  Physical standby  |  MaxPerformance  |  Disabled  |  Yes         |  Yes (Primary Running)  |  ASYNC       |  0          |  30          |  30                 |  30                     |  AUTO                   |  OK                            |
  |  FINPRD   |  FINPRD_A  |  Primary           |  MaxPerformance  |  Disabled  |  -           |  -                      |  ASYNC       |  0          |  30          |  30                 |  30                     |  AUTO                   |  WARN (configuration WARNING)  |
  |  FINPRD   |  FINPRD_B  |  Physical standby  |  MaxPerformance  |  Disabled  |  Yes         |  Yes (Primary Running)  |  ASYNC       |  0          |  30          |  30                 |  30                     |  AUTO                   |  WARN (configuration WARNING)  |
  |  FINPRD   |  FINPRD_C  |  Physical standby  |  MaxPerformance  |  Disabled  |  No          |  Yes (Primary Running)  |  SYNC        |  30         |  30          |  30                 |  30                     |  AUTO                   |  WARN (configuration WARNING)  |
  |  HRPRD    |  -         |  -                 |  -               |  -         |  -           |  -                      |  -           |  -          |  -           |  -                  |  -                      |  -                      |  NO_BROKER                     |
  +-----------+------------+--------------------+------------------+------------+--------------+-------------------------+--------------+-------------+--------------+---------------------+-------------------------+-------------------------+--------------------------------+
```

**Custom property list for one database**

```text
$ dbdgcheck --props LogXptMode,DelayMins --db FINPRD
  +----------+------------+--------------------+------------------+------------+--------------+-------------------------+--------------+-------------+--------------------------------+
  |  DB      |  MEMBER    |  ROLE              |  PROTECTION      |  FSFO      |  SWITCHOVER  |  FAILOVER               |  LogXptMode  |  DelayMins  |  STATUS                        |
  +----------+------------+--------------------+------------------+------------+--------------+-------------------------+--------------+-------------+--------------------------------+
  |  FINPRD  |  FINPRD_A  |  Primary           |  MaxPerformance  |  Disabled  |  -           |  -                      |  ASYNC       |  0          |  WARN (configuration WARNING)  |
  |  FINPRD  |  FINPRD_B  |  Physical standby  |  MaxPerformance  |  Disabled  |  Yes         |  Yes (Primary Running)  |  ASYNC       |  0          |  WARN (configuration WARNING)  |
  |  FINPRD  |  FINPRD_C  |  Physical standby  |  MaxPerformance  |  Disabled  |  No          |  Yes (Primary Running)  |  SYNC        |  30         |  WARN (configuration WARNING)  |
  +----------+------------+--------------------+------------------+------------+--------------+-------------------------+--------------+-------------+--------------------------------+
```

<details>
<summary>Full <code>dbdgcheck --help</code></summary>

```text
Usage: dbdgcheck [--props P1,P2,...] [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
                 [--csv|--json|--raw] [--no-header] [--no-color]

For every running database with a Data Guard broker configuration, one row per
configuration member:
  DB, MEMBER, ROLE, PROTECTION, FSFO, SWITCHOVER, FAILOVER, <properties>, STATUS

  SWITCHOVER / FAILOVER   'Ready for Switchover / Failover' from VALIDATE DATABASE
                          (standby members only)
  <properties>            Broker properties from SHOW DATABASE VERBOSE - use this to
                          confirm that a property policy (e.g. one applied by your
                          OEM onboarding tool) really took effect.
  STATUS                  CRIT  configuration status ERROR
                          WARN  configuration status WARNING, or not ready for switchover
                          OK    otherwise

Options:
  --props LIST   Comma-separated broker properties to show
                 (default: LogXptMode,DelayMins,NetTimeout,ApplyLagThreshold,
                  TransportLagThreshold,StandbyFileManagement; override with DBA_DG_PROPS)
  --db REGEX     Only check SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Notes:
  - VALIDATE DATABASE needs Oracle 12.1+. Databases without a broker configuration
    are listed with STATUS NO_BROKER.

Return code: 0 = all OK, 2 = WARN/CRIT found, 1 = error

Examples:
  dbdgcheck
  dbdgcheck --props LogXptMode,DelayMins,ApplyInstanceTimeout
```

</details>

[Back to the function list](#function-reference)

## Patching and upgrades

### dbdatapatch

Answers "is this database fully patched?" - compares the RU/OJVM/Datapump patches in the running home with what datapatch applied in every container.

**Features**

- HOME_RU (binaries) vs SQL_RU (latest successful datapatch RU)
- MISSING = patch in the home without a successful APPLY in this container; FAILED = latest datapatch action not SUCCESS
- STATUS OK / PENDING (run datapatch) / FAILED
- Mounted standbys are skipped (datapatch runs on the primary)

**Usage**

```text
dbdatapatch [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
            [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Binary RU/OJVM/Datapump patches vs what datapatch applied, per container**

```text
$ dbdatapatch
Reading patches of /u01/app/oracle/product/23.26.1/dbhome_1 - please wait...
Reading patches of /u01/app/oracle/product/19.32.0/dbhome_1 - please wait...
Reading patches of /u01/app/oracle/product/19.31.0/dbhome_1 - please wait...
  +-----------+------------+--------------------+--------------------+------------+------------+-----------------------------------------+
  |  DB       |  CON       |  HOME_RU           |  SQL_RU            |  MISSING   |  FAILED    |  STATUS                                 |
  +-----------+------------+--------------------+--------------------+------------+------------+-----------------------------------------+
  |  AIDEV    |  CDB$ROOT  |  23.26.1.0.0       |  23.26.1.0.0       |  -         |  -         |  OK                                     |
  |  AIDEV    |  AIPDB1    |  23.26.1.0.0       |  23.26.1.0.0       |  -         |  -         |  OK                                     |
  |  CRMSTBY  |  -         |  19.32.0.0.260721  |  -                 |  -         |  -         |  SKIPPED (MOUNTED - check the primary)  |
  |  FINPRD   |  CDB$ROOT  |  19.32.0.0.260721  |  19.32.0.0.260721  |  -         |  -         |  OK                                     |
  |  FINPRD   |  FINPDB1   |  19.32.0.0.260721  |  19.32.0.0.260721  |  -         |  39388555  |  FAILED                                 |
  |  FINPRD   |  FINPDB2   |  19.32.0.0.260721  |  19.32.0.0.260721  |  39222882  |  -         |  PENDING (run datapatch)                |
  |  HRPRD    |  -         |  19.31.0.0.260415  |  19.31.0.0.260415  |  -         |  -         |  OK                                     |
  +-----------+------------+--------------------+--------------------+------------+------------+-----------------------------------------+
```

**Only the containers that need datapatch attention**

```text
$ dbdatapatch --grep 'PENDING|FAILED'
Reading patches of /u01/app/oracle/product/23.26.1/dbhome_1 - please wait...
Reading patches of /u01/app/oracle/product/19.32.0/dbhome_1 - please wait...
Reading patches of /u01/app/oracle/product/19.31.0/dbhome_1 - please wait...
  +----------+-----------+--------------------+--------------------+------------+------------+---------------------------+
  |  DB      |  CON      |  HOME_RU           |  SQL_RU            |  MISSING   |  FAILED    |  STATUS                   |
  +----------+-----------+--------------------+--------------------+------------+------------+---------------------------+
  |  FINPRD  |  FINPDB1  |  19.32.0.0.260721  |  19.32.0.0.260721  |  -         |  39388555  |  FAILED                   |
  |  FINPRD  |  FINPDB2  |  19.32.0.0.260721  |  19.32.0.0.260721  |  39222882  |  -         |  PENDING (run datapatch)  |
  +----------+-----------+--------------------+--------------------+------------+------------+---------------------------+
```

<details>
<summary>Full <code>dbdatapatch --help</code></summary>

```text
Usage: dbdatapatch [--db REGEX] [--grep PATTERN] [--grep-v PATTERN]
                   [--csv|--json|--raw] [--no-header] [--no-color]

Answers "is this database fully patched?" for every running database and every
OPEN container (CDB$ROOT and PDBs).

The SQL-relevant patches installed in the RUNNING home (opatch lspatches: Release
Update, OJVM, Datapump bundle) are compared with CDB_REGISTRY_SQLPATCH (latest
action per patch):

  HOME_RU    Release Update installed in the running home's binaries
  SQL_RU     Latest Release Update successfully applied by datapatch
  MISSING    Binary patch IDs with no successful APPLY in this container
  FAILED     Binary patch IDs whose latest datapatch action did not succeed
  STATUS     OK / PENDING (run datapatch) / FAILED (datapatch errors - check the
             logs under $ORACLE_BASE/cfgtoollogs/sqlpatch)

Options:
  --db REGEX     Only query SIDs matching REGEX (case-insensitive)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Notes:
  - MOUNTED standbys are skipped: datapatch runs on the primary and is replicated.
  - Running 'opatch lspatches' takes a few seconds per home.

Return code: 0 = all OK, 2 = PENDING or FAILED found, 1 = error

Examples:
  dbdatapatch
  dbdatapatch --grep -v OK
```

</details>

[Back to the function list](#function-reference)

### ohdiff

Compares the patches of two Oracle homes - typically the old and new home of an out-of-place patch.

**Features**

- `ohdiff OLD_HOME NEW_HOME` or `ohdiff SID` (running home vs oratab home)
- ADDED (new home only), REPLACED (bundle only in the old home), MISSING (one-off only in the old home - re-apply or confirm it is in the new RU)
- `--ignore-oneoff [IDS]` accepts missing one-offs (shown as `MISSING (ignored)`, return code stays 0)
- `--all` also shows patches present in both homes

**Usage**

```text
ohdiff OLD_HOME NEW_HOME [--all] [--ignore-oneoff [ID1,ID2,...]] [--grep PATTERN] [--grep-v PATTERN]
       [--csv|--json|--raw] [--no-header] [--no-color]
ohdiff SID [...]     OLD = home the instance is RUNNING from, NEW = home in oratab
```

**Examples**

**Old (running) home vs new (oratab) home of a database**

```text
$ ohdiff HRPRD
OLD (running): /u01/app/oracle/product/19.31.0/dbhome_1
NEW (oratab) : /u01/app/oracle/product/19.32.0/dbhome_1
Running opatch lspatches on both homes - please wait...
  +------------+------------+------------------------------------------------------------------------+-------+-------+------------+
  |  PATCH_ID  |  TYPE      |  DESCRIPTION                                                           |  OLD  |  NEW  |  STATUS    |
  +------------+------------+------------------------------------------------------------------------+-------+-------+------------+
  |  37011234  |  ONE-OFF   |  Bug 37011234 - Wrong results with adaptive plans                      |  yes  |  -    |  MISSING   |
  |  38500777  |  ONE-OFF   |  Bug 38500777 - High CPU in LGWR with many redo threads                |  yes  |  -    |  MISSING   |
  |  38870444  |  JDK       |  JDK BUNDLE PATCH 19.0.0.0.260415                                      |  yes  |  -    |  REPLACED  |
  |  38871002  |  RU        |  Database Release Update : 19.31.0.0.260415 (38871002)                 |  yes  |  -    |  REPLACED  |
  |  38877001  |  OCW       |  OCW RELEASE UPDATE 19.31.0.0.0 (38877001)                             |  yes  |  -    |  REPLACED  |
  |  38900113  |  OJVM      |  OJVM RELEASE UPDATE: 19.31.0.0.260415 (38900113)                      |  yes  |  -    |  REPLACED  |
  |  38955210  |  DATAPUMP  |  DATAPUMP BUNDLE PATCH 19.31.0.0.0 (38955210)                          |  yes  |  -    |  REPLACED  |
  |  39222882  |  OJVM      |  OJVM RELEASE UPDATE: 19.32.0.0.260721 (39222882)                      |  -    |  yes  |  ADDED     |
  |  39388555  |  DATAPUMP  |  DATAPUMP BUNDLE PATCH 19.32.0.0.0 (39388555)                          |  -    |  yes  |  ADDED     |
  |  39412201  |  JDK       |  JDK BUNDLE PATCH 19.0.0.0.260818                                      |  -    |  yes  |  ADDED     |
  |  39467003  |  OCW       |  OCW RELEASE UPDATE 19.32.0.0.0 (39467003)                             |  -    |  yes  |  ADDED     |
  |  39472050  |  RU        |  Database Release Update : 19.32.0.0.260721 (39472050)                 |  -    |  yes  |  ADDED     |
  |  39500111  |  ONE-OFF   |  Bug 39500111 - ORA-00600 [kcbz_check_objd_typ_3] during parallel DML  |  -    |  yes  |  ADDED     |
  +------------+------------+------------------------------------------------------------------------+-------+-------+------------+
```

**Accept one missing one-off patch**

```text
$ ohdiff HRPRD --ignore-oneoff 37011234
OLD (running): /u01/app/oracle/product/19.31.0/dbhome_1
NEW (oratab) : /u01/app/oracle/product/19.32.0/dbhome_1
Running opatch lspatches on both homes - please wait...
  +------------+------------+------------------------------------------------------------------------+-------+-------+---------------------+
  |  PATCH_ID  |  TYPE      |  DESCRIPTION                                                           |  OLD  |  NEW  |  STATUS             |
  +------------+------------+------------------------------------------------------------------------+-------+-------+---------------------+
  |  37011234  |  ONE-OFF   |  Bug 37011234 - Wrong results with adaptive plans                      |  yes  |  -    |  MISSING (ignored)  |
  |  38500777  |  ONE-OFF   |  Bug 38500777 - High CPU in LGWR with many redo threads                |  yes  |  -    |  MISSING            |
  |  38870444  |  JDK       |  JDK BUNDLE PATCH 19.0.0.0.260415                                      |  yes  |  -    |  REPLACED           |
  |  38871002  |  RU        |  Database Release Update : 19.31.0.0.260415 (38871002)                 |  yes  |  -    |  REPLACED           |
  |  38877001  |  OCW       |  OCW RELEASE UPDATE 19.31.0.0.0 (38877001)                             |  yes  |  -    |  REPLACED           |
  |  38900113  |  OJVM      |  OJVM RELEASE UPDATE: 19.31.0.0.260415 (38900113)                      |  yes  |  -    |  REPLACED           |
  |  38955210  |  DATAPUMP  |  DATAPUMP BUNDLE PATCH 19.31.0.0.0 (38955210)                          |  yes  |  -    |  REPLACED           |
  |  39222882  |  OJVM      |  OJVM RELEASE UPDATE: 19.32.0.0.260721 (39222882)                      |  -    |  yes  |  ADDED              |
  |  39388555  |  DATAPUMP  |  DATAPUMP BUNDLE PATCH 19.32.0.0.0 (39388555)                          |  -    |  yes  |  ADDED              |
  |  39412201  |  JDK       |  JDK BUNDLE PATCH 19.0.0.0.260818                                      |  -    |  yes  |  ADDED              |
  |  39467003  |  OCW       |  OCW RELEASE UPDATE 19.32.0.0.0 (39467003)                             |  -    |  yes  |  ADDED              |
  |  39472050  |  RU        |  Database Release Update : 19.32.0.0.260721 (39472050)                 |  -    |  yes  |  ADDED              |
  |  39500111  |  ONE-OFF   |  Bug 39500111 - ORA-00600 [kcbz_check_objd_typ_3] during parallel DML  |  -    |  yes  |  ADDED              |
  +------------+------------+------------------------------------------------------------------------+-------+-------+---------------------+
```

**Two homes, including common patches, one-offs only**

```text
$ ohdiff /u01/app/oracle/product/19.31.0/dbhome_1 /u01/app/oracle/product/19.32.0/dbhome_1 --all --grep ONE-OFF
Running opatch lspatches on both homes - please wait...
  +------------+-----------+------------------------------------------------------------------------+-------+-------+-----------+
  |  PATCH_ID  |  TYPE     |  DESCRIPTION                                                           |  OLD  |  NEW  |  STATUS   |
  +------------+-----------+------------------------------------------------------------------------+-------+-------+-----------+
  |  37011234  |  ONE-OFF  |  Bug 37011234 - Wrong results with adaptive plans                      |  yes  |  -    |  MISSING  |
  |  38500777  |  ONE-OFF  |  Bug 38500777 - High CPU in LGWR with many redo threads                |  yes  |  -    |  MISSING  |
  |  39500111  |  ONE-OFF  |  Bug 39500111 - ORA-00600 [kcbz_check_objd_typ_3] during parallel DML  |  -    |  yes  |  ADDED    |
  +------------+-----------+------------------------------------------------------------------------+-------+-------+-----------+
```

<details>
<summary>Full <code>ohdiff --help</code></summary>

```text
Usage: ohdiff OLD_HOME NEW_HOME [--all] [--ignore-oneoff [ID1,ID2,...]] [--grep PATTERN] [--grep-v PATTERN]
              [--csv|--json|--raw] [--no-header] [--no-color]
       ohdiff SID [...]     OLD = home the instance is RUNNING from, NEW = home in oratab

Compares 'opatch lspatches' of two homes - typically the old and new home of an
out-of-place patch - and shows what the new home adds and drops.

Columns: PATCH_ID, TYPE, DESCRIPTION, OLD, NEW, STATUS
  TYPE     RU, OJVM, DATAPUMP, OCW, ACFS, DBWLM, TOMCAT, JDK or ONE-OFF
  STATUS   SAME      in both homes                       (only shown with --all)
           ADDED     only in the new home
           REPLACED  bundle (RU/OJVM/...) only in the old home - normally replaced
                     by the newer bundle in the new home
           MISSING   ONE-OFF patch only in the old home: check whether it is
                     included in the new RU or must be re-applied to the new home

           MISSING (ignored)  as MISSING, but accepted with --ignore-oneoff

Options:
  --all          Also show patches present in both homes
  --ignore-oneoff [IDS]
                 Accept missing one-off patches: without IDS every missing one-off is
                 ignored, with a comma-separated list only those patch IDs. Ignored
                 patches are still listed (MISSING (ignored)) but do not affect the return code.
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Return code: 0 = no MISSING one-offs (or all ignored), 2 = MISSING one-off patches found, 1 = error

Examples:
  ohdiff /u01/app/oracle/product/19.31.0/dbhome_1 /u01/app/oracle/product/19.32.2/dbhome_1
  ohdiff PRD1
  ohdiff PRD1 --ignore-oneoff
  ohdiff PRD1 --ignore-oneoff 34567890,35111222
```

</details>

[Back to the function list](#function-reference)

### dbprecheck

Pre-patch / pre-upgrade GO / NO-GO checks per database, per container and for the host - built to be used by people and by Ansible.

**Features**

- Every check has an ID (`--list-checks`); `--ignore` accepts IDs and globs, ignored checks are still shown but do not count
- Database checks: open mode, RMAN backup, Data Guard lag, FRA, guaranteed restore points, running jobs and Data Pump, long transactions, blocked sessions, free space for a new home
- Container checks (CDB$ROOT and every PDB): registry, datapatch, invalid objects (Oracle-maintained = FAIL, others = WARN), recycle bin, dictionary and fixed-object statistics, SYSTEM/SYSAUX/UNDO/TEMP free space
- Host checks: swap, HugePages sizing against all SGAs, /tmp, OS / kernel / RU certification of every home
- `--target 19c|26ai|RU` adds target_os (and target_cdb for 26ai: non-CDBs must be converted)
- `--full` adds every `oscheck` row as `os.<ID>`; `--summary` / `--issues` to reduce the output
- Return code 0 = all GO, 2 = at least one NO-GO

**Usage**

```text
dbprecheck [--summary | --issues] [--full] [--target 19c|26ai|RU] [--ignore ID1,ID2,...] [--list-checks]
           [--min-free-gb N] [--db-hours N] [--db REGEX]
           [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**GO / NO-GO per database and for the host**

```text
$ dbprecheck --summary
  +-----------+-------+------------+-----------+-----------------------------+----------+
  |  DB       |  CON  |  CHECK_ID  |  CHECK    |  VALUE                      |  STATUS  |
  +-----------+-------+------------+-----------+-----------------------------+----------+
  |  AIDEV    |  -    |  overall   |  OVERALL  |  1 FAIL, 1 WARN, 0 ignored  |  NO-GO   |
  |  CRMSTBY  |  -    |  overall   |  OVERALL  |  0 FAIL, 0 WARN, 0 ignored  |  GO      |
  |  FINPRD   |  -    |  overall   |  OVERALL  |  4 FAIL, 8 WARN, 0 ignored  |  NO-GO   |
  |  HRPRD    |  -    |  overall   |  OVERALL  |  1 FAIL, 2 WARN, 0 ignored  |  NO-GO   |
  |  HOST     |  -    |  overall   |  OVERALL  |  2 FAIL, 0 WARN, 0 ignored  |  NO-GO   |
  +-----------+-------+------------+-----------+-----------------------------+----------+
```

**Every check that is not PASS for one database**

```text
$ dbprecheck --issues --db FINPRD
  +----------+------------+------------------+---------------------------------------+----------------------------------------------+----------+
  |  DB      |  CON       |  CHECK_ID        |  CHECK                                |  VALUE                                       |  STATUS  |
  +----------+------------+------------------+---------------------------------------+----------------------------------------------+----------+
  |  FINPRD  |  -         |  blocked         |  Blocked sessions                     |  2                                           |  WARN    |
  |  FINPRD  |  -         |  jobs_running    |  Running scheduler jobs               |  1                                           |  WARN    |
  |  FINPRD  |  -         |  fra             |  FRA usage                            |  82.5%                                       |  WARN    |
  |  FINPRD  |  -         |  dg_lag          |  Data Guard lag                       |  CRIT (see dbdglag)                          |  FAIL    |
  |  FINPRD  |  CDB$ROOT  |  invalid_other   |  Invalid objects (other schemas)      |  2                                           |  WARN    |
  |  FINPRD  |  FINPDB1   |  invalid_other   |  Invalid objects (other schemas)      |  37                                          |  WARN    |
  |  FINPRD  |  FINPDB1   |  recyclebin      |  Recycle bin objects                  |  214                                         |  WARN    |
  |  FINPRD  |  FINPDB1   |  stats_fixed     |  Fixed objects statistics             |  2026-11-20 06:31 (5.6 days ago)             |  WARN    |
  |  FINPRD  |  FINPDB1   |  ts_sysaux       |  Free space SYSAUX                    |  4.20 GB                                     |  FAIL    |
  |  FINPRD  |  FINPDB1   |  ts_undo         |  Free space UNDOTBS1                  |  3.80 GB                                     |  WARN    |
  |  FINPRD  |  FINPDB2   |  registry        |  Registry components                  |  APEX=INVALID                                |  FAIL    |
  |  FINPRD  |  FINPDB2   |  invalid_oracle  |  Invalid objects (Oracle-maintained)  |  3                                           |  FAIL    |
  |  FINPRD  |  -         |  overall         |  OVERALL                              |  4 FAIL, 8 WARN, 0 ignored                   |  NO-GO   |
  |  HOST    |  -         |  swap            |  Swap configured                      |  none                                        |  FAIL    |
  |  HOST    |  -         |  hugepages       |  HugePages (vm.nr_hugepages)          |  0 configured, 20013 required (2048K pages)  |  FAIL    |
  |  HOST    |  -         |  overall         |  OVERALL                              |  2 FAIL, 0 WARN, 0 ignored                   |  NO-GO   |
  +----------+------------+------------------+---------------------------------------+----------------------------------------------+----------+
```

**Ignore some checks (still shown, but not counted)**

```text
$ dbprecheck --summary --db FINPRD --ignore 'recyclebin,ts_*,stats_*,dg_lag'
  +----------+-------+------------+-----------+-----------------------------+----------+
  |  DB      |  CON  |  CHECK_ID  |  CHECK    |  VALUE                      |  STATUS  |
  +----------+-------+------------+-----------+-----------------------------+----------+
  |  FINPRD  |  -    |  overall   |  OVERALL  |  2 FAIL, 5 WARN, 5 ignored  |  NO-GO   |
  |  HOST    |  -    |  overall   |  OVERALL  |  2 FAIL, 0 WARN, 0 ignored  |  NO-GO   |
  +----------+-------+------------+-----------+-----------------------------+----------+
```

**Upgrade readiness for 26ai (non-CDB detection, OS certification)**

```text
$ dbprecheck --target 26ai --issues --db HRPRD
  +---------+-------+------------------+-----------------------------------+----------------------------------------------+----------+
  |  DB     |  CON  |  CHECK_ID        |  CHECK                            |  VALUE                                       |  STATUS  |
  +---------+-------+------------------+-----------------------------------+----------------------------------------------+----------+
  |  HRPRD  |  -    |  target_cdb      |  26ai: multitenant (CDB)          |  non-CDB - convert to a PDB first            |  FAIL    |
  |  HRPRD  |  -    |  restore_points  |  Guaranteed restore points        |  1                                           |  WARN    |
  |  HRPRD  |  -    |  backup          |  Recent backup                    |  DB backup older than 26h                    |  FAIL    |
  |  HRPRD  |  -    |  invalid_other   |  Invalid objects (other schemas)  |  5                                           |  WARN    |
  |  HRPRD  |  -    |  overall         |  OVERALL                          |  2 FAIL, 2 WARN, 0 ignored                   |  NO-GO   |
  |  HOST   |  -    |  swap            |  Swap configured                  |  none                                        |  FAIL    |
  |  HOST   |  -    |  hugepages       |  HugePages (vm.nr_hugepages)      |  0 configured, 20013 required (2048K pages)  |  FAIL    |
  |  HOST   |  -    |  overall         |  OVERALL                          |  2 FAIL, 0 WARN, 0 ignored                   |  NO-GO   |
  +---------+-------+------------------+-----------------------------------+----------------------------------------------+----------+
```

**Readiness for a specific Release Update**

```text
$ dbprecheck --target 19.32 --summary --db FINPRD
  +----------+-------+------------+-----------+-----------------------------+----------+
  |  DB      |  CON  |  CHECK_ID  |  CHECK    |  VALUE                      |  STATUS  |
  +----------+-------+------------+-----------+-----------------------------+----------+
  |  FINPRD  |  -    |  overall   |  OVERALL  |  4 FAIL, 8 WARN, 0 ignored  |  NO-GO   |
  |  HOST    |  -    |  overall   |  OVERALL  |  2 FAIL, 0 WARN, 0 ignored  |  NO-GO   |
  +----------+-------+------------+-----------+-----------------------------+----------+
```

**Add every oscheck row to the HOST section**

```text
$ dbprecheck --full --issues --db CRMSTBY
  +-----------+-------+-------------------+--------------------------------+----------------------------------------------------------------+----------+
  |  DB       |  CON  |  CHECK_ID         |  CHECK                         |  VALUE                                                         |  STATUS  |
  +-----------+-------+-------------------+--------------------------------+----------------------------------------------------------------+----------+
  |  CRMSTBY  |  -    |  overall          |  OVERALL                       |  0 FAIL, 0 WARN, 0 ignored                                     |  GO      |
  |  HOST     |  -    |  swap             |  Swap configured               |  none                                                          |  FAIL    |
  |  HOST     |  -    |  hugepages        |  HugePages (vm.nr_hugepages)   |  0 configured, 20013 required (2048K pages)                    |  FAIL    |
  |  HOST     |  -    |  os.thp           |  Transparent HugePages         |  always (expected never)                                       |  FAIL    |
  |  HOST     |  -    |  os.swappiness    |  vm.swappiness                 |  60 (expected <= 10)                                           |  WARN    |
  |  HOST     |  -    |  os.file_max      |  fs.file-max                   |  577338 (expected >= 6815744)                                  |  WARN    |
  |  HOST     |  -    |  os.aio_max_nr    |  fs.aio-max-nr                 |  65536 (expected >= 1048576)                                   |  WARN    |
  |  HOST     |  -    |  os.rmem_default  |  net.core.rmem_default         |  ? (expected >= 262144)                                        |  WARN    |
  |  HOST     |  -    |  os.rmem_max      |  net.core.rmem_max             |  ? (expected >= 4194304)                                       |  WARN    |
  |  HOST     |  -    |  os.wmem_default  |  net.core.wmem_default         |  ? (expected >= 262144)                                        |  WARN    |
  |  HOST     |  -    |  os.wmem_max      |  net.core.wmem_max             |  ? (expected >= 1048576)                                       |  WARN    |
  |  HOST     |  -    |  os.port_range    |  net.ipv4.ip_local_port_range  |  32768 60999 (expected 9000 65500 (19c) or 9000 65535 (26ai))  |  WARN    |
  |  HOST     |  -    |  os.kernel_panic  |  kernel.panic                  |  -1 (expected 10 (26ai))                                       |  WARN    |
  |  HOST     |  -    |  os.stack         |  stack KB (+ASM)               |  8192 / unlimited (expected >= 10240 / 10240-32768)            |  WARN    |
  |  HOST     |  -    |  os.memlock       |  memlock KB (+ASM)             |  8192 (expected >= 3145728 (no HugePages))                     |  WARN    |
  |  HOST     |  -    |  os.stack         |  stack KB (AIDEV)              |  8192 / unlimited (expected >= 10240 / 10240-32768)            |  WARN    |
  |  HOST     |  -    |  os.memlock       |  memlock KB (AIDEV)            |  8192 (expected >= 3145728 (no HugePages))                     |  WARN    |
  |  HOST     |  -    |  os.stack         |  stack KB (CRMSTBY)            |  8192 / unlimited (expected >= 10240 / 10240-32768)            |  WARN    |
  |  HOST     |  -    |  os.memlock       |  memlock KB (CRMSTBY)          |  8192 (expected >= 3145728 (no HugePages))                     |  WARN    |
  |  HOST     |  -    |  os.stack         |  stack KB (FINPRD)             |  8192 / unlimited (expected >= 10240 / 10240-32768)            |  WARN    |
  |  HOST     |  -    |  os.memlock       |  memlock KB (FINPRD)           |  8192 (expected >= 3145728 (no HugePages))                     |  WARN    |
  |  HOST     |  -    |  os.stack         |  stack KB (HRPRD)              |  8192 / unlimited (expected >= 10240 / 10240-32768)            |  WARN    |
  |  HOST     |  -    |  os.memlock       |  memlock KB (HRPRD)            |  8192 (expected >= 3145728 (no HugePages))                     |  WARN    |
  |  HOST     |  -    |  os.time_sync     |  Time sync                     |  chronyc/ntpstat not found (expected chrony or ntpd)           |  WARN    |
  |  HOST     |  -    |  overall          |  OVERALL                       |  3 FAIL, 20 WARN, 0 ignored                                    |  NO-GO   |
  +-----------+-------+-------------------+--------------------------------+----------------------------------------------------------------+----------+
```

**The check catalog (IDs and thresholds)**

```text
$ dbprecheck --list-checks --csv
CHECK_ID,LEVEL,DESCRIPTION,FAIL WHEN,WARN WHEN
connect,DB,Connect as SYSDBA,cannot connect,-
open_mode,DB,Open mode / database role,-,not OPEN and not a standby
pdb_open,DB,PDB open state (one row per PDB that is not open),-,PDB not OPEN (datapatch skips it)
backup,DB,Recent RMAN backup (same rules as dbbkp),no DB backup within --db-hours,archivelog backup old / failed jobs
dg_lag,DB,Data Guard lag (same rules as dbdglag),CRIT,WARN or broker error
fra,DB,FRA usage,>= 90%,>= 80%
restore_points,DB,Guaranteed restore points,-,any exist
jobs_running,DB,Running scheduler jobs,-,> 0
datapump_jobs,DB,Running Data Pump jobs,-,> 0
long_tx,DB,Transactions open longer than 1 hour,-,> 0
blocked,DB,Blocked sessions,-,> 0
base_free,DB,Free space on the ORACLE_BASE filesystem,< --min-free-gb,-
registry,CON,Registry components (DBA_REGISTRY) not VALID,any,-
datapatch,CON,Latest datapatch action per patch not SUCCESS,any,-
invalid_oracle,CON,Invalid objects in Oracle-maintained schemas,> 0,-
invalid_other,CON,Invalid objects in other schemas,-,> 0
recyclebin,CON,Objects in DBA_RECYCLEBIN,-,> 100
stats_dict,CON,Last statistics on SYS dictionary tables (DBA_TABLES),-,older than 2 days / never
stats_fixed,CON,Last fixed objects statistics (FIXED TABLE),-,older than 2 days / never
ts_system,CON,Free space in SYSTEM (incl. autoextend),< 5 GB,-
ts_sysaux,CON,Free space in SYSAUX (incl. autoextend),< 5 GB,-
ts_undo,CON,"Free space in the UNDO tablespace (incl. autoextend, minus active/unexpired)",-,< 5 GB
ts_temp,CON,Free space in the default TEMP tablespace (incl. autoextend),-,< 5 GB
swap,HOST,Swap configured,no swap,< 16 GB
hugepages,HOST,vm.nr_hugepages vs sum(SGA_MAX_SIZE of running instances incl. ASM) / Hugepagesize + 5,below the requirement,an instance uses MEMORY_TARGET (AMM)
tmp_free,HOST,Free space in /tmp,-,< 2 GB
cert,HOST,OS / kernel / RU / patch certification of every home in use (same rules as oscheck cert),not certified,UEK kernel or rule needs a manual check
target_cdb,DB,--target 26ai: database must be a CDB (26ai supports the multitenant architecture only),non-CDB,-
target_os,HOST,"--target 19c / 26ai / RU: the target release (minimum RU for this OS, or the given RU) certified on this OS release and kernel",not certified,extra patch required in the new home / manual check
os.*,HOST,"All oscheck rows except swap, HugePages and /tmp (only with --full); ID os.<oscheck ID>, e.g. os.thp, os.nofile",oscheck FAIL,oscheck WARN
```

**JSON for an Ansible pre-task**

```text
$ dbprecheck --summary --json --db CRMSTBY
[
  {"DB":"CRMSTBY","CON":"-","CHECK_ID":"overall","CHECK":"OVERALL","VALUE":"0 FAIL, 0 WARN, 0 ignored","STATUS":"GO"},
  {"DB":"HOST","CON":"-","CHECK_ID":"overall","CHECK":"OVERALL","VALUE":"2 FAIL, 0 WARN, 0 ignored","STATUS":"NO-GO"}
]
```

<details>
<summary>Full <code>dbprecheck --help</code></summary>

```text
Usage: dbprecheck [--summary | --issues] [--full] [--target 19c|26ai|RU] [--ignore ID1,ID2,...] [--list-checks]
                  [--min-free-gb N] [--db-hours N] [--db REGEX]
                  [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Readiness checks before patching (out-of-place / AutoUpgrade).
Columns: DB, CON, CHECK_ID, CHECK, VALUE, STATUS (PASS / WARN / FAIL)

Three levels of checks (run 'dbprecheck --list-checks' for every ID and threshold):
  DB     once per database (CON = '-'): open mode, backup, Data Guard lag, FRA, ...
  CON    once per OPEN container - CDB$ROOT and every PDB, or the non-CDB itself:
         registry, datapatch, invalid objects (Oracle-maintained schemas = FAIL,
         other schemas = WARN), recycle bin, dictionary / fixed object statistics,
         SYSTEM / SYSAUX / UNDO / TEMP free space
  HOST   once per host (DB = 'HOST'): swap, HugePages sizing, /tmp, certification of
         every home in use (cert: OS / kernel / RU / required patches, RHEL/OL 8-10)
         (+ every oscheck row as 'os.<ID>' with --full; the per-instance limits get one
          row per running instance, e.g. 'nofile (PRD1)' - see 'oscheck --describe <ID>')

Each database (and HOST) ends with an OVERALL row: GO (no FAIL) or NO-GO.

Ignoring checks:
  --ignore takes CHECK_IDs or globs (comma separated, repeatable), e.g.
      --ignore recyclebin,stats_fixed     --ignore 'ts_*'     --ignore 'os.*'
  An ignored check is still run and shown, with STATUS 'FAIL (ignored)' or
  'WARN (ignored)' (yellow), but it does not count toward NO-GO or the return code.

Options:
  --summary         Only the OVERALL rows
  --issues          Only rows that are not PASS (plus OVERALL)
  --full            Add the oscheck rows (as os.<name> checks) to the HOST section
  --target T        Readiness for a target release / RU (patching, upgrade or a new home):
                      19c | 26ai       target_os: minimum RU of that release for this OS
                      19.32 | 23.26.2  target_os: that Release Update on this OS (incl. one-offs
                                       still required on top of it)
                    For 26ai (any 23.x value) every database must also be a CDB (target_cdb).
  --ignore LIST     See above
  --list-checks     Print the check catalog (IDs, level, thresholds) and exit
  --min-free-gb N   Free space needed on the ORACLE_BASE filesystem for a new home (default: 15)
  --db-hours N      Maximum age of the latest DB backup (default: 26)
  --db REGEX        Only check SIDs matching REGEX (case-insensitive). The HOST checks
                    always consider every running instance (HugePages needs all SGAs).
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Notes:
  - MOUNTED standbys: container checks are skipped (dictionary not open).
  - stats_dict uses the newest LAST_ANALYZED of SYS tables, stats_fixed the newest
    LAST_ANALYZED of fixed tables (DBA_TAB_STATISTICS, OBJECT_TYPE = 'FIXED TABLE').
  - HugePages: required = sum(ceil(SGA_MAX_SIZE / Hugepagesize)) + 5 over every running
    database and ASM instance, compared with vm.nr_hugepages.

Return code: 0 = everything GO, 2 = at least one NO-GO, 1 = error

Examples:
  dbprecheck
  dbprecheck --issues
  dbprecheck --summary --ignore recyclebin,invalid_other
  dbprecheck --db PRD --full --ignore 'os.*' --json      (for an Ansible pre-task)
  dbprecheck --target 26ai --issues
  dbprecheck --target 19.32 --summary            (before moving to 19c RU 19.32)
  dbprecheck --list-checks
```

</details>

[Back to the function list](#function-reference)

### lsautoupg

Progress of AutoUpgrade jobs on the host.

**Features**

- Log directories from `--dir`, `DBA_AUTOUPG_LOG_DIR`, the config file of running AutoUpgrade processes, or the default locations
- Job, SID, stage, operation, status and progress from `status.json` (parsed with python3)
- The last line of the newest job log

**Usage**

```text
lsautoupg [--dir AUTOUPG_LOG_DIR ...] [--grep PATTERN] [--grep-v PATTERN]
          [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**AutoUpgrade jobs found on this host**

```text
$ lsautoupg
AutoUpgrade processes running: 0
  +-------+---------+-------------+-------------+------------+------------+-----------------------+--------------------------------------------------------------------------------------------------+-------------------------------------------+
  |  JOB  |  SID    |  STAGE      |  OPERATION  |  STATUS    |  PROGRESS  |  UPDATED              |  LAST_LOG_LINE                                                                                   |  LOG_DIR                                  |
  +-------+---------+-------------+-------------+------------+------------+-----------------------+--------------------------------------------------------------------------------------------------+-------------------------------------------+
  |  104  |  HRPRD  |  DBUPGRADE  |  EXECUTING  |  RUNNING   |  46%       |  2026-11-25 06:25:12  |  2026-11-25 10:14:59.611 INFO [Upgrading] is [46%] completed for [hrprd] / Phase 42 of 107       |  /u01/app/oracle/cfgtoollogs/autoupgrade  |
  |  105  |  AIDEV  |  PRECHECKS  |  FINISHED   |  FINISHED  |  100%      |  2026-11-25 05:51:12  |  2026-11-25 09:41:02.118 INFO Prechecks completed - 0 errors, 2 warnings (see prechecks report)  |  /u01/app/oracle/cfgtoollogs/autoupgrade  |
  +-------+---------+-------------+-------------+------------+------------+-----------------------+--------------------------------------------------------------------------------------------------+-------------------------------------------+
```

**A specific log directory, CSV**

```text
$ lsautoupg --dir /u01/app/oracle/cfgtoollogs/autoupgrade --csv
AutoUpgrade processes running: 0
JOB,SID,STAGE,OPERATION,STATUS,PROGRESS,UPDATED,LAST_LOG_LINE,LOG_DIR
104,HRPRD,DBUPGRADE,EXECUTING,RUNNING,46%,2026-11-25 06:25:12,2026-11-25 10:14:59.611 INFO [Upgrading] is [46%] completed for [hrprd] / Phase 42 of 107,/u01/app/oracle/cfgtoollogs/autoupgrade
105,AIDEV,PRECHECKS,FINISHED,FINISHED,100%,2026-11-25 05:51:12,"2026-11-25 09:41:02.118 INFO Prechecks completed - 0 errors, 2 warnings (see prechecks report)",/u01/app/oracle/cfgtoollogs/autoupgrade
```

<details>
<summary>Full <code>lsautoupg --help</code></summary>

```text
Usage: lsautoupg [--dir AUTOUPG_LOG_DIR ...] [--grep PATTERN] [--grep-v PATTERN]
                 [--csv|--json|--raw] [--no-header] [--no-color]

Shows AutoUpgrade jobs on this host:
  JOB, SID, STAGE, OPERATION, STATUS, PROGRESS, UPDATED, LAST_LOG_LINE, LOG_DIR

Where it looks (global.autoupg_log_dir):
  1. --dir arguments, or DBA_AUTOUPG_LOG_DIR
  2. the config file (-config) of every running AutoUpgrade java process
  3. <ORACLE_BASE>/cfgtoollogs/autoupgrade and /tmp/autoupgrade (AutoUpgrade defaults)

Job data is read from <log_dir>/cfgtoollogs/upgrade/auto/status/status.json (python3
is used to parse it). When status.json is not available the job directories
<log_dir>/<SID>/<job#>/ are listed with the last line of their newest log file.

Options:
  --dir DIR      AutoUpgrade log directory (repeatable)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Notes:
  - The number of running AutoUpgrade processes is printed above the table.
  - Field names in status.json can differ between AutoUpgrade versions; missing
    values are shown as '-'.

Examples:
  lsautoupg
  lsautoupg --dir /u01/app/oracle/autoupgrade/logs
  watch -n 30 'bash -ic lsautoupg'
```

</details>

[Back to the function list](#function-reference)

## Running SQL on every database

### dbsqlall

Runs a SQL statement, PL/SQL block or SQL file on every running database (or a filtered set, or every PDB).

**Features**

- `--query` or `--file`; `--grep` / `--grep-v` to select databases, `--all` to include down databases, `--pdbs` to run in every open PDB
- Safety: SQL that can change data or structure (DML, DDL, GRANT, PL/SQL, SHUTDOWN ...) shows the targets and requires typing YES (or `--yes`); refused without a terminal
- `--dry-run` lists the targets only
- ORA-/SP2-/PLS-/TNS- errors mark a database as FAILED; `--stop-on-error` stops at the first failure
- A terminating `/` is added automatically for PL/SQL blocks
- Summary table at the end; return code 1 when any database failed

**Usage**

```text
dbsqlall --query SQL | --file FILE [--grep PATTERN] [--grep-v PATTERN] [--all] [--pdbs]
         [--stop-on-error] [--dry-run] [--yes]
```

**Examples**

**Run a query on selected databases**

```text
$ dbsqlall --query 'select name, open_mode, database_role from v$database' --grep 'FIN|HR'

======================================================================
Database   : FINPRD
Oracle Home: /u01/app/oracle/product/19.32.0/dbhome_1
======================================================================

NAME      OPEN_MODE            DATABASE_ROLE
--------- -------------------- ----------------
FINPRD    READ WRITE           PRIMARY

1 row selected.
Completed: FINPRD

======================================================================
Database   : HRPRD
Oracle Home: /u01/app/oracle/product/19.31.0/dbhome_1
======================================================================

NAME      OPEN_MODE            DATABASE_ROLE
--------- -------------------- ----------------
HRPRD     READ WRITE           PRIMARY

1 row selected.
Completed: HRPRD

Summary
  +----------+-------------+--------------------------------------------+----------+
  |  SID     |  CONTAINER  |  ORACLE_HOME                               |  RESULT  |
  +----------+-------------+--------------------------------------------+----------+
  |  FINPRD  |  -          |  /u01/app/oracle/product/19.32.0/dbhome_1  |  OK      |
  |  HRPRD   |  -          |  /u01/app/oracle/product/19.31.0/dbhome_1  |  OK      |
  +----------+-------------+--------------------------------------------+----------+
```

**Show the targets only - nothing is executed**

```text
$ dbsqlall --dry-run --query 'update app.config set val = 1'
Target databases (dry run - nothing executed):
  +-----------+--------------------------------------------+---------+
  |  SID      |  ORACLE_HOME                               |  STATE  |
  +-----------+--------------------------------------------+---------+
  |  AIDEV    |  /u01/app/oracle/product/23.26.1/dbhome_1  |  UP     |
  |  CRMSTBY  |  /u01/app/oracle/product/19.32.0/dbhome_1  |  UP     |
  |  FINPRD   |  /u01/app/oracle/product/19.32.0/dbhome_1  |  UP     |
  |  HRPRD    |  /u01/app/oracle/product/19.31.0/dbhome_1  |  UP     |
  +-----------+--------------------------------------------+---------+
NOTE: the SQL was classified as potentially modifying data/structure.
```

**Modifying SQL asks for confirmation (type YES)**

```text
$ dbsqlall --query 'update app.config set val = 1' --grep HRPRD
WARNING: the SQL can change data or structure and will run on these databases:
  +---------+--------------------------------------------+---------+
  |  SID    |  ORACLE_HOME                               |  STATE  |
  +---------+--------------------------------------------+---------+
  |  HRPRD  |  /u01/app/oracle/product/19.31.0/dbhome_1  |  UP     |
  +---------+--------------------------------------------+---------+
Type YES to continue: YES

======================================================================
Database   : HRPRD
Oracle Home: /u01/app/oracle/product/19.31.0/dbhome_1
======================================================================

3 rows updated.

Commit complete.
Completed: HRPRD

Summary
  +---------+-------------+--------------------------------------------+----------+
  |  SID    |  CONTAINER  |  ORACLE_HOME                               |  RESULT  |
  +---------+-------------+--------------------------------------------+----------+
  |  HRPRD  |  -          |  /u01/app/oracle/product/19.31.0/dbhome_1  |  OK      |
  +---------+-------------+--------------------------------------------+----------+
```

**A SQL file in every open PDB**

```text
$ dbsqlall --file /home/oracle/sql/check.sql --pdbs --grep FINPRD --yes

======================================================================
Database   : FINPRD  (container: FINPDB1)
Oracle Home: /u01/app/oracle/product/19.32.0/dbhome_1
======================================================================

INVALID_OBJECTS
---------------
             37

1 row selected.
Completed: FINPRD/FINPDB1

======================================================================
Database   : FINPRD  (container: FINPDB2)
Oracle Home: /u01/app/oracle/product/19.32.0/dbhome_1
======================================================================

INVALID_OBJECTS
---------------
              3

1 row selected.
Completed: FINPRD/FINPDB2

Summary
  +----------+-------------+--------------------------------------------+----------+
  |  SID     |  CONTAINER  |  ORACLE_HOME                               |  RESULT  |
  +----------+-------------+--------------------------------------------+----------+
  |  FINPRD  |  FINPDB1    |  /u01/app/oracle/product/19.32.0/dbhome_1  |  OK      |
  |  FINPRD  |  FINPDB2    |  /u01/app/oracle/product/19.32.0/dbhome_1  |  OK      |
  +----------+-------------+--------------------------------------------+----------+
```

<details>
<summary>Full <code>dbsqlall --help</code></summary>

```text
Usage:
  dbsqlall --query 'select name, open_mode from v$database'
  dbsqlall --file sqlfile.sql

Options:
  --query | -q SQL     SQL statement (or PL/SQL block) to execute
  --file  | -f FILE    SQL file to execute
  --grep  | -g PATTERN Include only SIDs matching PATTERN (case-insensitive regex)
  --grep-v PATTERN     Exclude SIDs matching PATTERN
  --all                Also try oratab databases whose instance is not running
  --pdbs               Run in every OPEN PDB (alter session set container) instead of
                       the CDB root. Non-CDBs run normally.
  --stop-on-error      Use WHENEVER SQLERROR EXIT and stop at the first failing database
  --dry-run            Only list the target databases, run nothing
  --yes | -y           Do not ask for confirmation for statements that can change data
  --help | -h          Show this help

Safety:
  If the SQL contains anything other than queries (INSERT/UPDATE/DELETE/MERGE, DDL,
  GRANT/REVOKE, PL/SQL blocks, EXEC, SHUTDOWN/STARTUP, nested @scripts ...), the target
  list is shown and you must type YES to continue (or pass --yes). Without a terminal
  and without --yes such SQL is refused.

Result detection:
  A database is reported as FAILED when SQL*Plus exits non-zero or the output contains
  ORA-, SP2-, PLS- or TNS- errors (e.g. "Connected to an idle instance").
  A summary table is printed at the end; the return code is 1 if any database failed.

PL/SQL:
  For --query, a block starting with BEGIN / DECLARE / CREATE [OR REPLACE] PROCEDURE|
  FUNCTION|PACKAGE|TRIGGER|TYPE gets a terminating "/" automatically.

Important:
  Use single quotes around SQL containing $ characters:
    dbsqlall --query 'select name from v$database'
```

</details>

[Back to the function list](#function-reference)

## Host, OS and filesystems

### oscheck

Checks the host against Oracle's Linux requirements for the releases in use (19c and/or 26ai), including certification of every home.

**Features**

- RHEL / Oracle Linux 8, 9 and 10; releases detected from the homes in use (`--release 19c|26ai|both` to override)
- Certification of each home: OS release, kernel, minimum Release Update and required one-off patches
- Pre-install check: `--release` adds a `Certification (planned)` row, `--ru` evaluates a specific RU
- Memory: HugePages, Transparent HugePages, swap, swappiness
- Every kernel parameter checked individually (no preinstall RPM needed), including the 26ai rules (kernel.panic = 10, port range up to 65535)
- nofile / nproc / stack / memlock checked for every running instance (each keeps the limits it was started with); `--sid` to narrow
- Time synchronization, /tmp and /dev/shm
- `--describe [ID]` explains each check and gives the Oracle documentation source
- What-if runs with `DBA_OS_RELEASE_FILE` / `DBA_KERNEL`

**Usage**

```text
oscheck [--release 19c|26ai|both|auto] [--ru VERSION] [--sid REGEX] [--grep PATTERN] [--grep-v PATTERN]
        [--csv|--json|--raw] [--no-header] [--no-color]
oscheck --describe [ID]
```

**Examples**

**Full OS check (per-instance limits for FINPRD only)**

```text
$ oscheck --sid FINPRD
  +-----------------+--------------------------------+--------------------------------------------+----------------------------------------------------------------------+-----------------------------------------------------------------------+----------+
  |  ID             |  CHECK                         |  SCOPE                                     |  CURRENT                                                             |  EXPECTED                                                             |  STATUS  |
  +-----------------+--------------------------------+--------------------------------------------+----------------------------------------------------------------------+-----------------------------------------------------------------------+----------+
  |  os_release     |  OS release                    |  host                                      |  rhel 9.4, kernel 5.14.0-427.13.1.el9_4.x86_64                       |  26ai 23.26.1.0.0, 19c 19.32.0.0.0, 19c 19.31.0.0.0, 19c 19.32.0.0.0  |  INFO    |
  |  cert           |  Certification (DB)            |  /u01/app/oracle/product/23.26.1/dbhome_1  |  26ai 23.26.1.0.0 on RHEL/OL 9.4 (kernel 5.14.0-427.13.1) certified  |  certified                                                            |  PASS    |
  |  cert           |  Certification (DB)            |  /u01/app/oracle/product/19.32.0/dbhome_1  |  19c 19.32.0.0.0 on RHEL/OL 9.4 (kernel 5.14.0-427.13.1) certified   |  certified                                                            |  PASS    |
  |  cert           |  Certification (DB)            |  /u01/app/oracle/product/19.31.0/dbhome_1  |  19c 19.31.0.0.0 on RHEL/OL 9.4 (kernel 5.14.0-427.13.1) certified   |  certified                                                            |  PASS    |
  |  cert           |  Certification (GRID)          |  /u01/app/19.32.0/grid                     |  19c 19.32.0.0.0 on RHEL/OL 9.4 (kernel 5.14.0-427.13.1) certified   |  certified                                                            |  PASS    |
  |  hugepages      |  HugePages configured          |  host                                      |  0                                                                   |  > 0 (SGA in HugePages)                                               |  WARN    |
  |  thp            |  Transparent HugePages         |  host                                      |  always                                                              |  never                                                                |  FAIL    |
  |  swap           |  Swap size                     |  host                                      |  0.0 GB (RAM 5.5 GB)                                                 |  >= 5.5 GB                                                            |  WARN    |
  |  swappiness     |  vm.swappiness                 |  host                                      |  60                                                                  |  <= 10                                                                |  WARN    |
  |  shmmni         |  kernel.shmmni                 |  host                                      |  4096                                                                |  >= 4096                                                              |  PASS    |
  |  file_max       |  fs.file-max                   |  host                                      |  577338                                                              |  >= 6815744                                                           |  WARN    |
  |  aio_max_nr     |  fs.aio-max-nr                 |  host                                      |  65536                                                               |  >= 1048576                                                           |  WARN    |
  |  rmem_default   |  net.core.rmem_default         |  host                                      |  ?                                                                   |  >= 262144                                                            |  WARN    |
  |  rmem_max       |  net.core.rmem_max             |  host                                      |  ?                                                                   |  >= 4194304                                                           |  WARN    |
  |  wmem_default   |  net.core.wmem_default         |  host                                      |  ?                                                                   |  >= 262144                                                            |  WARN    |
  |  wmem_max       |  net.core.wmem_max             |  host                                      |  ?                                                                   |  >= 1048576                                                           |  WARN    |
  |  sem            |  kernel.sem                    |  host                                      |  32000 1024000000 500 32000                                          |  >= 250 32000 100 128                                                 |  PASS    |
  |  shmmax         |  kernel.shmmax                 |  host                                      |  18446744073692774399                                                |  >= half of RAM                                                       |  PASS    |
  |  shmall         |  kernel.shmall                 |  host                                      |  18446744073692774399 pages                                          |  >= shmmax in pages                                                   |  PASS    |
  |  panic_on_oops  |  kernel.panic_on_oops          |  host                                      |  1                                                                   |  1                                                                    |  PASS    |
  |  port_range     |  net.ipv4.ip_local_port_range  |  host                                      |  32768 60999                                                         |  9000 65500 (19c) or 9000 65535 (26ai)                                |  WARN    |
  |  kernel_panic   |  kernel.panic                  |  host                                      |  -1                                                                  |  10 (26ai)                                                            |  WARN    |
  |  nofile         |  nofile                        |  FINPRD                                    |  1024 / 1048576                                                      |  >= 1024 / 65536                                                      |  PASS    |
  |  nproc          |  nproc                         |  FINPRD                                    |  22564 / 22564                                                       |  >= 2047 / 16384                                                      |  PASS    |
  |  stack          |  stack KB                      |  FINPRD                                    |  8192 / unlimited                                                    |  >= 10240 / 10240-32768                                               |  WARN    |
  |  memlock        |  memlock KB                    |  FINPRD                                    |  8192                                                                |  >= 3145728 (no HugePages)                                            |  WARN    |
  |  time_sync      |  Time sync                     |  host                                      |  chronyc/ntpstat not found                                           |  chrony or ntpd                                                       |  WARN    |
  |  tmp_free       |  /tmp free                     |  host                                      |  45.2 GB                                                             |  >= 1 GB                                                              |  PASS    |
  |  dev_shm        |  /dev/shm                      |  host                                      |  0.1 GB                                                              |  mounted                                                              |  PASS    |
  +-----------------+--------------------------------+--------------------------------------------+----------------------------------------------------------------------+-----------------------------------------------------------------------+----------+
```

**Platform and certification rows only**

```text
$ oscheck --grep '^(os_release|cert)'
  +--------------+------------------------+--------------------------------------------+----------------------------------------------------------------------+-----------------------------------------------------------------------+----------+
  |  ID          |  CHECK                 |  SCOPE                                     |  CURRENT                                                             |  EXPECTED                                                             |  STATUS  |
  +--------------+------------------------+--------------------------------------------+----------------------------------------------------------------------+-----------------------------------------------------------------------+----------+
  |  os_release  |  OS release            |  host                                      |  rhel 9.4, kernel 5.14.0-427.13.1.el9_4.x86_64                       |  26ai 23.26.1.0.0, 19c 19.32.0.0.0, 19c 19.31.0.0.0, 19c 19.32.0.0.0  |  INFO    |
  |  cert        |  Certification (DB)    |  /u01/app/oracle/product/23.26.1/dbhome_1  |  26ai 23.26.1.0.0 on RHEL/OL 9.4 (kernel 5.14.0-427.13.1) certified  |  certified                                                            |  PASS    |
  |  cert        |  Certification (DB)    |  /u01/app/oracle/product/19.32.0/dbhome_1  |  19c 19.32.0.0.0 on RHEL/OL 9.4 (kernel 5.14.0-427.13.1) certified   |  certified                                                            |  PASS    |
  |  cert        |  Certification (DB)    |  /u01/app/oracle/product/19.31.0/dbhome_1  |  19c 19.31.0.0.0 on RHEL/OL 9.4 (kernel 5.14.0-427.13.1) certified   |  certified                                                            |  PASS    |
  |  cert        |  Certification (GRID)  |  /u01/app/19.32.0/grid                     |  19c 19.32.0.0.0 on RHEL/OL 9.4 (kernel 5.14.0-427.13.1) certified   |  certified                                                            |  PASS    |
  +--------------+------------------------+--------------------------------------------+----------------------------------------------------------------------+-----------------------------------------------------------------------+----------+
```

**Pre-install check for 19c RU 19.32**

```text
$ oscheck --release 19c --ru 19.32 --grep '^(os_release|cert|port_range|kernel_panic)'
  +--------------+--------------------------------+--------------------------------------------+----------------------------------------------------------------------+-----------------------------------------------------------------------+----------+
  |  ID          |  CHECK                         |  SCOPE                                     |  CURRENT                                                             |  EXPECTED                                                             |  STATUS  |
  +--------------+--------------------------------+--------------------------------------------+----------------------------------------------------------------------+-----------------------------------------------------------------------+----------+
  |  os_release  |  OS release                    |  host                                      |  rhel 9.4, kernel 5.14.0-427.13.1.el9_4.x86_64                       |  26ai 23.26.1.0.0, 19c 19.32.0.0.0, 19c 19.31.0.0.0, 19c 19.32.0.0.0  |  INFO    |
  |  cert        |  Certification (DB)            |  /u01/app/oracle/product/23.26.1/dbhome_1  |  26ai 23.26.1.0.0 on RHEL/OL 9.4 (kernel 5.14.0-427.13.1) certified  |  certified                                                            |  PASS    |
  |  cert        |  Certification (DB)            |  /u01/app/oracle/product/19.32.0/dbhome_1  |  19c 19.32.0.0.0 on RHEL/OL 9.4 (kernel 5.14.0-427.13.1) certified   |  certified                                                            |  PASS    |
  |  cert        |  Certification (DB)            |  /u01/app/oracle/product/19.31.0/dbhome_1  |  19c 19.31.0.0.0 on RHEL/OL 9.4 (kernel 5.14.0-427.13.1) certified   |  certified                                                            |  PASS    |
  |  cert        |  Certification (GRID)          |  /u01/app/19.32.0/grid                     |  19c 19.32.0.0.0 on RHEL/OL 9.4 (kernel 5.14.0-427.13.1) certified   |  certified                                                            |  PASS    |
  |  cert        |  Certification (planned)       |  19c 19.32                                 |  19c 19.32.0.0.0 on RHEL/OL 9.4 (kernel 5.14.0-427.13.1) certified   |  certified                                                            |  PASS    |
  |  port_range  |  net.ipv4.ip_local_port_range  |  host                                      |  32768 60999                                                         |  9000 65500                                                           |  WARN    |
  +--------------+--------------------------------+--------------------------------------------+----------------------------------------------------------------------+-----------------------------------------------------------------------+----------+
```

**What-if: the same host on RHEL 10**

```text
$ DBA_OS_RELEASE_FILE=/tmp/rhel10 DBA_KERNEL=6.12.0-55.40.1.el10_0.x86_64 oscheck --release both --grep '^cert'
  +--------+---------------------------+--------------------------------------------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+-------------+----------+
  |  ID    |  CHECK                    |  SCOPE                                     |  CURRENT                                                                                                                                                                     |  EXPECTED   |  STATUS  |
  +--------+---------------------------+--------------------------------------------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+-------------+----------+
  |  cert  |  Certification (DB)       |  /u01/app/oracle/product/23.26.1/dbhome_1  |  26ai on RHEL/OL 10.0: 26ai RU 23.26.1.0.0 < 23.26.2 required on RHEL/OL 10; missing required patch(es) 39268330                                                             |  certified  |  FAIL    |
  |  cert  |  Certification (DB)       |  /u01/app/oracle/product/19.32.0/dbhome_1  |  19c on RHEL/OL 10.0: missing required patch(es) 39894800,38622857,39153061,39388682,39928540                                                                                |  certified  |  FAIL    |
  |  cert  |  Certification (DB)       |  /u01/app/oracle/product/19.31.0/dbhome_1  |  19c on RHEL/OL 10.0: 19c RU 19.31.0.0.0 < 19.32 required on RHEL/OL 10                                                                                                      |  certified  |  FAIL    |
  |  cert  |  Certification (GRID)     |  /u01/app/19.32.0/grid                     |  19c on RHEL/OL 10.0: missing required patch(es) 39894800,39153061,39388682,39928540                                                                                         |  certified  |  FAIL    |
  |  cert  |  Certification (planned)  |  19c                                       |  minimum RU for a new install on RHEL/OL 10: 19.32 - 19c 19.32.0.0.0 on RHEL/OL 10.0 certified; requires patch(es) 39894800,38622857,39153061,39388682,39928540 in the home  |  certified  |  WARN    |
  |  cert  |  Certification (planned)  |  26ai                                      |  minimum RU for a new install on RHEL/OL 10: 23.26.2 - 26ai 23.26.2.0.0 on RHEL/OL 10.0 certified; requires patch(es) 39268330 in the home                                   |  certified  |  WARN    |
  +--------+---------------------------+--------------------------------------------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+-------------+----------+
```

**One-line description of every check**

```text
$ oscheck --describe
  +------------------+--------------------------------+-------------------------------------------------------------------------------------------------+
  |  ID              |  CHECK                         |  DESCRIPTION                                                                                    |
  +------------------+--------------------------------+-------------------------------------------------------------------------------------------------+
  |  os_release      |  OS release                    |  Information only: operating system, release, kernel (RHCK or UEK) and the Oracle releases ...  |
  |  cert            |  Certification                 |  Checks every Oracle home in use (running databases, ASM / Grid) against the OS: RHEL/OL ...    |
  |  hugepages       |  HugePages configured          |  Standard HugePages (vm.nr_hugepages) pre-allocate large (2 MB) pages for the SGA. They ...     |
  |  hugepages_used  |  HugePages in use              |  While databases are running, some HugePages should be in use (Total - Free + Reserved > ...    |
  |  thp             |  Transparent HugePages         |  Transparent HugePages are allocated dynamically by the khugepaged kernel thread and are ...    |
  |  swap            |  Swap size                     |  Swap required by the installer: 1.5x RAM for 1-2 GB of RAM, equal to RAM for 2-16 GB, and ...  |
  |  swappiness      |  vm.swappiness                 |  How aggressively the kernel swaps anonymous memory. A low value (<= 10) keeps Oracle ...       |
  |  sem             |  kernel.sem                    |  Semaphore limits SEMMSL SEMMNS SEMOPM SEMMNI. Oracle processes use semaphores for ...          |
  |  shmall          |  kernel.shmall                 |  Total shared memory the system may use, in pages. Must be greater than or equal to shmmax ...  |
  |  shmmax          |  kernel.shmmax                 |  Largest single shared memory segment in bytes. Minimum: half of the physical memory (see ...   |
  |  shmmni          |  kernel.shmmni                 |  Maximum number of shared memory segments system wide. Minimum 4096.                            |
  |  panic_on_oops   |  kernel.panic_on_oops          |  When 1, the kernel panics (and reboots) on an oops instead of continuing in an undefined ...   |
  |  file_max        |  fs.file-max                   |  Maximum number of open files system wide (datafiles, redo, archive logs, sockets). ...         |
  |  aio_max_nr      |  fs.aio-max-nr                 |  Maximum number of concurrent outstanding asynchronous I/O requests. Too low a value ...        |
  |  port_range      |  net.ipv4.ip_local_port_range  |  Ephemeral port range used for outgoing connections (DB links, client connections, RAC ...      |
  |  kernel_panic    |  kernel.panic                  |  Seconds before the kernel reboots after a panic. Required value 10 for 26ai (new in the ...    |
  |  rmem_default    |  net.core.rmem_default         |  Default socket receive buffer. Minimum 262144.                                                 |
  |  rmem_max        |  net.core.rmem_max             |  Maximum socket receive buffer. Minimum 4194304.                                                |
  |  wmem_default    |  net.core.wmem_default         |  Default socket send buffer. Minimum 262144.                                                    |
  |  wmem_max        |  net.core.wmem_max             |  Maximum socket send buffer. Minimum 1048576.                                                   |
  |  nofile          |  nofile                        |  Open file descriptors per process: soft >= 1024, hard >= 65536. Checked for EVERY running ...  |
  |  nproc           |  nproc                         |  Processes available to the instance owner: soft >= 2047, hard >= 16384. Too low causes ...     |
  |  stack           |  stack                         |  Stack segment size: soft >= 10240 KB, hard >= 10240 KB and at most 32768 KB. Checked per ...   |
  |  memlock         |  memlock                       |  Maximum locked memory: at least 90% of RAM when HugePages are configured, at least ...         |
  |  time_sync       |  Time sync                     |  Clock synchronization with chrony or ntpd. Clock jumps break RAC (CTSS/evictions), Data ...    |
  |  tmp_free        |  /tmp free                     |  At least 1 GB free in /tmp for the installer, OPatch and AutoUpgrade.                          |
  |  dev_shm         |  /dev/shm                      |  tmpfs /dev/shm must be mounted. Required for Automatic Memory Management (MEMORY_TARGET); ...  |
  +------------------+--------------------------------+-------------------------------------------------------------------------------------------------+
Run 'oscheck --describe <ID>' for the full description and the documentation source.
```

**Full description and documentation source of one check**

```text
$ oscheck --describe memlock
ID          : memlock
CHECK       : memlock
DESCRIPTION :
    Maximum locked memory: at least 90% of RAM when HugePages are configured, at least 
    3145728 KB (3 GB) when they are not. Too low and the SGA cannot be locked in HugePages. 
    Checked per running instance (see nofile).
SOURCE      :
    19c Installation Guide - Checking Resource Limits for Oracle Software Installation Users
    https://docs.cloud.oracle.com/en/database/oracle/oracle-database/19/cwhpx/checking-resource-limits-for-oracle-software-installation-users.html
    26ai (same values)
    https://download.oracle.com/docs/en/database/oracle/oracle-database/23/cwlin/configuring-users-groups-and-environments-for-oracle-grid-infrastructure-and-oracle-ai-database/checking-resource-limits-for-oracle-software-installation-users.html
    and Configuring HugePages on Linux (memlock step)
```

<details>
<summary>Full <code>oscheck --help</code></summary>

```text
Usage: oscheck [--release 19c|26ai|both|auto] [--ru VERSION] [--sid REGEX] [--grep PATTERN] [--grep-v PATTERN]
               [--csv|--json|--raw] [--no-header] [--no-color]
       oscheck --describe [ID]

Checks this host against the Oracle Linux installation requirements of the Oracle
releases in use (19c and/or 26ai) and Oracle's recommendations. Every kernel parameter
and limit is checked individually - the preinstall RPM is not required.

Release and OS awareness (RHEL / Oracle Linux 8, 9, 10):
  - The releases are detected from the homes in use (running databases, ASM / Grid);
    with nothing running, from the DBMS / GRID homes in the inventory. --release overrides.
  - 26ai adds kernel.panic = 10 and allows ip_local_port_range up to 65535.
  - 'cert' rows check every home in use for OS / kernel / Release Update / required
    patch certification (e.g. 19c on RHEL 10 needs 19.32+, 26ai needs 23.26.2 + 39268330).

Checking a host BEFORE installing a release (pre-install check):
  --release 19c / 26ai / both adds a 'Certification (planned)' row per release, evaluated
  for this OS and kernel even when no home of that release exists yet:
    without --ru   the minimum Release Update for a new installation on this OS is
                   evaluated and shown (e.g. 'minimum RU for a new install on RHEL/OL 9: 19.19';
                   RHEL/OL 8: 19.18, the RU Oracle's release notes apply during installation)
    with --ru      the Release Update you plan to install, e.g. --ru 19.32 or --ru 23.26.2
                   (one-off patches still required on top of that RU are listed)
  The planned row uses the database home patch list; a Grid home can need a different list.
  The kernel parameter rules of the requested release(s) are applied as well.

Columns: ID, CHECK, SCOPE, CURRENT, EXPECTED, STATUS
  ID       Short check name - use it with --describe and with dbprecheck --ignore os.<ID>
  SCOPE    'host' for system-wide settings; for the per-process limits (nofile, nproc,
           stack, memlock) the instance the values were read from (one row per running
           database / ASM instance), or 'shell' when no instance is running.
  STATUS   PASS / WARN / FAIL (FAIL for settings known to cause instability, e.g.
           Transparent HugePages enabled, and for uncertified OS / release combinations);
           INFO rows are informational only

Why limits are checked per instance:
  A running instance keeps the limits of the process that started it. Instances started
  by srvctl/Clusterware get the CRS limits, instances started from sqlplus get the login
  shell limits, and an instance started before limits.conf was changed keeps the old
  values until it is restarted. One instance can pass while another one fails.

Checks:
  Platform  os_release (INFO), cert (one row per home in use)
  Memory    hugepages, hugepages_used, thp, swap, swappiness
  Kernel    sem, shmall, shmmax, shmmni, panic_on_oops, kernel_panic (26ai), file_max,
            aio_max_nr, port_range, rmem_default, rmem_max, wmem_default, wmem_max
  Limits    nofile, nproc, stack, memlock   (per running instance)
  Other     time_sync, tmp_free, dev_shm

Options:
  --describe [ID]   Without ID: one-line description of every check.
                    With an ID: full description and the documentation source.
  --release REL     Apply the rules of 19c, 26ai or both (default: auto-detect) and add a
                    'Certification (planned)' row per release (pre-install check)
  --ru VERSION      Release Update for the planned row: 19.N[.N.N.N] or 23.26.N[.N.N].
                    Implies --release of that RU when --release is not given.
  --sid REGEX       Only check the limits of instances whose SID matches REGEX
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Return code: 0 = no FAIL, 2 = at least one FAIL

Examples:
  oscheck
  oscheck --grep -v PASS
  oscheck --describe
  oscheck --describe memlock
  oscheck --sid PRD --grep 'nofile|nproc'
  oscheck --grep '^cert'
  oscheck --release 19c               (before installing 19c: minimum RU on this OS)
  oscheck --release 19c --ru 19.32    (before installing 19c RU 19.32)
  oscheck --ru 23.26.2                (before installing 26ai RU 23.26.2)
  oscheck --release 26ai              (before installing 26ai on this host)
```

</details>

[Back to the function list](#function-reference)

### lsfs

Usage of the filesystems holding Oracle homes, bases, Grid, agent and custom paths, or the largest housekeeping directories.

**Features**

- USED_BY shows what lives on each filesystem (HOME, BASE, GRID, AGENT, TMP, custom paths)
- Custom paths come from the `lsfs_custom` variable at the top of the function (`/stage` and `/dump` by default); a missing path is shown as `N/A (not found)` and never fails
- `--ignore` keeps chosen filesystems out of the return code (shown as `(ignored)`)
- `--top [N]` lists the largest diag, audit, `.patch_storage` and cfgtoollogs directories (du limited to 5 minutes)

**Usage**

```text
lsfs [--top [N]] [--warn PCT] [--crit PCT] [--ignore PATH1,PATH2]
     [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Filesystems holding Oracle data, plus the custom paths (/stage, /dump)**

```text
$ lsfs
  +----------+-----------+-----------+-----------+------------+----------------------------+-------------------+
  |  MOUNT   |  SIZE_GB  |  USED_GB  |  FREE_GB  |  PCT_USED  |  USED_BY                   |  STATUS           |
  +----------+-----------+-----------+-----------+------------+----------------------------+-------------------+
  |  /       |  49.2     |  1.5      |  45.2     |  3.2       |  HOME,BASE,GRID,AGENT,TMP  |  OK               |
  |  /stage  |  -        |  -        |  -        |  -         |  /stage                    |  N/A (not found)  |
  |  /dump   |  -        |  -        |  -        |  -         |  /dump                     |  N/A (not found)  |
  +----------+-----------+-----------+-----------+------------+----------------------------+-------------------+
```

**The 5 largest housekeeping directories (diag, audit, .patch_storage ...)**

```text
$ lsfs --top 5
Measuring 19 directories - please wait...
  +-----------------------------------------------------------+-----------------+-----------+
  |  PATH                                                     |  KIND           |  SIZE_GB  |
  +-----------------------------------------------------------+-----------------+-----------+
  |  /u01/app/oracle/diag/rdbms/finprd_a/FINPRD/trace         |  diag trace     |  0.09     |
  |  /u01/app/oracle/product/19.32.0/dbhome_1/.patch_storage  |  patch_storage  |  0.03     |
  |  /u01/app/oracle/diag/rdbms/hrprd/HRPRD/trace             |  diag trace     |  0.01     |
  |  /u01/app/oracle/diag/rdbms/finprd_a/FINPRD/incident      |  diag incident  |  0.01     |
  |  /u01/app/oracle/admin/FINPRD/adump                       |  audit          |  0.00     |
  +-----------------------------------------------------------+-----------------+-----------+
```

**Custom threshold; /stage and /dump never affect the return code**

```text
$ lsfs --ignore /stage,/dump --warn 70
  +----------+-----------+-----------+-----------+------------+----------------------------+----------------------------+
  |  MOUNT   |  SIZE_GB  |  USED_GB  |  FREE_GB  |  PCT_USED  |  USED_BY                   |  STATUS                    |
  +----------+-----------+-----------+-----------+------------+----------------------------+----------------------------+
  |  /       |  49.2     |  1.5      |  45.2     |  3.2       |  HOME,BASE,GRID,AGENT,TMP  |  OK                        |
  |  /stage  |  -        |  -        |  -        |  -         |  /stage                    |  N/A (not found, ignored)  |
  |  /dump   |  -        |  -        |  -        |  -         |  /dump                     |  N/A (not found, ignored)  |
  +----------+-----------+-----------+-----------+------------+----------------------------+----------------------------+
```

<details>
<summary>Full <code>lsfs --help</code></summary>

```text
Usage: lsfs [--top [N]] [--warn PCT] [--crit PCT] [--ignore PATH1,PATH2]
            [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Default: one row per filesystem that holds Oracle data on this host
  MOUNT, SIZE_GB, USED_GB, FREE_GB, PCT_USED, USED_BY, STATUS
  USED_BY lists what lives there: HOME, BASE, GRID, AGENT, TMP and the custom
  paths (by default /stage and /dump - edit the lsfs_custom variable at the top of
  the function to add more).
  A custom path that does not exist is shown with STATUS 'N/A (not found)' and never
  affects the return code.

--top [N]: the N largest Oracle "housekeeping" directories (default 10):
  diag trace/alert/incident/cdump directories (rdbms, listener, asm),
  audit dump directories (adump, rdbms/audit), .patch_storage, cfgtoollogs
  Columns: PATH, KIND, SIZE_GB   (du is limited to 5 minutes in total)

Options:
  --warn PCT          WARN threshold (default: 80)
  --crit PCT          CRIT threshold (default: 90)
  --ignore LIST       Comma-separated mount points or custom paths whose WARN/CRIT must not
                      affect the return code (still shown, STATUS gets '(ignored)').
                      A filesystem is ignored when its MOUNT is in the list, or when every
                      entry in its USED_BY is in the list. Repeatable.
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Return code: 0 = all OK/WARN/ignored, 2 = at least one CRIT (not ignored)

Examples:
  lsfs
  lsfs --ignore /stage,/dump
  lsfs --top
  lsfs --top 20 --csv
```

</details>

[Back to the function list](#function-reference)

### dbpurge

Purges old ADR diagnostic data of every ADR home on the host - dry run by default.

**Features**

- Purges TRACE, CDUMP, INCIDENT, HM and UTSCDMP with `adrci purge -age`; alert logs are never purged
- Dry run shows files and MB per ADR home; `--execute` purges after typing YES (`--yes` for scripts)
- `--include-audit` also removes old `*.aud` files from adump and `<home>/rdbms/audit`
- `--days N` (default 30), `--grep` / `--grep-v` to choose ADR homes

**Usage**

```text
dbpurge [--days N] [--include-audit] [--execute [--yes]]
        [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Dry run: what would be purged (older than 30 days)**

```text
$ dbpurge
  +----------------------------------+------------------------+---------+-----------+-----------+
  |  TARGET                          |  TYPE                  |  FILES  |  SIZE_MB  |  ACTION   |
  +----------------------------------+------------------------+---------+-----------+-----------+
  |  diag/rdbms/aidev/AIDEV          |  ADR (older than 30d)  |  0      |  0.0      |  DRY-RUN  |
  |  diag/rdbms/crmprd_b/CRMSTBY     |  ADR (older than 30d)  |  0      |  0.0      |  DRY-RUN  |
  |  diag/rdbms/dwtst/DWTST          |  ADR (older than 30d)  |  0      |  0.0      |  DRY-RUN  |
  |  diag/rdbms/finprd_a/FINPRD      |  ADR (older than 30d)  |  41     |  104.0    |  DRY-RUN  |
  |  diag/rdbms/hrprd/HRPRD          |  ADR (older than 30d)  |  8      |  11.4     |  DRY-RUN  |
  |  diag/tnslsnr/dbhost01/listener  |  ADR (older than 30d)  |  0      |  0.0      |  DRY-RUN  |
  |  TOTAL                           |                        |  49     |  115.4    |           |
  +----------------------------------+------------------------+---------+-----------+-----------+

Dry run only - nothing was deleted. Re-run with --execute to purge.
```

**Dry run including *.aud files**

```text
$ dbpurge --days 45 --include-audit
  +--------------------------------------+------------------------+---------+-----------+-----------+
  |  TARGET                              |  TYPE                  |  FILES  |  SIZE_MB  |  ACTION   |
  +--------------------------------------+------------------------+---------+-----------+-----------+
  |  diag/rdbms/aidev/AIDEV              |  ADR (older than 45d)  |  0      |  0.0      |  DRY-RUN  |
  |  diag/rdbms/crmprd_b/CRMSTBY         |  ADR (older than 45d)  |  0      |  0.0      |  DRY-RUN  |
  |  diag/rdbms/dwtst/DWTST              |  ADR (older than 45d)  |  0      |  0.0      |  DRY-RUN  |
  |  diag/rdbms/finprd_a/FINPRD          |  ADR (older than 45d)  |  40     |  95.4     |  DRY-RUN  |
  |  diag/rdbms/hrprd/HRPRD              |  ADR (older than 45d)  |  8      |  11.4     |  DRY-RUN  |
  |  diag/tnslsnr/dbhost01/listener      |  ADR (older than 45d)  |  0      |  0.0      |  DRY-RUN  |
  |  /u01/app/oracle/admin/FINPRD/adump  |  AUDIT *.aud           |  300    |  0.0      |  DRY-RUN  |
  |  /u01/app/oracle/admin/HRPRD/adump   |  AUDIT *.aud           |  0      |  0.0      |  DRY-RUN  |
  |  TOTAL                               |                        |  348    |  106.8    |           |
  +--------------------------------------+------------------------+---------+-----------+-----------+

Dry run only - nothing was deleted. Re-run with --execute to purge.
```

**Really purge (adrci purge per ADR home)**

```text
$ dbpurge --days 30 --execute --yes
  +----------------------------------+------------------------+---------+-----------+----------+
  |  TARGET                          |  TYPE                  |  FILES  |  SIZE_MB  |  ACTION  |
  +----------------------------------+------------------------+---------+-----------+----------+
  |  diag/rdbms/aidev/AIDEV          |  ADR (older than 30d)  |  0      |  0.0      |  PURGED  |
  |  diag/rdbms/crmprd_b/CRMSTBY     |  ADR (older than 30d)  |  0      |  0.0      |  PURGED  |
  |  diag/rdbms/dwtst/DWTST          |  ADR (older than 30d)  |  0      |  0.0      |  PURGED  |
  |  diag/rdbms/finprd_a/FINPRD      |  ADR (older than 30d)  |  41     |  104.0    |  PURGED  |
  |  diag/rdbms/hrprd/HRPRD          |  ADR (older than 30d)  |  8      |  11.4     |  PURGED  |
  |  diag/tnslsnr/dbhost01/listener  |  ADR (older than 30d)  |  0      |  0.0      |  PURGED  |
  |  TOTAL                           |                        |  49     |  115.4    |          |
  +----------------------------------+------------------------+---------+-----------+----------+
```

<details>
<summary>Full <code>dbpurge --help</code></summary>

```text
Usage: dbpurge [--days N] [--include-audit] [--execute [--yes]]
               [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Purges diagnostic data older than N days from every ADR home found under the
ORACLE_BASE(s) of this host (rdbms, tnslsnr, asm, crs, clients).

DRY RUN BY DEFAULT: without --execute nothing is deleted; the table shows how many
files and how much space would be released.

What is purged (adrci purge -age <minutes> -type ...):
  TRACE, CDUMP, INCIDENT, HM, UTSCDMP
What is NEVER purged:
  ALERT (alert logs) - and the text alert_<SID>.log / listener.log files

Options:
  --days N           Age in days (default: 30, minimum: 1)
  --include-audit    Also delete *.aud files older than N days in admin/*/adump and
                     <ORACLE_HOME>/rdbms/audit. Check your audit retention policy first!
  --execute          Really purge (asks for confirmation: type YES)
  --yes, -y          Do not ask for confirmation (for scripts)
  --grep / --grep-v  Limit the ADR homes / directories processed (matched against the TARGET column)
  --csv|--json|--raw, --no-header, --no-color

Examples:
  dbpurge                              (dry run, 30 days)
  dbpurge --days 14 --include-audit    (dry run)
  dbpurge --days 14 --execute
  dbpurge --grep tnslsnr --execute --yes
```

</details>

[Back to the function list](#function-reference)

### lscert

Certificate expiry for every kind of store a DBA meets: Oracle / OWM wallets (auto-login and password), PKCS#12, Java keystores and PEM/DER files.

**Features**

- Auto-login wallets via `orapki`; password wallets and `.p12/.pfx` via `openssl` (adds `-legacy` for older wallets on OpenSSL 3, falls back to `orapki`)
- Java keystores (`.jks`, `.keystore`) from OGG and OHS via `keytool`
- One hidden password prompt per protected store (Enter skips); passwords never appear on a command line
- Discovery: admin wallets, sqlnet.ora WALLET_LOCATION (read-only home aware), the OEM agent wallet, OGG deployment `etc/ssl`, `lscert_paths` and `DBA_CERT_PATHS`
- STATUS EXPIRED / CRIT / WARN / OK by days left (`--warn 30`, `--crit 7`); `--trusted` adds CA certificates

**Usage**

```text
lscert [LOCATION ...] [--trusted] [--no-prompt] [--warn DAYS] [--crit DAYS] [--depth N]
       [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Discovered wallets and certificates (no terminal: password stores are listed as PASSWORD REQUIRED)**

```text
$ lscert
  +--------------------------------------------------------+----------+--------+-------------------------------------------------------+--------------------+-------------+---------------------+
  |  LOCATION                                              |  FORMAT  |  TYPE  |  SUBJECT                                              |  EXPIRES           |  DAYS_LEFT  |  STATUS             |
  +--------------------------------------------------------+----------+--------+-------------------------------------------------------+--------------------+-------------+---------------------+
  |  /u01/app/oracle/admin/FINPRD/wallet                   |  SSO     |  USER  |  CN=finprd-db.example.com,OU=DBA,O=Example Corp,C=CA  |  2026-12-18 06:26  |  22         |  WARN               |
  |  /u01/app/oracle/admin/HRPRD/tls_wallet                |  P12     |  -     |  -                                                    |  -                 |  -          |  PASSWORD REQUIRED  |
  |  /u01/app/ogg/deployments/depl_fin/etc/ssl/server.pem  |  PEM     |  CERT  |  C=CA, O=Example Corp, CN=ogg-fin.example.com         |  2027-12-30 06:26  |  399        |  OK                 |
  +--------------------------------------------------------+----------+--------+-------------------------------------------------------+--------------------+-------------+---------------------+
```

**Interactive: one hidden prompt per password-protected store**

```text
$ lscert --trusted
Password for /u01/app/oracle/admin/HRPRD/tls_wallet/ewallet.p12 (Enter to skip): 
Password for /u01/app/oracle/ohs/keystores/keystore.jks (Enter to skip): 
  +--------------------------------------------------------+----------+-----------+-----------------------------------------------------------+--------------------+-------------+----------+
  |  LOCATION                                              |  FORMAT  |  TYPE     |  SUBJECT                                                  |  EXPIRES           |  DAYS_LEFT  |  STATUS  |
  +--------------------------------------------------------+----------+-----------+-----------------------------------------------------------+--------------------+-------------+----------+
  |  /u01/app/oracle/admin/FINPRD/wallet                   |  SSO     |  USER     |  CN=finprd-db.example.com,OU=DBA,O=Example Corp,C=CA      |  2026-12-18 06:26  |  22         |  WARN    |
  |  /u01/app/oracle/admin/FINPRD/wallet                   |  SSO     |  TRUSTED  |  CN=Example Issuing CA 01,O=Example Corp,C=CA             |  2030-11-24 06:26  |  1459       |  OK      |
  |  /u01/app/oracle/admin/FINPRD/wallet                   |  SSO     |  TRUSTED  |  CN=Example Root CA,O=Example Corp,C=CA                   |  2037-11-07 06:26  |  3999       |  OK      |
  |  /u01/app/oracle/admin/HRPRD/tls_wallet                |  P12     |  USER     |  C=CA, O=Example Corp, CN=hrprd-db.example.com            |  2026-11-30 06:26  |  4          |  CRIT    |
  |  /u01/app/oracle/admin/HRPRD/tls_wallet                |  P12     |  TRUSTED  |  C=CA, O=Example Corp, CN=Example Root CA                 |  2036-11-22 06:26  |  3649       |  OK      |
  |  /u01/app/ogg/deployments/depl_fin/etc/ssl/server.pem  |  PEM     |  CERT     |  C=CA, O=Example Corp, CN=ogg-fin.example.com             |  2027-12-30 06:26  |  399        |  OK      |
  |  /u01/app/oracle/ohs/keystores/keystore.jks            |  JKS     |  TRUSTED  |  examplerootca: CN=Example Root CA, O=Example Corp, C=CA  |  2036-11-22 06:26  |  3649       |  OK      |
  |  /u01/app/oracle/ohs/keystores/keystore.jks            |  JKS     |  USER     |  ohsserver: CN=ohs01.example.com, O=Example Corp, C=CA    |  2027-01-25 06:26  |  60         |  OK      |
  +--------------------------------------------------------+----------+-----------+-----------------------------------------------------------+--------------------+-------------+----------+
```

**One Java keystore without a password (listed without integrity check)**

```text
$ lscert /u01/app/oracle/ohs/keystores/keystore.jks --no-prompt --csv
LOCATION,FORMAT,TYPE,SUBJECT,EXPIRES,DAYS_LEFT,STATUS
/u01/app/oracle/ohs/keystores/keystore.jks,JKS,USER,"ohsserver: CN=ohs01.example.com, O=Example Corp, C=CA",2027-01-25 06:26,60,OK
```

<details>
<summary>Full <code>lscert --help</code></summary>

```text
Usage: lscert [LOCATION ...] [--trusted] [--no-prompt] [--warn DAYS] [--crit DAYS] [--depth N]
              [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Lists certificates and their expiry dates from every kind of store a DBA meets:

  FORMAT  Store                                        Password needed?
  SSO     Oracle / OWM auto-login wallet (cwallet.sso)  no
  P12     Oracle / OWM password wallet (ewallet.p12     yes - prompted per wallet
          without cwallet.sso), .p12 / .pfx files
  JKS     Java keystores (.jks, .keystore) - OGG, OHS   yes - prompted per keystore
          (Enter on an empty prompt lists a JKS without integrity check)
  PEM/DER Certificate files (.pem .crt .cer .der)       no

Discovery (when no LOCATION is given):
  <ORACLE_BASE>/admin/*/{wallet,xdb_wallet,tls_wallet}, /u01/app/oracle/.wallet,
  WALLET_LOCATION in sqlnet.ora of every home (ORACLE_BASE_HOME aware, so read-only
  Oracle homes are covered), the OEM agent wallet,
  the etc/ssl directory of every running OGG Microservices deployment, the
  lscert_paths variable at the top of this function and DBA_CERT_PATHS (colon separated).
  Directories are searched up to --depth levels (default 4).
LOCATION can be a wallet directory, a directory to search, or a single file.

Passwords:
  Each password-protected store gets its own hidden prompt (different passwords per
  wallet are expected). Press Enter to skip a store. Passwords are never put on a
  command line (they are passed to openssl / keytool through a file descriptor),
  are not stored and are cleared after use.
  Without a terminal, or with --no-prompt, password stores are listed with STATUS
  'PASSWORD REQUIRED' (DBA_WALLET_PWD is used if set - for scripted single-store runs).

Columns: LOCATION, FORMAT, TYPE, SUBJECT, EXPIRES, DAYS_LEFT, STATUS
  TYPE    USER (certificate with a private key), TRUSTED (CA / trusted certificate),
          CERT (single certificate file)
  STATUS  EXPIRED / CRIT (<= --crit days) / WARN (<= --warn days) / OK /
          UNKNOWN (no validity date reported) / PASSWORD REQUIRED / ERROR

Options:
  --trusted        Include trusted (CA) certificates (default: user certificates only)
  --no-prompt      Never prompt for passwords
  --warn DAYS      WARN threshold (default: 30)
  --crit DAYS      CRIT threshold (default: 7)
  --depth N        Directory search depth (default: 4)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Tools used: orapki (auto-login wallets), openssl (P12 and PEM/DER; '-legacy' is added
automatically when OpenSSL 3 needs it for older wallets), keytool (JKS; taken from the
PATH or the jdk of any Oracle home). If openssl cannot open a password wallet, orapki
is run and asks for the password itself.

Return code: 0 = nothing expiring within --crit, 2 = EXPIRED/CRIT found, 1 = error

Examples:
  lscert
  lscert --trusted
  lscert /u01/app/oracle/admin/PRD/wallet
  lscert /u01/app/ogg/deployments --grep -v TRUSTED
  lscert /u01/app/oracle/ohs/keystores/server.jks
```

</details>

[Back to the function list](#function-reference)

## Oracle Enterprise Manager agent

### lsagent

OEM agent health in one row: state, targets, uploads, pending files, heartbeat and blackouts.

**Features**

- DOWN when the agent is not running; CRIT when the heartbeat is not Ok
- WARN for many pending files (`--pending`), an old last upload (`--upload-mins`), not ready, or an active blackout
- `--detail` lists every field of `emctl status agent`
- Agent found via `DBA_AGENT_INST`, the running agent or `lsoh`

**Usage**

```text
lsagent [--detail] [--pending N] [--upload-mins N]
        [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**OEM agent health in one row**

```text
$ lsagent
  +------------------------------------+--------------+---------------------+-----------+-----------------------+------------------+-----------------+-------------+-------------+----------+
  |  AGENT_INST                        |  VERSION     |  STATE              |  TARGETS  |  LAST_UPLOAD          |  UPLOAD_AGE_MIN  |  PENDING_FILES  |  HEARTBEAT  |  BLACKOUTS  |  STATUS  |
  +------------------------------------+--------------+---------------------+-----------+-----------------------+------------------+-----------------+-------------+-------------+----------+
  |  /u01/app/oracle/agent/agent_inst  |  13.5.0.0.0  |  Running and Ready  |  31       |  2026-11-25 06:22:12  |  10              |  2              |  Ok         |  0          |  OK      |
  +------------------------------------+--------------+---------------------+-----------+-----------------------+------------------+-----------------+-------------+-------------+----------+
```

**Every field of `emctl status agent`**

```text
$ lsagent --detail
  +------------------------------------------------+------------------------------------------------------+
  |  KEY                                           |  VALUE                                               |
  +------------------------------------------------+------------------------------------------------------+
  |  Agent Version                                 |  13.5.0.0.0                                          |
  |  OMS Version                                   |  13.5.0.0.0                                          |
  |  Protocol Version                              |  12.1.0.1.0                                          |
  |  Agent Home                                    |  /u01/app/oracle/agent/agent_inst                    |
  |  Agent Log Directory                           |  /u01/app/oracle/agent/agent_inst/sysman/log         |
  |  Agent Binaries                                |  /u01/app/oracle/agent/agent_13.5.0.0.0              |
  |  Core JAR Location                             |  /u01/app/oracle/agent/agent_13.5.0.0.0/jlib         |
  |  Agent Process ID                              |  41022                                               |
  |  Parent Process ID                             |  40977                                               |
  |  Agent URL                                     |  https://dbhost01.example.com:3872/emd/main/         |
  |  Local Agent URL in NAT                        |  https://dbhost01.example.com:3872/emd/main/         |
  |  Repository URL                                |  https://oms01.example.com:4903/empbs/upload         |
  |  Started at                                    |  2026-11-13 06:26:12                                 |
  |  Started by user                               |  oracle                                              |
  |  Operating System                              |  Linux version 5.14.0-427.13.1.el9_4.x86_64 (amd64)  |
  |  Number of Targets                             |  31                                                  |
  |  Last Reload                                   |  (none)                                              |
  |  Last successful upload                        |  2026-11-25 06:22:12                                 |
  |  Last attempted upload                         |  2026-11-25 06:22:12                                 |
  |  Total Megabytes of XML files uploaded so far  |  1,224.61                                            |
  |  Number of XML files pending upload            |  2                                                   |
  |  Size of XML files pending upload(MB)          |  0.01                                                |
  |  Available disk space on upload filesystem     |  61.20%                                              |
  |  Collection Status                             |  Collections enabled                                 |
  |  Heartbeat Status                              |  Ok                                                  |
  |  Last attempted heartbeat to OMS               |  2026-11-25 06:25:12                                 |
  |  Last successful heartbeat to OMS              |  2026-11-25 06:25:12                                 |
  |  State                                         |  Agent is Running and Ready                          |
  +------------------------------------------------+------------------------------------------------------+
```

<details>
<summary>Full <code>lsagent --help</code></summary>

```text
Usage: lsagent [--detail] [--pending N] [--upload-mins N]
               [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Status of the local OEM agent from 'emctl status agent' and 'emctl status blackout'.

Default columns:
  AGENT_INST, VERSION, STATE, TARGETS, LAST_UPLOAD, UPLOAD_AGE_MIN, PENDING_FILES,
  HEARTBEAT, BLACKOUTS, STATUS
STATUS rules:
  DOWN   agent not running
  CRIT   heartbeat status is not Ok
  WARN   pending upload files > --pending, last upload older than --upload-mins,
         or an active agent-side blackout
  OK     otherwise

Options:
  --detail          Every 'emctl status agent' field as KEY | VALUE
  --pending N       Pending XML files threshold (default: 100)
  --upload-mins N   Last successful upload age threshold in minutes (default: 60)
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Notes:
  - Agent discovery: DBA_AGENT_INST, the running agent process, then lsoh (AGNT home).

Examples:
  lsagent
  lsagent --detail
```

</details>

[Back to the function list](#function-reference)

### emblackout

Lists, starts and stops OEM agent-side blackouts with a standard name, a mandatory reason and a duration.

**Features**

- Generated names: `DBA_<user>_<YYYYMMDD_HHMM>_<reason>`
- Node-level blackout or specific targets (`--target NAME:TYPE`)
- `--duration` is required (30m, 2h, 1d ...) and capped by `--max-hours` (default 72)
- `--dry-run` shows the `emctl` command; start and stop ask for YES unless `--yes`

**Usage**

```text
emblackout list  [--csv|--json|--raw] [--no-header]
emblackout start --reason "TEXT" --duration DUR [--target NAME:TYPE ...] [--name NAME]
                 [--max-hours N] [--dry-run] [--yes]
emblackout stop  --name NAME [--yes]
```

**Examples**

**Show the generated name and emctl command**

```text
$ emblackout start --reason 'OOP patch 19.32' --duration 3h --dry-run
Blackout : DBA_oracle_20261125_0632_OOP_patch_19_32
Scope    : whole node (-nodeLevel)
Duration : 3h (emctl -d '03:00')
Command  : /u01/app/oracle/agent/agent_inst/bin/emctl start blackout DBA_oracle_20261125_0632_OOP_patch_19_32 -nodeLevel -d 03:00
Dry run - nothing started.
```

**Start a node-level blackout (asks for YES)**

```text
$ emblackout start --reason 'OOP patch 19.32' --duration 3h
Blackout : DBA_oracle_20261125_0632_OOP_patch_19_32
Scope    : whole node (-nodeLevel)
Duration : 3h (emctl -d '03:00')
Command  : /u01/app/oracle/agent/agent_inst/bin/emctl start blackout DBA_oracle_20261125_0632_OOP_patch_19_32 -nodeLevel -d 03:00
Start this blackout? Type YES to continue: YES
Blackout DBA_oracle_20261125_0632_OOP_patch_19_32 added successfully
EMD_CTL blackout command started
```

**Agent-side blackouts**

```text
$ emblackout list
  +--------------------------------------------+--------------------+-----------------------------------------------+-----------+
  |  NAME                                      |  TARGETS           |  TIME                                         |  EXPIRED  |
  +--------------------------------------------+--------------------+-----------------------------------------------+-----------+
  |  DBA_oracle_20261125_0900_OOP_patch_19_32  |  (dbhost01:host,)  |  ({2026-11-25 09:00:00,2026-11-25 12:00:00})  |  False    |
  +--------------------------------------------+--------------------+-----------------------------------------------+-----------+
```

**Stop a blackout**

```text
$ emblackout stop --name DBA_oracle_20261125_0900_OOP_patch_19_32 --yes
Blackout DBA_oracle_20261125_0900_OOP_patch_19_32 stopped successfully
```

<details>
<summary>Full <code>emblackout --help</code></summary>

```text
Usage:
  emblackout list  [--csv|--json|--raw] [--no-header]
  emblackout start --reason "TEXT" --duration DUR [--target NAME:TYPE ...] [--name NAME]
                   [--max-hours N] [--dry-run] [--yes]
  emblackout stop  --name NAME [--yes]

Agent-side (emctl) blackouts on this host.

start:
  --reason TEXT      Required. Becomes part of the blackout name.
  --duration DUR     Required. 30m, 2h, 1d ... (the blackout ends automatically)
  --target N:T       Black out only this target (repeatable), e.g. PRD_host:oracle_database
                     Without --target the whole node is blacked out (-nodeLevel).
  --name NAME        Override the generated name
                     (default: DBA_<user>_<YYYYMMDD_HHMM>_<reason>)
  --max-hours N      Safety limit for --duration (default: 72)
  --dry-run          Show the emctl command, do not run it
  --yes, -y          Do not ask for confirmation

stop:
  --name NAME        Blackout to stop (see: emblackout list)

Notes:
  - Agent-side blackouts are only known to this agent; OMS-side blackouts are not listed.
  - Agent discovery: DBA_AGENT_INST, the running agent process, then lsoh (AGNT home).

Examples:
  emblackout list
  emblackout start --reason "OOP patch 19.32" --duration 3h
  emblackout start --reason "PRD restart" --duration 45m --target PRD_host1:oracle_database
  emblackout stop --name DBA_oracle_20261113_2100_OOP_patch_19_32
```

</details>

[Back to the function list](#function-reference)

### lsemtgt

Compares the targets registered with the local OEM agent with the homes really in use, and can fix them through EMCLI.

**Features**

- oracle_database, oracle_listener (OracleHome and ListenerOraDir), osm_instance, has, cluster and oracle_home targets
- Expected values from the running processes, oratab, srvctl and the Grid home
- MISMATCH / MISSING (oracle_home target whose directory was removed) / UNKNOWN
- `--fix` prints `emcli modify_target` commands; `--apply` runs them after YES (adds `-on_agent` when your EMCLI supports it)

**Usage**

```text
lsemtgt [--all] [--type T1,T2] [--fix | --apply [--yes]]
        [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Agent target properties that do not match the homes in use**

```text
$ lsemtgt
  +---------------------------+-------------------+--------------------+----------------------------------------------------------+--------------------------------------------+-----------------------+----------------------------------------------+
  |  TARGET                   |  TYPE             |  PROPERTY          |  AGENT_VALUE                                             |  EXPECTED                                  |  SOURCE               |  STATUS                                      |
  +---------------------------+-------------------+--------------------+----------------------------------------------------------+--------------------------------------------+-----------------------+----------------------------------------------+
  |  AIDEV                    |  oracle_database  |  OracleHome        |  /u01/app/oracle/product/19.32.0/dbhome_1                |  /u01/app/oracle/product/23.26.1/dbhome_1  |  running PMON         |  MISMATCH                                    |
  |  LISTENER_dbhost01        |  oracle_listener  |  OracleHome        |  /u01/app/oracle/product/19.31.0/dbhome_1                |  /u01/app/19.32.0/grid                     |  running tnslsnr      |  MISMATCH                                    |
  |  LISTENER_dbhost01        |  oracle_listener  |  ListenerOraDir    |  /u01/app/oracle/product/19.31.0/dbhome_1/network/admin  |  /u01/app/19.32.0/grid/network/admin       |  running tnslsnr      |  MISMATCH                                    |
  |  has_dbhost01             |  has              |  OracleHome        |  /u01/app/19.31.0/grid                                   |  /u01/app/19.32.0/grid                     |  Grid home (olr.loc)  |  MISMATCH                                    |
  |  OraDB19Home1_1_dbhost01  |  oracle_home      |  install location  |  /u01/app/oracle/product/19.30.0/dbhome_1                |  exists                                    |  filesystem           |  MISSING (home removed - delete the target)  |
  +---------------------------+-------------------+--------------------+----------------------------------------------------------+--------------------------------------------+-----------------------+----------------------------------------------+
```

**Every checked property of some target types**

```text
$ lsemtgt --all --type oracle_listener,has
  +---------------------+-------------------+------------------+----------------------------------------------------------+---------------------------------------+-----------------------+------------+
  |  TARGET             |  TYPE             |  PROPERTY        |  AGENT_VALUE                                             |  EXPECTED                             |  SOURCE               |  STATUS    |
  +---------------------+-------------------+------------------+----------------------------------------------------------+---------------------------------------+-----------------------+------------+
  |  LISTENER_dbhost01  |  oracle_listener  |  OracleHome      |  /u01/app/oracle/product/19.31.0/dbhome_1                |  /u01/app/19.32.0/grid                |  running tnslsnr      |  MISMATCH  |
  |  LISTENER_dbhost01  |  oracle_listener  |  ListenerOraDir  |  /u01/app/oracle/product/19.31.0/dbhome_1/network/admin  |  /u01/app/19.32.0/grid/network/admin  |  running tnslsnr      |  MISMATCH  |
  |  has_dbhost01       |  has              |  OracleHome      |  /u01/app/19.31.0/grid                                   |  /u01/app/19.32.0/grid                |  Grid home (olr.loc)  |  MISMATCH  |
  +---------------------+-------------------+------------------+----------------------------------------------------------+---------------------------------------+-----------------------+------------+
```

**Print the emcli commands that fix the mismatches**

```text
$ lsemtgt --fix
  +---------------------------+-------------------+--------------------+----------------------------------------------------------+--------------------------------------------+-----------------------+----------------------------------------------+
  |  TARGET                   |  TYPE             |  PROPERTY          |  AGENT_VALUE                                             |  EXPECTED                                  |  SOURCE               |  STATUS                                      |
  +---------------------------+-------------------+--------------------+----------------------------------------------------------+--------------------------------------------+-----------------------+----------------------------------------------+
  |  AIDEV                    |  oracle_database  |  OracleHome        |  /u01/app/oracle/product/19.32.0/dbhome_1                |  /u01/app/oracle/product/23.26.1/dbhome_1  |  running PMON         |  MISMATCH                                    |
  |  LISTENER_dbhost01        |  oracle_listener  |  OracleHome        |  /u01/app/oracle/product/19.31.0/dbhome_1                |  /u01/app/19.32.0/grid                     |  running tnslsnr      |  MISMATCH                                    |
  |  LISTENER_dbhost01        |  oracle_listener  |  ListenerOraDir    |  /u01/app/oracle/product/19.31.0/dbhome_1/network/admin  |  /u01/app/19.32.0/grid/network/admin       |  running tnslsnr      |  MISMATCH                                    |
  |  has_dbhost01             |  has              |  OracleHome        |  /u01/app/19.31.0/grid                                   |  /u01/app/19.32.0/grid                     |  Grid home (olr.loc)  |  MISMATCH                                    |
  |  OraDB19Home1_1_dbhost01  |  oracle_home      |  install location  |  /u01/app/oracle/product/19.30.0/dbhome_1                |  exists                                    |  filesystem           |  MISSING (home removed - delete the target)  |
  +---------------------------+-------------------+--------------------+----------------------------------------------------------+--------------------------------------------+-----------------------+----------------------------------------------+

-- emcli commands (run 'emcli login' and 'emcli sync' first):
emcli modify_target -name="AIDEV" -type="oracle_database" -properties="OracleHome:/u01/app/oracle/product/23.26.1/dbhome_1" -on_agent
emcli modify_target -name="LISTENER_dbhost01" -type="oracle_listener" -properties="OracleHome:/u01/app/19.32.0/grid;ListenerOraDir:/u01/app/19.32.0/grid/network/admin" -on_agent
emcli modify_target -name="has_dbhost01" -type="has" -properties="OracleHome:/u01/app/19.32.0/grid" -on_agent
```

**Run them (EMCLI must be logged in)**

```text
$ lsemtgt --apply --yes
  +---------------------------+-------------------+--------------------+----------------------------------------------------------+--------------------------------------------+-----------------------+----------------------------------------------+
  |  TARGET                   |  TYPE             |  PROPERTY          |  AGENT_VALUE                                             |  EXPECTED                                  |  SOURCE               |  STATUS                                      |
  +---------------------------+-------------------+--------------------+----------------------------------------------------------+--------------------------------------------+-----------------------+----------------------------------------------+
  |  AIDEV                    |  oracle_database  |  OracleHome        |  /u01/app/oracle/product/19.32.0/dbhome_1                |  /u01/app/oracle/product/23.26.1/dbhome_1  |  running PMON         |  MISMATCH                                    |
  |  LISTENER_dbhost01        |  oracle_listener  |  OracleHome        |  /u01/app/oracle/product/19.31.0/dbhome_1                |  /u01/app/19.32.0/grid                     |  running tnslsnr      |  MISMATCH                                    |
  |  LISTENER_dbhost01        |  oracle_listener  |  ListenerOraDir    |  /u01/app/oracle/product/19.31.0/dbhome_1/network/admin  |  /u01/app/19.32.0/grid/network/admin       |  running tnslsnr      |  MISMATCH                                    |
  |  has_dbhost01             |  has              |  OracleHome        |  /u01/app/19.31.0/grid                                   |  /u01/app/19.32.0/grid                     |  Grid home (olr.loc)  |  MISMATCH                                    |
  |  OraDB19Home1_1_dbhost01  |  oracle_home      |  install location  |  /u01/app/oracle/product/19.30.0/dbhome_1                |  exists                                    |  filesystem           |  MISSING (home removed - delete the target)  |
  +---------------------------+-------------------+--------------------+----------------------------------------------------------+--------------------------------------------+-----------------------+----------------------------------------------+

-- emcli commands (run 'emcli login' and 'emcli sync' first):
emcli modify_target -name="AIDEV" -type="oracle_database" -properties="OracleHome:/u01/app/oracle/product/23.26.1/dbhome_1" -on_agent
emcli modify_target -name="LISTENER_dbhost01" -type="oracle_listener" -properties="OracleHome:/u01/app/19.32.0/grid;ListenerOraDir:/u01/app/19.32.0/grid/network/admin" -on_agent
emcli modify_target -name="has_dbhost01" -type="has" -properties="OracleHome:/u01/app/19.32.0/grid" -on_agent

  +---------------------+-------------------+----------+
  |  TARGET             |  TYPE             |  RESULT  |
  +---------------------+-------------------+----------+
  |  has_dbhost01       |  has              |  OK      |
  |  AIDEV              |  oracle_database  |  OK      |
  |  LISTENER_dbhost01  |  oracle_listener  |  OK      |
  +---------------------+-------------------+----------+
```

<details>
<summary>Full <code>lsemtgt --help</code></summary>

```text
Usage: lsemtgt [--all] [--type T1,T2] [--fix | --apply [--yes]]
               [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Compares the properties of the targets registered with the LOCAL OEM agent
(<agent_inst>/sysman/emd/targets.xml) with what is really in use on this host.
Typical use: after out-of-place patching, find targets that still point to the old home.

Target types and properties checked:
  oracle_database   OracleHome      running PMON binary home (oratab when the DB is down)
  oracle_listener   OracleHome      running tnslsnr binary home (srvctl config when not running)
                    ListenerOraDir  TNS_ADMIN of the running listener, else the home's network/admin
                                    (ORACLE_BASE_HOME aware - correct for read-only homes)
  osm_instance      OracleHome      running ASM binary home (Grid home when ASM is down)
  has               OracleHome      Grid Infrastructure / Oracle Restart home (olr.loc)
  cluster           OracleHome      Grid Infrastructure home (olr.loc)
  oracle_home       install location   the directory still exists (stale target after a home was removed)

Columns: TARGET, TYPE, PROPERTY, AGENT_VALUE, EXPECTED, SOURCE, STATUS
  STATUS  MATCH / MISMATCH / UNKNOWN (expected value could not be determined) /
          MISSING (oracle_home target whose directory no longer exists)
  By default only MISMATCH / MISSING / UNKNOWN rows are shown; --all shows every row.

Fixing the targets (updates the OMS repository; the agent is updated too when the
installed EMCLI supports -on_agent):
  --fix        Print one 'emcli modify_target' command per target that needs changes.
  --apply      Run those commands after you type YES (or --yes). Needs EMCLI in the PATH
               (or DBA_EMCLI=/path/to/emcli) and an EMCLI session that is already
               logged in ('emcli login -username=...' + 'emcli sync').
               '-on_agent' is only added when 'emcli help modify_target' lists it.
  Do NOT edit targets.xml by hand - the OMS would not see the change.

Options:
  --all            Show matching rows too
  --type LIST      Only these target types (comma separated)
  --fix            Print the emcli commands
  --apply          Run the emcli commands (asks for confirmation)
  --yes, -y        No confirmation with --apply
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Notes:
  - Agent discovery: DBA_AGENT_INST, the running agent process, then lsoh (AGNT home).
  - RAC-level targets (rac_database, cluster databases) are not checked.

Return code: 0 = nothing to fix, 2 = MISMATCH/MISSING found, 1 = error

Examples:
  lsemtgt
  lsemtgt --all --type oracle_listener
  lsemtgt --fix
  lsemtgt --apply
```

</details>

[Back to the function list](#function-reference)

## Clusterware / Oracle Restart

### lscrs

Clusterware or Oracle Restart resources whose STATE does not match the TARGET.

**Features**

- Stack status row first (HAS / CRS online)
- MISMATCH when TARGET is ONLINE but the resource is not; WARN when TARGET is OFFLINE
- `--all` shows every resource, `--type REGEX` filters resource types
- Return code 2 when a MISMATCH is found

**Usage**

```text
lscrs [--all] [--type REGEX] [--grep PATTERN] [--grep-v PATTERN]
      [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Resources whose STATE does not match the TARGET**

```text
$ lscrs
  +----------------------------+---------------------+-----------+----------------+------------+-------------------------+
  |  NAME                      |  TYPE               |  TARGET   |  STATE         |  SERVER    |  STATUS                 |
  +----------------------------+---------------------+-----------+----------------+------------+-------------------------+
  |  (stack)                   |  Oracle Restart     |  ONLINE   |  -             |  dbhost01  |  OK (HAS online)        |
  |  ora.LISTENER_DG.lsnr      |  ora.listener.type  |  OFFLINE  |  OFFLINE       |  -         |  WARN (target OFFLINE)  |
  |  ora.finprd_a.fin_rpt.svc  |  ora.service.type   |  ONLINE   |  OFFLINE       |  -         |  MISMATCH               |
  |  ora.hrprd.db              |  ora.database.type  |  ONLINE   |  INTERMEDIATE  |  dbhost01  |  MISMATCH               |
  +----------------------------+---------------------+-----------+----------------+------------+-------------------------+
```

**Every database and listener resource**

```text
$ lscrs --all --type 'database|listener'
  +------------------------+---------------------+-----------+----------------+------------+-------------------------+
  |  NAME                  |  TYPE               |  TARGET   |  STATE         |  SERVER    |  STATUS                 |
  +------------------------+---------------------+-----------+----------------+------------+-------------------------+
  |  (stack)               |  Oracle Restart     |  ONLINE   |  -             |  dbhost01  |  OK (HAS online)        |
  |  ora.LISTENER.lsnr     |  ora.listener.type  |  ONLINE   |  ONLINE        |  dbhost01  |  OK                     |
  |  ora.LISTENER_DG.lsnr  |  ora.listener.type  |  OFFLINE  |  OFFLINE       |  -         |  WARN (target OFFLINE)  |
  |  ora.finprd_a.db       |  ora.database.type  |  ONLINE   |  ONLINE        |  dbhost01  |  OK                     |
  |  ora.hrprd.db          |  ora.database.type  |  ONLINE   |  INTERMEDIATE  |  dbhost01  |  MISMATCH               |
  +------------------------+---------------------+-----------+----------------+------------+-------------------------+
```

<details>
<summary>Full <code>lscrs --help</code></summary>

```text
Usage: lscrs [--all] [--type REGEX] [--grep PATTERN] [--grep-v PATTERN]
             [--csv|--json|--raw] [--no-header] [--no-color]

Clusterware (RAC) or Oracle Restart (HAS) resources from 'crsctl stat res', one row per
resource and server, with the stack status first.

Columns: NAME, TYPE, TARGET, STATE, SERVER, STATUS
  STATUS  OK        STATE matches TARGET
          MISMATCH  TARGET is ONLINE but STATE is OFFLINE / INTERMEDIATE / UNKNOWN
          WARN      TARGET is OFFLINE (resource stopped or disabled on purpose?)
By default only rows that are not OK are shown (plus the stack row); --all shows everything.

Options:
  --all          Show every resource
  --type REGEX   Only resource types matching REGEX, e.g. 'database|listener', 'diskgroup'
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color

Notes:
  - The Grid home is read from /etc/oracle/olr.loc.
  - Resources with an empty TARGET (e.g. ora.cvu on some releases) are reported as OK.

Return code: 0 = all OK, 2 = MISMATCH found, 1 = error

Examples:
  lscrs
  lscrs --all --type database
```

</details>

[Back to the function list](#function-reference)

## Utilities

### passgen

Generates strong random passwords.

**Features**

- Minimum length 15; at least one upper case letter, lower case letter, digit and underscore; never starts with a digit or underscore
- Warns above 30 characters (limit of Oracle releases before 23ai)
- Banner on stderr, passwords on stdout - `pw=$(passgen 20)` captures only the password

**Usage**

```text
passgen <length> [rounds]
```

**Examples**

**One 20-character password**

```text
$ passgen 20

------------------------------
 Password Length : 20
 Password Count  : 1
------------------------------

SjLKb36QHqU3dJIv9_bR
```

**Three 24-character passwords**

```text
$ passgen 24 3

------------------------------
 Password Length : 24
 Password Count  : 3
------------------------------

mYYxbd1eHv7xcOnPc_lPTwTA
qYrLwfzD1on68_WDe3azKElK
BDqwcSYYyzi_LDPK98NbDfu7
```

**Capture only the password - the banner goes to stderr**

```text
$ pw=$(passgen 20) && echo "${#pw} characters"
20 characters
```

<details>
<summary>Full <code>passgen --help</code></summary>

```text
Usage:
  passgen <length> [rounds]

Description:
  Generate one or more strong random passwords.
  Passwords are written to stdout (one per line); the banner goes to stderr,
  so  pw=$(passgen 20)  captures only the password.

Password Rules:
  - Minimum length: 15
  - Must contain at least one uppercase letter
  - Must contain at least one lowercase letter
  - Must contain at least one digit
  - Must contain at least one underscore (_)
  - Cannot start with a digit or an underscore
  - Cannot end with an underscore

Notes:
  - Oracle releases before 23ai limit passwords to 30 characters; a warning is shown above 30.

Arguments:
  length    Password length (minimum 15)
  rounds    Number of passwords to generate (default: 1, minimum 1)

Examples:
  passgen 20
  passgen 24 5
  pw=$(passgen 20)
```

</details>

[Back to the function list](#function-reference)

### wclip

Copies stdin to the Windows clipboard through a modified PuTTY / KiTTY (ANSI printer pass-through).

**Features**

- Usage: `<command> | wclip` or `wclip < file`

**Usage**

```text
<command> | wclip
wclip < file
```

**Examples**

**Copy the output of any command to the Windows clipboard (PuTTY/KiTTY with printer pass-through)**

```bash
lsoh --csv | wclip
```

<details>
<summary>Full <code>wclip --help</code></summary>

```text
Usage:
  <command> | wclip
  wclip < file

Sends stdin to the terminal using the ANSI printer pass-through sequence
(ESC[5i ... ESC[4i). A modified PuTTY/KiTTY captures it into the Windows clipboard.
```

</details>

[Back to the function list](#function-reference)

### lsmenu

Finds `/bin/sh ./menu` processes left behind by closed sessions (no terminal, or parent exited) and optionally kills them.

**Features**

- Orphaned = no controlling terminal (TTY `?`, the session that started it is gone - closed PuTTY window, dropped VPN, ssh timeout) **or** parent exited (PID 1 / systemd subreaper); the REASON column says which
- Menus whose session ended often loop on the closed terminal and burn a full CPU each: rows are sorted by CPU_TIME, highest first
- Exact command-line match - parent shells are never matched or killed
- `--all` also lists menus that still have a terminal (ORPHANED = NO); `--kill` never touches those
- `--kill` sends SIGTERM, then SIGKILL after 5 seconds; asks for YES unless `--yes`
- `--user` (default oracle), `--pattern` for a different menu command line
- Return code 2 when orphaned menus are found (list mode)

**Usage**

```text
lsmenu [--all] [--kill [--yes]] [--user USER] [--pattern TEXT]
       [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]
```

**Examples**

**Orphaned menus, busiest first (the first four have been spinning on a closed terminal for days)**

```text
$ lsmenu
Orphaned 'menu' processes found for user 'oracle': 6
  +-----------+-----------+-----------+----------+-------+--------------------+---------------+------------+------------+------------------------------+
  |  PID      |  PPID     |  PARENT   |  USER    |  TTY  |  STARTED           |  ELAPSED      |  CPU_TIME  |  ORPHANED  |  REASON                      |
  +-----------+-----------+-----------+----------+-------+--------------------+---------------+------------+------------+------------------------------+
  |  2210417  |  2210388  |  bash     |  oracle  |  ?    |  2026-11-04 09:12  |  20-22:10:41  |  20:05:22  |  YES       |  no terminal                 |
  |  1402236  |  1402207  |  bash     |  oracle  |  ?    |  2026-11-05 07:40  |  19-23:42:03  |  19:01:49  |  YES       |  no terminal                 |
  |  1755310  |  1755274  |  bash     |  oracle  |  ?    |  2026-11-05 10:02  |  19-21:20:15  |  18:48:22  |  YES       |  no terminal                 |
  |  3021988  |  3021950  |  bash     |  oracle  |  ?    |  2026-11-09 13:55  |  15-17:27:09  |  14:40:20  |  YES       |  no terminal                 |
  |  1610562  |  1        |  systemd  |  oracle  |  ?    |  2026-11-05 08:31  |  19-22:51:12  |  00:00:00  |  YES       |  no terminal, parent exited  |
  |  1893745  |  1893702  |  bash     |  oracle  |  ?    |  2026-11-05 14:17  |  19-17:05:44  |  00:00:00  |  YES       |  no terminal                 |
  +-----------+-----------+-----------+----------+-------+--------------------+---------------+------------+------------+------------------------------+
```

**Also show menus whose session is still active**

```text
$ lsmenu --all
Orphaned 'menu' processes found for user 'oracle': 6
  +-----------+-----------+-----------+----------+---------+--------------------+---------------+------------+------------+------------------------------+
  |  PID      |  PPID     |  PARENT   |  USER    |  TTY    |  STARTED           |  ELAPSED      |  CPU_TIME  |  ORPHANED  |  REASON                      |
  +-----------+-----------+-----------+----------+---------+--------------------+---------------+------------+------------+------------------------------+
  |  2210417  |  2210388  |  bash     |  oracle  |  ?      |  2026-11-04 09:12  |  20-22:10:41  |  20:05:22  |  YES       |  no terminal                 |
  |  1402236  |  1402207  |  bash     |  oracle  |  ?      |  2026-11-05 07:40  |  19-23:42:03  |  19:01:49  |  YES       |  no terminal                 |
  |  1755310  |  1755274  |  bash     |  oracle  |  ?      |  2026-11-05 10:02  |  19-21:20:15  |  18:48:22  |  YES       |  no terminal                 |
  |  3021988  |  3021950  |  bash     |  oracle  |  ?      |  2026-11-09 13:55  |  15-17:27:09  |  14:40:20  |  YES       |  no terminal                 |
  |  1610562  |  1        |  systemd  |  oracle  |  ?      |  2026-11-05 08:31  |  19-22:51:12  |  00:00:00  |  YES       |  no terminal, parent exited  |
  |  1893745  |  1893702  |  bash     |  oracle  |  ?      |  2026-11-05 14:17  |  19-17:05:44  |  00:00:00  |  YES       |  no terminal                 |
  |  3355128  |  3355090  |  bash     |  oracle  |  pts/4  |  2026-11-25 08:02  |  00:21:38     |  00:00:00  |  NO        |  session active              |
  +-----------+-----------+-----------+----------+---------+--------------------+---------------+------------+------------+------------------------------+
```

**Only menus whose parent shell has exited, as CSV**

```text
$ lsmenu --csv --grep 'no terminal, parent'
Orphaned 'menu' processes found for user 'oracle': 6
PID,PPID,PARENT,USER,TTY,STARTED,ELAPSED,CPU_TIME,ORPHANED,REASON
1610562,1,systemd,oracle,?,2026-11-05 08:31,19-22:51:12,00:00:00,YES,"no terminal, parent exited"
```

**Kill them (asks for YES; SIGKILL for anything still alive after 5 seconds)**

```text
$ lsmenu --kill
Orphaned 'menu' processes found for user 'oracle': 6
  +-----------+-----------+-----------+----------+-------+--------------------+---------------+------------+------------+------------------------------+
  |  PID      |  PPID     |  PARENT   |  USER    |  TTY  |  STARTED           |  ELAPSED      |  CPU_TIME  |  ORPHANED  |  REASON                      |
  +-----------+-----------+-----------+----------+-------+--------------------+---------------+------------+------------+------------------------------+
  |  2210417  |  2210388  |  bash     |  oracle  |  ?    |  2026-11-04 09:12  |  20-22:10:41  |  20:05:22  |  YES       |  no terminal                 |
  |  1402236  |  1402207  |  bash     |  oracle  |  ?    |  2026-11-05 07:40  |  19-23:42:03  |  19:01:49  |  YES       |  no terminal                 |
  |  1755310  |  1755274  |  bash     |  oracle  |  ?    |  2026-11-05 10:02  |  19-21:20:15  |  18:48:22  |  YES       |  no terminal                 |
  |  3021988  |  3021950  |  bash     |  oracle  |  ?    |  2026-11-09 13:55  |  15-17:27:09  |  14:40:20  |  YES       |  no terminal                 |
  |  1610562  |  1        |  systemd  |  oracle  |  ?    |  2026-11-05 08:31  |  19-22:51:12  |  00:00:00  |  YES       |  no terminal, parent exited  |
  |  1893745  |  1893702  |  bash     |  oracle  |  ?    |  2026-11-05 14:17  |  19-17:05:44  |  00:00:00  |  YES       |  no terminal                 |
  +-----------+-----------+-----------+----------+-------+--------------------+---------------+------------+------------+------------------------------+
Kill 6 orphaned process(es)? Type YES to continue: YES
Terminated process ID: 1402236 (SIGTERM)
Terminated process ID: 1610562 (SIGTERM)
Terminated process ID: 1755310 (SIGTERM)
Terminated process ID: 2210417 (SIGTERM)
Terminated process ID: 3021988 (SIGTERM)
Killed process ID: 1893745 (SIGKILL)
Total orphaned processes killed: 6
```

**Nothing left to clean up**

```text
$ lsmenu
No orphaned 'menu' processes found for user 'oracle'.
```

<details>
<summary>Full <code>lsmenu --help</code></summary>

```text
Usage: lsmenu [--all] [--kill [--yes]] [--user USER] [--pattern TEXT]
              [--grep PATTERN] [--grep-v PATTERN] [--csv|--json|--raw] [--no-header] [--no-color]

Identify and optionally kill orphaned 'menu' processes ('/bin/sh ./menu').

A menu process is considered orphaned when:
  - it has no controlling terminal (TTY '?'): the login session that started it is
    gone (closed PuTTY window, dropped VPN, ssh timeout) - the usual case, even when
    its parent shell still exists; or
  - its parent has exited (parent PID 1 or a 'systemd' process).
Menus whose session has ended often loop on the closed terminal and burn a full
CPU each - check the CPU_TIME column.

Columns: PID, PPID, PARENT (parent command), USER, TTY, STARTED, ELAPSED, CPU_TIME,
         ORPHANED (YES/NO), REASON
Rows are sorted by CPU_TIME, highest first.

Options:
  --all             Also list menu processes that still have a terminal (ORPHANED = NO);
                    --kill never touches those
  --kill            Kill the orphaned processes: SIGTERM first, then SIGKILL for any
                    process still alive after 5 seconds. Asks for confirmation.
  --yes, -y         Do not ask for confirmation with --kill.
  --user USER       Owner of the menu processes (default: oracle).
  --pattern TEXT    Command line to look for (default: '/bin/sh ./menu'). The process
                    command line must be exactly TEXT (optionally followed by arguments),
                    so shells that merely mention it are never matched.
  --grep / --grep-v, --csv|--json|--raw, --no-header, --no-color
  -h, --help        Display this help message.

Notes:
  - Only the menu processes are killed, never their parent shells.
  - A menu started from cron, nohup or setsid also has no terminal and is listed as
    orphaned - review the list before using --kill.

Return code: 0 = none found or all killed, 2 = orphaned processes found (list mode),
             1 = error or a process could not be killed

Examples:
  lsmenu
  lsmenu --all
  lsmenu --kill
  lsmenu --kill --yes
```

</details>

[Back to the function list](#function-reference)

## Aliases

| Alias | Command |
|---|---|
| `sqld_` | `sqlplus / as sysdba` |
| `sqla_` | `sqlplus / as sysasm` |
| `rsql` | `sqlplus` |
| `rman_` | `rman target /` |
| `rrman` | `rman` |
| `asm_` | `asmcmd -p` |
| `dgm_` | `dgmgrl /` |
| `dgmd_` | `dgmgrl / as sysdba` |
| `kfodstat` | `kfod status=TRUE asm_diskstring="ORCL:*" disks=all dscvgroup=TRUE` |
| `crsctl_` | `crsctl` from the Grid home in `/etc/oracle/olr.loc` |
| `crsstat` | `crsctl stat res -t` from the Grid home |
| `cdh` / `cdb` / `cda` | `cd $ORACLE_HOME` / `$ORACLE_BASE` / `$ADR_HOME` (set by `setdb`) |
| `cdd` / `cddp` | `cd /dump/$ORACLE_SID/` / `/dump/$ORACLE_SID/dpdump` |
| `cdw` | `cd /u01/app/oracle/.wallet` |
| `cds` | `cd` to the scripts directory (edit the path in the file for your site) |
| `p_` / `pp_` / `px_` | `ps -ef` filtered by a pattern / PMON processes / SMON processes |
| `tail_` | `tail -1000f` |
| `nocomment` | `grep` without empty and comment lines |
| `ll` / `ll.` | `ls -l` / `ls -la` with directories first |

`DISPLAY` is set from `who am i` only for interactive shells and only when it is not already set (ssh X11 forwarding is never overridden).

## Bash utility functions

General-purpose helpers that the functions above use and that you can use in your own scripts:

| Function | Purpose |
|---|---|
| `printTable DELIM DATA [colorHeader] [displayTotalCount]` | Render delimited data as a boxed table (the renderer behind every table in this README) |
| `trimString`, `isEmptyString`, `repeatString`, `replaceString`, `removeEmptyLines` | String helpers |
| `escapeSearchPattern`, `escapeGrepSearchPattern` | Escape text for sed / grep |
| `checkNonEmptyString`, `checkExistFile`, `checkExistFolder` | Validation (print `FATAL` and return 1) |
| `checkNaturalNumber`, `checkPositiveInteger`, `isNaturalNumber`, `isPositiveInteger` | Number validation |
| `getFileName`, `getFileExtension`, `formatPath` | Path helpers |
| `getTemporaryFile`, `getTemporaryFolder`, `getTemporaryFolderRoot` | Temporary files (honor `TMPDIR`) |
| `isValidJSONContent`, `isValidJSONFile` | JSON validation (python) |
| `displayListeningPorts`, `isPortInUse` | Listening ports (lsof) |
| `header`, `fatal` | Colored section header; error message that returns 1 (never exits your shell) |

Functions whose name starts with `_dba_` are internal.

## About the examples

The example outputs in this README were produced by running ora_utils 3.5.2 against a lab host with fictitious data: Grid Infrastructure 19.32 (Oracle Restart with ASM), the databases FINPRD (19c CDB with two PDBs and two standbys), HRPRD (19c non-CDB still running from the 19.31 home after an out-of-place patch), CRMSTBY (mounted physical standby), AIDEV (26ai CDB) and DWTST (down), an OEM 13.5 agent and GoldenGate 21c Microservices. Dates, sizes and identifiers will of course differ on your systems.

## Author

Parsa Bahrami - [parsabahrami.com](https://parsabahrami.com/) - [nightowldbre.com](https://nightowldbre.com/)
