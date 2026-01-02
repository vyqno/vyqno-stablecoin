.PHONY: all test clean install update build snapshot format anvil deploy-anvil deploy-sepolia deploy-polygon deploy-arbitrum verify help

# Load environment variables
include .env
export

# Default target
all: clean install update build test

# Help target
help:
	@echo "Available targets:"
	@echo "  install        - Install dependencies"
	@echo "  update         - Update dependencies"
	@echo "  build          - Build contracts"
	@echo "  test           - Run all tests"
	@echo "  test-unit      - Run unit tests only"
	@echo "  test-fuzz      - Run fuzz tests"
	@echo "  test-invariant - Run invariant tests"
	@echo "  coverage       - Generate test coverage report"
	@echo "  snapshot       - Generate gas snapshot"
	@echo "  format         - Format code with forge fmt"
	@echo "  clean          - Clean build artifacts"
	@echo "  anvil          - Start local Anvil node"
	@echo "  deploy-anvil   - Deploy to local Anvil"
	@echo "  deploy-sepolia - Deploy to Sepolia testnet"
	@echo "  deploy-polygon - Deploy to Polygon mainnet"
	@echo "  deploy-arbitrum- Deploy to Arbitrum mainnet"

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

coverage:
	forge coverage --report summary --report lcov

snapshot:
	forge snapshot

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
