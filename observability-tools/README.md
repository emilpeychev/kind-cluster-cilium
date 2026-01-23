# Observability tools — Argo CD repo secret

This folder contains Argo CD Applications and AppProjects for Kiali, Prometheus and Grafana.

Do NOT commit repository credentials to git. The provided `addrepo-argcd.yaml` files are templates and intentionally omit the `password` value.

To create the Argo CD repository secret from the robot credentials (saved by the install scripts to `.harbor-robot-pass.env`), run:

```bash
# from repository root
source .harbor-robot-pass.env
kubectl create secret generic harbor-helm-repo -n argocd \
  --from-literal=url=https://harbor.local \
  --from-literal=username='robot$argocd' \
  --from-literal=password="$ROBOT_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

# ensure Argo CD recognizes the repository (optional):
kubectl label secret harbor-helm-repo -n argocd argocd.argoproj.io/secret-type=repository --overwrite
kubectl rollout restart deployment argocd-repo-server -n argocd
```

Alternative (argocd CLI):

```bash
argocd repo add harbor.local --type helm --name harbor-helm --enable-oci \
  --username 'robot$argocd' --password "$ROBOT_PASS"
```

If you re-created the cluster from scratch, re-run `08-argocd.sh` (or otherwise ensure `argocd-tls-certs-cm` contains the Harbor CA) before attempting OCI pulls.
