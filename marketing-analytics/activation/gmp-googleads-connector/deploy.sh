#!/bin/bash
#
# Copyright 2019 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BASE_DIR}/../common-libs/install-script-library/install_functions.sh"

# Default project name is 'tentacles'. It will be used as prefix of Cloud
# Functions, Pub/Sub, etc. You can change it here (only lowercase letters,
# numbers and hyphens (-) are suggested).
PROJECT_NAME="${PROJECT_NAME:=tentacles}"

# Project configuration file.
CONFIG_FILE="./config.json"

# Parameter name used by functions to load and save config.
CONFIG_FOLDER_NAME="OUTBOUND"
CONFIG_ITEMS=("GCS_BUCKET" "${CONFIG_FOLDER_NAME}" "PS_TOPIC")

# Service account key file.
SA_KEY_FILE="./keys/service-account.key.json"

# Default service account user name.
DEFAULT_SERVICE_ACCOUNT="${PROJECT_NAME}-api"

# Whether service account is required for this installation based on the
# selected APIs.
NEED_SERVICE_ACCOUNT="false"

# Creation of topics and subscriptions.
ENABLED_INTEGRATED_APIS=()

# APIs to be enabled.
declare -A GOOGLE_CLOUD_APIS
GOOGLE_CLOUD_APIS=(
  ["iam.googleapis.com"]="Cloud Identity and Access Management API"
  ["cloudresourcemanager.googleapis.com"]="Resource Manager API"
  ["firestore.googleapis.com"]="Cloud Firestore API"
  ["cloudfunctions.googleapis.com"]="Cloud Functions API"
  ["pubsub.googleapis.com"]="Cloud Pub/Sub API"
)

# Description of external APIs.
INTEGRATION_APIS_DESCRIPTION=(
  "Google Analytics Measurement Protocol"
  "Google Analytics Data Import"
  "Campaign Manager Conversions Upload"
  "SFTP Upload"
  "Google Sheets API for Google Ads conversions scheduled uploads based on \
Google Sheets"
  "Search Ads 360 Conversions Upload"
)

# All build-in external APIs.
INTEGRATION_APIS=(
  "N/A"
  "analytics"
  "dfareporting doubleclicksearch"
  "N/A"
  "sheets.googleapis.com"
  "doubleclicksearch"
)

# Code of external APIs. Used to create different Pub/Sub topics and
# subscriptions for different APIs.
INTEGRATION_APIS_CODE=(
  "MP"
  "GA"
  "CM"
  "SFTP"
  "GS"
  "SA"
)

# Common permissions to install Tentacles.
# https://cloud.google.com/service-usage/docs/access-control
# https://cloud.google.com/storage/docs/access-control/iam-roles
# https://cloud.google.com/pubsub/docs/access-control
# https://cloud.google.com/iam/docs/understanding-roles#service-accounts-roles
# https://cloud.google.com/functions/docs/reference/iam/roles
# https://cloud.google.com/firestore/docs/security/iam#roles
declare -A GOOGLE_CLOUD_PERMISSIONS
GOOGLE_CLOUD_PERMISSIONS=(
  ["Service Management Administrator"]="servicemanagement.services.bind"
  ["Service Usage Admin"]="serviceusage.services.enable"
  ["Storage Admin"]="storage.buckets.create storage.buckets.list"
  ["Pub/Sub Editor"]="pubsub.subscriptions.create pubsub.topics.create"
  ["Service Account User"]="iam.serviceAccounts.actAs"
  ["Cloud Functions Developer"]="cloudfunctions.functions.create"
  ["Cloud Datastore User"]="appengine.applications.get \
    datastore.databases.get \
    datastore.entities.create \
    resourcemanager.projects.get"
)

# https://cloud.google.com/iam/docs/understanding-roles#service-accounts-roles
declare -A GOOGLE_SERVICE_ACCOUNT_PERMISSIONS
GOOGLE_SERVICE_ACCOUNT_PERMISSIONS=(
  ["Service Account Admin"]="iam.serviceAccounts.create"
  ["Service Account Key Admin"]="iam.serviceAccounts.create"
)

print_welcome() {
  cat <<EOF
###########################################################
##                                                       ##
##            Start installation of Tentacles            ##
##                                                       ##
###########################################################

EOF
}

