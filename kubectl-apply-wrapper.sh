#!/bin/sh
# fail on first error
set -e

cmdname="$(basename "$0")"
script_path="$(cd "$(dirname "$0")" && pwd)"

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

# load environment variables from .env files
# automatically export all variables
set -a
for environment_variable_file in "$script_path/"*.env; do
    test -e "$environment_variable_file" || continue
    . "${environment_variable_file}"
done
set +a


MANIFEST_DIR="${script_path}"/manifests

echo Installing k8s dashboard...
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.4/aio/deploy/recommended.yaml
kubectl apply -f "$MANIFEST_DIR"/dashboard

echo Installing load-balancer...
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.6/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.6/manifests/metallb.yaml

# On first install only
if [ -z "$(kubectl get secret generic -n metallb-system memberlist --ignore-not-found)" ]; then
    kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
fi
kubectl apply -f "$MANIFEST_DIR"/load-balancer

echo Installing ingress...
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.45.0/deploy/static/provider/cloud/deploy.yaml

echo Installing ingress test...
kubectl apply -f "$MANIFEST_DIR"/ingress-test
