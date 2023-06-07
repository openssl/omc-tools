#!/bin/bash

WORK_DIR=/opt/openssl/tests/build
REPO_DIR=${WORK_DIR}/openssl
TOOLSREPO_DIR=""
FLAG_FILE=${WORK_DIR}/RUNNING
[ -f ${FLAG_FILE} ] && echo "The build task is already running. Quitting." && exit 1 
# default metrics values
ALLOWED_OSSL_VERSIONS=("master" "1.1.1" "3.0" "3.1")
OSSL_BASE_GIT_LINK="https://github.com/openssl"
OSSL_GIT_LINK="${OSSL_BASE_GIT_LINK}/openssl"
OSSLTOOLS_GIT_LINK="${OSSL_BASE_GIT_LINK}/tools"
TOOLS=0
declare -A OSSL_GIT_VERSIONS
OSSL_GIT_VERSIONS[master]="master"
OSSL_GIT_VERSIONS[1.1.1]="OpenSSL_1_1_1-stable"
OSSL_GIT_VERSIONS[3.0]="openssl-3.0"
OSSL_GIT_VERSIONS[3.1]="openssl-3.1"
OSSL_VERSION=""

# print help
function print_help() {
    echo "Usage: ${0} [options]"
    echo "    options:"
    echo "        -h ....................... this help"
    echo "        -t ....................... build Tools as well"
    echo "        -V <OpenSSL version> ..... OpenSSL version to build"
    MAXLEN=0
    for i in ${ALLOWED_OSSL_VERSIONS[@]}; do [ ${#i} -gt ${MAXLEN} ] && MAXLEN=${#i}; done
    for value in ${ALLOWED_OSSL_VERSIONS[@]}; do
        echo -n "            ${value} ......"
        for i in $(seq 1 1 $(expr ${MAXLEN} - ${#value})); do echo -n "."; done
        [ "${value}" == "${ALLOWED_OSSL_VERSIONS[0]}" ] && \
            echo " openssl-${value} (DEFAULT)" || \
            echo " openssl-${value}"
    done
}

# arguments parser
function parse_args() {
    while getopts 'htV:' option; do
    case "${option}" in
        # help
        h)
            print_help
            exit 0
            ;;
        # Tools
        t)
            TOOLSREPO_DIR="${WORK_DIR}/tools"
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
        *)
            print_help
            exit 1
            ;;
    esac
    done
}

# cleanup
function cleanup() {
    [ -f ${FLAG_FILE} ] && rm ${FLAG_FILE}
}


# SETUP
echo "*************** Setup ***************"
# arguments
parse_args "$@"
# preparation and pulling code from the repository
echo "Prepairing fresh bits from GIT in Working directory. This may take a while..."
[ ! -d ${WORK_DIR} ] && mkdir -p ${WORK_DIR}
cd ${WORK_DIR} && touch ${FLAG_FILE} || { echo "Cannot access working directory: ${WORK_DIR}"; cleanup; exit 1; }
# clone OpenSSL repository
if [ ! -d ${REPO_DIR} ]; then
    git clone ${OSSL_GIT_LINK} ${REPO_DIR} >/dev/null 2>&1 || { echo "Cannot clone openssl repository. Quitting."; cleanup; exit 1; }
else
    cd ${REPO_DIR}
    git reset --hard >/dev/null 2>&1
    git clean -fxd >/dev/null 2>&1
    git pull >/dev/null 2>&1
    cd ${WORK_DIR}
fi
# clone Tools as well
if [ -n "${TOOLSREPO_DIR}" ]; then
    if [ ! -d ${TOOLSREPO_DIR} ]; then
        git clone ${OSSLTOOLS_GIT_LINK} ${TOOLSREPO_DIR} >/dev/null 2>&1 || { echo "Cannot clone openssl tools repository. Quitting."; cleanup; exit 1; }
    else
        cd ${TOOLSREPO_DIR}
        git reset --hard >/dev/null 2>&1
        git clean -fxd >/dev/null 2>&1
        git pull >/dev/null 2>&1
        cd ${WORK_DIR}
    fi
fi

# TEST
# determine whether to build all versions or there is a given one
[ -n "${OSSL_VERSION}" ] && ALLOWED_OSSL_VERSIONS=(${OSSL_VERSION})
for osslversion in ${ALLOWED_OSSL_VERSIONS[@]}; do
    # OpenSSL
    #   repo direcotry
    if [ ! -d ${WORK_DIR}/${osslversion} ]; then
        cp -r ${REPO_DIR} ${WORK_DIR}/${osslversion}
        cd ${WORK_DIR}/${osslversion}
        git checkout ${OSSL_GIT_VERSIONS[${osslversion}]}
    else
        cd ${WORK_DIR}/${osslversion}
        git checkout ${OSSL_GIT_VERSIONS[${osslversion}]}
        git reset --hard >/dev/null 2>&1
        git clean -fxd >/dev/null 2>&1
        git pull >/dev/null 2>&1
    fi
    #   BUILD
    #./Configure --prefix=/usr/local/ssl --openssldir=/usr/local/ssl -Wl,--enable-new-dtags,-rpath,$(LIBRPATH) && make
    ./config && make || { echo "Build failed. Quitting."; cleanup; exit 1; }
    # Tools
    #   repo direcotry
    if [ -n "${TOOLSREPO_DIR}" ]; then
        TOOLSREPO_VER_DIR=${WORK_DIR}/${osslversion}-tools
        # cleanup
        [ -d ${TOOLSREPO_VER_DIR} ] && rm -rf ${TOOLSREPO_VER_DIR}
        cp -r ${TOOLSREPO_DIR} ${TOOLSREPO_VER_DIR}
        #   BUILD
        cd ${TOOLSREPO_VER_DIR}/perf
        export TARGET_OSSL_INCLUDE_PATH=${WORK_DIR}/${osslversion}/include
        export TARGET_OSSL_LIBRARY_PATH=${WORK_DIR}/${osslversion}
        make || { echo "Build failed. Quitting."; cleanup; exit 1; }
    fi
    cd ${WORK_DIR}
done

echo "Finished successfuly."
cleanup
exit 0
