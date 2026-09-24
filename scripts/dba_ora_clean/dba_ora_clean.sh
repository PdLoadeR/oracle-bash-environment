#!/usr/bin/env bash
#============================================================================================================================
# Filename:     dba_ora_clean.sh
# Version:      v.2.7
# Author:       Parsa Bahrami (pb)
# Purpose:      Safe Oracle database-server cleanup with preflight, scoped execution, timeouts,
#               locking, ADRCI error detection, and per-database environment validation.
#
# Design:       Single, transportable Bash file. No companion configuration or library files.
# Default mode: Preflight. No deletion or database purge occurs unless --apply is supplied.
#
# Usage:
#   ./dba_ora_clean.sh --preflight
#   ./dba_ora_clean.sh --apply
#   ./dba_ora_clean.sh --apply --only filesystem
#   ./dba_ora_clean.sh --apply --only oem
#   ./dba_ora_clean.sh --apply --only adr
#   ./dba_ora_clean.sh --apply --only database
#
# Optional controls:
#   --allow-adr-schema-migration   Permit ADRCI "migrate schema" after DIA-49803.
#                                  Disabled by default because it changes ADR metadata.
#   --stop-on-error                Stop after the first failed phase or target.
#   --log-dir PATH                 Override the default ../log directory.
#
# Cleanup policy:
#   Oracle Home audit files        2 days
#   Database AUDIT_FILE_DEST files  2 days
#   Oracle Home rdbms trace files  32 days
#   CRS EVM logs                    32 days
#   Listener XML alert files        2 days
#   ADR-managed content            32 days, through ADRCI only
#   OEM Agent dumps/logs           14 days
#   Script execution logs          14 days
#   Traditional SYS.AUD$           365 days, deleted in batches of 10,000 rows
#   Scheduler job/window log       0 days
#   Unified audit trail            365 days
#
# Safety controls:
#   1. A non-blocking flock prevents concurrent cleanup runs.
#   2. Preflight is the default and reports planned work without changing data.
#   3. find, ADRCI, and SQLPlus operations have TERM/KILL timeouts.
#   4. Filesystem scans remain on one filesystem with find -xdev.
#   5. Candidate paths are validated before deletion.
#   6. ADR-managed directories are purged by ADRCI, not direct rm commands.
#   7. ADRCI output is inspected because ADRCI may return zero while printing DIA errors.
#   8. Each database is connected using the exact SID and Oracle Home from /etc/oratab.
#   9. A v$instance precheck requires OPEN status before database cleanup begins.
#  10. Automatic ADR schema migration is opt-in.
#
# Important operational notes:
#   - Root-owned ADR homes can return DIA-48191 / permission denied during an oracle-user run.
#     They are reported as failures and the script continues unless --stop-on-error is used.
#   - Stale ADR homes are still discovered by ADRCI and may be purged even when the associated
#     database or listener is no longer running.
#   - Review preflight output after patching because /etc/oratab may contain old and new homes.
#
# Version history:
# Date          Version   Who     Description
#---------------------------------------------------------------------------------------------------------------------------
# 20250825      1.0       pb      Initla Release
# 20250829      1.0.1     pb      Updated the rm to delete in batches of 10000
# 20250901      1.0.2     pb      Commented out db alert log rotation
# 20250902      1.1       pb      Implemented ADR Home cleanup
# 20250904      1.1.1     pb      Implemented logic to handle and fix schema mistmatch error in ADRCI
# 20260924      2.0       pb      Complete rewrite - Initial safety refactor: preflight, locking, timeouts, scoped phases
# 20260924      2.1       pb      Corrected Oracle environment loading and case-insensitive SID resolution
# 20260924      2.2       pb      Passed ORACLE_HOME and ORACLE_BASE explicitly to ADRCI
# 20260924      2.3       pb      Added semantic ADRCI error detection and exact database-SID prechecks
# 20260924      2.4       pb      Corrected SYS.AUD$ retention arithmetic with NUMTODSINTERVAL and reformatted source
# 20260924      2.5       pb      Limited processing to active SID/oratab homes and approved ADR home types
# 20260924      2.6       pb      Restored AUDIT_FILE_DEST, CRS EVM, and listener XML filesystem cleanup
# 20260924      2.7       pb      Resolve audit directory from V$PARAMETER instead of assuming ORACLE_SID
#
#---------------------------------------------------------------------------------------------------------------------------
# Credit:
#  The original v1.0 script was based on the historical scripts by Wayne Sharp, Muthu Venguidassalame, and M. Ali
#
#============================================================================================================================
set -uo pipefail
IFS=$'\n\t'
umask 027
VERSION=2.7.0
MODE=preflight
SCOPE=all
ALLOW_MIGRATE=false
STOP_ON_ERROR=false
ORATAB=/etc/oratab
ORAENV=/usr/local/bin/oraenv
ORAGCHOMELIST=/etc/oragchomelist
HOST_SHORT=$(hostname -s 2>/dev/null || uname -n)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
LOG_DIR="$SCRIPT_DIR/../log"
RUN_ID=$(date +%Y%m%d_%H%M%S)_$$
WORK_DIR=""
LOG_FILE=""
ADR_DAYS=32
ORACLE_HOME_AUD_DAYS=2
ADUMP_AUD_DAYS=2
LISTENER_XML_DAYS=2
CRS_EVM_DAYS=32
RDBMS_LOG_DAYS=32
OEM_DAYS=14
SCRIPT_LOG_DAYS=14
DB_AUD_DAYS=365
ADR_TIMEOUT=1800
SQL_TIMEOUT=1800
FIND_TIMEOUT=1800
RETURN_CODE=0
ADR_DISCOVERED=0
ADR_OK=0
ADR_FAIL=0
ADR_TIMEOUTS=0
ADR_SKIP=0
DB_OK=0
DB_FAIL=0
DB_TIMEOUTS=0
DB_SKIP=0
FILES=0
DIRS=0
BYTES=0
#-------------------------------- Logging and status ---------------------------------------------
log() {
    printf '[%s] %-9s %s\n' "$(date '+%F %T')" "$1" "$2"
}
fail() {
    RETURN_CODE=1
    log FAILED "$1"
}
usage() {
    cat <<EOF
====================================================================================================
 DBA ORACLE CLEANUP FRAMEWORK - VERSION ${VERSION}
====================================================================================================

USAGE
    $(basename "$0") [--preflight | --apply] [OPTIONS]

MODES
    --preflight                  Report planned work without deleting files or changing databases.
                                 This is the default mode.
    --apply                      Execute the selected cleanup scope.

SCOPES
    --only filesystem           Clean active Oracle Home audit/trace files, database
                                 AUDIT_FILE_DEST files, CRS EVM logs, listener XML files,
                                 and old script logs.
    --only oem                  Clean OEM Agent dumps, archived logs, and incident directories.
    --only adr                  Purge approved ADR home families through ADRCI.
    --only database             Purge SYS.AUD\$, Scheduler logs, and Unified Audit Trail.
    --only all                  Run all phases. This is the default scope.

OPTIONS
    --allow-adr-schema-migration Permit ADRCI schema migration after DIA-49803. Disabled by default.
    --stop-on-error             Stop after the first failed operation.
    --log-dir <directory>       Override the default ../log directory.
    --help, -h                  Display this help and exit.

FILESYSTEM RETENTION
    Oracle Home audit files        ${ORACLE_HOME_AUD_DAYS} days
    Database AUDIT_FILE_DEST       ${ADUMP_AUD_DAYS} days
    Listener XML alert files       ${LISTENER_XML_DAYS} days
    Oracle Home rdbms traces       ${RDBMS_LOG_DAYS} days
    CRS EVM logs                   ${CRS_EVM_DAYS} days
    OEM Agent files                ${OEM_DAYS} days
    Script logs                    ${SCRIPT_LOG_DAYS} days

DATABASE AND ADR RETENTION
    ADR-managed content            ${ADR_DAYS} days
    SYS.AUD\$                      ${DB_AUD_DAYS} days
    Unified Audit Trail            ${DB_AUD_DAYS} days
    Scheduler logs                 0 days

AUDIT FILE DESTINATION
    The script queries V\$PARAMETER.AUDIT_FILE_DEST for each running database.
    It does not assume that the directory is based on ORACLE_SID, DB_NAME, or DB_UNIQUE_NAME.

EXAMPLES
    $(basename "$0") --preflight
    $(basename "$0") --preflight --only filesystem
    $(basename "$0") --apply --only filesystem
    $(basename "$0") --apply --only adr
    $(basename "$0") --apply --only database
    $(basename "$0") --apply --stop-on-error

RECOMMENDED VALIDATION
    1. bash -n $(basename "$0")
    2. $(basename "$0") --preflight
    3. Validate and apply each --only scope independently.
    4. Run $(basename "$0") --apply after all phases are validated.
====================================================================================================
EOF
}

