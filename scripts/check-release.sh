#!/usr/bin/env bash
set -euo pipefail

version="$(cat VERSION)"
[[ "${RELEASE_TAG:-}" == "v$version" ]] || {
	echo "Il tag deve corrispondere a v<VERSION>" >&2
	exit 1
}
[[ "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || exit 1
git rev-parse --verify "refs/tags/$RELEASE_TAG" >/dev/null
[[ "$(git rev-parse HEAD)" == "$(git rev-list -n 1 "$RELEASE_TAG")" ]] || {
	echo "Il checkout non corrisponde al tag richiesto" >&2
	exit 1
}
