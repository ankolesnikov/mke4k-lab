#!/usr/bin/env bash
# Offline checks for the child-cluster guard in 't destroy lab': it must never
# tear down the management cluster while CAPA may still own child resources.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d /tmp/mke4-child-teardown-test.XXXXXX)"
trap 'rm -r "${test_dir}"' EXIT
mkdir -p "${test_dir}/bin" "${test_dir}/terraform" "${test_dir}/home/.mke"
cp "${repo_root}/bin/t-commandline.bash" "${test_dir}/bin/t-commandline.bash"
cp "${repo_root}/config" "${test_dir}/config"
export HOME="${test_dir}/home"
export test_dir lb="mke4k-lab-abcd-nlb-1.elb.eu-central-1.amazonaws.com"

terraform() {
    case "$*" in
        *" output -json") printf '{"lb_dns_name":{"value":"%s"}}\n' "${lb}" ;;
        *" destroy "*)    : > "${test_dir}/destroy-called" ;;
        *)                return 0 ;;
    esac
}
# Stateful kubectl stub. MOCK_CRD: present | absent | error.
# MOCK_CD_LEFT: how many more lookups still see the child's ClusterDeployment.
kubectl() {
    case "$*" in
        *"get nodes"*) return 0 ;;
        *"get crd"*)
            case "${MOCK_CRD}" in
                present) echo "customresourcedefinition.apiextensions.k8s.io/mkechildconfigs.mke.mirantis.com" ;;
                absent)  ;;
                error)   return 1 ;;
            esac ;;
        *"get clusterdeployments"*)
            local n; n="$(cat "${test_dir}/cd-left")"
            if (( n > 0 )); then
                echo "clusterdeployment.k0rdent.mirantis.com/mke4k-lab-abcd-child"
                echo $(( n - 1 )) > "${test_dir}/cd-left"
            fi ;;
        *"delete mkechildconfig"*) : > "${test_dir}/child-delete-called" ;;
        *) return 0 ;;   # mkechildconfig list/get, clusters, secrets: none
    esac
}
aws() { return 0; }
sleep() { :; }
export -f terraform kubectl aws sleep

fail() { printf '%s\n' "$*" >&2; exit 1; }
reset() {
    rm -f "${test_dir}/destroy-called" "${test_dir}/child-delete-called"
    echo abcd > "${test_dir}/.cluster-id"
    printf 'server: https://%s:6443\n' "${lb}" > "${HOME}/.mke/mke.kubeconf"
    echo "${MOCK_CD_LEFT:-0}" > "${test_dir}/cd-left"
}

# 1. CRD lookup fails while a child is recorded -> refuse, keep the record.
MOCK_CRD=error MOCK_CD_LEFT=0; export MOCK_CRD; reset
echo mke4k-lab-abcd-child > "${test_dir}/.child-cluster"
if "${test_dir}/bin/t-commandline.bash" destroy lab >/dev/null 2>&1; then
    fail "'t destroy lab' succeeded although the child CRD lookup failed"
fi
[[ ! -e "${test_dir}/destroy-called" ]] || fail "terraform destroy ran despite the failed CRD lookup"
[[ -f "${test_dir}/.child-cluster" ]] || fail ".child-cluster was dropped on a failed CRD lookup"

# 1b. CRD lookup fails with no local record -> still refuse (the record can be
#     missing, or the child was created outside t).
MOCK_CRD=error MOCK_CD_LEFT=0; reset
rm -f "${test_dir}/.child-cluster"
if "${test_dir}/bin/t-commandline.bash" destroy lab >/dev/null 2>&1; then
    fail "'t destroy lab' succeeded on a failed CRD lookup without a child record"
fi
[[ ! -e "${test_dir}/destroy-called" ]] || fail "terraform destroy ran despite the failed CRD lookup (no record)"

# 2. Interrupted delete: MkeChildConfig gone, ClusterDeployment still there ->
#    wait for it before terraform destroy.
MOCK_CRD=present MOCK_CD_LEFT=2; reset
"${test_dir}/bin/t-commandline.bash" destroy lab >/dev/null 2>&1 || fail "'t destroy lab' failed in the residual-objects case"
[[ -f "${test_dir}/child-delete-called" ]] || fail "residual CAPI objects were not waited for"
[[ "$(cat "${test_dir}/cd-left")" == 0 ]] || fail "terraform destroy ran before the ClusterDeployment was gone"
[[ -f "${test_dir}/destroy-called" ]] || fail "terraform destroy did not run after the child was gone"
[[ ! -e "${test_dir}/.child-cluster" ]] || fail ".child-cluster survived a completed delete"

# 3. CRD confirmed absent -> no child possible, destroy proceeds.
MOCK_CRD=absent MOCK_CD_LEFT=0; reset
echo mke4k-lab-abcd-child > "${test_dir}/.child-cluster"
"${test_dir}/bin/t-commandline.bash" destroy lab >/dev/null 2>&1 || fail "'t destroy lab' failed with the CRD absent"
[[ -f "${test_dir}/destroy-called" ]] || fail "terraform destroy did not run with the CRD absent"

echo "child teardown tests passed"
