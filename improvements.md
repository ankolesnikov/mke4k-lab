# Improvements

A running log of notable changes made to this repo beyond the upstream baseline, newest first.

## Container-only `t`, AWS SSO, and PATH-safe launcher

**Date:** 2026-09-28

**Files:** `bin/t-commandline.bash`, `run.sh`, `Dockerfile`, `.gitignore`, `.dockerignore`, `README.md`, `CLAUDE.md`, `tests/`

- `t` now rejects host execution before doing work. `run.sh` marks the current prebuilt container; future image builds include the same marker.
- `run.sh` supports a private, persistent AWS SSO directory, explicit profile setup/login, and symlink-safe invocation without forwarding host static keys.
- Added guard and launcher regression tests and updated container-only usage documentation.

## One-command container startup

**Date:** 2026-09-28

**Files:** `run.sh`, `README.md`

- Added `run.sh` to start the prebuilt image with the persistent project, MKE4k kubeconfig, MKE3 client bundle, and shell startup mounts plus UI tunnel ports. It resolves the checkout from its own location and works from another current directory.

## Persistent workspace and expiry status

**Date:** 2026-09-28

**Files:** `README.md`, `.gitignore`, `.dockerignore`, `.bashrc`, `bin/t-commandline.bash`, `tests/test_expiry_status.sh`

- Documented bind mounts that keep Terraform state, generated SSH keys, manifests, credentials, the MKE4k kubeconfig, and the online MKE3 client bundle on the host. The mounted `.bashrc` makes the local startup banner available with the prebuilt image.
- Added `t expiry status`. On shell start it reports no lab, disabled auto-expiry, time remaining, or a passed deadline. It reads local Terraform output and does not require AWS credentials or create a cluster ID.
- Corrected bare `t expiry` so a checkout without Terraform state reports that no lab exists before loading config or creating a cluster ID.
- Added regression coverage for those states and the no-side-effect behavior.
