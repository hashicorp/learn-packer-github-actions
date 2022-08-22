#! /usr/bin/env bash

set -eEuo pipefail

usage() {
  cat <<EOF
This script is a helper for setting a channel iteration in HCP Packer
Usage:
   $(basename "$0") <bucket_slug> <channel_name> <iteration_id>
---
Requires the following environment variables to be set:
 - HCP_CLIENT_ID
 - HCP_CLIENT_SECRET
 - HCP_ORGANIZATION_ID
 - HCP_PROJECT_ID
EOF
  exit 1
}

# Entry point
test "$#" -eq 3 || usage

bucket_slug="$1"
channel_name="$2"
iteration_id="$3"
base_url="https://api.cloud.hashicorp.com/packer/2021-04-30/organizations/$HCP_ORGANIZATION_ID/projects/$HCP_PROJECT_ID"

# If on main branch, set channel to release
if [ "$channel_name" == "main" ]; then
  channel_name="release"
fi


# Authenticate
response=$(curl --request POST --silent \
  --url 'https://auth.hashicorp.com/oauth/token' \
  --data grant_type=client_credentials \
  --data client_id="$HCP_CLIENT_ID" \
  --data client_secret="$HCP_CLIENT_SECRET" \
  --data audience="https://api.hashicorp.cloud")
api_error=$(echo "$response" | jq -r '.error')
if [ "$api_error" != null ]; then
  echo "Failed to get access token: $api_error"
  exit 1
fi
bearer=$(echo "$response" | jq -r '.access_token')

# Get channel info, create if doesn't exist
api_error=$(curl --request GET --silent \
  --url "$base_url/images/$bucket_slug/channels/$channel_name" \
  --header  "authorization: Bearer $bearer" | jq -r '.error')
if [ "$api_error" != null ]; then
  # Channel likely doesn't exist, create it
  api_error=$(curl --request POST --silent \
    --url "$base_url/images/$bucket_slug/channels" \
    --data-raw '{"slug":"'"$channel_name"'"}' \
    --header "authorization: Bearer $bearer" | jq -r '.error')
  if [ "$api_error" != null ]; then
    echo "Error creating channel: $api_error"
    exit 1
  fi
fi

# Update channel to point to iteration
api_error=$(curl --request PATCH --silent \
  --url "$base_url/images/$bucket_slug/channels/$channel_name" \
  --data-raw '{"iteration_id":"'"$iteration_id"'"}' \
  --header "authorization: Bearer $bearer" | jq -r '.error')
if [ "$api_error" != null ]; then
    echo "Error updating channel: $api_error"
    exit 1
fi
