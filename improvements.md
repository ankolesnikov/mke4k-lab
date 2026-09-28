# Improvements

A running log of notable changes made to this repo beyond the upstream baseline, newest first.

## Persistent workspace and expiry status

**Date:** 2026-09-28

**Files:** `README.md`, `.gitignore`, `.dockerignore`, `.bashrc`, `bin/t-commandline.bash`, `tests/test_expiry_status.sh`

- Documented bind mounts that keep Terraform state, generated SSH keys, manifests, credentials, the MKE4k kubeconfig, and the online MKE3 client bundle on the host. The mounted `.bashrc` makes the local startup banner available with the prebuilt image.
- Added `t expiry status`. On shell start it reports no lab, disabled auto-expiry, time remaining, or a passed deadline. It reads local Terraform output and does not require AWS credentials or create a cluster ID.
- Corrected bare `t expiry` so a checkout without Terraform state reports that no lab exists before loading config or creating a cluster ID.
- Added regression coverage for those states and the no-side-effect behavior.
