SHELL := /bin/bash
BATS := ./tests/bats/bin/bats
SHELLCHECK := shellcheck

.PHONY: test lint test-unit install-bats clean

# Default: lint + unit tests
test: lint test-unit

# Install bats-core locally
install-bats:
	@if [ ! -d tests/bats ]; then \
		echo "Installing bats-core..."; \
		git clone --depth 1 https://github.com/bats-core/bats-core.git tests/bats; \
	fi

# Static analysis with shellcheck
lint:
	$(SHELLCHECK) -s bash entrypoint.sh healthcheck.sh

# Unit tests (no Docker required)
test-unit: install-bats
	$(BATS) tests/test_logging.bats tests/test_validate_env.bats

# Build Docker image (smoke test)
build:
	docker build -t agent-container .

clean:
	rm -rf tests/bats
