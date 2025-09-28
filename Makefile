# Conspirapuppets Foundry Commands
include .env
export

.PHONY: help
help:
	@echo "🎭 Conspirapuppets Foundry Commands"
	@echo "=================================="
	@echo "test-all        - Run all tests with verbose output"
	@echo "test-integration - Run full integration test"
	@echo "test-edge       - Run edge case tests"
	@echo "test-gas        - Run gas usage tests"
	@echo "build           - Compile contracts"
	@echo "deploy-sepolia  - Deploy to Base Sepolia testnet"
	@echo "clean           - Clean build artifacts"

.PHONY: test-all
test-all:
	@echo "🧪 Running all tests..."
	forge test -vvv

.PHONY: test-integration
test-integration:
	@echo "🎯 Running full integration test..."
	forge test --match-test testFullIntegration -vvv

.PHONY: test-edge
test-edge:
	@echo "⚠️  Running edge case tests..."
	forge test --match-contract EdgeCasesTest -vvv

.PHONY: test-gas
test-gas:
	@echo "⛽ Running gas usage tests..."
	forge test --gas-report

.PHONY: build
build:
	forge build

.PHONY: install
install:
	forge install foundry-rs/forge-std
	forge install OpenZeppelin/openzeppelin-contracts
	forge install ProjectOpenSea/seadrop

.PHONY: clean
clean:
	forge clean