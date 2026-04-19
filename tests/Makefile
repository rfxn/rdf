# tests/Makefile — RDF adapter test suite
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# BATS runner: uses system bats (not batsman submodule).
# Rationale: RDF is governance/scripts, not a shipped Linux daemon.
# No multi-distro container matrix is needed. The CI workflow
# (Phase 9, .github/workflows/ci.yml) installs bats via apt on ubuntu-latest.
#
# Install bats locally:
#   apt install bats          (Debian/Ubuntu)
#   brew install bats-core    (macOS)

BATS ?= $(shell command -v bats 2>/dev/null)
TESTS_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: test lint help

test: _bats_check
	$(BATS) $(TESTS_DIR)adapter.bats

lint: _bats_check
	shellcheck $(TESTS_DIR)adapter.bats

help:
	@echo "Usage: make -C tests [target]"
	@echo ""
	@echo "Targets:"
	@echo "  test   Run BATS adapter tests (default)"
	@echo "  lint   Run shellcheck on test files"
	@echo "  help   Show this help"
	@echo ""
	@echo "Requirements:"
	@echo "  bats   apt install bats / brew install bats-core"
	@echo "  jq     apt install jq"

_bats_check:
	@if [ -z "$(BATS)" ]; then \
		echo "error: bats not found in PATH"; \
		echo "  Install: apt install bats  (Debian/Ubuntu)"; \
		echo "           brew install bats-core  (macOS)"; \
		exit 1; \
	fi
