#!/bin/bash -e
#
# DESC: List Oracle homes with filtering and automation suppor
function lsoh() {

    local output_mode="table"
    local grep_pattern=""
    local grep_invert=0
    local type_filter=""
    local no_header=0
    local raw_mode=0
    local column_filter=""
    local mode_count=0

    # JSON escape helper
    _lsoh_json_escape() {
        local s="$1"
        s=${s//\\/\\\\}
        s=${s//\"/\\\"}
        s=${s//$'\n'/\\n}
        s=${s//$'\r'/\\r}
        s=${s//$'\t'/\\t}
        printf '%s' "$s"
    }

    # TYPE matcher
    _lsoh_type_match() {
        local actual_type="$1"
        local requested_type="$2"

        shopt -s nocasematch
        case "$requested_type" in
            db|dbms)
                [[ "$actual_type" =~ ^DBMS ]]
                ;;
            grid)
                [[ "$actual_type" =~ ^GRID ]]
                ;;
            ogg)
                [[ "$actual_type" =~ ^OGG ]]
                ;;
            agent|agnt)
                [[ "$actual_type" == "AGNT" ]]
                ;;
            client|clnt)
                [[ "$actual_type" == "CLNT" ]]
                ;;
            ohs)
                [[ "$actual_type" == "OHS" ]]
                ;;
            ocmn)
                [[ "$actual_type" == "OCMN" ]]
                ;;
            *)
                printf '%s\n' "$actual_type" | grep -Eiq -- "$requested_type"
                ;;
        esac
        local rc=$?
        shopt -u nocasematch
        return $rc
    }

    # Extract requested column from row
    _lsoh_get_column_value() {
        local row="$1"
        local col="$2"
        local h l v e
        IFS='|' read -r h l v e <<< "$row"

        case "$col" in
            name)      printf '%s' "$h" ;;
            location)  printf '%s' "$l" ;;
            version)   printf '%s' "$v" ;;
            type)      printf '%s' "$e" ;;
            *)
                return 1
                ;;
        esac
    }

    # Render table helper
    _lsoh_render_table() {
        local csv_data="$1"
        local suppress_header="$2"

        if type printTable >/dev/null 2>&1; then
            if [[ "$suppress_header" -eq 1 ]]; then
                # Keep top border, strip header and header separator, keep rows + bottom border
                printTable "," "$csv_data" | awk 'NR==1 || NR>3'
            else
                printTable "," "$csv_data"
            fi
        else
            # Fallback to CSV if printTable is not available
            if [[ "$suppress_header" -eq 1 ]]; then
                printf '%s\n' "$csv_data" | tail -n +2
            else
                printf '%s\n' "$csv_data"
            fi
        fi
    }

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --csv)
                output_mode="csv"
                ((mode_count++))
                ;;
            --json)
                output_mode="json"
                ((mode_count++))
                ;;
            --raw)
                raw_mode=1
                ((mode_count++))
                ;;
            --type)
                shift
                [[ -z "$1" ]] && {
                    echo "Usage: lsoh [--csv|--json|--raw] [--grep <pattern>|--grep -v <pattern>] [--type <type>] [--column <name|location|version|type>] [--no-header]"
                    return 1
                }
                type_filter="$1"
                ;;
            --column)
                shift
                [[ -z "$1" ]] && {
                    echo "Usage: lsoh --column <name|location|version|type>"
                    return 1
                }
                column_filter=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
                case "$column_filter" in
                    name|location|version|type) ;;
                    *)
                        echo "Invalid --column value: $1"
                        echo "Valid values: name, location, version, type"
                        return 1
                        ;;
                esac
                ;;
            --no-header)
                no_header=1
                ;;
            --grep)
                shift
                [[ -z "$1" ]] && {
                    echo "Usage: lsoh [--grep <pattern>|--grep -v <pattern>]"
                    return 1
                }

                if [[ "$1" == "-v" ]]; then
                    grep_invert=1
                    shift
                    [[ -z "$1" ]] && {
                        echo "Usage: lsoh --grep -v <pattern>"
                        return 1
                    }
                fi

                grep_pattern="$1"
                ;;
            --grep-v)
                shift
                [[ -z "$1" ]] && {
                    echo "Usage: lsoh --grep-v <pattern>"
                    return 1
                }
                grep_pattern="$1"
                grep_invert=1
                ;;
            -h|--help)
                cat <<'EOF'
Usage: lsoh [options]

Options:
  --csv                       Output in CSV format
  --json                      Output in JSON format
  --raw                       Script-friendly raw output (no header, no table formatting)
  --grep PATTERN              Include only rows matching PATTERN (case-insensitive regex)
  --grep -v PATTERN           Exclude rows matching PATTERN (case-insensitive regex)
  --grep-v PATTERN            Same as: --grep -v PATTERN
  --type TYPE                 Filter by TYPE
  --column COL                Show only one column: name|location|version|type
  --no-header                 Suppress header row (table/csv only)
  -h, --help                  Show this help

