// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/ConspiraPuppets.sol";

contract RetryLPScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable nftAddress = payable(vm.envAddress("CONSPIRAPUPPETS_ADDRESS"));
        
        console.log("=================================================================");
        console.log("LP CREATION RETRY TOOL");
        console.log("=================================================================");
        console.log("NFT Contract:", nftAddress);
        console.log("Caller:", vm.addr(deployerPrivateKey));
        console.log("Block:", block.number);
        console.log("Timestamp:", block.timestamp);
        
        ConspiraPuppets conspiraPuppets = ConspiraPuppets(nftAddress);
        
        // Get current status
        (
            ,
            ,
            bool mintCompleted,
            uint256 contractBalance,
            ,
            uint256 operationalFunds,
            bool lpCreated,
            
        ) = conspiraPuppets.getMintStatus();
        
        console.log("\n[STATUS CHECK]");
        console.log("  Mint Completed:", mintCompleted);
        console.log("  LP Created:", lpCreated);
        console.log("  Contract Balance:", contractBalance / 1e18, "ETH");
        console.log("  Operational Funds:", operationalFunds / 1e18, "ETH");
        console.log("  Available for LP:", (contractBalance - operationalFunds) / 1e18, "ETH");
        
        require(mintCompleted, "Mint not completed yet - nothing to retry");
        require(!lpCreated, "LP already created successfully");
        require(contractBalance > operationalFunds, "No ETH available for LP");
        
        uint256 availableETH = contractBalance - operationalFunds;
        
        console.log("\n[RETRY STRATEGY]");
        console.log("  Will attempt LP creation with", availableETH / 1e18, "ETH");
        console.log("  Using 50% slippage tolerance (very safe)");
        console.log("  With automatic retry on failure");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Strategy: Try with increasing gas limits
        uint256[3] memory gasLimits = [uint256(3000000), 5000000, 8000000];
        
        for (uint256 i = 0; i < gasLimits.length; i++) {
            console.log("\n[ATTEMPT %s] Gas limit:", i + 1, gasLimits[i]);
            
            try conspiraPuppets.retryLPCreation{gas: gasLimits[i]}() {
                console.log("  [SUCCESS] LP creation succeeded!");
                
                // Verify it worked
                (, , , , , , bool nowCreated, ) = conspiraPuppets.getMintStatus();
                if (nowCreated) {
                    console.log("  [VERIFIED] LP is now created");
                    vm.stopBroadcast();
                    
                    console.log("\n=================================================================");
                    console.log("LP CREATION SUCCESSFUL");
                    console.log("=================================================================");
                    console.log("Next steps:");
                    console.log("  1. Run CheckStatus.s.sol to verify LP");
                    console.log("  2. Withdraw operational funds");
                    console.log("=================================================================");
                    return;
                } else {
                    console.log("  [WARNING] Call succeeded but LP not created");
                    console.log("  [INFO] Trying next gas limit...");
                }
                
            } catch Error(string memory reason) {
                console.log("  [FAILED] Reason:", reason);
                if (i < gasLimits.length - 1) {
                    console.log("  [INFO] Trying with higher gas limit...");
                }
            } catch (bytes memory) {
                console.log("  [FAILED] Unknown error");
                if (i < gasLimits.length - 1) {
                    console.log("  [INFO] Trying with higher gas limit...");
                }
            }
        }
        
        vm.stopBroadcast();
        
        console.log("\n=================================================================");
        console.log("ALL RETRY ATTEMPTS FAILED");
        console.log("=================================================================");
        console.log("Manual intervention required:");
        console.log("");
        console.log("Option 1: Use emergencyLPCreation with custom parameters");
        console.log("  Check contract balance and token balance first");
        console.log("  Then call with exact amounts and high gas");
        console.log("");
        console.log("Option 2: Check for issues");
        console.log("  - Verify whitelist: tokens, router, LP pair");
        console.log("  - Check if pair already exists");
        console.log("  - Verify sufficient ETH in contract");
        console.log("  - Check RPC provider is responsive");
        console.log("");
        console.log("Option 3: Emergency withdrawal");
        console.log("  If LP cannot be created, withdraw funds");
        console.log("  Then investigate and try again");
        console.log("=================================================================");
    }
}