parse() {
    while (($#))
    do case "$1" in
    --preflight) MODE=preflight;; --apply) MODE=apply;; --only) SCOPE=${2:?}
    shift;;
    --allow-adr-schema-migration) ALLOW_MIGRATE=true;; --stop-on-error) STOP_ON_ERROR=true;;
    --log-dir) LOG_DIR=${2:?}
    shift;; --help|-h) usage
    exit 0;; *) echo "Unknown option: $1" >&2
    exit 64;; esac
    shift
done
case "$SCOPE" in all|filesystem|oem|adr|database);; *) echo "Invalid scope: $SCOPE" >&2
exit 64;; esac
}
run_scope() {
    [[ $SCOPE == all || $SCOPE == "$1" ]]
}
stop_if_needed() {
    if $STOP_ON_ERROR && ((RETURN_CODE))
    then summary
    exit "$RETURN_CODE"
fi
}
cleanup() {
    [[ -n ${WORK_DIR:-} && -d $WORK_DIR ]] && rm -rf -- "$WORK_DIR"
}
#----------------------------- Runtime initialization and locking --------------------------------
init() {
    mkdir -p "$LOG_DIR" || exit 73
    LOG_DIR=$(cd "$LOG_DIR" && pwd -P)
    LOG_FILE="$LOG_DIR/ora_clean_${HOST_SHORT}.${RUN_ID}.log"
    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dba_ora_clean.${RUN_ID}.XXXX") || exit 73
    exec > >(tee -a "$LOG_FILE") 2>&1
    trap cleanup EXIT
    exec 9>"/var/tmp/dba_ora_clean.${HOST_SHORT}.lock"
    flock -n 9 || { log FAILED "Another cleanup is running"
    exit 75
}
}
need() {
    local x m=0
    for x in awk date dirname env find flock grep mktemp ps rm sort stat tee timeout tr wc xargs
    do command -v "$x" >/dev/null || { log FAILED "Missing command: $x"
    m=1
}
done
((m==0))
}
#------------------------------ Oracle environment discovery -------------------------------------
registered_homes() {
    [[ -r "$ORATAB" ]] || return 0

    awk -F: '''
        !/^[[:space:]]*#/ && NF > 1 && $2 != "" && $2 != "*" {
            print $2
        }
    ''' "$ORATAB" | sort -u
}

