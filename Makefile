# PixelPirates - Automated NFT-to-Token Launch System
# Makefile for common operations

# Load environment variables
include .env
export

# Default target
.PHONY: help
help:
	@echo "PixelPirates Launch System - Available Commands"
	@echo "================================================"
	@echo ""
	@echo "DEPLOYMENT:"
	@echo "  make deploy              Deploy all contracts to Base"
	@echo "  make deploy-test         Deploy with verification"
	@echo "  make verify              Verify contracts on Basescan"
	@echo ""
	@echo "CONFIGURATION:"
	@echo "  make setup-payout        Set payout address (CRITICAL - do first!)"
	@echo "  make setup-drop          Configure public drop parameters"
	@echo "  make setup-all           Run all setup commands"
	@echo ""
	@echo "MONITORING:"
	@echo "  make status              Check full system status"
	@echo "  make balance             Check your token balance"
	@echo "  make check-lp            Check LP creation status"
	@echo "  make check-eth           Check contract ETH balance"
	@echo ""
	@echo "LAUNCH OPERATIONS:"
	@echo "  make create-lp           Create liquidity pool (after delay)"
	@echo "  make create-lp-now       Create LP immediately (bypass delay)"
	@echo "  make retry-lp            Retry failed LP creation"
	@echo "  make withdraw            Withdraw operational funds"
	@echo ""
	@echo "EMERGENCY:"
	@echo "  make emergency-status    Run emergency diagnostics"
	@echo "  make emergency-withdraw  Emergency ETH withdrawal"
	@echo ""
	@echo "DEVELOPMENT:"
	@echo "  make build               Compile contracts"
	@echo "  make test                Run tests"
	@echo "  make clean               Clean build artifacts"
	@echo "  make update              Update dependencies"

# ============================================================================
# DEPLOYMENT
# ============================================================================

.PHONY: deploy
deploy:
	@echo "Deploying PixelPirates system to Base..."
	forge script script/Deploy.s.sol \
		--rpc-url $(BASE_RPC_URL) \
		--broadcast \
		--verify \
		-vvv

.PHONY: deploy-test
deploy-test:
	@echo "Test deployment (dry run)..."
	forge script script/Deploy.s.sol \
		--rpc-url $(BASE_RPC_URL) \
		-vvv

.PHONY: verify
verify:
	@echo "Verifying contracts on Basescan..."
	@echo "DoubloonToken: $(DOUBLOON_TOKEN_ADDRESS)"
	forge verify-contract $(DOUBLOON_TOKEN_ADDRESS) \
		src/DoubloonToken.sol:DoubloonToken \
		--chain-id 8453 \
		--etherscan-api-key $(BASESCAN_API_KEY)
	@echo "PixelPirates: $(PIXELPIRATES_ADDRESS)"
	forge verify-contract $(PIXELPIRATES_ADDRESS) \
		src/PixelPirates.sol:PixelPirates \
		--chain-id 8453 \
		--etherscan-api-key $(BASESCAN_API_KEY)
	@echo "LPManager: $(LP_MANAGER_ADDRESS)"
	forge verify-contract $(LP_MANAGER_ADDRESS) \
		src/LPManager.sol:LPManager \
		--chain-id 8453 \
		--etherscan-api-key $(BASESCAN_API_KEY)

# ============================================================================
# CONFIGURATION
# ============================================================================

.PHONY: setup-payout
setup-payout:
	@echo "Setting payout address to NFT contract..."
	@echo "This ensures mint proceeds go to the contract for LP creation"
	cast send $(PIXELPIRATES_ADDRESS) \
		'updatePayoutAddress(address,address)' \
		0x00005EA00Ac477B1030CE78506496e8C2dE24bf5 \
		$(PIXELPIRATES_ADDRESS) \
		--private-key $(PRIVATE_KEY) \
		--rpc-url $(BASE_RPC_URL)
	@echo "✅ Payout address set!"

.PHONY: setup-drop
setup-drop:
	@echo "Configuring public drop..."
	@echo "Mint price: 0.001 ETH"
	@echo "Max supply: 3333"
	@echo "Max per wallet: 10"
	cast send $(PIXELPIRATES_ADDRESS) \
		'updatePublicDrop(address,(uint80,uint48,uint48,uint16,uint16,bool))' \
		0x00005EA00Ac477B1030CE78506496e8C2dE24bf5 \
		'(1000000000000000,$$(date +%s),2000000000,3333,10,false)' \
		--private-key $(PRIVATE_KEY) \
		--rpc-url $(BASE_RPC_URL)
	@echo "✅ Drop configured!"

.PHONY: setup-all
setup-all: setup-payout setup-drop
	@echo "✅ All setup complete! Ready to launch."

# ============================================================================
# MONITORING
# ============================================================================

.PHONY: status
status:
	@echo "Checking system status..."
	forge script script/CheckStatus.s.sol \
		--rpc-url $(BASE_RPC_URL)

