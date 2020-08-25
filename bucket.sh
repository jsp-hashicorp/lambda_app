#!/bin/bash
# Script that clones Terraform configuration from a git repository
# creates a workspace if it does not already exist, uploads the
# Terraform configuration to it, adds variables to the workspace,
# triggers a run, checks the results of Sentinel policies (if any)
# checked against the workspace, and if $override=true and there were
# no hard-mandatory violations of Sentinel policies, does an apply.
# If an apply is done, the script waits for it to finish and then
# downloads the apply log and the before and after state files.

# Make sure TFE_TOKEN and TFE_ORG environment variables are set
# to owners team token and organization name for the respective
# TFE environment. TFE_ADDR should be set to the FQDN/URL of the private
# TFE server or if unset it will default to TF Cloud/SaaS address.

if [ ! -z "$TFE_TOKEN" ]; then
  token=$TFE_TOKEN
  echo "TFE_TOKEN environment variable was found."
else
  echo "TFE_TOKEN environment variable was not set."
  echo "You must export/set the TFE_TOKEN environment variable."
  echo "It should be a user or team token that has write or admin"
  echo "permission on the workspace."
  echo "Exiting."
  exit
fi

# Evaluate $TFE_ORG environment variable
# If not set, give error and exit
if [ ! -z "$TFE_ORG" ]; then
  organization=$TFE_ORG
  echo "TFE_ORG environment variable was set to ${TFE_ORG}."
  echo "Using organization, ${organization}."
else
  echo "You must export/set the TFE_ORG environment variable."
  echo "Exiting."
  exit
fi

# Evaluate $TFE_ADDR environment variable if it exists
# Otherwise, use "app.terraform.io"
# You should edit these before running the script.
if [ ! -z "$TFE_ADDR" ]; then
  address=$TFE_ADDR
  echo "TFE_ADDR environment variable was set to ${TFE_ADDR}."
  echo "Using address, ${address}"
else
  address="app.terraform.io"
  echo "TFE_ADDR environment variable was not set."
  echo "Using Terraform Cloud (TFE SaaS) address, app.terraform.io."
  echo "If you want to use a private TFE server, export/set TFE_ADDR."
fi

# workspace name should not have spaces and should be set as second
# argument from CLI

workspace="workspace-from-api"

# You can change sleep duration if desired
sleep_duration=5



config_dir="."

# Set workspace if provided as the second argument
if [ ! -z "$TFE_WORKSPACE" ]; then
  workspace=$TFE_WORKSPACE
  echo "Using workspace provided as argument: " $workspace
else
  echo "Using workspace set in the script."
fi

# Make sure $workspace does not have spaces
if [[ "${workspace}" != "${workspace% *}" ]] ; then
    echo "The workspace name cannot contain spaces."
    echo "Please pick a name without spaces and run again."
    exit
fi

# Override soft-mandatory policy checks that fail.
# Set to "yes" or "no" in second argument passed to script.
# If not specified, then this is set to "no"
# If not cloning a git repository, set first argument to ""
#if [ ! -z $3 ]; then
#  override=$3
#  echo "override set to ${override} on command line."
#else
#  override="no"
#  echo "override not set on command line. Will not override."
#fi
override="no"

# Check to see if the workspace already exists
echo "Checking to see if workspace exists"
check_workspace_result=$(curl -s --header "Authorization: Bearer $TFE_TOKEN" --header "Content-Type: application/vnd.api+json" "https://${address}/api/v2/organizations/${organization}/workspaces/${workspace}")

# Parse workspace_id from check_workspace_result
workspace_id=$(echo $check_workspace_result | python -c "import sys, json; print(json.load(sys.stdin)['data']['id'])")
echo "Workspace ID: " $workspace_id

# Create workspace if it does not already exist
if [ -z "$workspace_id" ]; then
  echo "Workspace did not already exist; will create it."
  workspace_result=$(curl -s --header "Authorization: Bearer $TFE_TOKEN" --header "Content-Type: application/vnd.api+json" --request POST --data @workspace.json "https://${address}/api/v2/organizations/${organization}/workspaces")

  # Parse workspace_id from workspace_result
  workspace_id=$(echo $workspace_result | python -c "import sys, json; print(json.load(sys.stdin)['data']['id'])")
  echo "Workspace ID: " $workspace_id
else
  echo "Workspace already existed."
fi

buildkite-agent meta-data set "workspaceid" $workspace_id

echo "Here is the get"
workspace_id=$(buildkite-agent meta-data get "workspaceid")


# Write out run.template.json
cat > run.template.json <<EOF
{
  "data": {
    "attributes": {
      "is-destroy":false
    },
    "type":"runs",
    "relationships": {
      "workspace": {
        "data": {
          "type": "workspaces",
          "id": "workspace_id"
        }
      }
    }
  }
}
EOF

# Write out apply.json
cat > apply.json <<EOF
{"comment": "apply via API"}
EOF



# Function to process special characters in sed
escape_string()
{
  printf '%s' "$1" | sed -e 's/\([&\]\)/\\\1/g'
}

