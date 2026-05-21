#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage:"
  echo "  $0 download <secret_name> <region> <output_file>"
  echo "  $0 upload <secret_name> <region> <input_file>"
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

COMMAND="$1"

download_secret() {
  local SECRET_NAME="$1"
  local REGION="$2"
  local OUTPUT_FILE="$3"

  echo "Downloading secret: $SECRET_NAME from $REGION"

  aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --region "$REGION" \
    --query SecretString \
    --output text > "$OUTPUT_FILE"

  echo "Saved to $OUTPUT_FILE"
}

upload_secret() {
  local SECRET_NAME="$1"
  local REGION="$2"
  local INPUT_FILE="$3"

  if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: File not found: $INPUT_FILE"
    exit 1
  fi

  echo "Uploading secret to: $SECRET_NAME in $REGION"

  SECRET_VALUE=$(cat "$INPUT_FILE")

  # Try to create; if it exists, update instead
  if aws secretsmanager describe-secret \
      --secret-id "$SECRET_NAME" \
      --region "$REGION" > /dev/null 2>&1; then

    echo "Secret exists. Updating..."
    aws secretsmanager put-secret-value \
      --secret-id "$SECRET_NAME" \
      --secret-string "$SECRET_VALUE" \
      --region "$REGION"
  else
    echo "Creating new secret..."
    aws secretsmanager create-secret \
      --name "$SECRET_NAME" \
      --secret-string "$SECRET_VALUE" \
      --region "$REGION"
  fi

  echo "Upload complete."
}

case "$COMMAND" in
  download)
    [[ $# -ne 4 ]] && usage
    download_secret "$2" "$3" "$4"
    ;;
  upload)
    [[ $# -ne 4 ]] && usage
    upload_secret "$2" "$3" "$4"
    ;;
  *)
    usage
    ;;
esac