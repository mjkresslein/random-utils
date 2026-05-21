#!/usr/bin/env bash

set -euo pipefail

echo "Cleaning All Terraform and Terragrunt Files... "
sudo find ~/ -name ".terraform" -type d -prune -exec rm -rf {} +
sudo find ~/ -name ".terragrunt-cache" -type d -prune -exec rm -rf {} +
sudo find ~/ -name ".terraform.lock.hcl" -type f -delete
sudo find ~/ -name "terraform.tfstate*" -type f -delete