.PHONY: balance
balance:
	@echo "Checking your DBLN token balance..."
	@cast call $(DOUBLOON_TOKEN_ADDRESS) \
		'balanceOf(address)(uint256)' \
		$$(cast wallet address --private-key $(PRIVATE_KEY)) \
		--rpc-url $(BASE_RPC_URL) | \
		awk '{printf "Balance: %s DBLN\n", $$1/1e18}'

.PHONY: check-lp
check-lp:
	@echo "Checking LP status..."
	@echo -n "LP Created: "
	@cast call $(LP_MANAGER_ADDRESS) \
		'lpCreated()(bool)' \
		--rpc-url $(BASE_RPC_URL)
	@echo -n "LP Pair Address: "
	@cast call $(LP_MANAGER_ADDRESS) \
		'getExpectedLPPair()(address)' \
		--rpc-url $(BASE_RPC_URL)

.PHONY: check-eth
check-eth:
	@echo "Checking contract ETH balances..."
	@echo -n "NFT Contract: "
	@cast balance $(PIXELPIRATES_ADDRESS) --rpc-url $(BASE_RPC_URL) --ether
	@echo -n "Your Wallet: "
	@cast balance $$(cast wallet address --private-key $(PRIVATE_KEY)) --rpc-url $(BASE_RPC_URL) --ether

.PHONY: check-trading
check-trading:
	@echo -n "Trading Enabled: "
	@cast call $(DOUBLOON_TOKEN_ADDRESS) \
		'tradingEnabled()(bool)' \
		--rpc-url $(BASE_RPC_URL)

# ============================================================================
# LAUNCH OPERATIONS
# ============================================================================

.PHONY: create-lp
create-lp:
	@echo "Creating liquidity pool (requires 5-minute delay to have passed)..."
	cast send $(PIXELPIRATES_ADDRESS) \
		'createLP()' \
		--private-key $(PRIVATE_KEY) \
		--rpc-url $(BASE_RPC_URL) \
		--gas-limit 5000000
	@echo "✅ LP creation transaction sent!"
	@echo "Run 'make status' to verify"

.PHONY: create-lp-now
create-lp-now:
	@echo "Creating liquidity pool IMMEDIATELY (bypasses delay)..."
	cast send $(PIXELPIRATES_ADDRESS) \
		'createLPImmediate()' \
		--private-key $(PRIVATE_KEY) \
		--rpc-url $(BASE_RPC_URL) \
		--gas-limit 5000000
	@echo "✅ LP creation transaction sent!"
	@echo "Run 'make status' to verify"

.PHONY: retry-lp
retry-lp:
	@echo "Retrying LP creation with multiple strategies..."
	forge script script/RetryLP.s.sol \
		--rpc-url $(BASE_RPC_URL) \
		--broadcast

.PHONY: withdraw
withdraw:
	@echo "Withdrawing operational funds..."
	cast send $(PIXELPIRATES_ADDRESS) \
		'withdrawOperationalFunds()' \
		--private-key $(PRIVATE_KEY) \
		--rpc-url $(BASE_RPC_URL)
	@echo "✅ Funds withdrawn!"

# ============================================================================
# EMERGENCY
# ============================================================================

.PHONY: emergency-status
emergency-status:
	@echo "Running emergency diagnostics..."
	forge script script/EmergencyRecover.s.sol \
		--rpc-url $(BASE_RPC_URL)

.PHONY: emergency-withdraw
emergency-withdraw:
	@echo "⚠️  EMERGENCY: Withdrawing all ETH from contract..."
	@echo "This should only be used if LP creation has failed completely."
	@read -p "Are you sure? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		cast send $(PIXELPIRATES_ADDRESS) \
			'emergencyWithdraw()' \
			--private-key $(PRIVATE_KEY) \
			--rpc-url $(BASE_RPC_URL); \
		echo "✅ Emergency withdrawal complete"; \
	else \
		echo "Cancelled"; \
	fi

# ============================================================================
# DEVELOPMENT
# ============================================================================

.PHONY: build
build:
	@echo "Compiling contracts..."
	forge build

.PHONY: test
test:
	@echo "Running tests..."
	forge test -vvv

.PHONY: test-gas
test-gas:
	@echo "Running tests with gas reports..."
	forge test --gas-report

.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	forge clean
	rm -rf cache out

.PHONY: update
update:
	@echo "Updating dependencies..."
	forge update

.PHONY: install
install:
	@echo "Installing dependencies..."
	forge install

# ============================================================================
# UTILITY COMMANDS
# ============================================================================

.PHONY: addresses
addresses:
	@echo "Deployed Contract Addresses:"
	@echo "============================"
	@echo "DoubloonToken: $(DOUBLOON_TOKEN_ADDRESS)"
	@echo "LPManager:     $(LP_MANAGER_ADDRESS)"
	@echo "PixelPirates:  $(PIXELPIRATES_ADDRESS)"
	@echo ""
	@echo "View on Basescan:"
	@echo "DoubloonToken: https://basescan.org/address/$(DOUBLOON_TOKEN_ADDRESS)"
	@echo "PixelPirates:  https://basescan.org/address/$(PIXELPIRATES_ADDRESS)"
	@echo "LPManager:     https://basescan.org/address/$(LP_MANAGER_ADDRESS)"

