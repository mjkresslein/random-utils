#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Requires AWSCLI (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) and
# Session manager plugin (s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe)

#################### SETTING AWS PROFILE ####################

$profiles = aws configure list-profiles | Where-Object { $_ -ne "" }

if (-not $profiles -or $profiles.Count -eq 0) {
    Write-Error "No AWS profiles found."
    exit 1
}

Write-Host "Select an AWS profile:"
for ($i = 0; $i -lt $profiles.Count; $i++) {
    Write-Host "$($i + 1)) $($profiles[$i])"
}

$AWS_PROFILE = $null
while (-not $AWS_PROFILE) {
    $selection = Read-Host "Enter number"
    if ($selection -match '^\d+$') {
        $index = [int]$selection - 1
        if ($index -ge 0 -and $index -lt $profiles.Count) {
            $AWS_PROFILE = $profiles[$index]
            Write-Host "Using profile: $AWS_PROFILE"
        }
    }
    if (-not $AWS_PROFILE) { Write-Host "Invalid selection. Try again." }
}

# Confirm profile being used -- REMOVE ME
aws sts get-caller-identity --profile $AWS_PROFILE

#################### GET INSTANCES ####################

$SEARCH_FILTER = Read-Host "Enter a search filter (optional)"

if ($SEARCH_FILTER) {
    Write-Host "Filtering by: $SEARCH_FILTER"
    $instances = aws ec2 describe-instances `
        --profile $AWS_PROFILE `
        --filters `
            "Name=instance-state-name,Values=running" `
            "Name=tag:Name,Values=*$SEARCH_FILTER*" `
        --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`]|[0].Value]' `
        --output text | Where-Object { $_ -ne "" }
} else {
    Write-Host "No filter specified."
    $instances = aws ec2 describe-instances `
        --profile $AWS_PROFILE `
        --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`]|[0].Value]' `
        --output text | Where-Object { $_ -ne "" }
}

if (-not $instances -or $instances.Count -eq 0) {
    Write-Error "No matching running instances found."
    exit 1
} else {
    Write-Host "Instances found!"  # -- REMOVE ME
}

#################### SELECT AN INSTANCE ####################

Write-Host "Select an instance:"
for ($i = 0; $i -lt $instances.Count; $i++) {
    Write-Host "$($i + 1)) $($instances[$i])"
}

$INSTANCE_ID = $null
$INSTANCE_NAME = $null
while (-not $INSTANCE_ID) {
    $selection = Read-Host "Enter number"
    if ($selection -match '^\d+$') {
        $index = [int]$selection - 1
        if ($index -ge 0 -and $index -lt $instances.Count) {
            $parts = $instances[$index] -split '\s+', 2
            $INSTANCE_ID   = $parts[0]
            $INSTANCE_NAME = if ($parts.Count -gt 1) { $parts[1] } else { "(no name)" }
        }
    }
    if (-not $INSTANCE_ID) { Write-Host "Invalid selection. Try again." }
}

Write-Host "Selected instance: $INSTANCE_ID ($INSTANCE_NAME)"

#################### IDENTIFY AVAILABLE LOCAL PORT ####################

$BASE = 3389
$LOCAL_PORT = $null

foreach ($ITER in 1..9) {
    $CANDIDATE = "$ITER$BASE"
    $inUse = Get-NetTCPConnection -LocalPort $CANDIDATE -State Listen -ErrorAction SilentlyContinue
    if (-not $inUse) {
        $LOCAL_PORT = $CANDIDATE
        break
    }
}

if (-not $LOCAL_PORT) {
    Write-Error "No available ports in range..."
    exit 1
}

Write-Host "Using port: $LOCAL_PORT"

#################### START PORT-FORWARDING ####################

$parametersFile = Join-Path $env:TEMP "ssm_params.json"
[System.IO.File]::WriteAllText($parametersFile, "{`"portNumber`":[`"3389`"],`"localPortNumber`":[`"$LOCAL_PORT`"]}")

aws ssm start-session `
    --profile $AWS_PROFILE `
    --target $INSTANCE_ID `
    --document-name AWS-StartPortForwardingSession `
    --parameters "file://$parametersFile"

Remove-Item $parametersFile -ErrorAction SilentlyContinue
