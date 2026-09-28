# TODO

Backlog of proposed improvements, not yet implemented. See `improvements.md` for a log of changes already made.

## 1. Support bundle / sosreport collection

Add a way to pull a support bundle from the deployed MKE3/MKE4k products, plus an `sosreport` from cluster nodes (controllers/workers/bastion). Likely a new `t` subcommand (e.g. `t support-bundle` or `t diagnostics`).

Two phases:
1. **Collect** — run `dsinfo` directly against the lab (on demand; there is no existing health-check/diagnostics command or trigger point today — `t status` only runs `kubectl get nodes`, see `bin/t-commandline.bash`) alongside `sosreport`, so diagnostics aren't lost before `t destroy lab`. Needs to define: execution host, node selection, privilege requirements, artifact destination/retention, partial-failure handling, and secret redaction before collection. An automatic "after a failed health check" trigger is a later addition once a health-check command exists, not part of this first cut.
2. **Triage** — once collection is routine, add lightweight pattern-based flagging of known MKE/MSR failure signatures (cert expiry, etcd health, node NotReady reasons) against the collected output. Full general-purpose analysis of `dsinfo`'s broad, unstructured output is a much bigger project and out of scope for a first cut.

## 2. OS chooser

Add an interactive picker for cluster node OS, enumerating the actual supported pairs: Ubuntu 22.04/24.04, RHEL 8.10/9.6. `os_name` is validated against `ubuntu|redhat` in `terraform/variables.tf`, but `os_version` is only validated there as a numeric-looking string — the real supported-pairs matrix is checked separately (warning-only) in `bin/t-commandline.bash`, so the picker is what should enforce the real matrix. Precedent for an interactive prompt exists in `bin/t-commandline.bash` (`deploy lab`/`deploy instances`), but note it's an owner/name-suffix prompt shown only when `cluster_name` is still the default — not an existing OS/version picker to copy directly.

## 3. Configurator

Split into two kinds of work rather than one item:
- **Guided editor for existing settings** — MKE version, MCR version, manager/worker node counts, and MSR4 replica count already exist as `config` values (`config:27-46`, `config:52-63`); this part is a guided-prompt UX layer over settings that already work today.
- **New capabilities (not implemented yet)** — MSR 2.x version/workflow does not exist in the repo at all; MSR4 mode is not actually selectable — MKE3 install currently hardcodes Kubernetes as the orchestrator (`bin/t-commandline.bash:2647-2653`). These need their own scoped items with acceptance criteria, not just a config toggle, since they're new install paths.

## 4. MKE/MSR install credentials

Scope per product rather than one generic "MKE/MSR credentials" item — current state differs a lot by product:
- **MKE3**: username is already configurable (`config:142-143`); password is generated (`bin/t-commandline.bash:2586-2595`).
- **MSR4**: username is fixed to `admin`; password is generated (`bin/t-commandline.bash:255-270`).
- **MKE4k**: no generated-admin-credential path exists at all today (`bin/t-commandline.bash:2413-2460`).

Needs: exact products/fields to expose, precedence over existing generated-credential files, a non-interactive input mechanism (env var/config), and secret-storage rules (not landing in tracked files or shell history).

## 5. First-run behavior for empty bind-mounted directories

`run.sh` creates `.mke`, `.mirantis-launchpad`, and `.aws` on the host and bind-mounts them into the container (`run.sh:70-77`, `run.sh:98-103`) — those mounts hide whatever the image has at the same paths, so "the image fills them" isn't accurate as originally phrased. The three directories also hold different kinds of content and need different first-run behavior, not one generic "seed with default data" policy:
- `.mke` / `.mirantis-launchpad` — generated deployment artifacts (kubeconfig, client bundle); a sensible first-run default here is plausible (e.g. placeholder/help content) but needs defining.
- `.aws` — user-specific SSO configuration/cache; generic seeding here is unsafe/inappropriate and should be explicitly out of scope — this directory should stay empty until the user runs `--sso-configure`/`--sso-login`.

## 6. Named lab workspaces (run multiple labs from one checkout)

Today, everything that isolates one lab from another — `.aws`, `.mke`, `.mirantis-launchpad`, `terraform.tfstate`/`terraform.tfvars`, `config`, `.cluster-id`/`.owner`/`.expiry-*` — lives directly at the repo root, scoped to `repo_dir` (`run.sh`). Running two labs at once means cloning the whole checkout a second time, which duplicates code/git history for no reason and is easy to lose track of.

Add a named workspace concept instead — e.g. `run.sh --lab NAME` / `t --lab NAME` — that namespaces all of the above under `labs/<name>/` in a single checkout, similar in spirit to `terraform workspace`. Touches `load_config`, `write_tfvars`, and the bind-mount paths in `run.sh`; a real architecture change, not a one-liner.

**Acceptance criterion:** must preserve the property the current single-lab model already has — the container is fully disposable (`docker run --rm`; nothing lab-specific lives in the container's writable layer), so exiting or deleting it and starting a fresh one with `--lab NAME` returns to that exact lab's state (Terraform state, generated files, kubeconfig, SSO cache) unchanged. This should hold per named lab, not just for the single default workspace.
