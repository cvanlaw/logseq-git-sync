.PHONY: help install uninstall status logs lint test clean

PREFIX ?= /usr/local
CONFIG_DIR := $(HOME)/.config/logseq-git-sync
LAUNCH_AGENTS := $(HOME)/Library/LaunchAgents

help:
	@echo "logseq-git-sync"
	@echo ""
	@echo "Targets:"
	@echo "  install     Install scripts and create config directory"
	@echo "  uninstall   Remove scripts and stop services"
	@echo "  add-graph   Add a new Logseq graph (interactive)"
	@echo "  status      Show service status"
	@echo "  logs        Tail logs"
	@echo "  lint        Run shellcheck on all scripts"
	@echo "  test        Run tests"
	@echo "  clean       Remove test artifacts"

install: check-deps
	@echo "Installing logseq-git-sync..."
	@mkdir -p $(CONFIG_DIR)/graphs
	@mkdir -p $(CONFIG_DIR)/logs
	@mkdir -p $(CONFIG_DIR)/conflicts
	@mkdir -p $(PREFIX)/bin
	@cp scripts/logseq-sync $(PREFIX)/bin/
	@cp scripts/logseq-sync-*.sh $(PREFIX)/bin/
	@chmod +x $(PREFIX)/bin/logseq-sync*
	@if [ ! -f $(CONFIG_DIR)/config ]; then \
		cp templates/config.template $(CONFIG_DIR)/config; \
	fi
	@echo "Installed. Run 'logseq-sync add-graph <path>' to add a graph."

uninstall:
	@echo "Uninstalling logseq-git-sync..."
	@logseq-sync stop-all 2>/dev/null || true
	@rm -f $(PREFIX)/bin/logseq-sync*
	@rm -f $(LAUNCH_AGENTS)/com.logseq-sync.*.plist
	@echo "Uninstalled. Config preserved at $(CONFIG_DIR)"

check-deps:
	@command -v fswatch >/dev/null || (echo "Error: fswatch not found. Run: brew install fswatch" && exit 1)
	@command -v git >/dev/null || (echo "Error: git not found" && exit 1)

add-graph:
	@logseq-sync add-graph

status:
	@logseq-sync status

logs:
	@logseq-sync logs

lint:
	@shellcheck scripts/logseq-sync scripts/logseq-sync-*.sh

test:
	@bats tests/

clean:
	@rm -rf test-tmp/
