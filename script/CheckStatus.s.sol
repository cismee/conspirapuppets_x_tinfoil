// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/TinfoilToken.sol";
import "../src/Conspirapuppets.sol";

contract CheckStatusScript is Script {
    function run() external view {
        // Get contract addresses from environment or use deployed addresses
        address tinfoilAddress = vm.envAddress("TINFOIL_TOKEN_ADDRESS");
        address payable nftAddress = payable(vm.envAddress("CONSPIRAPUPPETS_ADDRESS"));
        
        console.log("CHECKING CONSPIRAPUPPETS STATUS");
        console.log("=====================================");
        console.log("TinfoilToken:", tinfoilAddress);
        console.log("Conspirapuppets:", nftAddress);
        
        TinfoilToken tinfoilToken = TinfoilToken(tinfoilAddress);
        Conspirapuppets conspirapuppets = Conspirapuppets(nftAddress);
        
        // Get NFT status - NOW WITH 7 RETURN VALUES
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
        
        console.log("\nNFT Collection Status:");
        console.log("  Current Supply:", totalSupply, "/", maxSupply);
        console.log("  Mint Completed:", mintCompleted);
        console.log("  Contract Balance:", contractBalance / 1e18, "ETH");
        console.log("  Tokens per NFT:", tokensPerNFT / 1e18);
        console.log("  Operational Funds Available:", operationalFunds / 1e18, "ETH");
        console.log("  LP Created:", lpCreated);
        
        console.log("\nToken Status:");
        console.log("  Total Supply:", tokenTotalSupply / 1e18);
        console.log("  Max Supply:", tokenMaxSupply / 1e18);
        console.log("  Total Burned:", totalBurned / 1e18);
        console.log("  Circulating Supply:", circulatingSupply / 1e18);
        console.log("  Trading Enabled:", tradingEnabled);
        console.log("  Status:", statusMessage);
        
        // Calculate progress
        uint256 progress = (totalSupply * 100) / maxSupply;
        console.log("\nMint Progress:", progress, "%");
        
        if (mintCompleted) {
            console.log("COLLECTION SOLD OUT!");
            if (lpCreated) {
                console.log("   -> LP created and burned");
            } else {
                console.log("   -> WARNING: LP creation may have failed");
            }
            console.log("   -> Trading enabled");
            if (operationalFunds > 0) {
                console.log("   -> Operational funds available for withdrawal");
            } else {
                console.log("   -> Operational funds withdrawn");
            }
        } else {
            uint256 remaining = maxSupply - totalSupply;
            console.log("Remaining to mint:", remaining, "NFTs");
            uint256 remainingRevenue = (remaining * 0.005 ether) / 1e18;
            console.log("Potential revenue from remaining:", remainingRevenue, "ETH");
        }
        
        console.log("\nLinks:");
        console.log("  OpenSea: https://opensea.io/assets/base/", nftAddress);
        console.log("  Basescan NFT: https://basescan.org/address/", nftAddress);
        console.log("  Basescan Token: https://basescan.org/address/", tinfoilAddress);
    }
}