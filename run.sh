#!/usr/bin/env bash
set -euo pipefail

script_path="${BASH_SOURCE[0]}"
symlink_count=0
while [[ -L "${script_path}" ]]; do
    if (( ++symlink_count > 40 )); then
        printf 'Too many symlinks while resolving %s.\n' "$0" >&2
        exit 1
    fi
    script_dir="$(cd -P "$(dirname "${script_path}")" && pwd)"
    link_target="$(readlink "${script_path}")"
    if [[ "${link_target}" = /* ]]; then
        script_path="${link_target}"
    else
        script_path="${script_dir}/${link_target}"
    fi
done
repo_dir="$(cd -P "$(dirname "${script_path}")" && pwd)"
if [[ ! -f "${repo_dir}/.bashrc" ]]; then
    printf 'Missing %s/.bashrc; run this script from a complete repository checkout.\n' "${repo_dir}" >&2
    exit 1
fi

aws_profile=""
sso_action=""
while (( $# > 0 )); do
    case "$1" in
        --aws-profile)
            if (( $# < 2 )) || [[ -z "$2" || "$2" = -* ]]; then
                printf 'Usage: %s --aws-profile NAME [--sso-login] [-- bash-args...]\n' "$0" >&2
                exit 2
            fi
            if [[ -n "${aws_profile}" ]]; then
                printf 'Choose only one AWS profile.\n' >&2
                exit 2
            fi
            aws_profile="$2"
            shift 2
            ;;
        --sso-configure|--sso-login)
            if [[ -n "${sso_action}" ]]; then
                printf 'Choose only one SSO action.\n' >&2
                exit 2
            fi
            sso_action="$1"
            shift
            ;;
        --)
            shift
            break
            ;;
        *) break ;;
    esac
done

if [[ -n "${sso_action}" && $# -gt 0 ]]; then
    printf 'SSO actions cannot be combined with Bash arguments.\n' >&2
    exit 2
fi
if [[ "${sso_action}" == "--sso-login" && -z "${aws_profile}" ]]; then
    printf 'SSO login requires --aws-profile NAME.\n' >&2
    exit 2
fi
if [[ "${sso_action}" == "--sso-configure" && -n "${aws_profile}" ]]; then
    printf 'SSO configuration asks for a profile name; do not pass --aws-profile.\n' >&2
    exit 2
fi

for private_dir in .mke .mirantis-launchpad .aws; do
    if [[ -L "${repo_dir}/${private_dir}" ]]; then
        printf 'Refusing symlinked %s/%s; use a private project-local directory.\n' "${repo_dir}" "${private_dir}" >&2
        exit 1
    fi
done
mkdir -m 700 -p "${repo_dir}/.mke" "${repo_dir}/.mirantis-launchpad" "${repo_dir}/.aws"
chmod 700 "${repo_dir}/.mke" "${repo_dir}/.mirantis-launchpad" "${repo_dir}/.aws"

docker_env=(-e MKE4K_LAB_CONTAINER=1)
if [[ -n "${aws_profile}" ]]; then
    docker_env+=(-e "AWS_PROFILE=${aws_profile}")
fi

case "${sso_action}" in
    --sso-configure)
        set -- -c 'exec aws configure sso --use-device-code'
        ;;
    --sso-login)
        set -- -c 'exec aws sso login --no-browser --use-device-code --profile "$1"' _ "${aws_profile}"
        ;;
esac

docker_tty=(-i)
if [[ -t 0 && -t 1 ]]; then
    docker_tty+=(-t)
fi

exec docker run --rm "${docker_tty[@]}" "${docker_env[@]}" \
    -v "${repo_dir}:/mke4k-lab" \
    -v "${repo_dir}/.mke:/root/.mke" \
    -v "${repo_dir}/.mirantis-launchpad:/root/.mirantis-launchpad" \
    -v "${repo_dir}/.aws:/root/.aws" \
    -v "${repo_dir}/.bashrc:/root/.bashrc:ro" \
    -p 3000:3000 -p 8443:8443 -p 8444:8444 -p 8445:8445 \
    registry.ci.mirantis.com/ajagiello/mke4k-lab:latest "$@"