sids() {
    ps -ef | grep -v grep | grep pmon | awk -r '{print $8;}' 2>/dev/null |
        awk '''
            /^ora_pmon_/ {
                sub(/^ora_pmon_/, "")
                print
            }
            /^asm_pmon_/ {
                sub(/^asm_pmon_/, "")
                print
            }
        ''' |
        sort -u
}

lookup_home() {
    awk -F: -v sid="$1" '''
        BEGIN { sid = toupper(sid) }
        !/^[[:space:]]*#/ && toupper($1) == sid && $2 != "" && $2 != "*" {
            print $2
            exit
        }
    ''' "$ORATAB" 2>/dev/null
}

lookup_sid() {
    awk -F: -v sid="$1" '''
        BEGIN { sid = toupper(sid) }
        !/^[[:space:]]*#/ && toupper($1) == sid && $2 != "" && $2 != "*" {
            print $1
            exit
        }
    ''' "$ORATAB" 2>/dev/null
}

# Return unique Oracle Homes that are present in both the running PMON
# inventory and uncommented /etc/oratab entries.
active_homes() {
    local sid home

    while IFS= read -r sid; do
        [[ -n "$sid" ]] || continue
        home=$(lookup_home "$sid" || true)

        if [[ -z "$home" ]]; then
            log WARNING "Running SID missing from $ORATAB; excluding from home cleanup: $sid" >&2
            continue
        fi

        if [[ ! -d "$home" ]]; then
            log WARNING "Active SID has missing Oracle Home; excluding SID=$sid home=$home" >&2
            continue
        fi

        printf '%s\n' "$home"
    done < <(sids) | sort -u
}