TYPE values:
  db | dbms                   Database homes (TYPE begins with DBMS)
  grid                        Grid homes
  ogg                         GoldenGate homes
  agent | agnt                OEM agent homes
  client | clnt               Oracle client homes
  ohs                         Oracle HTTP Server homes
  ocmn                        Oracle common homes
  <regex>                     Any regex matched against TYPE column

Notes:
  - --raw with --column prints one value per line
  - --raw without --column prints tab-separated rows
  - --no-header has no effect on --json or --raw

Examples:
  lsoh
  lsoh --csv
  lsoh --json
  lsoh --grep grid
  lsoh --grep -v grid
  lsoh --type db
  lsoh --type grid --no-header
  lsoh --column location
  lsoh --column location --raw
  lsoh --type db --column version --csv
  lsoh --type ogg --raw
EOF
                return 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Usage: lsoh [--csv|--json|--raw] [--grep <pattern>|--grep -v <pattern>] [--type <type>] [--column <name|location|version|type>] [--no-header]"
                return 1
                ;;
        esac
        shift
    done

    if (( mode_count > 1 )); then
        echo "Please specify only one output mode: --csv, --json, or --raw"
        return 1
    fi

    local CENTRAL_ORAINV
    CENTRAL_ORAINV=$(grep '^inventory_loc' /etc/oraInst.loc 2>/dev/null | awk -F= '{print $2}')
    [[ -z "$CENTRAL_ORAINV" ]] && echo "Could not determine central inventory location." && return 1
    [[ ! -f "$CENTRAL_ORAINV/ContentsXML/inventory.xml" ]] && echo "No inventory file found." && return 1

    local -a rows
    local line OH OH_NAME comp_file comp_xml comp_name comp_vers
    local ORAEDITION ORAVERSION ORAMAJOR row_text

    while IFS= read -r line; do
        OH=$(echo "$line" | tr ' ' '\n' | grep '^LOC=' | awk -F\" '{print $2}')
        [[ -z "$OH" || ! -d "$OH" ]] && continue

        OH_NAME=$(echo "$line" | tr ' ' '\n' | grep '^NAME=' | awk -F\" '{print $2}')
        comp_file="$OH/inventory/ContentsXML/comps.xml"
        [[ ! -f "$comp_file" ]] && continue

        comp_xml=$(grep "COMP NAME" "$comp_file" | grep "oracle.sysman.top.agent")
        [[ -z "$comp_xml" ]] && comp_xml=$(grep "COMP NAME" "$comp_file" | head -1)
        [[ -z "$comp_xml" ]] && continue

        comp_name=$(echo "$comp_xml" | tr ' ' '\n' | grep '^NAME=' | awk -F\" '{print $2}')
        comp_vers=$(echo "$comp_xml" | tr ' ' '\n' | grep '^VER=' | awk -F\" '{print $2}')

        ORAEDITION=""
        ORAVERSION="$comp_vers"

        case "$comp_name" in
            "oracle.crs")
                [[ -x "$OH/bin/oraversion" ]] && ORAVERSION=$("$OH/bin/oraversion" -compositeVersion)
                if [[ -x "$OH/srvm/admin/getcrshome" ]] && [[ "$("$OH/srvm/admin/getcrshome" 2>/dev/null)" == "$OH" ]]; then
                    ORAEDITION="GRID ACTIVE"
                else
                    ORAEDITION="GRID INSTLD"
                fi
                ;;
            "oracle.sysman.top.agent"|"oracle.sysman.emagent.installer")
                ORAEDITION="AGNT"
                ;;
            "oracle.server")
                ORAVERSION=$(grep 'PATCH NAME="oracle.server"' "$comp_file" 2>/dev/null | tr ' ' '\n' | grep '^VER=' | awk -F\" '{print $2}')
                [[ -z "$ORAVERSION" ]] && ORAVERSION="$comp_vers"
                [[ -x "$OH/bin/oraversion" ]] && ORAVERSION=$("$OH/bin/oraversion" -compositeVersion)

                ORAMAJOR=$(echo "$ORAVERSION" | cut -d. -f1)
                case "$ORAMAJOR" in
                    11|12|19)
                        ORAEDITION="DBMS $(grep 'oracle_install_db_InstallType' "$OH"/inventory/globalvariables/oracle.server/globalvariables.xml 2>/dev/null | tr ' ' '\n' | grep VALUE | awk -F\" '{print $2}')"
                        ;;
                    10)
                        ORAEDITION="DBMS $(grep 's_serverInstallType' "$OH"/inventory/Components21/oracle.server/*/context.xml 2>/dev/null | tr ' ' '\n' | grep VALUE | awk -F\" '{print $2}')"
                        ;;
                    *)
                        ORAEDITION="DBMS"
                        ;;
                esac
                ;;
            "oracle.client")
                ORAEDITION="CLNT"
                [[ -x "$OH/bin/oraversion" ]] && ORAVERSION=$("$OH/bin/oraversion" -compositeVersion)
                ;;
            "oracle.as.webtiercd.top")
                ORAEDITION="OHS"
                [[ -x "$OH/bin/oraversion" ]] && ORAVERSION=$("$OH/bin/oraversion" -compositeVersion)
                ;;
            "oracle.as.common.top")
                ORAEDITION="OCMN"
                [[ -x "$OH/bin/oraversion" ]] && ORAVERSION=$("$OH/bin/oraversion" -compositeVersion)
                ;;
            "oracle.oggcore.top")
                ORAEDITION="OGG CA"
                [[ -x "$OH/bin/oraversion" ]] && ORAVERSION=$("$OH/bin/oraversion" -compositeVersion)
                ;;
            "oracle.oggcore.services")
                ORAEDITION="OGG MA"
                [[ -x "$OH/bin/adminclient" ]] && ORAVERSION=$("$OH/bin/adminclient" --version 2>/dev/null | grep -i version | cut -d' ' -f2 | xargs)
                ;;
            *)
                ORAEDITION=$(echo "$comp_name" | xargs)
                [[ -x "$OH/bin/oraversion" ]] && ORAVERSION=$("$OH/bin/oraversion" -compositeVersion)
                ;;
        esac

        # TYPE filter
        if [[ -n "$type_filter" ]]; then
            _lsoh_type_match "$ORAEDITION" "$type_filter" || continue
        fi

        row_text="$OH_NAME|$OH|$ORAVERSION|$ORAEDITION"

        # GREP filter (include or exclude)
        if [[ -n "$grep_pattern" ]]; then
            if [[ "$grep_invert" -eq 1 ]]; then
                printf '%s\n' "$row_text" | grep -Eiq -- "$grep_pattern" && continue
            else
                printf '%s\n' "$row_text" | grep -Eiq -- "$grep_pattern" || continue
            fi
        fi

        rows+=("$row_text")
    done < <(grep '<HOME NAME=' "${CENTRAL_ORAINV}/ContentsXML/inventory.xml" 2>/dev/null)

    # RAW output (best for scripts)
    if [[ "$raw_mode" -eq 1 ]]; then
        local row h l v e value
        for row in "${rows[@]}"; do
            if [[ -n "$column_filter" ]]; then
                _lsoh_get_column_value "$row" "$column_filter"
                printf '\n'
            else
                IFS='|' read -r h l v e <<< "$row"
                printf '%s\t%s\t%s\t%s\n' "$h" "$l" "$v" "$e"
            fi
        done
        return 0
    fi

    # Build CSV output
    local header csv_output row h l v e value
    if [[ -n "$column_filter" ]]; then
        header=$(printf '%s' "$column_filter" | tr '[:lower:]' '[:upper:]')
    else
        header="NAME,LOCATION,VERSION,TYPE"
    fi

    csv_output="$header"

    for row in "${rows[@]}"; do
        if [[ -n "$column_filter" ]]; then
            value=$(_lsoh_get_column_value "$row" "$column_filter") || return 1
            csv_output+=$'\n'"$value"
        else
            IFS='|' read -r h l v e <<< "$row"
            csv_output+=$'\n'"$h,$l,$v,$e"
        fi
    done

    case "$output_mode" in
        csv)
            if [[ "$no_header" -eq 1 ]]; then
                printf '%s\n' "$csv_output" | tail -n +2
            else
                printf '%s\n' "$csv_output"
            fi
            ;;
        json)
            echo "["
            local first=1
            for row in "${rows[@]}"; do
                IFS='|' read -r h l v e <<< "$row"
                [[ $first -eq 0 ]] && echo ","

                if [[ -n "$column_filter" ]]; then
                    value=$(_lsoh_get_column_value "$row" "$column_filter") || return 1
                    printf '  {"%s":"%s"}' \
                        "$(printf '%s' "$column_filter" | tr '[:lower:]' '[:upper:]')" \
                        "$(_lsoh_json_escape "$value")"
                else
                    printf '  {"NAME":"%s","LOCATION":"%s","VERSION":"%s","TYPE":"%s"}' \
                        "$(_lsoh_json_escape "$h")" \
                        "$(_lsoh_json_escape "$l")" \
                        "$(_lsoh_json_escape "$v")" \
                        "$(_lsoh_json_escape "$e")"
                fi

                first=0
            done
            echo
            echo "]"
            ;;
        *)
            _lsoh_render_table "$csv_output" "$no_header"
            ;;
    esac
}
