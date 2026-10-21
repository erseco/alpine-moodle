#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
log=$(mktemp)
trap 'rm -f "$log"' EXIT
export log
export remote_tags=$'hash refs/tags/v5.3.3\nhash refs/tags/v5.3.9\nhash refs/tags/v5.3.10\nhash refs/tags/v5.3.11-beta\nhash refs/tags/v5.4.0\nhash refs/tags/v5.2.99\nhash refs/tags/v4.5.14'
git() { [[ "${fail_git:-false}" == false ]] || return 1; printf '%s\n' "$remote_tags"; }
docker() { printf '%s\n' "$*" >> "$log"; [[ "${fail_docker:-false}" == false ]]; }
export -f git docker
digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
[[ $(bash scripts/release-policy.sh --newest) == v5.3.10 ]]
bash scripts/promote-latest.sh v5.3.10 "$digest" example/moodle
[[ $(wc -l < "$log") -eq 2 ]]
grep -qx "buildx imagetools create --prefer-index=false --tag example/moodle:latest example/moodle@$digest" "$log"
grep -qx "buildx imagetools create --prefer-index=false --tag ghcr.io/example/moodle:latest ghcr.io/example/moodle@$digest" "$log"
# Late older builds, other stable lines and prereleases must leave latest alone.
for version in v5.3.9 v5.3.3 v5.2.99 v4.5.14 v5.3.11-beta v5.3.11-rc1 v5.4.0 main; do
  bash scripts/promote-latest.sh "$version" "$digest" example/moodle
done
[[ $(wc -l < "$log") -eq 2 ]]
# A newer release arriving while the build runs invalidates its old eligibility.
export remote_tags="$remote_tags"$'\nhash refs/tags/v5.3.11'
bash scripts/promote-latest.sh v5.3.10 "$digest" example/moodle
[[ $(wc -l < "$log") -eq 2 ]]
must_fail() {
  if bash scripts/promote-latest.sh "$@"; then
    echo 'Expected promotion to fail' >&2; exit 1
  fi
}
must_fail v5.3.11 'sha256:invalid' example/moodle
must_fail v5.3.11 "$digest" 'example/moodle;id'
must_fail 'v5.3.11;id' "$digest" example/moodle
export fail_git=true
must_fail v5.3.11 "$digest" example/moodle
export fail_git=false remote_tags=''
bash scripts/promote-latest.sh v5.3.11 "$digest" example/moodle
[[ $(wc -l < "$log") -eq 2 ]]
export remote_tags='hash refs/tags/v5.3.11' fail_docker=true
must_fail v5.3.11 "$digest" example/moodle
[[ $(wc -l < "$log") -eq 3 ]] # Stop on first failed registry, do not hide it.
echo 'Latest promotion: digest copy, late builds, new releases and failure guards passed.'