oracle_base() {
    local h=$1 b="" x=""
    if [[ -x $h/bin/orabase ]]
    then x=$(ORACLE_HOME="$h" "$h/bin/orabase" 2>/dev/null|tail -1 || true)
    [[ $x == /* && -d $x ]] && b=$x
fi
if [[ -z $b ]]
then x=$(dirname "$(dirname "$h")")
[[ $x == /* && -d $x ]] || return 1
b=$x
log WARNING "orabase invalid for $h; derived ORACLE_BASE=$b"
fi
printf '%s\n' "$b"
}
load_env() {
    local detected_sid=$1 exact_sid h
    unset ORACLE_HOME ORACLE_BASE TNS_ADMIN TWO_TASK
    exact_sid=$(lookup_sid "$detected_sid" || true)
    h=$(lookup_home "$detected_sid" || true)
    if [[ -z $exact_sid ]]
    then exact_sid=${detected_sid^^}
fi
export ORACLE_SID=$exact_sid ORAENV_ASK=NO
if [[ -z $h && -r $ORAENV ]]
then . "$ORAENV" <<< "$exact_sid" >/dev/null 2>&1 || true
h=${ORACLE_HOME:-}
fi
[[ $h == /* && -d $h ]] || { log FAILED "Unable to resolve ORACLE_HOME for detected_SID=$detected_sid resolved_SID=$exact_sid value=${h:-unset}"
return 1
}
ORACLE_HOME=$h
ORACLE_BASE=$(oracle_base "$h") || return 1
export ORACLE_HOME ORACLE_BASE
log INFO "Database environment detected_SID=$detected_sid ORACLE_SID=$ORACLE_SID ORACLE_HOME=$ORACLE_HOME"
}
#-------------------------------- Filesystem cleanup engine ---------------------------------------
safe_path() {
    local p=$1 r
    [[ -d $p ]] || return 1
    r=$(cd "$p" && pwd -P) || return 1
    case "$r" in /|/bin|/boot|/dev|/etc|/home|/opt|/proc|/root|/run|/sys|/tmp|/u01|/usr|/var) return 1;; esac
}
scan() {
    local kind=$1 path=$2 pattern=$3 days=$4 desc=$5 list="$WORK_DIR/list.$RANDOM" count=0 size=0 rc
    safe_path "$path" || { log WARNING "Skipping missing or unsafe path: $path [$desc]"
    return 0
}
if [[ $kind == file ]]
then timeout --signal=TERM --kill-after=30s "$FIND_TIMEOUT" find "$path" -xdev -type f -name "$pattern" -mtime "+$days" -print0 >"$list"
else timeout --signal=TERM --kill-after=30s "$FIND_TIMEOUT" find "$path" -xdev -depth -type d -name "$pattern" -mtime "+$days" -print0 >"$list"
fi
rc=$?
((rc==0)) || { fail "Find failed/timed out: $path [$desc] rc=$rc"
return $rc
}
count=$(tr -cd '\0' <"$list"|wc -c)
if [[ $kind == file ]]
then while IFS= read -r -d '' f
do n=$(stat -c %s "$f" 2>/dev/null||echo 0)
size=$((size+n))
done <"$list"
FILES=$((FILES+count))
BYTES=$((BYTES+size))
else DIRS=$((DIRS+count))
fi
log PLAN "$desc: path=$path pattern=$pattern age>${days}d candidates=$count bytes=$size"
if [[ $MODE == apply && $count -gt 0 ]]
then if [[ $kind == file ]]
then xargs -0 -r -n 1000 rm -f -- <"$list"
else xargs -0 -r -n 100 rm -rf -- <"$list"
fi
rc=$?
((rc==0)) && log SUCCESS "Removed $count candidate(s) [$desc]" || fail "Removal failed [$desc] rc=$rc"
fi
rm -f "$list"
}
# Query the exact operating-system audit destination. This is safer than
# constructing a path from ORACLE_SID because AUDIT_FILE_DEST can follow
# DB_NAME, DB_UNIQUE_NAME, or a custom convention.
resolve_audit_file_dest() {
    local output_file="$WORK_DIR/audit_file_dest.${ORACLE_SID}.$RANDOM.out"
    local rc audit_dir

    timeout --signal=TERM --kill-after=30s 60 \
        env ORACLE_SID="$ORACLE_SID" \
            ORACLE_HOME="$ORACLE_HOME" \
            ORACLE_BASE="$ORACLE_BASE" \
            PATH="$ORACLE_HOME/bin:$PATH" \
        "$ORACLE_HOME/bin/sqlplus" -s -L "/ as sysdba" \
        >"$output_file" 2>&1 <<'SQL'
WHENEVER OSERROR EXIT 21
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF ECHO OFF
SELECT TRIM(value)
  FROM v$parameter
 WHERE name = 'audit_file_dest';
EXIT SUCCESS
SQL
    rc=$?

    if (( rc != 0 )); then
        log FAILED "Unable to query AUDIT_FILE_DEST for ORACLE_SID=$ORACLE_SID rc=$rc"
        sed "s/^/[SQL $ORACLE_SID AUDIT_FILE_DEST] /" "$output_file"
        return "$rc"
    fi

    audit_dir=$(awk 'NF {gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit}' "$output_file")
    if [[ -z "$audit_dir" || "$audit_dir" != /* ]]; then
        log FAILED "AUDIT_FILE_DEST is empty or non-absolute for ORACLE_SID=$ORACLE_SID: ${audit_dir:-unset}"
        return 1
    fi

    printf '%s\n' "$audit_dir"
}

cleanup_database_adump() {
    local detected_sid sid_upper audit_dir

    while IFS= read -r detected_sid; do
        [[ -n "$detected_sid" ]] || continue
        sid_upper=${detected_sid^^}
        case "$sid_upper" in
            +ASM* | ASM* | *MGMTDB*) continue ;;
        esac

        if ! load_env "$detected_sid"; then
            fail "Unable to resolve environment for audit cleanup SID=$detected_sid"
            stop_if_needed
            continue
        fi

        audit_dir=$(resolve_audit_file_dest) || {
            fail "Unable to resolve AUDIT_FILE_DEST for ORACLE_SID=$ORACLE_SID"
            stop_if_needed
            continue
        }

        log INFO "Resolved AUDIT_FILE_DEST for ORACLE_SID=$ORACLE_SID: $audit_dir"
        scan file "$audit_dir" '*.aud' "$ADUMP_AUD_DAYS" "$ORACLE_SID database audit files"
        stop_if_needed
    done < <(sids)
}

cleanup_crs_evm_logs() {
    local base
    while IFS= read -r base; do
        [[ -n "$base" ]] || continue
        scan file "$base/crsdata/$HOST_SHORT/evm" 'evmlog*' "$CRS_EVM_DAYS" "CRS EVM logs"
        stop_if_needed
    done < <(bases)
}

cleanup_listener_xml_files() {
    local base
    while IFS= read -r base; do
        [[ -n "$base" ]] || continue
        scan file "$base/diag/tnslsnr/$HOST_SHORT" '*.xml' "$LISTENER_XML_DAYS" "Listener XML alert files"
        stop_if_needed
    done < <(bases)
}

#-------------------------------- Cleanup phase: filesystem ---------------------------------------
filesystem() {
    log START "Non-ADR filesystem cleanup"
    local h
    while IFS= read -r h
    do [[ -d $h ]] || continue
    log INFO "Oracle home=$h Oracle base=$(oracle_base "$h" || echo unresolved)"
    scan file "$h/rdbms/audit" '*.aud' "$ORACLE_HOME_AUD_DAYS" "Oracle home audit"
    scan file "$h/rdbms/log" '*.trc' "$RDBMS_LOG_DAYS" "Oracle home rdbms traces"
    stop_if_needed
done < <(active_homes)

cleanup_database_adump
cleanup_crs_evm_logs
cleanup_listener_xml_files
}
#----------------------------------- Cleanup phase: OEM ------------------------------------------
oem() {
    log START "OEM Agent cleanup"
    local h
    [[ -r $ORAGCHOMELIST ]] || { log WARNING "Missing $ORAGCHOMELIST"
    return
}
while IFS= read -r h
do [[ -n $h ]] || continue
scan file "$h/sysman/emd" 'heapdump*.phd' "$OEM_DAYS" "OEM heapdump"
scan file "$h/sysman/emd" 'Snap*.trc' "$OEM_DAYS" "OEM snap"
scan file "$h/sysman/emd" 'core*.dmp' "$OEM_DAYS" "OEM core"
scan file "$h/sysman/emd" 'javacore*.txt' "$OEM_DAYS" "OEM javacore"
scan file "$h/sysman/log" '*.log.*' "$OEM_DAYS" "OEM archived log"
scan dir "$h/diag/ofm/emagent/emagent/incident" 'incdir_*' "$OEM_DAYS" "OEM incidents"
done < <(awk -F: 'BEGIN{IGNORECASE=1}/agent/{for(i=1;i<=NF;i++)if($i~/^\//)print $i}' "$ORAGCHOMELIST"|sort -u)
}
#----------------------------------- ADRCI support functions --------------------------------------
adrci_bin() {
    local h b
    while IFS= read -r h
    do [[ -x $h/bin/adrci ]]&&{ printf '%s|%s\n' "$h" "$h/bin/adrci"
    return
}
done < <(active_homes)
b=$(command -v adrci 2>/dev/null)||return 1
h=${ORACLE_HOME:-}
[[ $h == /* && -d $h ]]||return 1
printf '%s|%s\n' "$h" "$b"
}
bases() {
    local h
    while IFS= read -r h
    do [[ -d $h ]]&&oracle_base "$h"
done < <(active_homes)|grep '^/'|sort -u
}
adr_discover() {
    local oh=$1 bin=$2 out=$3 b raw rc
    :>"$out"
    while IFS= read -r b
    do raw="$WORK_DIR/adr.$RANDOM"
    log START "Discover ADR homes under base $b"
    timeout --signal=TERM --kill-after=30s 120 env ORACLE_HOME="$oh" ORACLE_BASE="$b" PATH="$oh/bin:$PATH" "$bin" exec="set base ${b}; show homes" >"$raw" 2>&1
    rc=$?
    if ((rc))
    then log FAILED "ADR discovery failed for base=$b rc=$rc"
    sed 's/^/[ADRCI] /' "$raw"
    continue
fi
awk -v b="$b" '/^ADR Homes:/{f=1;next} f{gsub(/^[ \t]+|[ \t]+$/,"");if($0~/^diag\//)print b"|"$0}' "$raw" >>"$out"
done < <(bases)
sort -u -o "$out" "$out"
[[ -s $out ]]
}
adr_home_type_allowed() {
    local home="$1"

    case "$home" in
        diag/rdbms/* | \
        diag/asm/* | \
        diag/tnslsnr/* | \
        diag/crs/* | \
        diag/clients/* | \
        diag/kfod/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

adr_run() {
    local oh=$1 bin=$2 base=$3 home=$4 cmd=$5 t=$6 label=$7 out="$WORK_DIR/adrout.$RANDOM" rc semantic=0
    log START "$label [$base/$home]"
    timeout --signal=TERM --kill-after=30s "$t" env ORACLE_HOME="$oh" ORACLE_BASE="$base" PATH="$oh/bin:$PATH" "$bin" exec="set base ${base}; set homepath ${home}; ${cmd}" >"$out" 2>&1
    rc=$?
    sed 's/^/[ADRCI] /' "$out"
    ADR_LAST=$out
    if grep -Eq '(^|[[:space:]])(DIA-|ORA-|SP2-)|Linux-.*Error:|Permission denied' "$out"
    then semantic=1
fi
if ((rc==124||rc==137))
then log TIMEOUT "$label [$base/$home]"
RETURN_CODE=1
return $rc
elif ((rc!=0))
    then log FAILED "$label [$base/$home] rc=$rc"
    RETURN_CODE=1
    return $rc
elif ((semantic))
    then log FAILED "$label reported ADRCI errors [$base/$home]"
    RETURN_CODE=1
    return 65
else log SUCCESS "$label [$base/$home]"
return 0
fi
}
#----------------------------------- Cleanup phase: ADR ------------------------------------------
adr() {
    log START "ADRCI cleanup retention=${ADR_DAYS}d migration=$ALLOW_MIGRATE"
    local selected oh bin list="$WORK_DIR/adrhomes" rec base home rc minutes=$((ADR_DAYS*1440))
    selected=$(adrci_bin)||{ fail "Unable to locate adrci with a valid ORACLE_HOME"
    return
}
oh=${selected%%|*}
bin=${selected#*|}
log INFO "Using ADRCI: $bin ORACLE_HOME=$oh"
adr_discover "$oh" "$bin" "$list"||{ fail "No ADR homes discovered under configured Oracle bases"
return
}
ADR_DISCOVERED=$(wc -l <"$list")
log INFO "ADR homes discovered: $ADR_DISCOVERED"
while IFS='|' read -r base home
do
    [[ $base == /* && $home == diag/* ]] || {
        log WARNING "Skipping invalid ADR base/home: base=$base home=$home"
        ADR_SKIP=$((ADR_SKIP+1))
        continue
    }

    if ! adr_home_type_allowed "$home"; then
        log INFO "Skipping ADR home outside approved type allowlist: $home"
        ADR_SKIP=$((ADR_SKIP+1))
        continue
    fi

    if [[ $MODE == preflight ]]
then log PLAN "Would purge base=$base home=$home age>${ADR_DAYS}d timeout=${ADR_TIMEOUT}s"
ADR_SKIP=$((ADR_SKIP+1))
continue
fi
adr_run "$oh" "$bin" "$base" "$home" "purge -age $minutes" "$ADR_TIMEOUT" "Purge ADR"
rc=$?
if ((rc==0))
then ADR_OK=$((ADR_OK+1))
continue
elif ((rc==124||rc==137))
    then ADR_TIMEOUTS=$((ADR_TIMEOUTS+1))
    continue
fi
if grep -q DIA-49803 "$ADR_LAST"
then if ! $ALLOW_MIGRATE
then log WARNING "Schema mismatch; migration disabled [$base/$home]"
ADR_SKIP=$((ADR_SKIP+1))
continue
fi
adr_run "$oh" "$bin" "$base" "$home" "migrate schema" 900 "Migrate ADR schema"&&adr_run "$oh" "$bin" "$base" "$home" "purge -age $minutes" "$ADR_TIMEOUT" "Retry ADR purge"
rc=$?
((rc==0))&&ADR_OK=$((ADR_OK+1))||ADR_FAIL=$((ADR_FAIL+1))
else ADR_FAIL=$((ADR_FAIL+1))
fi
stop_if_needed
done <"$list"
}
#-------------------------------- Database SQL generation -----------------------------------------
sqlfile() {
    local type=$1 f=$2
    case $type in audit) body="DECLARE n PLS_INTEGER:=1; t PLS_INTEGER:=0; BEGIN WHILE n>0 LOOP DELETE FROM sys.aud\$ WHERE ROWID IN (SELECT ROWID FROM sys.aud\$ WHERE NTIMESTAMP# < SYSTIMESTAMP-NUMTODSINTERVAL($DB_AUD_DAYS,'DAY') AND ROWNUM<=10000); n:=SQL%ROWCOUNT;t:=t+n;COMMIT;END LOOP;DBMS_OUTPUT.PUT_LINE('AUDIT_ROWS_DELETED='||t);END;";; scheduler) body="BEGIN DBMS_SCHEDULER.PURGE_LOG(log_history=>0,which_log=>'JOB_AND_WINDOW_LOG');END;";; unified) body="BEGIN DBMS_AUDIT_MGMT.SET_LAST_ARCHIVE_TIMESTAMP(DBMS_AUDIT_MGMT.AUDIT_TRAIL_UNIFIED,SYSTIMESTAMP-INTERVAL '$DB_AUD_DAYS' DAY);DBMS_AUDIT_MGMT.CLEAN_AUDIT_TRAIL(DBMS_AUDIT_MGMT.AUDIT_TRAIL_UNIFIED,TRUE);END;";; esac
    cat >"$f" <<EOF
    WHENEVER OSERROR EXIT 21
    WHENEVER SQLERROR EXIT SQL.SQLCODE
    SET SERVEROUTPUT ON FEEDBACK ON HEADING OFF
    $body
    /
    EXIT SUCCESS
EOF
}
#-------------------------------- Cleanup phase: databases ----------------------------------------
database() {
    log START "Database cleanup"
    local sid u f rc bad check
    for u in audit scheduler unified
    do sqlfile "$u" "$WORK_DIR/$u.sql"
done
while IFS= read -r sid
do case "${sid^^}" in +ASM*|ASM*|*MGMTDB*|APX*) log INFO "Skipping non-database SID=$sid"
DB_SKIP=$((DB_SKIP+1))
continue;;esac
if [[ $MODE == preflight ]]
then log PLAN "Would validate and run database cleanup SID=$sid timeout=${SQL_TIMEOUT}s"
DB_SKIP=$((DB_SKIP+1))
continue
fi
load_env "$sid"||{ DB_FAIL=$((DB_FAIL+1))
RETURN_CODE=1
continue
}
bad=0
check="$WORK_DIR/check.${ORACLE_SID}.sql"; cat >"$check" <<'SQL'
WHENEVER OSERROR EXIT 21
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT status FROM v$instance;
EXIT SUCCESS
SQL
f="$WORK_DIR/check.${ORACLE_SID}.out"
timeout --signal=TERM --kill-after=30s 60 env ORACLE_SID="$ORACLE_SID" ORACLE_HOME="$ORACLE_HOME" ORACLE_BASE="$ORACLE_BASE" PATH="$ORACLE_HOME/bin:$PATH" "$ORACLE_HOME/bin/sqlplus" -s -L '/ as sysdba' @"$check" >"$f" 2>&1
rc=$?
sed "s/^/[SQL $ORACLE_SID PRECHECK] /" "$f"
if ((rc!=0)) || ! grep -Eq '^[[:space:]]*(OPEN|MOUNTED|STARTED)[[:space:]]*$' "$f"
then log FAILED "Database precheck failed detected_SID=$sid ORACLE_SID=$ORACLE_SID rc=$rc; skipping all cleanup operations"
DB_FAIL=$((DB_FAIL+1))
RETURN_CODE=1
stop_if_needed
continue
fi
if ! grep -Eq '^[[:space:]]*OPEN[[:space:]]*$' "$f"
then log WARNING "Database ORACLE_SID=$ORACLE_SID is not OPEN; skipping cleanup"
DB_SKIP=$((DB_SKIP+1))
continue
fi
for u in audit scheduler unified
do f="$WORK_DIR/sql.$ORACLE_SID.$u.out"
log START "$u cleanup SID=$ORACLE_SID"
timeout --signal=TERM --kill-after=30s "$SQL_TIMEOUT" env ORACLE_SID="$ORACLE_SID" ORACLE_HOME="$ORACLE_HOME" ORACLE_BASE="$ORACLE_BASE" PATH="$ORACLE_HOME/bin:$PATH" "$ORACLE_HOME/bin/sqlplus" -s -L '/ as sysdba' @"$WORK_DIR/$u.sql" >"$f" 2>&1
rc=$?
sed "s/^/[SQL $ORACLE_SID] /" "$f"
case $rc in 0)log SUCCESS "$u cleanup SID=$ORACLE_SID";;124|137)log TIMEOUT "$u cleanup SID=$ORACLE_SID"
DB_TIMEOUTS=$((DB_TIMEOUTS+1))
bad=1
RETURN_CODE=1;;*)log FAILED "$u cleanup SID=$ORACLE_SID rc=$rc"
bad=1
RETURN_CODE=1;;esac
done
((bad==0))&&DB_OK=$((DB_OK+1))||DB_FAIL=$((DB_FAIL+1))
stop_if_needed
done < <(sids)
}
#-------------------------------- Summary and entry point -----------------------------------------
summary() {
    log SUMMARY "version=$VERSION mode=$MODE scope=$SCOPE return_code=$RETURN_CODE"
    log SUMMARY "filesystem files=$FILES dirs=$DIRS bytes=$BYTES"
    log SUMMARY "ADR discovered=$ADR_DISCOVERED success=$ADR_OK failed=$ADR_FAIL timed_out=$ADR_TIMEOUTS skipped=$ADR_SKIP"
    log SUMMARY "DB success=$DB_OK failed=$DB_FAIL timed_out=$DB_TIMEOUTS skipped=$DB_SKIP"
    log SUMMARY "log=$LOG_FILE"
}
main() {
    parse "$@"
    init
    need||exit 1
    log INFO "Script=$(basename "$0") version=$VERSION host=$HOST_SHORT mode=$MODE scope=$SCOPE user=$(id -un)"
    log INFO "Detected SIDs: $(sids|tr '\n' ' ')"
    log INFO "Registered Oracle homes from $ORATAB: $(registered_homes | tr '\n' ' ')"
    log INFO "Active Oracle homes selected for cleanup: $(active_homes | tr '\n' ' ')"
    run_scope filesystem&&filesystem
    run_scope oem&&oem
    run_scope adr&&adr
    run_scope database&&database
    if [[ $SCOPE == all || $SCOPE == filesystem ]]
    then scan file "$LOG_DIR" 'ora_clean_*' "$SCRIPT_LOG_DAYS" "Old cleanup logs"
fi
summary
[[ $MODE == preflight ]]&&log INFO "Preflight only; no deletions performed"
exit "$RETURN_CODE"
}
main "$@"
