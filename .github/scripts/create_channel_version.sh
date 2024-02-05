#! /usr/bin/env bash
# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0


set -eEuo pipefail

usage() {
  cat <<EOF
This script is a helper for setting a channel version in HCP Packer
Usage:
   $(basename "$0") <bucket_slug> <channel_name> <version_fingerprint>
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
version_fingerprint="$3"
auth_url="${HCP_AUTH_URL:-https://auth.hashicorp.com}"
api_host="${HCP_API_HOST:-https://api.cloud.hashicorp.com}"
base_url="$api_host/packer/2023-01-01/organizations/$HCP_ORGANIZATION_ID/projects/$HCP_PROJECT_ID"

# If on main branch, set channel to release
if [ "$channel_name" == "main" ]; then
  channel_name="release"
fi

echo "Attempting to assign version ${version_fingerprint} in bucket ${bucket_slug} to channel ${channel_name}"

# Authenticate
response=$(curl --request POST --silent \
  --url "$auth_url/oauth/token" \
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

# Get or create channel
echo "Getting channel ${channel_name}"
response=$(curl --request GET --silent \
  --url "$base_url/buckets/$bucket_slug/channels/$channel_name" \
  --header "authorization: Bearer $bearer")
api_error=$(echo "$response" | jq -r '.message')
if [ "$api_error" != null ]; then
  echo "Channel ${channel_name} like doesn't exist, creating new channel"
  # Channel likely doesn't exist, create it
  api_error=$(curl --request POST --silent \
    --url "$base_url/buckets/$bucket_slug/channels" \
    --data-raw '{"name":"'"$channel_name"'"}' \
    --header "authorization: Bearer $bearer" | jq -r '.error')
  if [ "$api_error" != null ]; then
    echo "Error creating channel: $api_error"
    exit 1
  fi
fi

# Update channel to point to version
echo "Updating channel ${channel_name} to version fingerprint ${version_fingerprint}"
api_error=$(curl --request PATCH --silent \
  --url "$base_url/buckets/$bucket_slug/channels/$channel_name" \
  --data-raw '{"version_fingerprint": "'$version_fingerprint'", "update_mask": "versionFingerprint"}' \
  --header "authorization: Bearer $bearer" | jq -r '.message')
if [ "$api_error" != null ]; then
    echo "Error updating channel: $api_error"
    exit 1
fi
