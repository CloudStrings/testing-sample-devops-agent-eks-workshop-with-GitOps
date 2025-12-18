#!/bin/bash
# Shared verification functions for fault injection scripts

# Check pod status for a namespace/deployment
check_pod_status() {
  local namespace=$1
  local label=$2
  
  echo "  $namespace pods:"
  kubectl get pods -n $namespace -l $label --no-headers 2>/dev/null | sed 's/^/    /' || echo "    No pods found"
}

# Check for OOMKilled pods
check_oom_errors() {
  local namespace=$1
  local label=$2
  
  echo "  Checking for OOMKilled events in $namespace..."
  local oom_count=$(kubectl get pods -n $namespace -l $label -o jsonpath='{.items[*].status.containerStatuses[*].lastState.terminated.reason}' 2>/dev/null | grep -c "OOMKilled" || echo "0")
  if [ "$oom_count" -gt 0 ]; then
    echo "    ⚠ Found $oom_count OOMKilled container(s)"
    kubectl get pods -n $namespace -l $label -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.status.containerStatuses[*].lastState.terminated.reason}{"\n"}{end}' 2>/dev/null | grep OOMKilled | sed 's/^/    /'
  else
    echo "    ✓ No OOMKilled containers"
  fi
}

# Check pod resource usage (CPU/Memory)
check_resource_usage() {
  local namespace=$1
  local label=$2
  
  echo "  Resource usage in $namespace:"
  kubectl top pods -n $namespace -l $label 2>/dev/null | sed 's/^/    /' || echo "    Metrics not available (metrics-server may not be installed)"
}

# Check service connectivity via port-forward
check_service_connectivity() {
  local namespace=$1
  local service=$2
  local local_port=$3
  local endpoint=$4
  local expected_status=${5:-"200"}
  
  kubectl port-forward -n $namespace svc/$service $local_port:80 &>/dev/null &
  local pf_pid=$!
  sleep 2
  
  if kill -0 $pf_pid 2>/dev/null; then
    local start_time=$(date +%s%3N)
    local status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://localhost:$local_port$endpoint" 2>/dev/null)
    local end_time=$(date +%s%3N)
    local latency=$((end_time - start_time))
    kill $pf_pid 2>/dev/null
    
    if [ "$status" == "$expected_status" ] || [ "$status" == "200" ] || [ "$status" == "201" ]; then
      echo "  ✓ $service: HTTP $status (${latency}ms)"
    elif [ "$status" == "000" ]; then
      echo "  ✗ $service: Connection timeout"
    else
      echo "  ⚠ $service: HTTP $status (${latency}ms)"
    fi
  else
    echo "  ✗ $service: Could not establish port-forward"
  fi
}

# Check application logs for errors
check_logs_for_errors() {
  local namespace=$1
  local label=$2
  local pattern=${3:-"error|exception|timeout|refused|failed"}
  local lines=${4:-10}
  
  echo "  Recent errors in $namespace logs:"
  local errors=$(kubectl logs -n $namespace -l $label --tail=100 2>/dev/null | grep -iE "$pattern" | tail -$lines)
  if [ -n "$errors" ]; then
    echo "$errors" | sed 's/^/    /'
  else
    echo "    ✓ No recent errors found"
  fi
}

# Check network connectivity from a pod
check_network_connectivity() {
  local source_namespace=$1
  local source_label=$2
  local target_url=$3
  
  local pod=$(kubectl get pod -n $source_namespace -l $source_label -o name 2>/dev/null | head -1)
  if [ -n "$pod" ]; then
    echo "  Testing connectivity from $source_namespace to $target_url..."
    local result=$(kubectl exec -n $source_namespace $pod -- curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$target_url" 2>/dev/null || echo "failed")
    if [ "$result" == "200" ] || [ "$result" == "201" ]; then
      echo "    ✓ Connection successful (HTTP $result)"
    elif [ "$result" == "failed" ] || [ "$result" == "000" ]; then
      echo "    ✗ Connection failed/timeout"
    else
      echo "    ⚠ HTTP $result"
    fi
  else
    echo "    - No pod found in $source_namespace"
  fi
}

# Show recent pod events
check_pod_events() {
  local namespace=$1
  local label=$2
  
  echo "  Recent events in $namespace:"
  kubectl get events -n $namespace --sort-by='.lastTimestamp' 2>/dev/null | grep -E "Warning|Error" | tail -5 | sed 's/^/    /' || echo "    No warning/error events"
}

# Verify pods are healthy (Running and Ready)
verify_pods_healthy() {
  local namespace=$1
  local label=$2
  local timeout=${3:-60}
  
  echo "  Waiting for pods to be healthy in $namespace (timeout: ${timeout}s)..."
  local end_time=$(($(date +%s) + timeout))
  
  while [ $(date +%s) -lt $end_time ]; do
    local not_ready=$(kubectl get pods -n $namespace -l $label --no-headers 2>/dev/null | grep -v "Running" | grep -v "Completed" | wc -l)
    if [ "$not_ready" -eq 0 ]; then
      echo "    ✓ All pods healthy"
      return 0
    fi
    sleep 5
  done
  
  echo "    ⚠ Some pods not healthy after ${timeout}s"
  kubectl get pods -n $namespace -l $label --no-headers 2>/dev/null | grep -v "Running" | sed 's/^/    /'
  return 1
}

# Generate traffic burst to a service
generate_traffic_burst() {
  local namespace=$1
  local service=$2
  local local_port=$3
  local endpoint=$4
  local count=${5:-10}
  
  kubectl port-forward -n $namespace svc/$service $local_port:80 &>/dev/null &
  local pf_pid=$!
  sleep 2
  
  if kill -0 $pf_pid 2>/dev/null; then
    echo "  Sending $count requests to $service..."
    for i in $(seq 1 $count); do
      curl -s -o /dev/null -w "%{http_code} " --max-time 10 "http://localhost:$local_port$endpoint" 2>/dev/null &
    done
    wait
    echo ""
    kill $pf_pid 2>/dev/null
    echo "  ✓ $service: $count requests sent"
  else
    echo "  - Could not port-forward to $service"
  fi
}