.PHONY: wallet
wallet:
	@echo "Wallet Information:"
	@echo "==================="
	@echo -n "Address: "
	@cast wallet address --private-key $(PRIVATE_KEY)
	@echo -n "Balance: "
	@cast balance $$(cast wallet address --private-key $(PRIVATE_KEY)) --rpc-url $(BASE_RPC_URL) --ether

.PHONY: check-payout
check-payout:
	@echo -n "Current Payout Address: "
	@cast call $(PIXELPIRATES_ADDRESS) \
		'getCreatorPayoutAddress(address)(address)' \
		0x00005EA00Ac477B1030CE78506496e8C2dE24bf5 \
		--rpc-url $(BASE_RPC_URL)

# ============================================================================
# AIRDROP (Owner Only)
# ============================================================================

.PHONY: airdrop
airdrop:
	@echo "Airdrop function - requires manual parameters"
	@echo "Usage: cast send $(PIXELPIRATES_ADDRESS) 'airdrop(address[],uint256[])' '[ADDRESSES]' '[QUANTITIES]' --private-key $(PRIVATE_KEY) --rpc-url $(BASE_RPC_URL)"

# ============================================================================
# QUICK LAUNCH WORKFLOW
# ============================================================================

.PHONY: quick-launch
quick-launch:
	@echo "🚀 Quick Launch Workflow"
	@echo "========================"
	@echo ""
	@echo "Step 1: Deploying contracts..."
	@make deploy
	@echo ""
	@echo "Step 2: Setting up payout address..."
	@make setup-payout
	@echo ""
	@echo "Step 3: Configuring drop..."
	@make setup-drop
	@echo ""
	@echo "✅ Launch setup complete!"
	@echo ""
	@echo "Next steps:"
	@echo "1. Upload metadata to IPFS"
	@echo "2. Set base URI"
	@echo "3. Announce mint"
	@echo "4. Monitor with: make status"

# ============================================================================
# POST-LAUNCH WORKFLOW
# ============================================================================

.PHONY: post-launch
post-launch:
	@echo "📊 Post-Launch Checklist"
	@echo "========================"
	@echo ""
	@echo "1. Checking LP status..."
	@make check-lp
	@echo ""
	@echo "2. Checking trading status..."
	@make check-trading
	@echo ""
	@echo "3. Checking your balance..."
	@make balance
	@echo ""
	@echo "If LP is created and trading is enabled:"
	@echo "  make withdraw    - Withdraw operational funds"
	@echo ""
	@echo "If LP needs to be created:"
	@echo "  make create-lp   - Create LP (after delay)"
	@echo "  make create-lp-now - Create LP immediately"

# ============================================================================
# CONTINUOUS MONITORING
# ============================================================================

.PHONY: watch
watch:
	@echo "Watching system status (updates every 10 seconds)..."
	@echo "Press Ctrl+C to stop"
	@while true; do \
		clear; \
		echo "PixelPirates Status - $$(date)"; \
		echo "====================================="; \
		make status 2>/dev/null || true; \
		sleep 10; \
	done

# ============================================================================
# TESTING SHORTCUTS
# ============================================================================

.PHONY: test-mint
test-mint:
	@echo "Test minting 1 NFT..."
	@echo "⚠️  This will spend 0.001 ETH"
	cast send $(PIXELPIRATES_ADDRESS) \
		'mintPublic(address,uint256,address,bytes)' \
		0x00005EA00Ac477B1030CE78506496e8C2dE24bf5 \
		1 \
		$$(cast wallet address --private-key $(PRIVATE_KEY)) \
		0x \
		--value 0.001ether \
		--private-key $(PRIVATE_KEY) \
		--rpc-url $(BASE_RPC_URL)
	@echo "✅ Test mint complete!"

# ============================================================================
# DOCUMENTATION
# ============================================================================

.PHONY: docs
docs:
	@echo "Generating documentation..."
	forge doc --build

.PHONY: docs-serve
docs-serve:
	@echo "Serving documentation at http://localhost:3000"
	forge doc --serve

# ============================================================================
# CONFIGURATION TEMPLATES
# ============================================================================

.PHONY: env-template
env-template:
	@echo "Creating .env template..."
	@cat > .env.template <<'EOF'
# Private key for deployment and transactions
PRIVATE_KEY=your_private_key_here

# RPC URLs
BASE_RPC_URL=https://mainnet.base.org

# Basescan API key for contract verification
BASESCAN_API_KEY=your_basescan_api_key

# Deployed contract addresses (fill after deployment)
DOUBLOON_TOKEN_ADDRESS=
LP_MANAGER_ADDRESS=
PIXELPIRATES_ADDRESS=
EOF
	@echo "✅ .env.template created!"