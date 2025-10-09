# PixelPirates - Automated NFT-to-Token Launch System

A production-ready, fully automated NFT launch system that seamlessly distributes ERC20 tokens to NFT minters and creates a permissionless, rug-proof liquidity pool on Aerodrome DEX.

## 🎯 Overview

This system combines three smart contracts to create a trustless NFT-to-token launch pipeline:

1. **ERC721 NFT Collection** (PixelPirates.sol) - SeaDrop-powered minting
2. **ERC20 Token** (DoubloonToken.sol) - Tradeable token with transfer restrictions
3. **LP Manager** (LPManager.sol) - Automated DEX liquidity creation

### Key Features

- ✅ **Automatic Token Distribution**: Each NFT mint instantly distributes tokens to the minter
- ✅ **Permissionless LP Creation**: Anyone can trigger LP creation after sellout delay
- ✅ **100% LP Burn**: All liquidity pool tokens sent to dead address (rug-proof)
- ✅ **Fair 50/50 Split**: ETH from mints split evenly between LP and operational funds
- ✅ **Automatic Trading Activation**: Token trading enables automatically post-LP creation
- ✅ **Security First**: Max supply caps, transfer whitelisting, emergency functions

---

## 📋 Current Configuration

### NFT Collection
- **Name**: PixelPirates
- **Symbol**: PIXX
- **Max Supply**: 3,333 NFTs
- **Tokens per NFT**: 499,549 DBLN

### Token (Doubloon)
- **Name**: Doubloon
- **Symbol**: DBLN
- **Max Supply**: 3,330,000,000 tokens (3.33 billion)
- **Decimals**: 18

### Economics
- **50%** of tokens → NFT minters (1,664,996,817 DBLN)
- **50%** of tokens → Liquidity Pool (1,665,000,000 DBLN)
- **0.01%** remainder → Project owner (3,183 DBLN)

### ETH Distribution (Post-Mint)
- **50%** → Liquidity Pool
- **50%** → Operational Funds (withdrawable by owner)

---

## 🏗️ Architecture
```text
┌─────────────────┐
│  NFT Minter     │
│  Pays ETH       │
└────────┬────────┘
│
▼
┌─────────────────┐      ┌──────────────────┐
│  PixelPirates   │◄────►│  DoubloonToken   │
│  (ERC721)       │      │  (ERC20)         │
└────────┬────────┘      └──────────────────┘
│                         ▲
│ ETH                     │ Mints tokens
▼                         │
┌─────────────────┐                │
│  Collects ETH   │                │
│  Until Sellout  │                │
└────────┬────────┘                │
│                         │
│ Triggers LP             │
▼                         │
┌─────────────────┐                │
│   LPManager     │────────────────┘
│  Creates Pool   │
└────────┬────────┘
│
▼
┌─────────────────┐
│  Aerodrome DEX  │
│  DBLN/WETH Pool │
└─────────────────┘
```

---

## 🚀 Deployment Guide

### Prerequisites

- Foundry installed
- Base RPC URL configured
- Private key with ETH for gas

### Environment Setup

Create a `.env` file:
```bash
PRIVATE_KEY=your_private_key_here
BASE_RPC_URL=https://mainnet.base.org
BASESCAN_API_KEY=your_basescan_api_key

# After deployment, add these:
DOUBLOON_TOKEN_ADDRESS=
LP_MANAGER_ADDRESS=
PIXELPIRATES_ADDRESS=
```

### Deploy Contracts
```bash
# Deploy all contracts
forge script script/Deploy.s.sol --rpc-url $BASE_RPC_URL --broadcast --verify
```

---

## ⚙️ Configuration

### Step 1: Set Payout Address (CRITICAL - Do This First!)
```bash
bashcast send $PIXELPIRATES_ADDRESS   'updatePayoutAddress(address,address)'   0x00005EA00Ac477B1030CE78506496e8C2dE24bf5   $PIXELPIRATES_ADDRESS   --private-key $PRIVATE_KEY   --rpc-url $BASE_RPC_URL
```
**Why:** Ensures mint proceeds go to the NFT contract for automated LP creation.

### Step 2: Configure Public Drop
```bash
bashcast send $PIXELPIRATES_ADDRESS   'updatePublicDrop(address,(uint80,uint48,uint48,uint16,uint16,bool))'   0x00005EA00Ac477B1030CE78506496e8C2dE24bf5   '(1000000000000000,$(date +%s),2000000000,3333,10,false)'   --private-key $PRIVATE_KEY   --rpc-url $BASE_RPC_URL
```

### Step 3: Upload Metadata
```bash
bashcast send $PIXELPIRATES_ADDRESS   'setBaseURI(string)'   'ipfs://YOUR_CID/'   --private-key $PRIVATE_KEY   --rpc-url $BASE_RPC_URL
```

---

## 📊 Monitoring
```bash
bashforge script script/CheckStatus.s.sol --rpc-url $BASE_RPC_URL
```
Shows:
- NFTs minted / remaining
- ETH collected
- Token distribution
- LP creation status
- Trading enabled status

---

## 🧪 Testing
```bash
forge script script/CheckStatus.s.sol --rpc-url $BASE_RPC_URL
```

---

## 📄 License
MIT License - See LICENSE file for details

---

## 🙏 Acknowledgments
Built with:
- Foundry
- SeaDrop
- Aerodrome Finance
- OpenZeppelin Contracts
