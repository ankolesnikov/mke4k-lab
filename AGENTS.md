# AGENTS.md

How AI agents (Claude Code, Codex, Cursor, etc.) should **use** and **change** this repo.
Read this first, then `README.md` + `docs/` (user docs) and `CLAUDE.md` (architecture + deploy-flow detail).
This file is the rulebook; those two are the reference — don't duplicate them here.

## 1. What you are operating

`t` is a CLI that spends real money in a real AWS account: every `t deploy lab*` creates a VPC,
several EC2 instances (nodes, plus NFS server / bastion when enabled), 1–2 NLBs and IAM objects. State (`terraform/terraform.tfstate`,
`terraform/aws_private.pem`) lives **only** on the machine/container that ran the deploy — with `run.sh` that is the
host checkout (bind-mounted at `/mke4k-lab`); with a bare `docker run` it is the named container.

`t` runs **only inside the lab container**: it exits immediately unless `MKE4K_LAB_CONTAINER=1`
(set by the Dockerfile and by `run.sh`). Don't work around the guard by exporting the variable on the host.

## 2. Hard rules

1. **Never run a cost- or state-changing command without the user's explicit go-ahead for that
   command in this conversation.** That is: `t deploy *`, `t destroy *`, `t expiry <n>|off`,
   `t config apply|edit`, `t rotate child-creds`, `terraform apply|destroy`, `bin/cleanup-aws.sh`,
   `mkectl apply|reset`, `launchpad apply|reset`. `t deploy child-cluster` also creates AWS resources
   that Terraform, the reaper and `cleanup-aws.sh` do not track (CAPA owns them). Approval for one does not carry over to the next.
2. **`t destroy lab` does not prompt** (`terraform destroy -auto-approve`). Before running it,
   show the user the target (`t show nodes`, cluster name from `.cluster-id`) and get a yes.
3. **Never delete or overwrite** `terraform/terraform.tfstate*`, `terraform/aws_private.pem`,
   `.cluster-id`, `.owner`, `.expiry-*`, or the `run.sh` mounts `.aws/`, `.mke/`, `.mirantis-launchpad/`. Losing them orphans AWS resources (recovery path:
   `bin/cleanup-aws.sh <cluster-name> [region]`, which is itself destructive — rule 1 applies).
   `t destroy lab` itself removes the lab's generated logins, configs, kubeconfig and client bundle
   after a successful destroy; that is expected.
4. **Never print, commit or send secrets**: AWS keys, the AWS SSO cache under `.aws/`, `aws_private.pem`, `terraform/*_credentials.txt`,
   `msr4_*.key`, the MKE3 bearer token, Grafana passwords. They are git- and docker-ignored; keep it so.
   When the user needs a password, point them at the file path instead of echoing it. Note that
   deploy output, `t show summary` (MKE3 / airgap) and `t deploy kof` print passwords in plaintext —
   never copy those lines into chat, PRs or commits.
5. **Never set `expiry_days=0` / `t expiry off` on your own** — the reaper is the safety net for
   forgotten labs.
6. **Read-only commands are always fine**: `t status` and `t status child` (all modes — airgap runs on the bastion, MKE3 via
   the client bundle; on first use in airgap it installs `kubectl` on the bastion, lab tooling only),
   `t show nodes`, `t show summary` (output contains passwords — rule 4), `t expiry` (no arg), `t expiry status`
   (local Terraform output only — no AWS credentials needed),
   `t tunnel` (no arg), `t config get` *(overwrites `terraform/mke4.yaml` / `mke3-config.toml` — expected)*,
   `terraform output`, `kubectl get …`.

## 3. Using the CLI as an agent

