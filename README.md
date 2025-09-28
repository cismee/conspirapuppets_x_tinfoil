cat > README.md << 'EOF'
# Conspirapuppets 🎭

A revolutionary NFT collection with integrated tokenomics featuring an "explosive finale" when the collection sells out.

## Overview

Conspirapuppets combines NFT collecting with DeFi mechanics:
- **3,333 unique NFTs** at 0.005 ETH each
- **1M TINFOIL tokens** automatically distributed per NFT minted
- **Trading locked** until collection sells out
- **Explosive finale** creates permanent liquidity when final NFT mints

## Contracts

- `TinfoilToken.sol` - ERC20 token with trading restrictions
- `Conspirapuppets.sol` - SeaDrop-integrated NFT contract
- Deployed on Base network

## Economics

- **Total Supply**: 3.33B TINFOIL tokens
- **Distribution**: 50% to NFT holders, 50% to liquidity pool
- **Revenue Split**: 50% to operations, 50% to permanent liquidity
- **Deflationary**: Public burn function available

## Installation
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone repository
git clone [YOUR_REPO_URL]
cd conspirapuppets

# Install dependencies
make install

# Build contracts
make build

# Run tests
make test-all