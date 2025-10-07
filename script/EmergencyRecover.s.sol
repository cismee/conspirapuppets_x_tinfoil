// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/TinfoilToken.sol";
import "../src/Conspirapuppets.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract EmergencyRecoverScript is Script {
    address constant AERODROME_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    address constant AERODROME_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    function run() external view {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address tinfoilAddress = vm.envAddress("TINFOIL_TOKEN_ADDRESS");
        address payable nftAddress = payable(vm.envAddress("CONSPIRAPUPPETS_ADDRESS"));
        
        console.log("=================================================================");
        console.log("EMERGENCY RECOVERY TOOL");
        console.log("=================================================================");
        console.log("Operator:", deployer);
        console.log("TinfoilToken:", tinfoilAddress);
        console.log("Conspirapuppets:", nftAddress);
        
        TinfoilToken tinfoilToken = TinfoilToken(tinfoilAddress);
        Conspirapuppets conspirapuppets = Conspirapuppets(nftAddress);
        
        // Diagnostic checks
        console.log("\n[DIAGNOSTIC CHECKS]");
        
        (
            uint256 totalSupply,
            ,
            bool mintCompleted,
            uint256 contractBalance,
            ,
            uint256 operationalFunds,
            bool lpCreated,
            uint256 totalEthReceived
        ) = conspirapuppets.getMintStatus();
        
        console.log("  NFTs Minted:", totalSupply);
        console.log("  Mint Completed:", mintCompleted);
        console.log("  LP Created:", lpCreated);
        console.log("  Contract Balance:", contractBalance / 1e18, "ETH");
        console.log("  Operational Funds:", operationalFunds / 1e18, "ETH");
        console.log("  Total ETH Received:", totalEthReceived / 1e18, "ETH");
        
        // Check token balances
        uint256 nftTokenBalance = tinfoilToken.balanceOf(nftAddress);
        console.log("  Tokens in NFT contract:", nftTokenBalance / 1e18);
        
        // Check LP pair
        IAerodromeFactory factory = IAerodromeFactory(AERODROME_FACTORY);
        address pair = factory.getPair(tinfoilAddress, WETH, false);
        console.log("  LP Pair:", pair);
        
        if (pair != address(0)) {
            uint256 tokenInPair = tinfoilToken.balanceOf(pair);
            uint256 ethInPair = IERC20(WETH).balanceOf(pair);
            uint256 lpAtBurn = IERC20(pair).balanceOf(BURN_ADDRESS);
            
            console.log("  Tokens in Pair:", tokenInPair / 1e18);
            console.log("  ETH in Pair:", ethInPair / 1e18);
            console.log("  LP at Burn:", lpAtBurn / 1e18);
        }
        
        // Check whitelists
        bool nftWhitelisted = tinfoilToken.transferWhitelist(nftAddress);
        bool routerWhitelisted = tinfoilToken.transferWhitelist(AERODROME_ROUTER);
        bool pairWhitelisted = pair != address(0) ? tinfoilToken.transferWhitelist(pair) : false;
        
        console.log("\n[WHITELIST STATUS]");
        console.log("  NFT Contract:", nftWhitelisted ? "YES" : "NO");
        console.log("  Router:", routerWhitelisted ? "YES" : "NO");
        console.log("  LP Pair:", pairWhitelisted ? "YES" : "NO");
        
        // Trading status
        bool tradingEnabled = tinfoilToken.tradingEnabled();
        console.log("\n[TRADING STATUS]");
        console.log("  Trading Enabled:", tradingEnabled);
        
        console.log("\n=================================================================");
        console.log("RECOVERY OPTIONS");
        console.log("=================================================================");
        
        if (!mintCompleted) {
            console.log("[INFO] Mint not completed - no recovery needed yet");
            console.log("  Wait for sell-out to complete");
            return;
        }
        
        if (lpCreated && tradingEnabled) {
            console.log("[SUCCESS] System is healthy - no recovery needed");
            if (operationalFunds > 0) {
                console.log("  Action: Withdraw", operationalFunds / 1e18, "ETH operational funds");
            }
            return;
        }
        
        // Recovery scenarios
        if (!lpCreated && nftTokenBalance >= 1665000000 * 1e18) {
            console.log("\n[SCENARIO 1] LP creation failed but tokens are ready");
            console.log("  Tokens minted:", nftTokenBalance / 1e18);
            console.log("  ETH available:", (contractBalance - operationalFunds) / 1e18);
            console.log("");
            console.log("  Suggested action:");
            console.log("  1. Use RetryLP.s.sol for automatic retry");
            console.log("  2. Or use emergencyLPCreation with these params:");
            console.log("     tokens: %s", nftTokenBalance);
            console.log("     eth: %s", contractBalance - operationalFunds);
            console.log("     slippage: 9999 (99.99%)");
            console.log("     gas: 5000000");
        }
        
        if (!lpCreated && nftTokenBalance == 0) {
            console.log("\n[SCENARIO 2] Tokens not minted for LP yet");
            console.log("  This is unusual - tokens should be minted");
            console.log("");
            console.log("  Suggested action:");
            console.log("  1. Call completeMint() to trigger the process");
            console.log("  2. Then retry LP creation");
        }
        
        if (lpCreated && !tradingEnabled) {
            console.log("\n[SCENARIO 3] LP created but trading not enabled");
            console.log("  LP Pair:", pair);
            console.log("");
            console.log("  Suggested action:");
            console.log("  Call enableTradingManual() to enable trading");
        }
        
        if (!nftWhitelisted || !routerWhitelisted) {
            console.log("\n[SCENARIO 4] Critical whitelist missing");
            console.log("  This will cause LP creation to fail");
            console.log("");
            console.log("  Required actions:");
            if (!nftWhitelisted) {
                console.log("  1. Whitelist NFT contract:");
                console.log("     cast send %s", tinfoilAddress);
                console.log("     'setTransferWhitelist(address,bool)'");
                console.log("     %s true --private-key $PRIVATE_KEY", nftAddress);
            }
            if (!routerWhitelisted) {
                console.log("  2. Whitelist Router:");
                console.log("     cast send %s", tinfoilAddress);
                console.log("     'setTransferWhitelist(address,bool)'");
                console.log("     %s true --private-key $PRIVATE_KEY", AERODROME_ROUTER);
            }
            if (pair != address(0) && !pairWhitelisted) {
                console.log("  3. Whitelist LP Pair:");
                console.log("     cast send %s", tinfoilAddress);
                console.log("     'setTransferWhitelist(address,bool)'");
                console.log("     %s true --private-key $PRIVATE_KEY", pair);
            }
        }
        
        console.log("\n=================================================================");
        console.log("LAST RESORT OPTIONS");
        console.log("=================================================================");
        console.log("If all LP creation attempts fail:");
        console.log("");
        console.log("Option A: Emergency withdrawal");
        console.log("  1. Call emergencyWithdraw() on NFT contract");
        console.log("  2. Recover all ETH to owner");
        console.log("  3. Manually create LP via Aerodrome UI");
        console.log("  4. Call enableTradingManual()");
        console.log("");
        console.log("Option B: Contact Aerodrome support");
        console.log("  If router is malfunctioning");
        console.log("  Discord: discord.gg/aerodrome");
        console.log("=================================================================");
    }
}