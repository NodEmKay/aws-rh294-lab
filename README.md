# AWS RH294 Lab

Reusable AWS-based RH294 / Ansible practice environment.

## Repository

GitHub:

`git@github.com:NodEmKay/aws-rh294-lab.git`

Branch: `main`

## Lab topology

| Host | Purpose | Root disk | Practice disks |
|---|---|---:|---|
| workstation.lab.com | Ansible workstation | 20 GiB | — |
| servera.lab.com | Managed node | 10 GiB | 2 GiB |
| serverb.lab.com | Managed node | 10 GiB | 2 GiB |
| serverc.lab.com | Managed node | 10 GiB | 2 GiB |
| serverd.lab.com | Managed node | 10 GiB | 2 GiB + 1 GiB |

AWS private IP addresses are dynamic and are not committed to Git.

## External assets

The following must be kept outside GitHub.

### SSH private key

File:

`ansiblelab1.pem`

Place it on the workstation as:

`~/.ssh/ansiblelab1.pem`

Set permissions:

`chmod 600 ~/.ssh/ansiblelab1.pem`

## AWS provisioning

The AWS infrastructure is created or reused with:

`scripts/create-aws-lab.ps1`

The script provisions:

- workstation
- servera
- serverb
- serverc
- serverd
- security group
- RH294 practice EBS volumes

It also discovers the current private IP addresses and generates:

`scripts/lab-hosts.txt`

The generated IP mapping is intentionally excluded from Git.

## Workstation bootstrap

On the RHEL workstation:

`./scripts/bootstrap-workstation.sh`

The bootstrap validates:

- RHEL
- Podman
- SSH private key
- project directory
- required container images
- development container
- nested Podman
- custom RH294 EE
- dynamic `/etc/hosts`
- Ansible inventory

## Dynamic host mappings

After AWS provisioning, the generated:

`scripts/lab-hosts.txt`

contains the current private IP addresses for the lab hosts.

The file is used by the workstation bootstrap to update the RH294 entries in:

`/etc/hosts`

Do not commit `lab-hosts.txt`.

## Ansible inventory

The inventory uses hostnames rather than IP addresses:

[prod]
servera.lab.com
serverb.lab.com

[test]
serverc.lab.com
serverd.lab.com

This means the inventory does not need to change when AWS assigns new private IP addresses.

## Development container

The workstation uses the Podman development container:

`ansible-dev`

The development container provides the Ansible development tooling and nested Podman environment used for the lab.

The custom RH294 execution environment is:

`localhost/rh294-ee:1.0`

The custom EE is available inside the nested Podman environment.

## Practice disk verification

Run:

`./scripts/verify-lab-disks.sh`

Expected practice disks:

- servera: 2 GiB
- serverb: 2 GiB
- serverc: 2 GiB
- serverd: 2 GiB + 1 GiB

The verification script only checks the disks. It does not partition or format them.

## Verify Ansible connectivity

Run:

`podman exec ansible-dev ansible-navigator run ping.yml --mode stdout`

All four managed nodes should report zero unreachable and zero failed hosts.

## Rebuild sequence

1. Clone this repository.
2. Restore `ansiblelab1.pem` to `~/.ssh/ansiblelab1.pem`.
3. Restore the custom RH294 execution environment.
4. Run `scripts/create-aws-lab.ps1` from the administration machine.
5. Transfer the newly generated `scripts/lab-hosts.txt` to the workstation.
6. Run `./scripts/bootstrap-workstation.sh`.
7. Run `./scripts/verify-lab-disks.sh`.
8. Run the Ansible Navigator connectivity test.
9. Continue with RH294 practice.

## Git exclusions

The repository must not contain:

- SSH private keys
- AWS credentials
- generated AWS private-IP mappings
- Ansible Navigator artifacts
- Navigator logs
- temporary files
- large external execution-environment archives

## Current verification

The environment has been verified for:

- AWS EC2 infrastructure
- EBS practice disks
- dynamic private-IP mapping
- `/etc/hosts`
- Ansible inventory
- Podman
- `ansible-dev`
- nested Podman
- custom `rh294-ee:1.0`
- Ansible Navigator
- connectivity to servera, serverb, serverc and serverd

## Architecture

```text
AWS
|
+-- workstation.lab.com
|     |
|     +-- ansible-dev
|           |
|           +-- nested Podman
|                 |
|                 +-- localhost/rh294-ee:1.0
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
