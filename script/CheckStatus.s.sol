// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/TinfoilToken.sol";
import "../src/Conspirapuppets.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract CheckStatusScript is Script {
    address constant AERODROME_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    // ADDED: Helper to handle pair visibility lag
    function getPairWithRetry(
        address factory,
        address tokenA,
        address tokenB,
        bool stable,
        uint256 maxAttempts
    ) internal view returns (address) {
        for (uint256 i = 0; i < maxAttempts; i++) {
            address pair = IAerodromeFactory(factory).getPair(tokenA, tokenB, stable);
            if (pair != address(0)) {
                return pair;
            }
        }
        return address(0);
    }
    
    function run() external view {
        address tinfoilAddress = vm.envAddress("TINFOIL_TOKEN_ADDRESS");
        address payable nftAddress = payable(vm.envAddress("CONSPIRAPUPPETS_ADDRESS"));
        
        console.log("=================================================================");
        console.log("CONSPIRAPUPPETS STATUS CHECK");
        console.log("=================================================================");
        console.log("Timestamp:", block.timestamp);
        console.log("Block Number:", block.number);
        console.log("");
        console.log("TinfoilToken:", tinfoilAddress);
        console.log("Conspirapuppets:", nftAddress);
        
        TinfoilToken tinfoilToken = TinfoilToken(tinfoilAddress);
        Conspirapuppets conspirapuppets = Conspirapuppets(nftAddress);
        
        // Get mint status
        (
            uint256 totalSupply,
            uint256 maxSupply,
            bool mintCompleted,
            uint256 contractBalance,
            uint256 tokensPerNFT,
            uint256 operationalFunds,
            bool lpCreated,
            uint256 totalEthReceived
        ) = conspirapuppets.getMintStatus();
        
        // Get token info
        (
            uint256 tokenTotalSupply,
            uint256 tokenMaxSupply,
            uint256 totalBurned,
            uint256 circulatingSupply,
            bool tradingEnabled,
            bool maxSupplyReached
        ) = tinfoilToken.getTokenInfo();
        
        // Get LP creation status
        (
            bool lpCreationScheduled,
            uint256 lpCreationTimestamp,
            bool canCreateLP,
            uint256 timeRemaining
        ) = conspirapuppets.getLPCreationStatus();
        
        console.log("\n=================================================================");
        console.log("NFT COLLECTION STATUS");
        console.log("=================================================================");
        console.log("  Total Supply:", totalSupply);
        console.log("  Max Supply:", maxSupply);
        console.log("  Progress:", (totalSupply * 100) / maxSupply, "%");
        console.log("  Remaining:", maxSupply - totalSupply, "NFTs");
        console.log("  Tokens per NFT:", tokensPerNFT / 1e18);
        console.log("");
        console.log("  Mint Completed:", mintCompleted ? "YES" : "NO");
        console.log("  Contract Balance:", contractBalance / 1e18, "ETH");
        console.log("  Total ETH Received:", totalEthReceived / 1e18, "ETH");
        console.log("  Operational Funds:", operationalFunds / 1e18, "ETH");
        
        console.log("\n=================================================================");
        console.log("TINFOIL TOKEN STATUS");
        console.log("=================================================================");
        console.log("  Total Supply:", tokenTotalSupply / 1e18);
        console.log("  Max Supply:", tokenMaxSupply / 1e18);
        console.log("  Circulating Supply:", circulatingSupply / 1e18);
        console.log("  Total Burned:", totalBurned / 1e18);
        console.log("  Trading Enabled:", tradingEnabled ? "YES" : "NO");
        console.log("  Max Supply Reached:", maxSupplyReached ? "YES" : "NO");
        
        console.log("\n=================================================================");
        console.log("LIQUIDITY POOL STATUS");
        console.log("=================================================================");
        console.log("  LP Created:", lpCreated ? "YES" : "NO");
        console.log("  LP Creation Scheduled:", lpCreationScheduled ? "YES" : "NO");
        
        if (lpCreationScheduled) {
            console.log("  LP Creation Timestamp:", lpCreationTimestamp);
            console.log("  Current Timestamp:", block.timestamp);
            console.log("  Can Create LP Now:", canCreateLP ? "YES" : "NO");
            
            if (timeRemaining > 0) {
                console.log("  Time Until LP Creation:", timeRemaining, "seconds");
                console.log("  Time Until LP Creation (min):", timeRemaining / 60);
            } else if (!lpCreated) {
                console.log("  [ACTION REQUIRED] LP creation delay has passed!");
                console.log("  [ACTION REQUIRED] Call createLP() to create liquidity pool");
            }
        }
        
        if (lpCreated || canCreateLP) {
            // FIXED: Use retry logic to handle pair visibility lag
            address pair = getPairWithRetry(AERODROME_FACTORY, tinfoilAddress, WETH, false, 3);
            
            console.log("");
            console.log("  LP Pair Address:", pair);
            
            if (pair == address(0)) {
                console.log("  [INFO] LP pair not visible yet");
                console.log("  [INFO] This is normal immediately after LP creation");
                console.log("  [INFO] Wait 10-30 seconds and re-run this script");
                console.log("  [INFO] Or check: https://basescan.org/address/%s", nftAddress);
            } else {
                uint256 lpAtBurn = IERC20(pair).balanceOf(BURN_ADDRESS);
                uint256 lpTotalSupply = IERC20(pair).totalSupply();
                uint256 tokenInPair = IERC20(tinfoilAddress).balanceOf(pair);
                uint256 ethInPair = IERC20(WETH).balanceOf(pair);
                
                console.log("  LP Total Supply:", lpTotalSupply / 1e18);
                console.log("  LP Burned:", lpAtBurn / 1e18);
                if (lpTotalSupply > 0) {
                    console.log("  LP Burn %:", (lpAtBurn * 100) / lpTotalSupply);
                }
                console.log("");
                console.log("  Tokens in Pair:", tokenInPair / 1e18);
                console.log("  ETH in Pair:", ethInPair / 1e18);
                
                if (tokenInPair > 0 && ethInPair > 0) {
                    uint256 pricePerToken = (ethInPair * 1e18) / tokenInPair;
                    console.log("  Price per Token (wei):", pricePerToken);
                    console.log("  Price per Token (gwei):", pricePerToken / 1e9);
                }
            }
        }
        
        console.log("\n=================================================================");
        console.log("WORKFLOW STATUS");
        console.log("=================================================================");
        
        if (!mintCompleted) {
            console.log("  [PHASE 1] MINTING IN PROGRESS");
            console.log("  - NFTs are being minted");
            console.log("  - Waiting for sell-out");
            uint256 remaining = maxSupply - totalSupply;
            console.log("  - Remaining to mint:", remaining, "NFTs");
            console.log("  - Remaining ETH to raise:", (remaining * 5) / 1000, "ETH");
        } else if (mintCompleted && !lpCreated && !lpCreationScheduled) {
            console.log("  [PHASE 2] MINT COMPLETE - LP CREATION PENDING");
            console.log("  [WARNING] Mint completed but LP creation not scheduled!");
            console.log("  [ACTION] Owner should call completeMint()");
        } else if (mintCompleted && lpCreationScheduled && !canCreateLP) {
            console.log("  [PHASE 2] MINT COMPLETE - WAITING FOR LP DELAY");
            console.log("  [INFO] LP creation is scheduled");
            console.log("  [INFO] Delay has not passed yet");
            console.log("  [INFO] Wait", timeRemaining, "seconds");
            console.log("  [INFO] Or", timeRemaining / 60, "minutes");
            console.log("  [INFO] Then call createLP()");
            console.log("  [INFO] Or call createLPImmediate() to bypass");
        } else if (mintCompleted && canCreateLP && !lpCreated) {
            console.log("  [PHASE 2] READY FOR LP CREATION");
            console.log("  [ACTION REQUIRED] Call createLP()");
        } else if (lpCreated && !tradingEnabled) {
            console.log("  [PHASE 3] LP CREATED - TRADING NOT ENABLED");
            console.log("  [WARNING] LP created but trading not enabled!");
            console.log("  [ACTION] Call enableTradingManual()");
        } else if (lpCreated && tradingEnabled) {
            console.log("  [PHASE 3] COMPLETE - TRADING LIVE");
            console.log("  [SUCCESS] All systems operational!");
            
            if (operationalFunds > 0) {
                console.log("");
                console.log("  [ACTION] Withdraw operational funds");
                console.log("  - Amount available:", operationalFunds / 1e18, "ETH");
            }
        }
        
        console.log("\n=================================================================");
        console.log("AVAILABLE ACTIONS");
        console.log("=================================================================");
        
        if (!mintCompleted) {
            console.log("  - Wait for sell-out");
        } else if (mintCompleted && !lpCreated) {
            if (canCreateLP) {
                console.log("  [PRIMARY] createLP()");
            }
            console.log("  [EMERGENCY] createLPImmediate()");
            console.log("  [RETRY] retryLPCreation()");
            console.log("  [CUSTOM] emergencyLPCreation(tokens,eth,slippage,gas)");
        } else if (lpCreated && !tradingEnabled) {
            console.log("  [ACTION] enableTradingManual()");
        } else if (lpCreated && tradingEnabled) {
            if (operationalFunds > 0) {
                console.log("  [ACTION] withdrawOperationalFunds()");
            } else {
                console.log("  [INFO] All operations complete!");
            }
        }
        
        console.log("\n=================================================================");
        console.log("WHITELIST STATUS");
        console.log("=================================================================");
        address nftContract = nftAddress;
        address aerodromeRouter = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
        
        bool nftWhitelisted = tinfoilToken.transferWhitelist(nftContract);
        bool routerWhitelisted = tinfoilToken.transferWhitelist(aerodromeRouter);
        
        console.log("  NFT Contract:", nftWhitelisted ? "YES" : "NO");
        console.log("  Router:", routerWhitelisted ? "YES" : "NO");
        
        if (!nftWhitelisted || !routerWhitelisted) {
            console.log("");
            console.log("  [WARNING] Critical addresses not whitelisted!");
            console.log("  [WARNING] LP creation will fail!");
        }
        
        console.log("\n=================================================================");
        console.log("SUMMARY");
        console.log("=================================================================");
        console.log("  NFTs Minted:", totalSupply, "/", maxSupply);
        console.log("  Tokens Distributed:", (totalSupply * tokensPerNFT) / 1e18);
        console.log("  ETH Raised:", totalEthReceived / 1e18, "ETH");
        console.log("  Mint Complete:", mintCompleted ? "YES" : "NO");
        console.log("  LP Created:", lpCreated ? "YES" : "NO");
        console.log("  Trading Enabled:", tradingEnabled ? "YES" : "NO");
        
        if (mintCompleted && lpCreated && tradingEnabled) {
            console.log("\n  PROJECT FULLY LAUNCHED!");
        } else if (mintCompleted && !lpCreated) {
            console.log("\n  ACTION REQUIRED: Create liquidity pool");
        } else {
            console.log("\n  Waiting for sell-out...");
        }
        
        console.log("=================================================================");
    }
}