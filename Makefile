.PHONY: test lint check-tools check dist

test:
	bats tests
	python3 -B -m unittest discover -s tests -p 'test_*.py'

lint:
	shellcheck -x bin/*.sh lib/*.sh tests/*.bash scripts/*.sh completions/eng.bash
	zsh -n completions/_eng
	python3 -c 'import ast, pathlib; [ast.parse(p.read_text()) for p in [*pathlib.Path("lib").glob("*.py"), *pathlib.Path("scripts").glob("*.py")]]'

check-tools:
	.tools/bin/actionlint
	.tools/bin/gitleaks dir . --redact --no-banner

check: lint test check-tools

dist:
	python3 scripts/package.py
