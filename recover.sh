#!/usr/bin/env bash
# Heal the cluster after a JarvisLabs pause/relaunch. Run on the control-plane.
set -uo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "== 1. delete NotReady ghost nodes =="
for n in $(kubectl get nodes --no-headers | awk '$2=="NotReady"{print $1}'); do
  echo "  deleting ghost $n"; kubectl delete node "$n"
done

echo "== 2. find the GPU node, re-label, re-MIG =="
# GPU node = a Ready node that has (or had) nvidia resources; detect via node-feature-discovery label
GPU_NODE=$(kubectl get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | awk '{print $1}' | head -1)
# fallback: any Ready worker (non control-plane)
[ -z "$GPU_NODE" ] && GPU_NODE=$(kubectl get nodes --no-headers | awk '$3=="<none>" && $2=="Ready"{print $1}' | head -1)
echo "  GPU node: $GPU_NODE"

kubectl label node "$GPU_NODE" nodepool=gpu gpu-type=h100 --overwrite
kubectl patch clusterpolicy cluster-policy --type merge -p '{"spec":{"mig":{"strategy":"mixed"}}}'
kubectl label node "$GPU_NODE" nvidia.com/mig.config=all-balanced --overwrite

echo "  waiting for MIG partition to apply (up to ~5 min)..."
for i in $(seq 1 60); do
  state=$(kubectl get node "$GPU_NODE" -o jsonpath='{.metadata.labels.nvidia\.com/mig\.config\.state}' 2>/dev/null)
  mig3g=$(kubectl get node "$GPU_NODE" -o jsonpath='{.status.capacity.nvidia\.com/mig-3g\.40gb}' 2>/dev/null)
  echo "    state=$state  mig-3g.40gb=$mig3g"
  [ "$state" = "success" ] && [ "$mig3g" = "1" ] && { echo "  MIG ready."; break; }
  sleep 5
done

echo "== 3. restart port-forwards =="
pkill -f "port-forward" 2>/dev/null; sleep 1
nohup kubectl -n monitoring port-forward svc/kube-prom-grafana 3000:80 >/tmp/pf-g.log 2>&1 &
nohup kubectl -n monitoring port-forward svc/kube-prom-kube-prometheus-prometheus 9090:9090 >/tmp/pf-p.log 2>&1 &
nohup kubectl -n inference  port-forward svc/litellm 4000:4000 >/tmp/pf-l.log 2>&1 &

echo "== done. check: kubectl get nodes ; kubectl -n inference get pods =="
