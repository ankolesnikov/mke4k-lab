#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d /tmp/mke4-expiry-test.XXXXXX)"
trap 'rm -r "${test_dir}"' EXIT
mkdir -p "${test_dir}/bin" "${test_dir}/terraform"
cp "${repo_root}/bin/t-commandline.bash" "${test_dir}/bin/t-commandline.bash"
export MKE4K_LAB_CONTAINER=1

terraform() {
    [[ "$*" == *" output -json" ]] || return 2
    printf '%s\n' "${MOCK_TF_OUTPUT}"
}
export -f terraform

assert_contains() {
    [[ "$1" == *"$2"* ]] || {
        printf 'Expected output to contain: %s\nActual output: %s\n' "$2" "$1" >&2
        exit 1
    }
}

MOCK_TF_OUTPUT='{}'
export MOCK_TF_OUTPUT
output="$("${test_dir}/bin/t-commandline.bash" expiry status)"
assert_contains "${output}" 'No lab currently provisioned'
[[ ! -e "${test_dir}/.cluster-id" ]]

if "${test_dir}/bin/t-commandline.bash" expiry >"${test_dir}/bare-expiry-output" 2>&1; then
    echo 'Bare t expiry unexpectedly succeeded without a lab' >&2
    exit 1
fi
output="$(<"${test_dir}/bare-expiry-output")"
assert_contains "${output}" 'No lab found'
[[ ! -e "${test_dir}/.cluster-id" ]]

MOCK_TF_OUTPUT='{"expiry_time":{"value":""},"lb_dns_name":{"value":"lab.example"}}'
output="$("${test_dir}/bin/t-commandline.bash" expiry status)"
assert_contains "${output}" 'auto-expiry is disabled'

MOCK_TF_OUTPUT='{"expiry_time":{"value":"2099-01-01T00:00:00Z"}}'
output="$("${test_dir}/bin/t-commandline.bash" expiry status)"
assert_contains "${output}" 'Lab expires in'
assert_contains "${output}" '2099-01-01 00:00 UTC'

MOCK_TF_OUTPUT='{"expiry_time":{"value":"2020-01-01T00:00:00Z"}}'
output="$("${test_dir}/bin/t-commandline.bash" expiry status)"
assert_contains "${output}" 'may already have been deleted'

printf 'expiry_dry_run = true\n' >"${test_dir}/terraform/terraform.tfvars"
output="$("${test_dir}/bin/t-commandline.bash" expiry status)"
assert_contains "${output}" 'expiry_dry_run is on'

[[ ! -e "${test_dir}/.cluster-id" ]]
echo 'expiry status tests passed'
