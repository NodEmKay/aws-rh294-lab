# AWS RH294 Lab Provisioning Script
# Creates:
#   workstation.lab.com
#   servera.lab.com
#   serverb.lab.com
#   serverc.lab.com
#   serverd.lab.com
#
# No AWS credentials or private keys are stored in this script.

param(
    [string]$Region = "us-east-1",
    [string]$AvailabilityZone = "us-east-1d",
    [string]$AmiId = "ami-00adafae70b8029d8",
    [string]$InstanceType = "t2.medium",
    [string]$KeyName = "ansiblelab1",
    [string]$AllowedSshCidr = ""
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$LabName = "aws-rh294-lab"

Write-Host "AWS RH294 Lab"
Write-Host "Region:        $Region"
Write-Host "AZ:            $AvailabilityZone"
Write-Host "AMI:           $AmiId"
Write-Host "Instance Type: $InstanceType"
Write-Host "Key Pair:      $KeyName"
Write-Host ""

# Lab topology
$Instances = @(
    @{ Name = "workstation"; RootSize = 20 },
    @{ Name = "servera";     RootSize = 10 },
    @{ Name = "serverb";     RootSize = 10 },
    @{ Name = "serverc";     RootSize = 10 },
    @{ Name = "serverd";     RootSize = 10 }
)

Write-Host "Planned instances:"
foreach ($Instance in $Instances) {
    Write-Host "  $($Instance.Name).lab.com - root disk $($Instance.RootSize) GiB"
}

Write-Host ""
Write-Host "RH294 practice disks:"
Write-Host "  servera: 2 GiB"
Write-Host "  serverb: 2 GiB"
Write-Host "  serverc: 2 GiB"
Write-Host "  serverd: 2 GiB + 1 GiB"

# ------------------------------------------------------------
# Validate AWS access
# ------------------------------------------------------------

Write-Host ""
Write-Host "Checking AWS credentials..."

$Identity = aws sts get-caller-identity `
    --region $Region `
    --output json | ConvertFrom-Json

if (-not $Identity.Account) {
    throw "Unable to determine AWS account."
}

Write-Host "AWS authentication successful."

# ------------------------------------------------------------
# Discover default VPC
# ------------------------------------------------------------

$VpcId = aws ec2 describe-vpcs `
    --region $Region `
    --filters "Name=is-default,Values=true" `
    --query "Vpcs[0].VpcId" `
    --output text

if (-not $VpcId -or $VpcId -eq "None") {
    throw "No default VPC found in region $Region."
}

Write-Host "Default VPC:   $VpcId"

# ------------------------------------------------------------
# Find subnet in requested Availability Zone
# ------------------------------------------------------------

$SubnetId = aws ec2 describe-subnets `
    --region $Region `
    --filters `
        "Name=vpc-id,Values=$VpcId" `
        "Name=availability-zone,Values=$AvailabilityZone" `
    --query "Subnets[0].SubnetId" `
    --output text

if (-not $SubnetId -or $SubnetId -eq "None") {
    throw "No subnet found in $AvailabilityZone."
}

Write-Host "Subnet:        $SubnetId"

# ------------------------------------------------------------
# Verify EC2 key pair
# ------------------------------------------------------------

aws ec2 describe-key-pairs `
    --region $Region `
    --key-names $KeyName `
    --output json | Out-Null

Write-Host "Key pair:      $KeyName - found"

# ------------------------------------------------------------
# Security group
# ------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($AllowedSshCidr)) {
    throw "AllowedSshCidr is required. Example: -AllowedSshCidr '203.0.113.10/32'"
}

$SecurityGroupName = "$LabName-sg"

$SecurityGroupId = aws ec2 describe-security-groups `
    --region $Region `
    --filters `
        "Name=vpc-id,Values=$VpcId" `
        "Name=group-name,Values=$SecurityGroupName" `
    --query "SecurityGroups[0].GroupId" `
    --output text

if (-not $SecurityGroupId -or $SecurityGroupId -eq "None") {

    Write-Host "Creating security group: $SecurityGroupName"

    $SecurityGroupId = aws ec2 create-security-group `
        --region $Region `
        --group-name $SecurityGroupName `
        --description "Security group for AWS RH294 lab" `
        --vpc-id $VpcId `
        --query "GroupId" `
        --output text
aws ec2 create-tags `
    --region $Region `
    --resources $SecurityGroupId `
    --tags `
        "Key=Name,Value=$SecurityGroupName" `
        "Key=Lab,Value=$LabName" | Out-Null

    # SSH from administrator workstation only
    aws ec2 authorize-security-group-ingress `
        --region $Region `
        --group-id $SecurityGroupId `
        --protocol tcp `
        --port 22 `
        --cidr $AllowedSshCidr | Out-Null

    # Allow all communication between RH294 lab instances
    aws ec2 authorize-security-group-ingress `
        --region $Region `
        --group-id $SecurityGroupId `
        --protocol -1 `
        --source-group $SecurityGroupId | Out-Null
}
else {
    Write-Host "Reusing security group: $SecurityGroupName"
}

Write-Host "Security Group: $SecurityGroupId"

# ------------------------------------------------------------
# Create or reuse EC2 instances
# ------------------------------------------------------------

$InstanceResults = @{}

foreach ($Instance in $Instances) {

    $Name = $Instance.Name
    $Fqdn = "$Name.lab.com"

    Write-Host ""
    Write-Host "Checking instance: $Fqdn"

    $ExistingInstanceId = aws ec2 describe-instances `
        --region $Region `
        --filters `
            "Name=tag:Lab,Values=$LabName" `
            "Name=tag:Name,Values=$Fqdn" `
            "Name=instance-state-name,Values=pending,running,stopping,stopped" `
        --query "Reservations[0].Instances[0].InstanceId" `
        --output text

    if ($ExistingInstanceId -and $ExistingInstanceId -ne "None") {

        Write-Host "Reusing existing instance: $ExistingInstanceId"
        $InstanceId = $ExistingInstanceId

        $State = aws ec2 describe-instances `
            --region $Region `
            --instance-ids $InstanceId `
            --query "Reservations[0].Instances[0].State.Name" `
            --output text

        if ($State -eq "stopped") {
            Write-Host "Starting stopped instance..."
            aws ec2 start-instances `
                --region $Region `
                --instance-ids $InstanceId | Out-Null
        }
    }
    else {

        Write-Host "Creating instance: $Fqdn"

        $InstanceId = aws ec2 run-instances `
            --region $Region `
            --image-id $AmiId `
            --instance-type $InstanceType `
            --key-name $KeyName `
            --subnet-id $SubnetId `
            --security-group-ids $SecurityGroupId `
            --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$($Instance.RootSize),VolumeType=gp3,DeleteOnTermination=true}" `
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$Fqdn},{Key=Lab,Value=$LabName}]" `
            --query "Instances[0].InstanceId" `
            --output text

        Write-Host "Created: $InstanceId"
    }

    $InstanceResults[$Name] = $InstanceId
}

Write-Host ""
Write-Host "Waiting for all instances to reach running state..."

aws ec2 wait instance-running `
    --region $Region `
    --instance-ids $InstanceResults.Values

Write-Host "All lab instances are running."

# ------------------------------------------------------------
# RH294 practice EBS disk definitions
# ------------------------------------------------------------

$LabDisks = @(
    @{ Server = "servera"; Size = 2; Device = "/dev/sdb"; Disk = "disk1" },
    @{ Server = "serverb"; Size = 2; Device = "/dev/sdb"; Disk = "disk1" },
    @{ Server = "serverc"; Size = 2; Device = "/dev/sdb"; Disk = "disk1" },
    @{ Server = "serverd"; Size = 2; Device = "/dev/sdb"; Disk = "disk1" },
    @{ Server = "serverd"; Size = 1; Device = "/dev/sdc"; Disk = "disk2" }
)

Write-Host ""
Write-Host "RH294 practice disk plan:"

foreach ($Disk in $LabDisks) {
    Write-Host "  $($Disk.Server) - $($Disk.Size) GiB - $($Disk.Device)"
}

# ------------------------------------------------------------
# Create or reuse RH294 practice EBS volumes
# ------------------------------------------------------------

foreach ($Disk in $LabDisks) {

    $Server = $Disk.Server
    $DiskName = "$Server-$($Disk.Disk)"
    $InstanceId = $InstanceResults[$Server]

    Write-Host ""
    Write-Host "Checking practice disk: $DiskName"

    $VolumeId = aws ec2 describe-volumes `
        --region $Region `
        --filters `
            "Name=tag:Lab,Values=$LabName" `
            "Name=tag:Name,Values=$DiskName" `
            "Name=tag:Purpose,Values=rh294-practice" `
        --query "Volumes[0].VolumeId" `
        --output text

    if (-not $VolumeId -or $VolumeId -eq "None") {

        Write-Host "Creating $($Disk.Size) GiB volume..."

        $VolumeId = aws ec2 create-volume `
            --region $Region `
            --availability-zone $AvailabilityZone `
            --size $Disk.Size `
            --volume-type gp3 `
            --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=$DiskName},{Key=Lab,Value=$LabName},{Key=Purpose,Value=rh294-practice}]" `
            --query "VolumeId" `
            --output text

        Write-Host "Created volume: $VolumeId"

        aws ec2 wait volume-available `
            --region $Region `
            --volume-ids $VolumeId
    }
    else {
        Write-Host "Reusing volume: $VolumeId"
    }

    $AttachedInstance = aws ec2 describe-volumes `
        --region $Region `
        --volume-ids $VolumeId `
        --query "Volumes[0].Attachments[0].InstanceId" `
        --output text

    if (-not $AttachedInstance -or $AttachedInstance -eq "None") {

        Write-Host "Attaching $VolumeId to $Server as $($Disk.Device)..."

        aws ec2 attach-volume `
            --region $Region `
            --volume-id $VolumeId `
            --instance-id $InstanceId `
            --device $Disk.Device | Out-Null
    }
    elseif ($AttachedInstance -eq $InstanceId) {
        Write-Host "Volume already attached to $Server."
    }
    else {
        throw "Volume $VolumeId is already attached to another instance: $AttachedInstance"
    }
}

Write-Host ""
Write-Host "AWS RH294 infrastructure provisioning complete."

# ------------------------------------------------------------
# Display resulting lab topology
# ------------------------------------------------------------

Write-Host ""
Write-Host "Lab topology:"
Write-Host ""

foreach ($Instance in $Instances) {

    $Name = $Instance.Name
    $InstanceId = $InstanceResults[$Name]

    $Details = aws ec2 describe-instances `
        --region $Region `
        --instance-ids $InstanceId `
        --query "Reservations[0].Instances[0].{PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress}" `
        --output json | ConvertFrom-Json

    Write-Host ("{0,-12} {1,-20} Private: {2,-16} Public: {3}" -f `
        $Name, `
        "$Name.lab.com", `
        $Details.PrivateIp, `
        $Details.PublicIp)
}

Write-Host ""
Write-Host "Infrastructure ready."
Write-Host "Next: bootstrap workstation and generate Ansible inventory."

# ------------------------------------------------------------
# Generate dynamic lab host mappings
# ------------------------------------------------------------

Write-Host ""
Write-Host "Generating lab host mappings..."

$HostsFile = Join-Path $PSScriptRoot "lab-hosts.txt"
$HostLines = @()

foreach ($Instance in $Instances) {

    $Name = $Instance.Name
    $InstanceId = $InstanceResults[$Name]

    $PrivateIp = aws ec2 describe-instances `
        --region $Region `
        --instance-ids $InstanceId `
        --query "Reservations[0].Instances[0].PrivateIpAddress" `
        --output text

    if (-not $PrivateIp -or $PrivateIp -eq "None") {
        throw "Unable to determine private IP for $Name."
    }

    $HostLines += "$PrivateIp`t$Name.lab.com $Name"
}

$HostLines | Set-Content -Path $HostsFile -Encoding ascii

Write-Host ""
Write-Host "Generated:"
Write-Host "  $HostsFile"
Write-Host ""

Get-Content $HostsFile
