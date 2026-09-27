# AWS RH294 Lab Destruction Script
# Deletes ONLY resources tagged Lab=aws-rh294-lab.
# Does NOT delete the VPC, subnet, key pair, or unrelated resources.

param(
    [string]$Region = "us-east-1",
    [switch]$Confirm
)

$ErrorActionPreference = "Stop"

$LabName = "aws-rh294-lab"

if (-not $Confirm) {
    Write-Host ""
    Write-Host "WARNING: This will DELETE the AWS RH294 lab resources." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Lab tag: $LabName"
    Write-Host "Region:  $Region"
    Write-Host ""
    Write-Host "Run with -Confirm to proceed."
    exit 1
}

Write-Host ""
Write-Host "Destroying AWS RH294 lab..."
Write-Host "Region: $Region"
Write-Host "Lab:    $LabName"
Write-Host ""

# ------------------------------------------------------------
# Find lab instances
# ------------------------------------------------------------

$InstanceIds = @(
    aws ec2 describe-instances `
        --region $Region `
        --filters "Name=tag:Lab,Values=$LabName" `
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" `
        --query "Reservations[].Instances[].InstanceId" `
        --output text
) -split '\s+' | Where-Object { $_ -and $_ -ne "None" }

# ------------------------------------------------------------
# Terminate instances
# ------------------------------------------------------------

if ($InstanceIds.Count -gt 0) {

    Write-Host "Terminating instances:"
    $InstanceIds | ForEach-Object { Write-Host "  $_" }

    aws ec2 terminate-instances `
        --region $Region `
        --instance-ids $InstanceIds | Out-Null

    aws ec2 wait instance-terminated `
        --region $Region `
        --instance-ids $InstanceIds

    Write-Host "Instances terminated."
}
else {
    Write-Host "No lab instances found."
}

# ------------------------------------------------------------
# Delete tagged practice EBS volumes
# ------------------------------------------------------------

$VolumeIds = @(
    aws ec2 describe-volumes `
        --region $Region `
        --filters "Name=tag:Lab,Values=$LabName" `
        --query "Volumes[].VolumeId" `
        --output text
) -split '\s+' | Where-Object { $_ -and $_ -ne "None" }

if ($VolumeIds.Count -gt 0) {

    Write-Host ""
    Write-Host "Deleting practice volumes:"

    foreach ($VolumeId in $VolumeIds) {
        Write-Host "  $VolumeId"

        aws ec2 delete-volume `
            --region $Region `
            --volume-id $VolumeId
    }

    Write-Host "Practice volumes deleted."
}
else {
    Write-Host ""
    Write-Host "No tagged practice volumes found."
}

# ------------------------------------------------------------
# Delete tagged security group
# ------------------------------------------------------------

$SecurityGroupName = "$LabName-sg"

$SecurityGroupId = aws ec2 describe-security-groups `
    --region $Region `
    --filters `
        "Name=group-name,Values=$SecurityGroupName" `
    --query "SecurityGroups[0].GroupId" `
    --output text

if ($SecurityGroupId -and $SecurityGroupId -ne "None") {

    Write-Host ""
    Write-Host "Deleting security group: $SecurityGroupId"

    aws ec2 delete-security-group `
        --region $Region `
        --group-id $SecurityGroupId

    Write-Host "Security group deleted."
}
else {
    Write-Host ""
    Write-Host "No lab security group found."
}

Write-Host ""
Write-Host "AWS RH294 lab destruction complete."