#######################################
# Confirm the APIs that this instance supports. Based on the APIs selected, you
# might need to do the following: 1) Enable new APIs in your Google Cloud
# project; 2) use a service account key file. If the second case, the
# permissions array will be updated to be checked.
# Globals:
#   INTEGRATION_APIS_DESCRIPTION
#   INTEGRATION_APIS
#   INTEGRATION_APIS_CODE
#   ENABLED_INTEGRATED_APIS
#   NEED_SERVICE_ACCOUNT
#   GOOGLE_CLOUD_APIS
#   GOOGLE_CLOUD_PERMISSIONS
#   GOOGLE_SERVICE_ACCOUNT_PERMISSIONS
# Arguments:
#   None
#######################################
confirm_apis() {
  (( STEP += 1 ))
  printf '%s\n' "Step ${STEP}: Select the APIs that will be integrated: "
  local api
  for api in "${!INTEGRATION_APIS_DESCRIPTION[@]}"; do
    printf "%s) %s\n" "${api}" "${INTEGRATION_APIS_DESCRIPTION[$api]}"
  done
  printf '%s' "Use a comma to separate APIs or enter * for all: [*]"
  local input=()
  IFS=', ' read -r -a input

  if [[ ${#input[@]} = 0 || ${input[0]} = '*' ]]; then
    for ((i=0; i<${#INTEGRATION_APIS_DESCRIPTION[@]}; i+=1)); do
      input["${i}"]="${i}"
    done
  fi
  local selection
  for selection in "${!input[@]}"; do
    local index="${input[$selection]}"
    ENABLED_INTEGRATED_APIS+=("${INTEGRATION_APIS_CODE["${index}"]}")
    if [[ ${INTEGRATION_APIS[${index}]} != "N/A" ]]; then
      NEED_SERVICE_ACCOUNT="true"
      GOOGLE_CLOUD_APIS[${INTEGRATION_APIS["${index}"]}]=\
"${INTEGRATION_APIS_DESCRIPTION["${index}"]}"
      printf '%s\n' "  Add ${INTEGRATION_APIS_DESCRIPTION["${index}"]} to \
enable API list."
    fi
  done
  if [[ ${NEED_SERVICE_ACCOUNT} = 'true' ]]; then
    local role
    for role in "${!GOOGLE_SERVICE_ACCOUNT_PERMISSIONS[@]}"; do
      GOOGLE_CLOUD_PERMISSIONS["${role}"]=\
"${GOOGLE_SERVICE_ACCOUNT_PERMISSIONS["${role}"]}"
    done
  fi
}

#######################################
# Create Pub/Sub topics and subscriptions based on the selected APIs.
# Globals:
#   PS_TOPIC
#   ENABLED_INTEGRATED_APIS
# Arguments:
#   None
# Returns:
#   0 if all topics and subscriptions are created, non-zero on error.
#######################################
create_subscriptions() {
  (( STEP += 1 ))
  cat <<EOF
Step ${STEP}: Creating topics and subscriptions for Pub/Sub...
  Pub/Sub subscribers will not receive messages until subscriptions are created.
EOF

  node -e "require('./index.js').initPubsub(process.argv[1], \
process.argv.slice(2))" "${PS_TOPIC}"  "${ENABLED_INTEGRATED_APIS[@]}"
  if [[ $? -gt 0 ]]; then
    echo "Failed to create Pub/Sub topics or subscriptions."
    return 1
  else
    echo "OK. Successfully created Pub/Sub topics and subscriptions."
    return 0
  fi
}

#######################################
# Download a service account key file and save as `$SA_KEY_FILE`.
# Globals:
#   SA_NAME
#   GCP_PROJECT
#   SA_KEY_FILE
# Arguments:
#   None
# Returns:
#   0 if service key files exists or created, non-zero on error.
#######################################
download_service_account_key() {
  (( STEP += 1 ))
  printf '%s\n' "Step ${STEP}: Downloading the key file for the service \
account..."
  if [[ -z ${SA_NAME} ]];then
    confirm_service_account
  fi
  local suffix exist
  suffix=$(get_sa_domain_from_gcp_id "${GCP_PROJECT}")
  local email="${SA_NAME}@${suffix}"
  local prompt="Would you like to download the key file for [${email}] and \
save it as ${SA_KEY_FILE}? [Y/n]: "
  local default_value="y"
  if [[ -f "${SA_KEY_FILE}" && -s "${SA_KEY_FILE}" ]]; then
    exist=$(get_value_from_json_file ${SA_KEY_FILE} 'client_email' 2>&1)
    if [[ ${exist} =~ .*("@${suffix}") ]]; then
      prompt="A key file for [${exist}] with the key ID '\
$(get_value_from_json_file ${SA_KEY_FILE} 'private_key_id') already exists'. \
Would you like to create a new key to overwrite it? [N/y]: "
      default_value="n"
    fi
  fi
  printf '%s' "${prompt}"
  local input
  read -r input
  input=${input:-"${default_value}"}
  if [[ ${input} = 'y' || ${input} = 'Y' ]];then
    printf '%s\n' "Downloading a new key file for [${email}]..."
    gcloud iam service-accounts keys create "${SA_KEY_FILE}" --iam-account \
"${email}"
    if [[ $? -gt 0 ]]; then
      printf '%s\n' "Failed to download new key files for [${email}]."
      return 1
    else
      printf '%s\n' "OK. New key file is saved at [${SA_KEY_FILE}]."
      return 0
    fi
  else
    printf '%s\n' "Skipped downloading new key file. See \
https://cloud.google.com/iam/docs/creating-managing-service-account-keys \
to learn more about service account key files."
    return 0
  fi
}

#######################################
# Make sure a service account for this integration exists and set the email of
# the service account to the global variable `SA_NAME`.
# Globals:
#   GCP_PROJECT
#   SA_KEY_FILE
#   SA_NAME
#   DEFAULT_SERVICE_ACCOUNT
# Arguments:
#   None
#######################################
confirm_service_account() {
  cat <<EOF
  Some external APIs might require authentication based on OAuth or \
JWT(service account), for example, Google Analytics Data Import or Campaign \
Manager. In this step, you prepare the service account. See \
https://cloud.google.com/iam/docs/creating-managing-service-accounts for more \
information.
EOF

  local suffix
  suffix=$(get_sa_domain_from_gcp_id "${GCP_PROJECT}")
  local email
  if [[ -f "${SA_KEY_FILE}" && -s "${SA_KEY_FILE}" ]]; then
    email=$(get_value_from_json_file "${SA_KEY_FILE}" 'client_email')
    if [[ ${email} =~ .*("@${suffix}") ]]; then
      printf '%s' "A key file for service account [${email}] already exists. \
Would you like to create a new service account? [N/y]: "
      local input
      read -r input
      if [[ ${input} != 'y' && ${input} != 'Y' ]]; then
        printf '%s\n' "OK. Will use existing service account [${email}]."
        SA_NAME=$(printf "${email}" | cut -d@ -f1)
        return 0
      fi
    fi
  fi

  SA_NAME="${SA_NAME:-"${DEFAULT_SERVICE_ACCOUNT}"}"
  while :; do
    printf '%s' "Enter the name of service account [${SA_NAME}]: "
    local input sa_elements=() sa
    read -r input
    input=${input:-"${SA_NAME}"}
    IFS='@' read -a sa_elements <<< "${input}"
    if [[ ${#sa_elements[@]} = 1 ]]; then
      echo "  Append default suffix to service account name and get: ${email}"
      sa="${input}"
      email="${sa}@${suffix}"
    else
      if [[ ${sa_elements[1]} != "${suffix}" ]]; then
        printf '%s\n' "  Error: Service account domain name ${sa_elements[1]} \
doesn't belong to the current project. The service account domain name for the \
current project should be: ${suffix}."
        continue
      fi
      sa="${sa_elements[0]}"
      email="${input}"
    fi

    printf '%s\n' "Checking the existence of the service account [${email}]..."
    if ! result=$(gcloud iam service-accounts describe "${email}" 2>&1); then
      printf '%s\n' "  Service account [${email}] does not exist. Trying to \
create..."
      gcloud iam service-accounts create "${sa}" --display-name \
"Tentacles API requester"
      if [[ $? -gt 0 ]]; then
        printf '%s\n' 'Creating the service account [${email}] failed. Please \
try again...'
      else
        printf '%s\n' 'The service account [${email}] was successfully created.'
        SA_NAME=${sa}
        break
      fi
    else
      printf ' found.\n'
      SA_NAME=${sa}
      break
    fi
  done
  printf '%s\n' "OK. Service account [${SA_NAME}] is ready."
}

#######################################
# Deploy three Cloud Functions for Tentacles.
# Globals:
#   REGION
#   CF_RUNTIME
#   PROJECT_NAME
#   GCS_BUCKET
#   CONFIG_FOLDER_NAME
#   PS_TOPIC
#   SA_KEY_FILE
# Arguments:
#   None
# Returns:
#   0 if all Cloud Functions deployed, non-zero on error.
#######################################
deploy_tentacles() {
  (( STEP += 1 ))
  printf '%s\n' "Step ${STEP}: Starting to deploy Tentacles..."
  printf '%s\n' "Tentacles is composed of three Cloud Functions."
  while [[ -z ${REGION} ]]; do
    set_region
  done
  printf '%s\n' "OK. Cloud Functions will be deployed to ${REGION}."

  local cf_flag=()
  cf_flag+=(--region="${REGION}")
  cf_flag+=(--timeout=540 --memory=2048MB --runtime="${CF_RUNTIME}")
  cf_flag+=(--set-env-vars=TENTACLES_TOPIC_PREFIX="${PS_TOPIC}")

  printf '%s\n' " 1. '${PROJECT_NAME}_init' is triggered by new files from \
Cloud Storage bucket [${GCS_BUCKET}]."
  gcloud functions deploy "${PROJECT_NAME}"_init --entry-point initiate \
--trigger-bucket "${GCS_BUCKET}" "${cf_flag[@]}" \
--set-env-vars=TENTACLES_OUTBOUND="${!CONFIG_FOLDER_NAME}"
  quit_if_failed $?

  printf '%s\n' " 2. '${PROJECT_NAME}_tran' is triggered by new messages from \
Pub/Sub topic [${PS_TOPIC}-trigger]."
  gcloud functions deploy "${PROJECT_NAME}"_tran --entry-point transport \
--trigger-topic "${PS_TOPIC}"-trigger "${cf_flag[@]}"
  quit_if_failed $?

  if [[ -f "${SA_KEY_FILE}" ]]; then
    cf_flag+=(--set-env-vars=API_SERVICE_ACCOUNT="${SA_KEY_FILE}")
  fi
  printf '%s\n' " 3. '${PROJECT_NAME}_api' is triggered by new messages from \
Pub/Sub topic [${PS_TOPIC}-push]."
  gcloud functions deploy "${PROJECT_NAME}"_api --entry-point requestApi \
--trigger-topic "${PS_TOPIC}"-push "${cf_flag[@]}"
  quit_if_failed $?

  printf '%s\n' " 3. '${PROJECT_NAME}_api_python' is triggered by new messages from \
Pub/Sub topic [${PS_TOPIC}-push]."
  gcloud functions deploy "${PROJECT_NAME}"_api_python --entry-point request_api \
--trigger-topic "${PS_TOPIC}"-push "${cf_flag[@]}"
  quit_if_failed $?
}

#######################################
# Check Firestore status and print next steps information after installation.
# Globals:
#   NEED_SERVICE_ACCOUNT
#   SA_KEY_FILE
#   PROJECT_NAME
#   GCS_BUCKET
#   CONFIG_FOLDER_NAME
#   PS_TOPIC
#   SA_KEY_FILE
# Arguments:
#   None
#######################################
post_installation() {
  (( STEP += 1 ))
  printf '%s\n' "Step ${STEP}: Post-installation checks..."
  check_firestore_existence
  printf '%s\n' "OK. Firestore/Datastore is ready."
  if [[ ${NEED_SERVICE_ACCOUNT} = 'true' ]]; then
    local exist
    exist=$(get_value_from_json_file "${SA_KEY_FILE}" 'client_email')
    cat <<EOF
Some enabled APIs require a service account. Extra steps are required to grant \
access to the service account's email in external systems, for example, Google \
Analytics or Campaign Manager.
You need to grant access to the service account's email before Tentacles can \
send out data to the target APIs.

  1. Google Analytics Data Import:
   * Set up dataset for Data Import, see: \
https://support.google.com/analytics/answer/3191417?hl=en
   * Grant the 'Edit' access to [${exist}]
  2. Campaign Manager:
   * DCM/DFA Reporting and Trafficking API's Conversions service, see: \
https://developers.google.com/doubleclick-advertisers/guides/conversions_overview
   * Create User Profile for [${exist}] and grant the access to 'Insert \
offline conversions'
  3. Google Sheets API for Google Ads conversions scheduled uploads based on \
Google Sheets:
   * Import conversions from ad clicks into Google Ads, see: \
https://support.google.com/google-ads/answer/7014069
   * Add [${exist}] as an Editor of the Google Spreadsheet that Google Ads \
will take conversions from.
EOF
  fi
  cat <<EOF

Follow the document \
https://github.com/GoogleCloudPlatform/cloud-for-marketing/blob/master/marketing-analytics/activation/gmp-googleads-connector/README.md#4-api-details\
 to create a configuration of the integration.
Save the configuration to a JSON file, for example, './config_api.json', and \
then run the following command:
  ./deploy.sh update_api_config
This command updates the configuration of Firestore/Datastore before Tentacles \
can use them.
EOF
}

print_finished(){
  cat <<EOF
###########################################################
##          Tentacles has been installed.                ##
###########################################################
EOF
}

#######################################
# Start the automatic process to install Tentacles.
# Globals:
#   NEED_SERVICE_ACCOUNT
# Arguments:
#   None
#######################################
install_tentacles() {

  print_welcome
  load_config

  local tasks=(
    check_in_cloud_shell prepare_dependencies
    confirm_project confirm_region confirm_apis
    check_permissions enable_apis create_bucket
    confirm_folder confirm_topic save_config
    create_subscriptions
  )
  local task
  for task in "${tasks[@]}"; do
    "${task}"
    quit_if_failed $?
  done
  # Confirmed during the tasks.
  if [[ ${NEED_SERVICE_ACCOUNT} = 'true' ]]; then
    download_service_account_key
    quit_if_failed $?
  fi

  deploy_tentacles
  post_installation
  print_finished
}

#######################################
# Print the email address of the service account.
# Globals:
#   SA_KEY_FILE
# Arguments:
#   None
#######################################
print_service_account(){
  printf '%s\n' "=========================="
  local email
  email=$(get_value_from_json_file "${SA_KEY_FILE}" 'client_email')
  printf '%s\n' "The email address of the current service account is ${email}."
}

#######################################
# Upload API configuration in local JSON file to Firestore or Datastore.
# The uploading process adapts to Firestore or Datastore automatically.
# Globals:
#   None
# Arguments:
#   None
#######################################
update_api_config(){
  printf '%s\n' "=========================="
  printf '%s\n' "Update API configurations in Firestore/Datastore."
  check_authentication
  quit_if_failed $?
  check_firestore_existence

  local default_config_file='./config_api.json'
  printf '%s' "Enter the configuration file [${default_config_file}]: "
  local api_config
  read -r api_config
  api_config=${api_config:-"${default_config_file}"}
  printf '\n'
  node -e "require('./index.js').uploadApiConfig(require(process.argv[1]))" \
"${api_config}"
}

#######################################
# Invoke the Cloud Function 'API requester' directly based on a local file.
# Note: The API configuration is still expected to be on Google Cloud. You need
# to update the API configuration first if you made any modifications.
# Globals:
#   SA_KEY_FILE
# Arguments:
#   File to be sent out, a path.
#######################################
run_test_locally(){
  printf '%s\n' "=========================="
  cat <<EOF
Invoke the Cloud Function 'API requester' directly based on a local file.
Note: The API configuration is still expected to be on Google Cloud. You need \
to update the API configuration first if you made any modifications.
EOF
  if [[ -f "${SA_KEY_FILE}" ]]; then
    API_SERVICE_ACCOUNT="$(pwd)/${SA_KEY_FILE}"
    printf '%s\n' "Use environment variable \
API_SERVICE_ACCOUNT=${API_SERVICE_ACCOUNT}"
  fi
  DEBUG=true CODE_LOCATION='' API_SERVICE_ACCOUNT="${API_SERVICE_ACCOUNT}" \
node -e "require('./index.js').localApiRequester(process.argv[1])" "$@"
}

#######################################
# Start process by copying a file to target folder.
# Note: The API configuration is still expected to be on Google Cloud. You need
# to update the API configuration first if you made any modifications.
# Globals:
#   CONFIG_FILE
#   CONFIG_FOLDER_NAME
# Arguments:
#   File to be sent out, a path.
#######################################
copy_file_to_gcs(){
  printf '%s\n' "=========================="
  local bucket
  bucket=$(get_value_from_json_file "${CONFIG_FILE}" "GCS_BUCKET")
  local folder
  folder=$(get_value_from_json_file "${CONFIG_FILE}" "${CONFIG_FOLDER_NAME}")
  local target="gs://${bucket}/${folder}"
  echo "Copy local file to target folder in Cloud Storage to start process."
  printf '%s\n' "  Source: $1"
  printf '%s\n' "  Target: ${target}"
  printf '%s' "Confirm? [Y/n]: "
  local input
  read -n1 -s input
  printf '%s\n' "${input}"
  if [[ -z ${input} || ${input} = 'y' || ${input} = 'Y' ]];then
    # gsutil support wildcard name. Use '*' to replace '[' here.
    local source
    source="$(printf '%s' "$1" | sed -r 's/\[/\*/g' )"
    gsutil cp ''"${source}"'' "${target}"
  else
    printf '%s\n' "User cancelled."
  fi
}

if [[ "${BASH_SOURCE[0]}" -ef "$0" ]]; then
  MAIN_FUNCTION="install_tentacles"
  run_default_function "$@"
else
  printf '%s\n' "Tentacles Bash Library is loaded."
fi
