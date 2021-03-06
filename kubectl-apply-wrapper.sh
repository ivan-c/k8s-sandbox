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


ensure_helm() {
    if command -v helm > /dev/null; then return; fi
    echo Installing helm...
    curl --silent https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
fi

# load environment variables from .env files
load_env_files "$script_path/"*.env


MANIFEST_DIR="${script_path}"/manifests
FILES_DIR="${script_path}"/files


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
kubectl wait --for=condition=available --timeout=600s -n cert-manager --all deploy

# https://cert-manager.io/docs/configuration/acme/#creating-a-basic-acme-issuer
kubectl apply -f "$MANIFEST_DIR"/cert-manager
# https://cert-manager.io/docs/configuration/acme/dns01/digitalocean/
envsubst < "$MANIFEST_DIR"/cert-manager/05dns-challenge-secret.yaml.tmpl | kubectl apply -f -
envsubst < "$MANIFEST_DIR"/cert-manager/05dns-challenge-secret-cluster-issuer.yaml.tmpl | kubectl apply -f -

echo Installing external-dns...
# https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/digitalocean.md#manifest-for-clusters-with-rbac-enabled
kubectl apply -f "$MANIFEST_DIR"/external-dns
# https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/digitalocean.md
envsubst < "$MANIFEST_DIR"/external-dns/30service.yaml.tmpl | kubectl apply -f -

echo Waiting for ingress-nginx admission webhook...
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=600s

echo Installing ingress test...
# https://cert-manager.io/docs/tutorials/acme/ingress/
kubectl apply -f "$MANIFEST_DIR"/ingress-test

ensure_helm

echo Installing NFS External Storage Provisioner...
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm upgrade nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --install \
    --set nfs.server=doduo \
    --set nfs.path=/doduo/system-data/kubernetes

# connect to http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:k8s-dashboard-kubernetes-dashboard:https/proxy/
echo Installing k8s dashboard...
# https://github.com/kubernetes/dashboard#install
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm upgrade k8s-dashboard kubernetes-dashboard/kubernetes-dashboard \
    --install \
    --create-namespace --namespace kubernetes-dashboard \
    --values "$MANIFEST_DIR"/helm/dashboard/values-k8s-dashboard.yml

# TODO investigate better way of accessing dashboard than ServiceAccount
echo Granting admin to dashboard user...
# https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md
kubectl apply -f "$MANIFEST_DIR"/dashboard

echo Installing openldap...
helm repo add helm-openldap https://jp-gouin.github.io/helm-openldap/
helm upgrade openldap helm-openldap/openldap-stack-ha \
    --install \
    --create-namespace --namespace identity \
    --values "$MANIFEST_DIR"/helm/ldap/values-openldap.yml

# On first install only
if [ -z "$(kubectl get secret generic -n identity realm-secret --ignore-not-found)" ]; then
    echo Configuring Keycloak secrets...
    kubectl create secret generic -n identity realm-secret --from-file="$FILES_DIR"/helm/keycloak/realm.json
fi

echo Installing Keycloak...
helm repo add codecentric https://codecentric.github.io/helm-charts
helm upgrade --install --create-namespace --namespace identity keycloak codecentric/keycloak --values "$MANIFEST_DIR"/helm/keycloak/values-keycloak.yml

echo Installing oauth2-proxy
helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests
helm upgrade oauth2-proxy oauth2-proxy/oauth2-proxy \
    --install \
    --create-namespace --namespace identity \
    --values "$MANIFEST_DIR"/helm/oauth2-proxy/values-oauth2-proxy.yml
