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
    
    function run() external view {
        address tinfoilAddress = vm.envAddress("TINFOIL_TOKEN_ADDRESS");
        address payable nftAddress = payable(vm.envAddress("CONSPIRAPUPPETS_ADDRESS"));
        
        console.log("=================================================================");
        console.log("CONSPIRAPUPPETS STATUS CHECK");
        console.log("=================================================================");
        console.log("TinfoilToken:", tinfoilAddress);
        console.log("Conspirapuppets:", nftAddress);
        
        TinfoilToken tinfoilToken = TinfoilToken(tinfoilAddress);
        Conspirapuppets conspirapuppets = Conspirapuppets(nftAddress);
        
        // UPDATED: Now includes totalEthReceived as 8th return value
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
        
        (
            uint256 tokenTotalSupply,
            uint256 tokenMaxSupply,
            uint256 totalBurned,
            uint256 circulatingSupply,
            bool tradingEnabled,
            bool maxSupplyReached
        ) = tinfoilToken.getTokenInfo();
        
        console.log("\nNFT Collection:");
        console.log("  Supply:", totalSupply, "/", maxSupply);
        console.log("  Mint Completed:", mintCompleted);
        console.log("  Contract Balance:", contractBalance / 1e18, "ETH");
        console.log("  Operational Funds:", operationalFunds / 1e18, "ETH");
        console.log("  LP Created:", lpCreated);
        console.log("  Total ETH Received:", totalEthReceived / 1e18, "ETH");
        
        console.log("\nToken:");
        console.log("  Total Supply:", tokenTotalSupply / 1e18);
        console.log("  Trading Enabled:", tradingEnabled);
        console.log("  Total Burned:", totalBurned / 1e18);
        
        if (lpCreated) {
            IAerodromeFactory factory = IAerodromeFactory(AERODROME_FACTORY);
            address pair = factory.getPair(tinfoilAddress, WETH, false);
            console.log("\nLiquidity Pool:");
            console.log("  LP Pair:", pair);
            if (pair != address(0)) {
                uint256 lpAtBurn = IERC20(pair).balanceOf(BURN_ADDRESS);
                console.log("  LP @ Burn Address:", lpAtBurn / 1e18);
            }
        }
        
        console.log("\nProgress:", (totalSupply * 100) / maxSupply, "%");
        
        if (!mintCompleted && totalSupply < maxSupply) {
            console.log("\nRemaining:", maxSupply - totalSupply, "NFTs");
        }
        
        if (mintCompleted) {
            console.log("\n=================================================================");
            console.log("MINT COMPLETE");
            console.log("=================================================================");
            if (lpCreated) {
                console.log("  [OK] LP created and burned");
            } else {
                console.log("  [WARNING] LP creation failed");
            }
            if (tradingEnabled) {
                console.log("  [OK] Trading enabled");
            } else {
                console.log("  [WARNING] Trading not enabled");
            }
            if (operationalFunds > 0) {
                console.log("  [ACTION] Withdraw", operationalFunds / 1e18, "ETH");
            }
        }
    }
}