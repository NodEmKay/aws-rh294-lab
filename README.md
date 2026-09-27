# AWS AU294 / RH294 Ansible Practice Lab

Reusable AWS-based Red Hat Ansible Automation Platform practice environment for AU294 / RH294-style hands-on learning.

The goal of this repository is to allow a learner to start with a fresh Windows administration machine and a fresh AWS account, provision the complete lab, bootstrap the Ansible workstation, and begin running playbooks with minimal manual configuration.

---

## Architecture

```text
Windows Administration Machine
        |
        | PowerShell / AWS CLI
        | create-aws-lab.ps1
        v
AWS
|
+-- workstation.lab.com
|     |
|     +-- Podman
|           |
|           +-- ansible-dev
|                 |
|                 +-- ansible-navigator
|                 +-- nested Podman
|                       |
|                       +-- localhost/rh294-ee:1.0
|
+-- servera.lab.com
|     +-- 2 GiB practice disk
|
+-- serverb.lab.com
|     +-- 2 GiB practice disk
|
+-- serverc.lab.com
|     +-- 2 GiB practice disk
|
+-- serverd.lab.com
      +-- 2 GiB practice disk
      +-- 1 GiB practice disk
```

Playbook execution path:

```text
VS Code / Terminal
       |
       v
ansible-dev
       |
       v
ansible-navigator
       |
       v
localhost/rh294-ee:1.0
       |
       | SSH
       v
servera / serverb / serverc / serverd
```

---

## Lab topology

| Host | Purpose | Root disk | Practice disks |
|---|---|---:|---|
| workstation.lab.com | Ansible development workstation | 20 GiB | — |
| servera.lab.com | Managed node | 10 GiB | 2 GiB |
| serverb.lab.com | Managed node | 10 GiB | 2 GiB |
| serverc.lab.com | Managed node | 10 GiB | 2 GiB |
| serverd.lab.com | Managed node | 10 GiB | 2 GiB + 1 GiB |

AWS private IP addresses are dynamically discovered and are not committed to Git.

---

# 1. Windows prerequisites

Install the following on the Windows administration machine:

- Git
- AWS CLI v2
- OpenSSH client
- PowerShell

Verify:

```powershell
git --version
aws --version
ssh -V
```

Configure AWS credentials:

```powershell
aws configure
```

Verify the active AWS identity:

```powershell
aws sts get-caller-identity
```

Do not store AWS credentials in this repository.

---

# 2. Clone the repository

HTTPS is recommended for a new machine because it does not require GitHub SSH key configuration.

```powershell
git clone https://github.com/NodEmKay/aws-rh294-lab.git
cd aws-rh294-lab
```

Verify:

```powershell
git status
git log -1 --oneline
```

---

# 3. Create an AWS EC2 SSH key

Choose your own EC2 key-pair name.

Example:

```powershell
$KeyName = "ansiblelab3"

New-Item -ItemType Directory -Force "$HOME\.ssh" | Out-Null

$PemPath = Join-Path $HOME ".ssh\$KeyName.pem"

cmd.exe /d /c "aws ec2 create-key-pair --key-name $KeyName --key-type rsa --query KeyMaterial --output text > `"$PemPath`""
```

Validate the private key before provisioning:

```powershell
ssh-keygen -y -f "$PemPath" | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "SSH PRIVATE KEY VALID"
}
```

Do not commit the PEM file to Git.

> Important: preserve the EC2 private key exactly as returned by AWS. Avoid rewriting the key contents through text-processing commands that may alter its encoding or line endings.

---

# 4. Restrict SSH access

Determine the current public IP address of the administration machine:

```powershell
$AllowedSshCidr = ((Invoke-RestMethod https://checkip.amazonaws.com).Trim() + "/32")
$AllowedSshCidr
```

The generated security group uses this CIDR for SSH access.

---

# 5. Provision the AWS lab

Run:

```powershell
.\scripts\create-aws-lab.ps1 `
    -AllowedSshCidr $AllowedSshCidr `
    -KeyName $KeyName `
    -PrivateKeyPath $PemPath
```

The script provisions the lab infrastructure, including:

- workstation
- servera
- serverb
- serverc
- serverd
- security group
- RH294 practice EBS volumes

It also:

- discovers the current AWS private IP addresses
- generates `scripts/lab-hosts.txt`
- waits for workstation SSH availability
- stages the SSH private key on the workstation as `~/.ssh/ansiblelab.pem`
- stages the dynamic host mapping as `~/.rh294/lab-hosts.txt`

Successful provisioning ends with:

```text
AWS RH294 INFRASTRUCTURE READY
```

Use the SSH command displayed by the provisioning script to connect to the workstation.

---

# 6. Dynamic host mappings

AWS private IP addresses can change between lab deployments.

The provisioning script therefore dynamically generates:

```text
scripts/lab-hosts.txt
```

Example structure:

```text
<private-ip> workstation.lab.com workstation
<private-ip> servera.lab.com servera
<private-ip> serverb.lab.com serverb
<private-ip> serverc.lab.com serverc
<private-ip> serverd.lab.com serverd
```

The file is copied to the workstation as:

```text
~/.rh294/lab-hosts.txt
```

The workstation bootstrap uses this information to configure `/etc/hosts`.

Do not commit `lab-hosts.txt`.

---

# 7. Prepare the AWS workstation

Connect to the workstation using the SSH command produced by the provisioning script.

Verify the automatically staged files:

```bash
ls -l ~/.ssh/ansiblelab.pem ~/.rh294/lab-hosts.txt
```

The project should be available at:

```text
~/ansible-projects/aws-rh294
```

If the repository is not already present, clone it:

```bash
mkdir -p ~/ansible-projects

git clone https://github.com/NodEmKay/aws-rh294-lab.git \
    ~/ansible-projects/aws-rh294
```

Then:

```bash
cd ~/ansible-projects/aws-rh294
```

---

# 8. Authenticate to the Red Hat registry

The lab uses Red Hat Ansible Automation Platform container images.

Authenticate:

```bash
podman login registry.redhat.io
```

A Red Hat account with permission to access the required container images is required.

Registry credentials must never be committed to Git.

---

# 9. Bootstrap the Ansible workstation

From the repository:

```bash
./scripts/bootstrap-workstation.sh
```

The bootstrap performs the following operations:

1. Validates the RHEL workstation.
2. Validates Podman.
3. Validates the project directory and SSH key.
4. Configures dynamic lab hostname mappings.
5. Pulls the Red Hat Ansible Development Tools image.
6. Pulls the Red Hat supported Execution Environment.
7. Builds the custom `localhost/rh294-ee:1.0` execution environment.
8. Installs `community.general` into the custom EE.
9. Creates the `ansible-dev` development container.
10. Makes the custom EE available to nested Podman.
11. Validates the Ansible inventory.
12. Tests SSH connectivity to all managed nodes.

Successful completion displays:

```text
WORKSTATION BOOTSTRAP COMPLETE
```

The bootstrap is designed to be re-runnable. If execution is interrupted, run it again:

```bash
cd ~/ansible-projects/aws-rh294
./scripts/bootstrap-workstation.sh
```

Existing successfully created components are reused where possible.

---

# 10. Container images

The environment uses two Red Hat images.

### Ansible Development Tools

```text
registry.redhat.io/ansible-automation-platform-25/ansible-dev-tools-rhel8:latest
```

This provides the development environment containing tools such as Ansible Navigator.

### Supported Execution Environment

```text
registry.redhat.io/ansible-automation-platform-25/ee-supported-rhel8:latest
```

This is used as the base for the custom RH294 execution environment.

### Custom execution environment

The repository builds:

```text
localhost/rh294-ee:1.0
```

from the files under:

```text
execution-environment/
```

The custom EE includes:

```text
community.general 7.3.0
```

The custom image is built from source during bootstrap. A prebuilt multi-gigabyte EE archive is therefore not required in Git.

---

# 11. Enter the development container

After bootstrap:

```bash
podman exec -it ansible-dev bash
```

Inside the container:

```bash
cd /workspaces/aws-rh294
```

The prompt should identify the development container.

The repository on the workstation:

```text
~/ansible-projects/aws-rh294
```

is mounted inside the container as:

```text
/workspaces/aws-rh294
```

Changes made inside the development container therefore modify the same Git working tree.

---

# 12. Ansible inventory

The inventory uses hostnames instead of AWS IP addresses:

```ini
[prod]
servera.lab.com
serverb.lab.com

[test]
serverc.lab.com
serverd.lab.com
```

This allows AWS private addresses to change without modifying the committed inventory.

---

# 13. Run playbooks

Run playbooks from inside `ansible-dev`.

Example:

```bash
ansible-navigator run ping.yml
```

Privilege escalation test:

```bash
ansible-navigator run sudo-test.yml
```

General syntax:

```bash
ansible-navigator run <playbook>.yml
```

The project configuration automatically provides the inventory, SSH configuration, and execution environment.

---

# 14. Verify Ansible connectivity

Run:

```bash
ansible-navigator run ping.yml
```

Expected result for every managed node:

```text
unreachable=0
failed=0
```

Then verify privilege escalation:

```bash
ansible-navigator run sudo-test.yml
```

The effective user should be:

```text
root
```

for servera, serverb, serverc, and serverd.

---

# 15. Practice disk verification

From the AWS workstation, run:

```bash
./scripts/verify-lab-disks.sh
```

Expected practice disks:

- servera: 2 GiB
- serverb: 2 GiB
- serverc: 2 GiB
- serverd: 2 GiB + 1 GiB

The verification script only checks the disks.

It does not partition, format, or otherwise prepare them for exercises.

Always verify the actual Linux block-device names before performing storage exercises. Never assume a device is a practice disk solely from its device name.

The operating-system disk must never be modified for practice storage exercises.

---

# 16. VS Code workflow

A convenient development workflow is:

```text
Windows VS Code
      |
      | Remote SSH
      v
AWS workstation
      |
      | Dev Containers
      v
ansible-dev
      |
      v
/workspaces/aws-rh294
```

First connect VS Code to the AWS workstation using Remote SSH.

Then attach/open the `ansible-dev` container and open:

```text
/workspaces/aws-rh294
```

Playbooks can then be edited in VS Code and executed from the integrated terminal using:

```bash
ansible-navigator run <playbook>.yml
```

---

# 17. Validated deployment workflow

The tested deployment sequence is:

```text
Fresh Windows machine
        |
        v
Install Git + AWS CLI + OpenSSH
        |
        v
aws configure
        |
        v
Create + validate EC2 SSH key
        |
        v
Clone public GitHub repository
        |
        v
create-aws-lab.ps1
        |
        v
AWS infrastructure ready
        |
        v
SSH to workstation
        |
        v
podman login registry.redhat.io
        |
        v
bootstrap-workstation.sh
        |
        v
ansible-dev
        |
        v
ansible-navigator
        |
        v
servera / serverb / serverc / serverd
```

This workflow has been tested using fresh AWS lab deployments, including a clean deployment using a separate AWS account.

---

# 18. Git exclusions and security

The repository must never contain:

- SSH private keys
- AWS access keys
- AWS secret access keys
- Red Hat registry credentials
- Podman authentication files
- generated AWS private-IP mappings
- Ansible Vault passwords
- Ansible Navigator artifacts
- Navigator logs
- temporary files
- exported execution-environment archives

Never paste credentials or private-key contents into Git commits, issue trackers, documentation, or chat systems.

---

# 19. Destroy the lab

AWS resources incur charges while they exist.

When the practice environment is no longer required, use:

```powershell
.\scripts\destroy-aws-lab.ps1
```

Review the output carefully before confirming destruction.

The destruction process is intended for resources belonging to this RH294 lab.

After destruction, verify the AWS account for any remaining chargeable lab resources.

---

# 20. Current verification

The environment has been verified for:

- AWS EC2 infrastructure provisioning
- fresh AWS account deployment
- EBS practice disks
- dynamic private-IP discovery
- automatic workstation handoff
- dynamic `/etc/hosts`
- Ansible inventory
- Podman
- Red Hat AAP container images
- custom EE build from Git source
- `community.general`
- `ansible-dev`
- nested Podman
- `localhost/rh294-ee:1.0`
- Ansible Navigator
- SSH connectivity to servera–serverd
- passwordless privilege escalation to root

Example validation:

```bash
ansible-navigator run ping.yml
ansible-navigator run sudo-test.yml
```

All four managed nodes should complete with:

```text
unreachable=0
failed=0
```

---

## Important

This repository is a personal/community practice environment.

It is not official Red Hat training material and does not contain Red Hat course or exam content.

Access to Red Hat container images requires appropriate Red Hat credentials and entitlements.
