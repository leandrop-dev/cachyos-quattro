SHELLCHECK_FILES := $(wildcard bin/* lib/*.sh package/libexec/* package/*.install tools/* tests/unit/*.bash tests/unit/*.bats tests/vm/*.sh tests/vm/scenarios/*.sh tests/vm/guest/*.sh)

.PHONY: check lint test

check: lint test

lint:
	@if [ -n "$(SHELLCHECK_FILES)" ]; then shellcheck -x -S style $(SHELLCHECK_FILES); fi
	actionlint .github/workflows/*.yml

test:
	bats -r tests/unit
