
echo "== restart port-forwards =="
pkill -f "port-forward" 2>/dev/null; sleep 1
nohup kubectl -n monitoring port-forward svc/kube-prom-grafana 3000:80 >/tmp/pf-g.log 2>&1 &
nohup kubectl -n monitoring port-forward svc/kube-prom-kube-prometheus-prometheus 9090:9090 >/tmp/pf-p.log 2>&1 &
nohup kubectl -n inference  port-forward svc/litellm 4000:4000 >/tmp/pf-l.log 2>&1 &
