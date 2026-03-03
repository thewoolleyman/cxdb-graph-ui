.PHONY: build release build-all test clippy fmt fmt-check check clean run \
        ui-install ui-build ui-dev ui-lint ui-test-unit ui-test-e2e precommit

# Rust server targets
build:
	cd server && cargo build

release:
	cd server && cargo build --release

test:
	cd server && cargo test

clippy:
	cd server && cargo clippy -- -D warnings

fmt:
	cd server && cargo fmt

fmt-check:
	cd server && cargo fmt --check

check:
	cd server && cargo check

clean:
	cd server && cargo clean

run:
	cd server && cargo run --

# Frontend targets
ui-install:
	cd frontend && pnpm install

ui-build:
	cd frontend && pnpm build

ui-dev:
	cd frontend && pnpm dev

ui-lint:
	cd frontend && pnpm lint

ui-test-unit:
	cd frontend && pnpm test:unit

ui-test-e2e:
	cd frontend && pnpm test:e2e

# Full build (frontend assets must be built before Rust server embeds them)
build-all:
	$(MAKE) ui-build
	$(MAKE) build

# Pre-commit validation gate
precommit:
	$(MAKE) fmt-check
	$(MAKE) clippy
	$(MAKE) test
	$(MAKE) ui-lint
	$(MAKE) ui-test-unit
