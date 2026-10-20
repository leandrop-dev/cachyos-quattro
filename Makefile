SHELLCHECK_FILES := $(wildcard bin/* lib/*.sh package/libexec/* package/stubs/* tools/* tests/unit/*.bash tests/unit/*.bats)

.PHONY: check lint test

check: lint test

lint:
	@if [ -n "$(SHELLCHECK_FILES)" ]; then shellcheck -x -S style $(SHELLCHECK_FILES); fi

test:
	bats -r tests/unit
