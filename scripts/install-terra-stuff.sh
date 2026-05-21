#!/bin/bash

# designed for RHEL

set -e

# # Install required packages
sudo dnf install -y dnf-plugins-core gnupg2 curl wget

# # Add HashiCorp repository
# sudo dnf config-manager addrepo \
#   --from-repofile=https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo --overwrite

# # Install Terraform
sudo dnf install -y terraform

# Terragrunt installation
OS="linux"
ARCH="amd64"
VERSION="v0.93.8"
BINARY_NAME="terragrunt_${OS}_${ARCH}"

curl -sL \
  "https://github.com/gruntwork-io/terragrunt/releases/download/${VERSION}/${BINARY_NAME}" \
  -o "${BINARY_NAME}"

chmod +x "${BINARY_NAME}"

sudo mv "${BINARY_NAME}" /home/user/.local/bin/terragrunt

# Verify installations
terraform -version
terragrunt --version
