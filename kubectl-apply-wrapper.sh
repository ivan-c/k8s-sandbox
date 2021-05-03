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


load_env_files() {
    # load environment variables into current shell given list of environment variable files
    # automatically export all variables
    set -a
    . $@
    set +a
}


if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
fi

# load environment variables from .env files
load_env_files "$script_path/"*.env


MANIFEST_DIR="${script_path}"/manifests

echo Installing k8s dashboard...
# https://github.com/kubernetes/dashboard#install
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.4/aio/deploy/recommended.yaml
# https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md
kubectl apply -f "$MANIFEST_DIR"/dashboard

echo Installing load-balancer...
# https://metallb.universe.tf/installation#installation-by-manifest
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.6/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.6/manifests/metallb.yaml

# On first install only
if [ -z "$(kubectl get secret generic -n metallb-system memberlist --ignore-not-found)" ]; then
    kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
fi
# https://metallb.universe.tf/configuration#layer-2-configuration
kubectl apply -f "$MANIFEST_DIR"/load-balancer

echo Installing ingress...
# https://kubernetes.github.io/ingress-nginx/deploy/#provider-specific-steps
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.45.0/deploy/static/provider/cloud/deploy.yaml

echo Installing certificate manager...
# https://cert-manager.io/docs/installation/kubernetes/#installing-with-regular-manifests
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.3.0/cert-manager.yaml

echo Waiting for cert-manager startup...
time kubectl wait --for=condition=available --timeout=600s -n cert-manager --all deploy

# https://cert-manager.io/docs/configuration/acme/#creating-a-basic-acme-issuer
kubectl apply -f "$MANIFEST_DIR"/cert-manager
# https://cert-manager.io/docs/configuration/acme/dns01/digitalocean/
cat "$MANIFEST_DIR"/cert-manager/05dns-challenge-secret.yaml.tmpl | envsubst | kubectl apply -f -

echo Installing external-dns...
# https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/digitalocean.md#manifest-for-clusters-with-rbac-enabled
kubectl apply -f "$MANIFEST_DIR"/external-dns
# https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/digitalocean.md
cat "$MANIFEST_DIR"/external-dns/30service.yaml.tmpl | envsubst | kubectl apply -f -

echo Waiting for ingress-nginx admission webhook...
time kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=600s

echo Installing ingress test...
# https://cert-manager.io/docs/tutorials/acme/ingress/
kubectl apply -f "$MANIFEST_DIR"/ingress-test
