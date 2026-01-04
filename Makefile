.PHONY: all test clean install update build snapshot format anvil deploy-anvil deploy-sepolia deploy-polygon deploy-arbitrum verify help

# Load environment variables
include .env
export

# Default target
all: clean install update build test

# Help target
help:
	@echo "Vyqno Stablecoin Protocol - Available Commands"
	@echo "=============================================="
	@echo ""
	@echo "Build & Setup:"
	@echo "  make install        - Install dependencies"
	@echo "  make update         - Update dependencies"
	@echo "  make build          - Build contracts"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make format         - Format code with forge fmt"
	@echo ""
	@echo "Testing:"
	@echo "  make test           - Run all tests"
	@echo "  make test-unit      - Run unit tests only"
	@echo "  make test-fuzz      - Run fuzz tests"
	@echo "  make test-invariant - Run invariant tests"
	@echo "  make test-integration - Run integration tests"
	@echo "  make test-advanced  - Run advanced edge case tests"
	@echo "  make test-gas       - Run tests with gas reporting"
	@echo "  make test-quick     - Run quick unit tests"
	@echo ""
	@echo "Coverage & Analysis:"
	@echo "  make coverage       - Generate coverage report"
	@echo "  make coverage-html  - Generate HTML coverage report"
	@echo "  make snapshot       - Generate gas snapshot"
	@echo "  make snapshot-diff  - Compare gas snapshots"
	@echo "  make slither        - Run Slither static analysis"
	@echo ""
	@echo "Deployment:"
	@echo "  make anvil          - Start local Anvil node"
	@echo "  make deploy-anvil   - Deploy to local Anvil"
	@echo "  make deploy-sepolia - Deploy to Sepolia testnet"
	@echo "  make deploy-polygon - Deploy to Polygon mainnet (with confirmation)"
	@echo "  make deploy-arbitrum - Deploy to Arbitrum mainnet (with confirmation)"
	@echo ""
	@echo "Verification:"
	@echo "  make verify-sepolia CONTRACT=<address>"
	@echo "  make verify-polygon CONTRACT=<address>"
	@echo "  make verify-arbitrum CONTRACT=<address>"

# Installation and setup
install:
	forge install

update:
	forge update

# Building
build:
	forge build

clean:
	forge clean

# Testing
test:
	forge test -vv

test-unit:
	forge test --match-path "test/unit/**/*.sol" -vv

test-fuzz:
	forge test --match-path "test/fuzz/**/*.sol" -vv

test-invariant:
	forge test --match-path "test/invariant/**/*.sol" -vv

test-integration:
	@echo "Running integration tests..."
	forge test --match-path "test/integration/**/*.sol" -vv

test-advanced:
	@echo "Running advanced edge case tests..."
	forge test --match-path "test/unit/VyqnoEngineAdvanced.t.sol" -vvv

test-gas:
	@echo "Running tests with gas reporting..."
	forge test --gas-report

test-quick:
	@echo "Running quick unit tests (no fuzz/invariant)..."
	forge test --match-path "test/unit/VyqnoEngineTest.t.sol" -vv --no-match-contract "Fuzz|Invariant"

coverage:
	@echo "Generating coverage report..."
	forge coverage --report summary --report lcov

coverage-html:
	@echo "Generating HTML coverage report..."
	@forge coverage --report lcov
	@genhtml lcov.info --output-directory coverage --branch-coverage --function-coverage || echo "Install genhtml: brew install lcov or apt-get install lcov"
	@echo "Coverage report generated in ./coverage/index.html"

snapshot:
	forge snapshot

snapshot-diff:
	@echo "Comparing gas snapshots..."
	forge snapshot --diff

# Code formatting
format:
	forge fmt

# Local development
anvil:
	anvil --block-time 1

deploy-anvil:
	@echo "Deploying to Anvil..."
	forge script script/DeployVyqno.s.sol:DeployVyqno --rpc-url http://localhost:8545 --broadcast -vvvv

# Testnet deployment
deploy-sepolia:
	@echo "Deploying to Sepolia..."
	forge script script/DeployVyqno.s.sol:DeployVyqno --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

# Mainnet deployments
deploy-polygon:
	@echo "Deploying to Polygon..."
	@echo "⚠️  WARNING: You are about to deploy to POLYGON MAINNET"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		forge script script/DeployVyqno.s.sol:DeployVyqno --rpc-url $(POLYGON_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(POLYGONSCAN_API_KEY) -vvvv; \
	fi

deploy-arbitrum:
	@echo "Deploying to Arbitrum..."
	@echo "⚠️  WARNING: You are about to deploy to ARBITRUM MAINNET"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		forge script script/DeployVyqno.s.sol:DeployVyqno --rpc-url $(ARBITRUM_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ARBISCAN_API_KEY) -vvvv; \
	fi

# Contract verification (if deployment verification failed)
verify-sepolia:
	@echo "Verifying on Sepolia..."
	@echo "Usage: make verify-sepolia CONTRACT=<address>"
	forge verify-contract $(CONTRACT) src/VyqnoEngine.sol:VyqnoEngine --chain-id 11155111 --etherscan-api-key $(ETHERSCAN_API_KEY)

verify-polygon:
	@echo "Verifying on Polygon..."
	@echo "Usage: make verify-polygon CONTRACT=<address>"
	forge verify-contract $(CONTRACT) src/VyqnoEngine.sol:VyqnoEngine --chain-id 137 --etherscan-api-key $(POLYGONSCAN_API_KEY)

verify-arbitrum:
	@echo "Verifying on Arbitrum..."
	@echo "Usage: make verify-arbitrum CONTRACT=<address>"
	forge verify-contract $(CONTRACT) src/VyqnoEngine.sol:VyqnoEngine --chain-id 42161 --etherscan-api-key $(ARBISCAN_API_KEY)

# Slither static analysis (requires slither installation: pip install slither-analyzer)
slither:
	slither . --config-file slither.config.json || true
