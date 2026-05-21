#!/usr/bin/env bash
set -euo pipefail

# Usage:
# ./ssm-connect.sh [options] <aws-profile> [region]
# Options:
#   --simple, --no-setup    Skip kubectl setup and credential export, just connect

SIMPLE_MODE=false
PROFILE=""
REGION=""
CLUSTER_NAME="strata-eks-133-blue"

# Parse options
while [[ $# -gt 0 ]]; do
  case $1 in
    --simple|--no-setup)
      SIMPLE_MODE=true
      shift
      ;;
    *)
      if [[ -z "$PROFILE" ]]; then
        PROFILE="$1"
      elif [[ -z "$REGION" ]]; then
        REGION="$1"
      else
        echo "Unknown argument: $1"
        exit 1
      fi
      shift
      ;;
  esac
done

# Set defaults
PROFILE="${PROFILE:-default}"
REGION="${REGION:-us-gov-west-1}"

echo "Using profile: $PROFILE"
echo "Using region:  $REGION"
echo "Using cluster: $CLUSTER_NAME"
echo

instances=$(aws ec2 describe-instances \
  --profile "$PROFILE" \
  --region "$REGION" \
  --filters Name=instance-state-name,Values=running Name=tag:Name,Values=strata-eks*-blue \
  --query 'Reservations[].Instances[].{
    ID:InstanceId,
    Name:Tags[?Key==`Name`]|[0].Value,
    PrivateIP:PrivateIpAddress,
    State:State.Name
  }' \
  --output json)

count=$(echo "$instances" | jq length)

if [[ "$count" -eq 0 ]]; then
  echo "No running instances found."
  exit 1
fi

echo "Running EC2 instances:"
echo

echo "$instances" | jq -r '
  to_entries[] |
  "\(.key + 1)) \(.value.ID)  \(.value.Name // "NoName")  \(.value.PrivateIP // "NoIP")"
'

echo
read -rp "Select instance number: " selection

instance_id=$(echo "$instances" | jq -r ".[$((selection - 1))].ID")

if [[ -z "$instance_id" || "$instance_id" == "null" ]]; then
  echo "Invalid selection."
  exit 1
fi

if [[ "$SIMPLE_MODE" == "true" ]]; then
  echo
  echo "Connecting to $instance_id via SSM (simple mode)..."
  echo

  aws ssm start-session \
    --profile "$PROFILE" \
    --region "$REGION" \
    --target "$instance_id"
else
  echo
  echo "Running kubectl setup on $instance_id..."
  echo

  aws ssm send-command \
    --profile "$PROFILE" \
    --region "$REGION" \
    --document-name "AWS-RunShellScript" \
    --targets "Key=instanceids,Values=$instance_id" \
    --parameters '{
      "commands": [
        "cd ~",
        "export AWS_PAGER=\"\"",
        "export PAGER=cat",
        "set -euo pipefail",

        "if ! command -v kubectl >/dev/null 2>&1; then",
        "  echo Installing kubectl...",
        "  ARCH=$(uname -m)",
        "  if [ \"$ARCH\" = \"x86_64\" ]; then ARCH=amd64; fi",
        "  if [ \"$ARCH\" = \"aarch64\" ]; then ARCH=arm64; fi",
        "  curl -Lo /tmp/kubectl https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl",
        "  chmod +x /tmp/kubectl",
        "  if command -v sudo >/dev/null 2>&1; then",
        "    sudo mv /tmp/kubectl /usr/local/bin/kubectl",
        "  else",
        "    mv /tmp/kubectl /usr/local/bin/kubectl",
        "  fi",
        "fi",

        "kubectl version --client --output=yaml >/dev/null",

        "if ! command -v k9s >/dev/null 2>&1; then",
        "  echo Installing k9s...",
        "  curl -LO https://github.com/derailed/k9s/releases/download/v0.50.15/k9s_Linux_amd64.tar.gz",
        "  tar xzvf k9s_Linux_amd64.tar.gz",
        "  if command -v sudo >/dev/null 2>&1; then",
        "    sudo cp k9s /usr/local/bin/",
        "    sudo chmod 755 /usr/local/bin/k9s",
        "  else",
        "    sudo cp k9s /usr/local/bin/",
        "    sudo chmod 755 /usr/local/bin/k9s",
        "  fi",
        "fi",

        "k9s version",

        "if ! command -v helm >/dev/null 2>&1; then",
        "  echo Installing Helm...",
        "  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash",
        "fi",

        "helm version"
      ]
    }' >/dev/null

  echo "Kubectl/k9s/Helm setup commands sent."
  echo

  echo "Exporting temporary credentials from profile $PROFILE..."
  creds=$(aws configure export-credentials \
    --profile "$PROFILE" \
    --format env)

remote_command=$(cat <<EOF
    export AWS_REGION="$REGION"
    export AWS_DEFAULT_REGION="$REGION"
    export AWS_PAGER=""
    export PAGER=cat
    $creds
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null
    echo "Connected to $instance_id"
    echo "AWS identity:"
    aws sts get-caller-identity
    echo
    echo "Try: kubectl get nodes"
    exec bash -l
EOF
)

  echo
  echo "Connecting to $instance_id via SSM..."
  echo

  aws ssm start-session \
    --profile "$PROFILE" \
    --region "$REGION" \
    --target "$instance_id" \
    --document-name AWS-StartInteractiveCommand \
    --parameters "$(jq -n --arg cmd "$remote_command" '{command: [$cmd]}')"
fi
