#!/bin/bash

set -e
set -o nounset
set -o pipefail

# Set variables
GREEN="\033[32m"
RESET="\033[0m"
NAMESPACE="openshift-machine-api"
CA_NAME="default"

# Get current logVerbosity value
current_log_verbosity=$(oc get clusterautoscalers $CA_NAME -o jsonpath='{.spec.logVerbosity}')

# Check if current_log_verbosity is empty
if [ -z "$current_log_verbosity" ]; then
  printf "Failed to retrieve current logVerbosity value.\n\
Kindly verify if the cluster autoscaling is enabled. To verify it, search the cluster on OCM (https://console.redhat.com/openshift/) and on the overview page, check if the cluster autoscaling section is \"Enabled\". If it is \"Disabled\", enable the cluster-autoscaling by following:\n\
1. Search the cluster on OCM (https://console.redhat.com/openshift/)\n\
2. Navigate to Machine Pools tab -> Click on \"Edit cluster autoscaling\" -> Save the desired settings.\n"
  exit 1
fi

echo
echo "CURRENT LOG VERBOSITY = $current_log_verbosity"
echo

# Update logVerbosity to 6
oc patch clusterautoscalers $CA_NAME --type='json' -p='[{"op": "replace", "path": "/spec/logVerbosity", "value": 6}]'

updated_log_verbosity=$(oc get clusterautoscalers $CA_NAME -o jsonpath='{.spec.logVerbosity}')
echo
echo "UPDATED LOG VERBOSITY = $updated_log_verbosity"
echo

# Wait for the update to take effect
echo "Waiting for the log verbosity to update..."

# Sleep for 10 seconds so that the new pod name gets reflected
sleep 10

CA_POD=$(oc get pods -n openshift-machine-api | grep cluster-autoscaler-default | awk '{print $1}')
echo "POD Name: $CA_POD"

while true; do
  # Get the name and status of the cluster-autoscaler pod
  POD_STATUS=$(oc get pod "$CA_POD" -n $NAMESPACE -o jsonpath='{.status.phase}')

  # Check if the pod status is "Running"
  if [ "$POD_STATUS" == "Running" ]; then
    echo "The cluster-autoscaler pod is now 'Running'."
    break
  fi

  # Print the current status and wait before rechecking
  echo "Current status: $POD_STATUS. Waiting..."
  sleep 5
done

# Collect logs for the next 6 minutes
echo
echo "Collecting logs for the next 6 minutes..."
echo

# Sleep for 6 minutes to let CA pod generate logs
sleep 360

echo "---------------------"
echo "LOG COLLECTION: START"
echo "---------------------"
echo
CA_LOGS=$(oc logs -n $NAMESPACE "$CA_POD" --since=6m)

# Collect the list of nodes from the cluster
node_names=$(oc get nodes -o jsonpath='{.items[*].metadata.name}')

for node in $node_names; 
do
    echo -e "${GREEN}Searching for node: $node ${RESET}"
    # Step 3: Display all the log lines where the node name is present
    echo "$CA_LOGS" | grep "$node"
    echo
done

echo
echo "---------------------"
echo "LOG COLLECTION: END"
echo "---------------------"

echo

# Revert logVerbosity to previous value
oc patch clusterautoscalers $CA_NAME --type='json' -p="[{'op': 'replace', 'path': '/spec/logVerbosity', 'value': $current_log_verbosity}]"

# Wait for the update to take effect
echo
echo "Waiting for the log verbosity to be reverted back..."
echo

# Sleep for 10 seconds so that the new pod name gets reflected
sleep 10

CA_POD=$(oc get pods -n openshift-machine-api | grep cluster-autoscaler-default | awk '{print $1}')
echo "POD Name: $CA_POD"

while true; do
  # Get the name and status of the cluster-autoscaler pod
  POD_STATUS=$(oc get pod "$CA_POD" -n $NAMESPACE -o jsonpath='{.status.phase}')

  # Check if the pod status is "Running"
  if [ "$POD_STATUS" == "Running" ]; then
    echo "The cluster-autoscaler pod is now 'Running'."
    break
  fi

  # Print the current status and wait before rechecking
  echo "Current status: $POD_STATUS. Waiting..."
  sleep 5
done

current_log_verbosity=$(oc get clusterautoscalers $CA_NAME -o jsonpath='{.spec.logVerbosity}')
echo "REVERTED LOG VERBOSITY = $current_log_verbosity"
echo
