k8s sandbox
===========
Kubernetes sandbox for personal infrastructure

Contents
--------
- kubernetes dashboard for debugging
- metallb as a bare-metal load-balancer
- ingress-nginx for ingress
- cert-manager for https certificate management
- external-dns for managing public DNS records

Usage
-----
Run the following command to apply all configured kubernetes manifests:

```
./kubectl-apply-wrapper.sh
```
