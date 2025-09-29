// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/TinfoilToken.sol";
import "../src/Conspirapuppets.sol";

contract CheckStatusScript is Script {
    function run() external view {
        address tinfoilAddress = vm.envAddress("TINFOIL_TOKEN_ADDRESS");
        address payable nftAddress = payable(vm.envAddress("CONSPIRAPUPPETS_ADDRESS"));
        
        console.log("=================================================================");
        console.log("CONSPIRAPUPPETS STATUS CHECK");
        console.log("=================================================================");
        console.log("TinfoilToken:", tinfoilAddress);
        console.log("Conspirapuppets:", nftAddress);
        console.log("Timestamp:", block.timestamp);
        
        TinfoilToken tinfoilToken = TinfoilToken(tinfoilAddress);
        Conspirapuppets conspirapuppets = Conspirapuppets(nftAddress);
        
        // Get NFT status
        (
            uint256 totalSupply,
            uint256 maxSupply,
            bool mintCompleted,
            uint256 contractBalance,
            uint256 tokensPerNFT,
            uint256 operationalFunds,
            bool lpCreated
        ) = conspirapuppets.getMintStatus();
        
        // Get token status
        (
            uint256 tokenTotalSupply,
            uint256 tokenMaxSupply,
            uint256 totalBurned,
            uint256 circulatingSupply,
            bool tradingEnabled,
            bool maxSupplyReached
        ) = tinfoilToken.getTokenInfo();
        
        // Get trading status
        (bool trading, string memory statusMessage) = tinfoilToken.getTradingStatus();
        
        console.log("\n=================================================================");
        console.log("NFT COLLECTION STATUS");
        console.log("=================================================================");
        console.log("Current Supply:", totalSupply, "/", maxSupply);
        console.log("Mint Completed:", mintCompleted);
        console.log("Contract ETH Balance:", contractBalance / 1e18, "ETH");
        console.log("Tokens per NFT:", tokensPerNFT / 1e18);
        console.log("Operational Funds:", operationalFunds / 1e18, "ETH");
        console.log("LP Created:", lpCreated);
        console.log("Total ETH Received:", conspirapuppets.totalEthReceived() / 1e18, "ETH");
        
        console.log("\n=================================================================");
        console.log("TOKEN STATUS");
        console.log("=================================================================");
        console.log("Total Supply:", tokenTotalSupply / 1e18, "TINFOIL");
        console.log("Max Supply:", tokenMaxSupply / 1e18, "TINFOIL");
        console.log("Total Burned:", totalBurned / 1e18, "TINFOIL");
        console.log("Circulating Supply:", circulatingSupply / 1e18, "TINFOIL");
        console.log("Trading Enabled:", tradingEnabled);
        console.log("Max Supply Reached:", maxSupplyReached);
        console.log("Status:", statusMessage);
        
        // Calculate progress
        uint256 progress = totalSupply > 0 ? (totalSupply * 100) / maxSupply : 0;
        console.log("\n=================================================================");
        console.log("MINT PROGRESS");
        console.log("=================================================================");
        console.log("Progress:", progress, "%");
        console.log("Minted:", totalSupply, "NFTs");
        
        if (mintCompleted) {
            console.log("\nSTATUS: COLLECTION SOLD OUT!");
            console.log("=================================================================");
            if (lpCreated) {
                console.log("  [OK] LP created and LP tokens burned");
            } else {
                console.log("  [WARNING] LP creation may have failed - check events");
                console.log("  [ACTION] Owner can call retryLPCreation() or emergencyLPCreation()");
            }
            
            if (tradingEnabled) {
                console.log("  [OK] Trading enabled");
            } else {
                console.log("  [WARNING] Trading not enabled - LP may have failed");
            }
            
            if (operationalFunds > 0) {
                console.log("  [ACTION] Operational funds available for withdrawal:", operationalFunds / 1e18, "ETH");
                console.log("  [ACTION] Call withdrawOperationalFunds() to claim");
            } else {
                console.log("  [OK] Operational funds withdrawn");
            }
        } else {
            uint256 remaining = maxSupply - totalSupply;
            console.log("\nSTATUS: MINTING IN PROGRESS");
            console.log("=================================================================");
            console.log("Remaining:", remaining, "NFTs");
            
            if (remaining > 0) {
                uint256 potentialRevenue = (remaining * 5) / 1000; // 0.005 ETH in ETH
                console.log("Potential Revenue:", potentialRevenue, "ETH");
            }
            
            console.log("\n[INFO] At sellout:");
            console.log("  - LP will be created automatically");
            console.log("  - LP tokens will be burned");
            console.log("  - Trading will be enabled");
            console.log("  - 50% of ETH for operations");
        }
        
        // Burn statistics
        if (totalBurned > 0) {
            uint256 burnPercentage = tinfoilToken.burnPercentage();
            console.log("\n=================================================================");
            console.log("BURN STATISTICS");
            console.log("=================================================================");
            console.log("Total Burned:", totalBurned / 1e18, "TINFOIL");
            console.log("Burn Percentage:", burnPercentage, "%");
        }
        
        console.log("\n=================================================================");
        console.log("LINKS");
        console.log("=================================================================");
        console.log("OpenSea:", "https://opensea.io/assets/base/", nftAddress);
        console.log("Basescan NFT:", "https://basescan.org/address/", nftAddress);
        console.log("Basescan Token:", "https://basescan.org/address/", tinfoilAddress);
    }
}