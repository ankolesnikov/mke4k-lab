#!/usr/bin/env bash
# Offline checks for per-lab local state: commands run without a lab must not
# create .cluster-id, and 't destroy lab' removes only this lab's local files.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d /tmp/mke4-local-state-test.XXXXXX)"
trap 'rm -r "${test_dir}"' EXIT
mkdir -p "${test_dir}/bin" "${test_dir}/terraform" "${test_dir}/home"
cp "${repo_root}/bin/t-commandline.bash" "${test_dir}/bin/t-commandline.bash"
cp "${repo_root}/config" "${test_dir}/config"
export MKE4K_LAB_CONTAINER=1 HOME="${test_dir}/home"

terraform() {
    case "$*" in
        *" output -json") printf '%s\n' "${MOCK_TF_OUTPUT}" ;;
        *" destroy "*)    printf 'destroyed\n' > "${test_dir}/destroy-called" ;;
        *)                return 0 ;;
    esac
}
kubectl() { return 1; }                       # management cluster unreachable
yq() { sed -n 's/^  name: *//p' "${@: -1}" | head -1; }   # .metadata.name only
export -f terraform kubectl yq
export test_dir

fail() { printf '%s\n' "$*" >&2; exit 1; }

# 1. Commands without a lab never pin a cluster name.
MOCK_TF_OUTPUT='{}'
export MOCK_TF_OUTPUT
for cmd in "status child" "status" "show summary"; do
    rm -f "${test_dir}/.cluster-id"
    # shellcheck disable=SC2086
    "${test_dir}/bin/t-commandline.bash" ${cmd} >/dev/null 2>&1 || true
    [[ ! -e "${test_dir}/.cluster-id" ]] || fail "'t ${cmd}' created .cluster-id without a lab"
done

# 2. 't destroy lab' removes this lab's leftovers, keeps other labs' files.
lb="mke4k-lab-abcd-nlb-1234.elb.eu-central-1.amazonaws.com"
MOCK_TF_OUTPUT="{\"lb_dns_name\":{\"value\":\"${lb}\"}}"
echo abcd > "${test_dir}/.cluster-id"
for f in mke4.yaml nodes.yaml mke3_credentials.txt registry_credentials.txt registry_ca.crt \
         msr4_credentials.txt msr4_tls.key k0rdent_ui_credentials.txt terraform.tfstate aws_private.pem; do
    echo x > "${test_dir}/terraform/${f}"
done
printf 'metadata:\n  name: mke4k-lab-abcd\n' > "${test_dir}/terraform/launchpad.yaml"
mkdir -p "${HOME}/.mke" "${HOME}/.mirantis-launchpad/cluster/mke4k-lab-abcd/bundle/admin" \
         "${HOME}/.mirantis-launchpad/cluster/other-lab/bundle/admin"
printf 'server: https://%s:6443\n' "${lb}" > "${HOME}/.mke/mke.kubeconf"

"${test_dir}/bin/t-commandline.bash" destroy lab >/dev/null 2>&1 || fail "'t destroy lab' failed"
[[ -f "${test_dir}/destroy-called" ]] || fail "terraform destroy was not called"
for f in mke4.yaml nodes.yaml launchpad.yaml mke3_credentials.txt registry_credentials.txt \
         registry_ca.crt msr4_credentials.txt msr4_tls.key k0rdent_ui_credentials.txt; do
    [[ ! -e "${test_dir}/terraform/${f}" ]] || fail "terraform/${f} survived 't destroy lab'"
done
# tfstate is never touched by t (aws_private.pem is removed by terraform
# destroy itself as a local_file resource, which the mock doesn't model).
[[ -e "${test_dir}/terraform/terraform.tfstate" ]] || fail "terraform/terraform.tfstate must not be removed by t"
[[ ! -e "${HOME}/.mke/mke.kubeconf" ]] || fail "this lab's kubeconfig survived"
[[ ! -e "${HOME}/.mirantis-launchpad/cluster/mke4k-lab-abcd" ]] || fail "this lab's client bundle survived"
[[ -d "${HOME}/.mirantis-launchpad/cluster/other-lab" ]] || fail "another lab's client bundle was removed"

# 3. A kubeconfig for a different lab is left alone.
printf 'server: https://some-other-lab-nlb:6443\n' > "${HOME}/.mke/mke.kubeconf"
"${test_dir}/bin/t-commandline.bash" destroy lab >/dev/null 2>&1 || fail "second 't destroy lab' failed"
[[ -e "${HOME}/.mke/mke.kubeconf" ]] || fail "another lab's kubeconfig was removed"

echo "lab local state tests passed"
