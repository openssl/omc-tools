#!/bin/bash

ZABBIX_SERVER=127.0.0.1
TIMESTAMP=$(date +%s)
DRY_RUN=0
VERBOSITY=0
CMD=""
GROUP_TITLE="Performance tests"
METRIC_TITLE=""
METRIC_VALUE=

# print help
function print_help() {
    echo "Usage: ${0} [options]"
    echo "    options:"
    echo "        -c <a command produces a number>"
    echo "        -d ... dry run"
    echo "                ... executes command but results are printed insted of sent to servers"
    echo "        -g <group of metrics title>"
    echo "                ... this is defined as a 'host' in Zabbix server, default value set to 'Performance tests'"
    echo "        -h ... print this help"
    echo "        -m <metric title>"
    echo "                ... this is defined as an 'item' in Zabbix server"
    echo "        -v ... set verbosity"
    echo "        -z <Zabbix server IP address / hostname>"
    echo
    echo "Dependencies:"
    echo "    zabbix_sender"
}

# arguments parser
function parse_args() {
    [ $# -eq 0 ] && print_help && exit 1
    while getopts 'c:dg:hm:vz:' option; do
    case "${option}" in
        # command
        c)
            # wrapped command
            if [ -z "${OPTARG}" ]; then
                print_help
                exit 1
            fi
            CMD=${OPTARG}
            ;;
        # dry run
        d)
            DRY_RUN=1
            ;;
        # group of metrics title (or "host" in Zabbix server)
        #  it must follow the name of "host" in Zabbix server, for example: "Performance tests"
        g)
            if [ -z "${OPTARG}" ]; then
                print_help
                exit 1
            fi
            GROUP_TITLE=${OPTARG}
            ;;
        # help
        h)
            print_help
            exit 0
            ;;
        # metric title
        #   it must follow the name defined in Zabbix item, for example: "perftest.openssl-master.build_time"
        m)
            if [ -z "${OPTARG}" ]; then
                print_help
                exit 1
            fi
            METRIC_TITLE=${OPTARG}
            ;;
        # verbosity
        v)
            VERBOSITY=1
            ;;
        z)
            if [ -z "${OPTARG}" ]; then
                print_help
                exit 1
            fi
            ZABBIX_SERVER=${OPTARG}
            ;;
        *)
            print_help
            exit 1
            ;;
    esac
    done
}

# test of variables
function test_vars() {
    local err=0
    # command
    if [ -z "${CMD}" ]; then
        echo "Error: 'command' to run is not set"
        err=1
    fi
    # metrics "host"
    if [ -z "${GROUP_TITLE}" ]; then
        echo "Error: 'group title' is not set"
        err=1
    fi
    # metric
    if [ -z "${METRIC_TITLE}" ]; then
        echo "Error: 'metric title' is not set"
        err=1
    fi
    # zabbix server connection
    which zabbix_sender 2>&1 >/dev/null && {
        zabbix_sender -z ${ZABBIX_SERVER} -s "this_connection_test_host" -k "connection_test_key" -o 1 | grep -q 'sent: 1;'
        if [ $? -ne 0 ]; then
            echo "Error: Zabbix server is not accessible."
            err=1
        fi
    } ||
    { echo "Error: zabbix_sender must be installed."; err=1; }
    [ ${err} -ne 0 ] && exit 1
}


# ****** START ******
# arguments
parse_args "$@"
# verbosity
if [ ${VERBOSITY} -ne 0 ]; then
    echo "****** Variables ******"
    echo "DRY_RUN        = ${DRY_RUN}"
    echo "VERBOSITY      = ${VERBOSITY}"
    echo "GROUP_TITLE    = ${GROUP_TITLE}"
    echo "METRIC_TITLE   = ${METRIC_TITLE}"
    echo "ZABBIX_SERVER  = ${ZABBIX_SERVER}"
    echo "CMD            = ${CMD}"
    echo "***********************"
    echo
fi
# set variables
test_vars

# cmd execution
METRIC_VALUE=$(eval "${CMD}")
# check
[ -z "${METRIC_VALUE}" ] && echo "Error: empty metric, nothing to report. Quitting..." && exit 1 

CMD2RUN="zabbix_sender -z ${ZABBIX_SERVER} -s '${GROUP_TITLE}' -k '${METRIC_TITLE}' -o ${METRIC_VALUE} >/dev/null"
# verbosity
if [ ${VERBOSITY} -ne 0 ]; then
    echo "****** Data collection commands ******"
    echo "METRIC_VALUE = ${METRIC_VALUE}"
    echo "zabbix_sender ${CMD2RUN}"
    echo "**************************************"
    echo
fi
if [ ${DRY_RUN} -eq 0 ]; then
    # sending data to Zabbix server
    eval ${CMD2RUN}
    [ $? -eq 0 ] && echo "[Zabbix] '${METRIC_TITLE}'->${METRIC_VALUE} .... PASSED" || echo "[Zabbix] '${METRIC_TITLE}'->${METRIC_VALUE} .... FAILED"
else
    echo "Dry run, data are not sent to Zabbix server."
    echo "[Test] '${METRIC_TITLE}'->${METRIC_VALUE}"
fi

exit 0
