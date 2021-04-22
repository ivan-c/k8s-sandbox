#!/bin/sh
# fail on first error
set -e

cmdname="$(basename "$0")"

usage() {
   cat << USAGE >&2
Usage:
   $cmdname [-h] [--help]
   -h
   --help
          Show this help message

USAGE
   exit 1
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
fi

MANIFEST_DIR=manifests

echo Installing k8s dashboard...
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.4/aio/deploy/recommended.yaml
kubectl apply -f "$MANIFEST_DIR"/dashboard

