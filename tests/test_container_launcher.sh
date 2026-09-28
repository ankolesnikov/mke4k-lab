#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d /tmp/mke4-launcher-test.XXXXXX)"
test_dir="$(cd -P "${test_dir}" && pwd)"
trap 'rm -r "${test_dir}"' EXIT
mkdir -p "${test_dir}/repo" "${test_dir}/bin" "${test_dir}/links"
cp "${repo_root}/run.sh" "${repo_root}/.bashrc" "${test_dir}/repo/"
ln -s "${repo_root}/tests/mock_docker.sh" "${test_dir}/bin/docker"
ln -s "../repo/run.sh" "${test_dir}/links/mke4-lab"
ln -s "${test_dir}/repo/run.sh" "${test_dir}/links/mke4-lab-absolute"

assert_line() {
    printf '%s\n' "$1" | grep -Fqx -- "$2" || {
        printf 'Expected Docker argument: %s\nActual arguments:\n%s\n' "$2" "$1" >&2
        exit 1
    }
}

launcher="${test_dir}/links/mke4-lab"
output="$(cd /tmp && PATH="${test_dir}/bin:${PATH}" "${launcher}")"
assert_line "${output}" "${test_dir}/repo:/mke4k-lab"
assert_line "${output}" "${test_dir}/repo/.aws:/root/.aws"
assert_line "${output}" 'MKE4K_LAB_CONTAINER=1'
output="$(cd /tmp && PATH="${test_dir}/links:${test_dir}/bin:${PATH}" mke4-lab)"
assert_line "${output}" "${test_dir}/repo:/mke4k-lab"
output="$(PATH="${test_dir}/bin:${PATH}" "${test_dir}/links/mke4-lab-absolute")"
assert_line "${output}" "${test_dir}/repo:/mke4k-lab"
[[ -d "${test_dir}/repo/.aws" ]]
for private_dir in .mke .mirantis-launchpad .aws; do
    permissions="$(stat -c '%a' "${test_dir}/repo/${private_dir}" 2>/dev/null || stat -f '%Lp' "${test_dir}/repo/${private_dir}")"
    [[ "${permissions}" == 700 ]]
done

output="$(PATH="${test_dir}/bin:${PATH}" "${launcher}" --aws-profile lab-dev --sso-login)"
assert_line "${output}" 'AWS_PROFILE=lab-dev'
assert_line "${output}" 'exec aws sso login --no-browser --use-device-code --profile "$1"'
assert_line "${output}" 'lab-dev'

output="$(PATH="${test_dir}/bin:${PATH}" "${launcher}" --sso-configure)"
assert_line "${output}" 'exec aws configure sso --use-device-code'

output="$(PATH="${test_dir}/bin:${PATH}" "${launcher}" -- -lc 'printf hello')"
assert_line "${output}" '-lc'
assert_line "${output}" 'printf hello'

output="$(AWS_ACCESS_KEY_ID=dummy AWS_SECRET_ACCESS_KEY=dummy PATH="${test_dir}/bin:${PATH}" "${launcher}" --aws-profile lab-dev)"
[[ "${output}" != *AWS_ACCESS_KEY_ID* && "${output}" != *AWS_SECRET_ACCESS_KEY* ]]

if PATH="${test_dir}/bin:${PATH}" "${launcher}" --sso-login >"${test_dir}/invalid" 2>&1; then
    printf 'SSO login unexpectedly accepted a missing profile.\n' >&2
    exit 1
fi
grep -Fq 'requires --aws-profile NAME' "${test_dir}/invalid"

if PATH="${test_dir}/bin:${PATH}" "${launcher}" --aws-profile lab-dev --aws-profile other >"${test_dir}/invalid" 2>&1; then
    printf 'Launcher unexpectedly accepted duplicate AWS profiles.\n' >&2
    exit 1
fi
grep -Fq 'Choose only one AWS profile' "${test_dir}/invalid"

if PATH="${test_dir}/bin:${PATH}" "${launcher}" --aws-profile lab-dev --sso-configure >"${test_dir}/invalid" 2>&1; then
    printf 'Launcher unexpectedly accepted a profile with SSO configuration.\n' >&2
    exit 1
fi
grep -Fq 'do not pass --aws-profile' "${test_dir}/invalid"

mv "${test_dir}/repo/.aws" "${test_dir}/aws-real"
ln -s "${test_dir}/aws-real" "${test_dir}/repo/.aws"
if PATH="${test_dir}/bin:${PATH}" "${launcher}" >"${test_dir}/invalid" 2>&1; then
    printf 'Launcher unexpectedly accepted a symlinked AWS directory.\n' >&2
    exit 1
fi
grep -Fq 'Refusing symlinked' "${test_dir}/invalid"

if env -u MKE4K_LAB_CONTAINER "${repo_root}/bin/t" help >"${test_dir}/host-output" 2>&1; then
    printf 't unexpectedly ran on the host.\n' >&2
    exit 1
fi
grep -Fq 't must run inside the MKE4 Lab container' "${test_dir}/host-output"
MKE4K_LAB_CONTAINER=1 "${repo_root}/bin/t" help >"${test_dir}/container-output"
grep -Fq 'deploy lab' "${test_dir}/container-output"
grep -Fq 'selected SSO profile' "${test_dir}/container-output"

printf 'container launcher tests passed\n'
