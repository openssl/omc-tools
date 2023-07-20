#!/bin/bash

PERFTEST_WRAPPER=/opt/openssl/tests/perftest/perftest_wrapper.sh
BUILDS_DIR=/opt/openssl/tests/build
# default metrics values
ALLOWED_OSSL_VERSIONS=("master" "1.1.1" "3.0" "3.1")
OSSL_VERSION=${ALLOWED_OSSL_VERSIONS[0]}
ALLOWED_THREADS=(0 1 10 100 500 1000)
ZABBIX_SERVER=127.0.0.1
THREADS=1
REPEAT=1
# PerfTest-OpenSSL-<openssl-branch>
METRIC_HOST=""
# perftest.handshakes-per-second-<threads>"
METRIC_TITLE=""
DATA=()
DRY_RUN=0
VERBOSITY=0
OPTS=""


# print help
function print_help() {
    echo "Usage: ${0} [options]"
    echo "    options:"
    echo "        -d ...... dry run, don't send results anywhere"
    echo "        -h ...... this help"
    echo "        -r <repeat test N times>"
    echo "        -t <number of threads>"
    MAXLEN=0
    for i in ${ALLOWED_THREADS[@]}; do [ ${#i} -gt ${MAXLEN} ] && MAXLEN=${#i}; done
    for value in ${ALLOWED_THREADS[@]}; do
        for i in $(seq 1 1 $(expr ${MAXLEN} - ${#value})); do echo -n " "; done
        [ ${value} -eq 0 ] && \
            echo "             0 (multiple runs with all the allowed values)" && continue
        [ ${value} -eq 1 ] && \
            echo "             ${value} (DEFAULT)" || \
            echo "             ${value}"
    done
    echo "        -V <OpenSSL version> to run on"
    MAXLEN=0
    for i in ${ALLOWED_OSSL_VERSIONS[@]}; do [ ${#i} -gt ${MAXLEN} ] && MAXLEN=${#i}; done
    for value in ${ALLOWED_OSSL_VERSIONS[@]}; do
        echo -n "            ${value} ......"
        for i in $(seq 1 1 $(expr ${MAXLEN} - ${#value})); do echo -n "."; done
        [ "${value}" == "${ALLOWED_OSSL_VERSIONS[0]}" ] && \
            echo " openssl-${value} (DEFAULT)" || \
            echo " openssl-${value}"
    done
    echo "        -v ...... verbosity"
    echo "        -z <Zabbix server IP address / hostname>"
    echo
    echo "Dependencies:"
    echo "    OpenSSL and OpenSSL-tools built in ../build/<version> and ../build/<version>-tools"
}

# arguments parser
function parse_args() {
    while getopts 'dhr:t:V:vz:' option; do
    case "${option}" in
        # dry run
        d)
            DRY_RUN=1
            OPTS+=" -d"
            ;;
        # help
        h)
            print_help
            exit 0
            ;;
        # repeat
        r)
            # used parameter but no or wrong value given
            if [ -z "${OPTARG}" ] || $(echo "${OPTARG}" | grep -q "^-") || [[ ${OPTARG} != ?(-)+([0-9]) ]] || [ ${OPTARG} -le 0 ]; then
                print_help
                exit 1
            fi
            REPEAT=${OPTARG}
            ;;
        # thread count
        t)
            # used parameter but no or wrong value given
            if [ -z "${OPTARG}" ] || $(echo "${OPTARG}" | grep -q "^-") || [[ ${OPTARG} != ?(-)+([0-9]) ]]; then
                print_help
                exit 1
            fi
            # threads count check - available options in $ALLOWED_THREADS
            for value in ${ALLOWED_THREADS[@]}; do
                [ ${value} -eq ${OPTARG} ] && THREADS=${OPTARG} && break
            done
            # 0 ... run with all the defined thread values
            [ ${THREADS} -ne ${OPTARG} ] && print_help && exit 1
            ;;
        # OpenSSL version
        V)
            # used parameter but no version given
            if [ -z "${OPTARG}" ] || $(echo "${OPTARG}" | grep -q "^-"); then
                print_help
                exit 1
            fi
            # allowed values
            for value in ${ALLOWED_OSSL_VERSIONS[@]}; do
                [ "${value}" == "${OPTARG}" ] && OSSL_VERSION=${OPTARG} && break
            done
            [ "${OSSL_VERSION}" != "${OPTARG}" ] && print_help && exit 1
            ;;
        # verbosity
        v)
            VERBOSITY=1
            OPTS+=" -v"
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


# return median from array of $DATA
function median() {
    MID_INDEX=$(expr ${REPEAT} / 2)
    TMP_DATA=($(printf '%s\n' "${DATA[@]}" | sort))
    echo ${TMP_DATA[${MID_INDEX}]}
}


# SETUP
echo "*************** Setup ***************"
[ ! -x ${PERFTEST_WRAPPER} ] && echo "Error: ${PERFTEST_WRAPPER} not executble or doesn't exist. Quitting..." && exit 1
# arguments
parse_args "$@"
# builds check
[ ! -x ${BUILDS_DIR}/${OSSL_VERSION}-tools/perf/handshake ] && echo "Error: The handshake test for OpenSSL ${OSSL_VERSION} not available. Quitting." && exit 1
# metrics setup
METRIC_HOST="PerfTest-OpenSSL-${OSSL_VERSION}"
METRIC_TITLE="perftest.handshakes-per-second-${THREADS}"

# TEST
echo "*************** Tests ***************"
# test execution via "perftest wrapper"
# only 1 test -> redefining the array
[ ${THREADS} -ne 0 ] && ALLOWED_THREADS=(${THREADS})
for value in ${ALLOWED_THREADS[@]}; do
    [ ${value} -eq 0 ] && continue
    THREADS=${value}
    METRIC_TITLE="perftest.handshakes-per-second-${THREADS}"
    echo "----"
    echo "Running test '${METRIC_TITLE}'"
    DATA=()
    for i in $(seq 1 1 ${REPEAT}); do
        CMD2RUN="LD_LIBRARY_PATH=${BUILDS_DIR}/${OSSL_VERSION} ${BUILDS_DIR}/${OSSL_VERSION}-tools/perf/handshake ${BUILDS_DIR}/${OSSL_VERSION}/test/certs ${THREADS} | grep 'Handshakes per second' | awk '{ print \$4; }'"
        if [ ${VERBOSITY} -ne 0 ]; then
            echo "Running: ${CMD2RUN}"
            DATA+=($(eval "${CMD2RUN}"))
            echo "    Rusult: ${DATA[$((${#DATA[@]} - 1))]}"
            echo 
        else
            DATA+=($(eval ${CMD2RUN}))
        fi
    done
    # "dry run" and "verbosity" are passed to perftest_wrapper as well
    ${PERFTEST_WRAPPER} -z ${ZABBIX_SERVER} -g "${METRIC_HOST}" -m "${METRIC_TITLE}" -c "echo $(median)" ${OPTS}
done

exit 0