sedDelim=$(printf '\001')

# Do a run
sed "s/workspace_id/$workspace_id/" < run.template.json  > run.json
run_result=$(curl -s --header "Authorization: Bearer $TFE_TOKEN" --header "Content-Type: application/vnd.api+json" --data @run.json https://${address}/api/v2/runs)

# Parse run_result
run_id=$(echo $run_result | python -c "import sys, json; print(json.load(sys.stdin)['data']['id'])")
echo "Run ID: " $run_id

buildkite-agent meta-data set "runid" $run_id

run_id=$(buildkite-agent meta-data get "runid")

#echo "Doing Apply"
#apply_result=$(curl -s --header "Authorization: Bearer $TFE_TOKEN" --header "Content-Type: application/vnd.api+json" --data @apply.json https://${address}/api/v2/runs/${run_id}/actions/apply)
applied="true"




# Get the apply log and state files (before and after) if an apply was done
if [[ "$applied" == "true" ]]; then

  echo "An apply was done."
  echo "Will download apply log and state file."

  # Get run details including apply information
  check_result=$(curl -s --header "Authorization: Bearer $TFE_TOKEN" --header "Content-Type: application/vnd.api+json" https://${address}/api/v2/runs/${run_id}?include=apply)

  # Get apply ID
  apply_id=$(echo $check_result | python -c "import sys, json; print(json.load(sys.stdin)['included'][0]['id'])")
  echo "Apply ID:" $apply_id

  # Check apply status periodically in loop
  continue=1
  while [ $continue -ne 0 ]; do

    sleep $sleep_duration
    echo "Checking apply status"

    # Check run status
    run_result=$(curl -s --header "Authorization: Bearer $TFE_TOKEN" --header "Content-Type: application/vnd.api+json" https://${address}/api/v2/runs/${run_id}?include=apply)
    run_status=$(echo $run_result | python -c "import sys, json; print(json.load(sys.stdin['data']['status']))")
    echo "Run Status: ${run_status}"
    # Check the apply status
    check_result=$(curl -s --header "Authorization: Bearer $TFE_TOKEN" --header "Content-Type: application/vnd.api+json" https://${address}/api/v2/applies/${apply_id})

    # Parse out the apply status
    apply_status=$(echo $check_result | python -c "import sys, json; print(json.load(sys.stdin)['data']['attributes']['status'])")
    echo "Apply Status: ${apply_status}"

    # Decide whether to continue
    if [[ "$apply_status" == "finished" ]]; then
      echo "Apply finished."
      continue=0
    elif [["$run_status" == "planned_and_finished"]]; then
      echo "Nothing to change."
      continue=0
    else
      # Sleep and then check apply status again in next loop
      echo "We will sleep and try again soon."
    fi
  done

  # Get apply log URL
  apply_log_url=$(echo $check_result | python -c "import sys, json; print(json.load(sys.stdin)['data']['attributes']['log-read-url'])")
  echo "Apply Log URL:"
  echo "${apply_log_url}"

  # Retrieve Apply Log from the URL
  # and output to shell and file
  curl -s $apply_log_url | tee ${apply_id}.log

  # Get state version IDs from after the apply
  state_id_before=$(echo $check_result | python -c "import sys, json; print(json.load(sys.stdin)['data']['relationships']['state-versions']['data'][1]['id'])")
  echo "State ID 1:" ${state_id_before}

  # Call API to get information about the state version including its URL
  state_file_before_url_result=$(curl -s --header "Authorization: Bearer $TFE_TOKEN" https://${address}/api/v2/state-versions/${state_id_before})

  # Get state file URL from the result
  state_file_before_url=$(echo $state_file_before_url_result | python -c "import sys, json; print(json.load(sys.stdin)['data']['attributes']['hosted-state-download-url'])")
  echo "URL for state file before apply:"
  echo ${state_file_before_url}

  # Retrieve state file from the URL
  # and output to shell and file
  echo "State file before the apply:"
  curl -s $state_file_before_url | tee ${apply_id}-before.tfstate

  # Get state version IDs from before the apply
  state_id_after=$(echo $check_result | python -c "import sys, json; print(json.load(sys.stdin)['data']['relationships']['state-versions']['data'][0]['id'])")
  echo "State ID 0:" ${state_id_after}

  # Call API to get information about the state version including its URL
  state_file_after_url_result=$(curl -s --header "Authorization: Bearer $TFE_TOKEN" https://${address}/api/v2/state-versions/${state_id_after})

  # Get state file URL from the result
  state_file_after_url=$(echo $state_file_after_url_result | python -c "import sys, json; print(json.load(sys.stdin)['data']['attributes']['hosted-state-download-url'])")
  echo "URL for state file after apply:"
  echo ${state_file_after_url}

  # Retrieve state file from the URL
  # and output to shell and file
  echo "State file after the apply:"
  curl -s $state_file_after_url | tee ${apply_id}-after.tfstate

fi

# Remove json files
rm apply.json
rm configversion.json
rm run.template.json
rm run.json


echo "Finished"