#!/bin/sh -e
git_sha="$1"
pr_number_or_branch="$2"

summarize_and_quit() {
  echo "$1" | tee -a "$GITHUB_STEP_SUMMARY"
  exit $2
}

summarize_without_notice() {
  perl -pe 's/::notice :://' | tee -a "$GITHUB_STEP_SUMMARY"
}

check_for_updates() {
  if [ -n "$CHECK_FOR_UPDATES_DIR" ]; then
    (
      cd "$CHECK_FOR_UPDATES_DIR"
      git fetch && git checkout FETCH_HEAD
    )
    if [ ! -e "$CHECK_FOR_UPDATES_FILE" ]; then
      summarize_and_quit "check-for-updates-file '$CHECK_FOR_UPDATES_FILE' no longer exists" 2
    fi
    if [ ! -s "$CHECK_FOR_UPDATES_FILE" ]; then
      summarize_and_quit "check-for-updates-file '$CHECK_FOR_UPDATES_FILE' is empty" 3
    fi
    NEW_SHA_VALUE=$(cat "$CHECK_FOR_UPDATES_FILE")
    if [ "$git_sha" != "$NEW_SHA_VALUE" ]; then
      summarize_and_quit "check-for-updates-file '$CHECK_FOR_UPDATES_FILE' now refers to a new value: $NEW_SHA_VALUE" 4
    fi
  fi
}

if [ -z "$git_sha" ]; then
  summarize_and_quit "Usage $0 GIT_SHA [PR_NUMBER_OR_BRANCH]" 1
fi

if [ -z "$pr_number_or_branch" ]; then
  pr_number_or_branch="master"
fi

if [ -n "$CHECK_FOR_UPDATES_FILE" ]; then
  CHECK_FOR_UPDATES_DIR=$(dirname "$CHECK_FOR_UPDATES_FILE")
fi

export workflow_name="${pr_number_or_branch}-${git_sha}"

if [ -n "$ARGO_URL_BASE" ]; then
  echo "::notice ::Looking for $ARGO_URL_BASE/workflows/e2e-tests/$workflow_name" |
    summarize_without_notice
fi

if [ -n "$GOOGLE_CLOUD_PROJECT_ID" ]; then
  echo "::notice ::See logs in https://console.cloud.google.com/logs/query;query=resource.labels.namespace_name%3D%22e2e-tests%22%0Alabels.%22k8s-pod%2Fworkflows_argoproj_io%2Fworkflow%22%3D%22$workflow_name%22;aroundTime=$(date '+%Y-%m-%dT%H:%M:%SZ');duration=PT15M?project=$GOOGLE_CLOUD_PROJECT_ID" |
    summarize_without_notice
fi

while true; do
  check_for_updates
  workflow_status=$(
    kubectl get -n e2e-tests workflow/$workflow_name -o json 2>/dev/null |
    jq -r .status.phase
  )
  if [ -z "$workflow_status" ]; then
    echo "Waiting for e2e workflow for $workflow_name to appear..."
  elif [ "$workflow_status" = "Pending" ] ||
       [ "$workflow_status" = "Running" ] ||
       [ "$workflow_status" = "null" ]; then
    echo "Waiting for e2e workflow for $workflow_name to complete..."
  else
    break
  fi
  sleep 5
done

echo "E2E workflow for $workflow_name finished with status $workflow_status"
if [ "$workflow_status" = "Succeeded" ]; then
  exit 0
fi

check_for_updates
e2e_pod=$(
  kubectl get pods -n e2e-tests -l "$POD_LABEL_NAME=$POD_LABEL_VALUE" --sort-by=.status.startTime --no-headers |
  perl -ne 'next unless /$ENV{workflow_name}/; s/^\s*(\S+).*/$1/; print;' |
  tail -n 1
)
if [ -z "$e2e_pod" ]; then
  echo "::error ::Unable to find the $POD_LABEL_VALUE pod for $workflow_name to retrieve logs"
  exit 2
fi

if [ -z "$CAPTURE_LOG" ]; then
  $GITHUB_ACTION_PATH/../scripts/add-matchers.sh
  echo "Showing log for pod: $e2e_pod"
  log_file=/dev/stdout
else
  log_file=$(mktemp)
  echo "log=$log_file" >> "$GITHUB_OUTPUT"
fi

kubectl -n e2e-tests logs "$e2e_pod" -c main >> "$log_file"
if [ -z "$CAPTURE_LOG" ]; then
  exit 1
fi
