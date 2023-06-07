#!/bin/bash
echo "Creating working directory in /opt/openssl/tests and copying necesary files."
mkdir -p /opt/openssl/tests && cp -r build perftest /opt/openssl/tests
[ $? -eq 0 ] && { echo "PASSED"; exit 0; } || { echo "FAILED"; exit 1; }
