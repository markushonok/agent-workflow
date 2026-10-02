#!/usr/bin/env bash

set -euo pipefail

if (( $# == 0 )); then
	echo "Usage: ${0##*/} <pathspec> [<pathspec> ...]" >&2
	exit 2
fi

root="$(git rev-parse --show-toplevel)"
cd "$root"

	trim()
	{
		local file="$1" content

		[ -f "$file" ] && [ ! -L "$file" ] || return 0

		# Skip binary files.
		grep -Iq -- '' "$file" || return 0

		# Drop trailing newlines and carriage returns.
		content="$(cat -- "$file")"
		while :; do
			case "$content" in
				*$'\r' | *$'\n') content="${content%?}" ;;
				*) break ;;
			esac
		done
		printf '%s' "$content" > "$file"
	}

while IFS= read -r -d '' file; do
	trim "$file"
done < <(
	git diff --name-only -z --diff-filter=ACMR -- "$@"
	git diff --cached --name-only -z --diff-filter=ACMR -- "$@"
	git ls-files --others --exclude-standard -z -- "$@"
)