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

# Write out workspace.template.json
cat > workspace.template.json <<EOF
{
  "data":
  {
    "attributes": {
      "name":"placeholder",
      "terraform-version": "0.11.14"
    },
    "type":"workspaces"
  }
}
EOF

#Set name of workspace in workspace.json
sed "s/placeholder/${workspace}/" < workspace.template.json > workspace.json

# Check to see if the workspace already exists
echo "Checking to see if workspace exists"
check_workspace_result=$(curl -s --header "Authorization: Bearer $TFE_TOKEN" --header "Content-Type: application/vnd.api+json" "https://${address}/api/v2/organizations/${organization}/workspaces/${workspace}")

# Parse workspace_id from check_workspace_result
#workspace_id=$(echo $check_workspace_result | python -c "import sys, json; print(json.load(sys.stdin)['data']['id'])")
workspace_id=$(echo $check_workspace_result | jq -r .data.id)
echo "Workspace ID: " $workspace_id

# Create workspace if it does not already exist
if [ -z "$workspace_id" ]; then
  echo "Workspace did not already exist; will create it."
  workspace_result=$(curl -s --header "Authorization: Bearer ${TFE_TOKEN}" --header "Content-Type: application/vnd.api+json" --request POST --data @workspace.json "https://${address}/api/v2/organizations/${organization}/workspaces")

  # Parse workspace_id from workspace_result
  #workspace_id=$(echo $workspace_result | python -c "import sys, json; print(json.load(sys.stdin)['data']['id'])")
  workspace_id=$(echo $check_workspace_result | jq -r .data.id)
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
#escape_string()
#{
#  printf '%s' "$1" | sed -e 's/\([&\]\)/\\\1/g'
#}

#sedDelim=$(printf '\001')

# Do a run
sed "s/workspace_id/${workspace_id}/" < run.template.json  > run.json
run_result=$(curl -s --header "Authorization: Bearer $TFE_TOKEN" --header "Content-Type: application/vnd.api+json" --data @run.json https://${address}/api/v2/runs)

# Parse run_result
#run_id=$(echo $run_result | python -c "import sys, json; print(json.load(sys.stdin)['data']['id'])")
run_id=$(echo $run_result | jq -r .data.id)

echo "Run ID: " $run_id

#buildkite-agent meta-data set "runid" $run_id

#run_id=$(buildkite-agent meta-data get $run_id)
run_id =$run_id

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
  #apply_id=$(echo $check_result | python -c "import sys, json; print(json.load(sys.stdin)['included'][0]['id'])")
  apply_id=$(echo $check_result | jq -r .included.0.id)
  echo "Apply ID:" $apply_id

  # Check apply status periodically in loop
  continue=1
  while [ $continue -ne 0 ]; do

    sleep $sleep_duration
    echo "Checking apply status"

    # Check run status
    run_result=$(curl -s --header "Authorization: Bearer $TFE_TOKEN" --header "Content-Type: application/vnd.api+json" https://${address}/api/v2/runs/${run_id}?include=apply)
    #run_status=$(echo $run_result | python -c "import sys, json; print(json.load(sys.stdin)['data']['attributes']['status'])")
    run_status=$(echo $run_result | jq -r .data.attributes.status)
    echo "Run Status: ${run_status}"
    # Check the apply status
    check_result=$(curl -s --header "Authorization: Bearer $TFE_TOKEN" --header "Content-Type: application/vnd.api+json" https://${address}/api/v2/applies/${apply_id})

    # Parse out the apply status
    #apply_status=$(echo $check_result | python -c "import sys, json; print(json.load(sys.stdin)['data']['attributes']['status'])")
    apply_status=$(echo $check_result | jq -r .data.attributes.status)
    echo "Apply Status: ${apply_status}"

    # Decide whether to continue
    if [[ "$apply_status" == "finished" ]]; then
      echo "Apply finished."
      continue=0
    elif [[ "$run_status" == "planned_and_finished" ]]; then
      echo "Nothing to change."
      continue=0
    else
      # Sleep and then check apply status again in next loop
      echo "We will sleep and try again soon."
    fi
  done

  # Get apply log URL
  #apply_log_url=$(echo $check_result | python -c "import sys, json; print(json.load(sys.stdin)['data']['attributes']['log-read-url'])")
  apply_log_url=$(echo $check_result | jq -r .data.attributes.log-read-url)
  echo "Apply Log URL:"
  echo "${apply_log_url}"


fi

# Remove json files
rm apply.json
rm run.template.json
rm run.json


echo "Finished"