- **Credentials**: an AWS SSO profile (`run.sh --aws-profile NAME`, `AWS_PROFILE` in the container) or
  `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in the container environment. Check with
  `aws sts get-caller-identity`. If missing or expired, stop and ask — SSO login
  (`./run.sh --aws-profile NAME --sso-login`) is a device-code flow the user completes in a browser.
  Don't hunt for credentials in files.
- **Configure via `config` only** (bash-sourced; keep `key="value"` syntax, no spaces around `=`).
  Never hand-edit `terraform/terraform.tfvars` — it is regenerated from `config` on every run.
- **Pick the command from the mode** — the variant suffix must be consistent across deploy/destroy:

  | Want | Command |
  |---|---|
  | MKE4k online | `t deploy lab` |
  | MKE3 (upgrade testing) | `t deploy lab mke3` |
  | MKE4k airgap | `t deploy lab airgap` |
  | MKE3 airgap | `t deploy lab mke3-airgap` |
  | Re-run only the install on existing instances | `t deploy cluster [mke3\|airgap\|mke3-airgap]` |
  | Add-ons on a running cluster | `t deploy nfs [mke3]`, `t deploy msr4 [airgap]`, `t deploy kof [full\|lean] [airgap]`, `t deploy k0rdent-ui`, `t deploy child-cluster` (online MKE4k) |

  Some add-ons also change AWS: online `t deploy kof` (Grafana gateway) and `t deploy k0rdent-ui`
  run `terraform apply` for an NLB listener + SG rule; `t destroy k0rdent-ui` does a targeted
  `terraform destroy` of its listener. Treat them like any deploy (rule 1).

  Add-ons, `t config`, `t connect` and `t destroy kof` auto-detect airgap from Terraform outputs.
- **Interactive prompts — plan for them**, since agent shells usually have no TTY:
  - `cluster_name` left at `mke4k-lab`: first deploy asks for an owner name on a TTY; without one it
    silently picks a random suffix. Prefer setting `cluster_name` explicitly (≤ 20 chars, `a-z0-9-`).
  - After `t deploy lab mke3`, `t deploy lab mke3-airgap` and `t deploy lab|cluster airgap`, an
    upgrade-prep `[y/N]` prompt runs. Without a TTY it is skipped (answer = No) and the deploy exits 0;
    if the user wants the prep, they run the deploy step interactively.
  - `t config apply` / `t config edit` require a TTY to confirm and will refuse otherwise. Hand
    those to the user.
- **Long-running**: a full deploy takes tens of minutes (airgap noticeably longer: bundle upload). Run it in the
  background with a generous timeout and stream the log; don't kill and restart it mid-flight
  (Terraform/mkectl are not safely re-entrant mid-run — re-run the *same* command after it ends).
- **Kubeconfig**: `~/.mke/mke.kubeconf` (exported as `KUBECONFIG` by `t`). In airgap it points at
  the internal NLB, so kubectl only works on the bastion (`t connect bastion "kubectl …"`) or through
  a 6443 tunnel (`t tunnel`). MKE3 has no such kubeconfig — use `t gen client-bundle` (`source env.sh`).
- **Reporting back**: after a deploy, run `t show summary` and relay only URLs/IPs/expiry — never the
  password lines; reference credential files by path.

## 4. Changing the code

Layout and flows are documented in `CLAUDE.md` → *Architecture*. Key conventions:

- **`bin/t-commandline.bash`** (single ~7k-line file, `set -euo pipefail`):
  - Entry points are `cmd_<verb>_<noun>[_<variant>]`, dispatched by the `case` block at the bottom.
    A new command needs: the function, a dispatch arm, the usage/help text, a `docs/commands.md` row
    (README only for everyday commands) and the CLAUDE.md list.
  - Log only via `info` / `success` / `warn` / `error` / `die`. Fail loudly with `die "<actionable msg>"`.
  - Reuse helpers instead of re-implementing: `load_config`, `write_tfvars`, `tf_apply`, `tf_output`,
    `detect_deploy_mode`, `ssh_node`, `fetch_current_mke4_yaml`, `mkectl_apply_mode`, `version_gte`.
  - Every feature must work in **all four modes** and on **both OSes** (Ubuntu `ubuntu` user / RHEL
    `ec2-user`, apt vs dnf) — or `die` clearly where unsupported. Airgap nodes have **no internet**:
    anything they need comes from the bastion (Harbor, bind9, Squid, scp'd packages).
  - The bastion has no `jq`; parse remote output with `sed`/`awk`. Pass untrusted strings to remote
    shells base64-encoded (see `_mke3_remote_login_snippet`).
  - Interactive prompts must be guarded with `has_tty` (or `die` with a hint when a TTY is
    mandatory), read `< /dev/tty … || true`, and fall back to a safe non-interactive default.
    An unguarded `read < /dev/tty` kills the whole command under `set -e` when there is no terminal.
- **`config`**: new knobs go in the right section (basic / airgap / advanced) with a comment, a sane
  default, and a row in `docs/configuration.md` (and the CLAUDE.md table if user-facing).
  Thread them through `write_tfvars` + `terraform/variables.tf` if Terraform needs them.
- **Terraform**: tag everything with `Cluster` (the reaper and `cleanup-aws.sh` find resources by
  it). Mode-specific resources are gated with `count` on `airgap_enabled` / `mke3_enabled` /
  `nfs_enabled` / `ccm_enabled`. NLB target groups stay `target_type = "ip"`. Don't change
  instance `user_data` back to a curl/IMDSv1 hostname script (see CLAUDE.md *Node hostnames*).
- **`terraform/reaper.py`**: every destructive call must go through `mutate()` so `DRY_RUN` stays
  read-only; when you add a resource type to Terraform, add its teardown here **and** in
  `bin/cleanup-aws.sh`.
- **New generated/secret files** go into both `.gitignore` and `.dockerignore`.

## 5. Validating changes (no AWS needed)

Run what applies before committing:

```bash
bash -n bin/t-commandline.bash bin/cleanup-aws.sh           # syntax
shellcheck -S warning bin/t-commandline.bash bin/cleanup-aws.sh   # if installed
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false && terraform -chdir=terraform validate
python3 -m py_compile terraform/reaper.py
bash tests/test_container_launcher.sh                        # run.sh + host guard (mock docker)
bash tests/test_expiry_status.sh                             # needs GNU date: run in the container
bash tests/test_lab_local_state.sh                           # needs jq: run in the container
bash tests/test_child_teardown.sh                            # needs jq: run in the container
docker build -t mke4k-lab .                                  # if Docker is available
```

The `tests/` scripts are offline regression checks with mocked `docker`/`terraform`; there is no CI.
End-to-end verification means a real deploy, which needs the user's approval (rule 1). Say plainly in your summary what was and wasn't exercised.

## 6. Commits and docs

- Commit subjects follow the existing style: `<area>: <imperative summary>` (e.g.
  `nfs: fail loudly on client-install errors`, `expiry: …`, `mke3: …`).
- Keep `README.md` + `docs/` (user-facing; detail goes in `docs/`), `CLAUDE.md` (architecture) and this file in sync with behavior
  changes in the same commit.
