#!/bin/bash


set -e
NAMESPACE="${NAMESPACE:-dev}"
JOB_NAME="backend-migration"
MAX_MINUTES=60
SLEEP_SECONDS=60

echo "Waiting for job '$JOB_NAME' to complete..."

for ((i=1; i<=MAX_MINUTES; i++)); do
  STATUS=$(kubectl get job $JOB_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
  if [[ "$STATUS" == "True" ]]; then
    echo "Migration job completed after $i minute(s)."
    break
  fi

  STATUS_FAILED=$(kubectl get job $JOB_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null)
  if [[ "$STATUS_FAILED" == "True" ]]; then
    echo "Migration job failed after $i minute(s)."
    break
  fi

  echo "Minute $i: migration still running..."
  sleep $SLEEP_SECONDS
done

# Get pod name
POD=$(kubectl get pods -n "$NAMESPACE" -l job-name="$JOB_NAME" -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || true)

# Wait 10s in case pod is finalizing
sleep 10

if [[ -n "$POD" ]]; then
  echo "Logs from pod $POD:"
  kubectl logs "$POD" -n "$NAMESPACE" || echo "No logs found, possibly pod deleted"
else
  echo "Pod not found for job '$JOB_NAME' in namespace '$NAMESPACE'"
fi

# Final check: fail if still not completed
FINAL_STATUS=$(kubectl get job $JOB_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
if [[ "$FINAL_STATUS" != "True" ]]; then
  echo "Migration did not complete in time."
  exit 1
fi

exit 0