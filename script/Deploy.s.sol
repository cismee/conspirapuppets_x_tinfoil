// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/TinfoilToken.sol";
import "../src/Conspirapuppets.sol";

contract DeployScript is Script {
    // Base network addresses
    address constant SEADROP_ADDRESS = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5; // Base Seadrop
    address constant AERODROME_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43; // Base Aerodrome
    
    function run() external {
        // Get deployment private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=================================================================");
        console.log("DEPLOYING CONSPIRAPUPPETS WITH SEADROP ON BASE");
        console.log("=================================================================");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance / 1e18, "ETH");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy TinfoilToken
        console.log("\nStep 1: Deploying TinfoilToken...");
        TinfoilToken tinfoilToken = new TinfoilToken();
        console.log("TinfoilToken deployed at:", address(tinfoilToken));
        
        // 2. Deploy Conspirapuppets
        console.log("\nStep 2: Deploying Conspirapuppets...");
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = SEADROP_ADDRESS;
        
        Conspirapuppets conspirapuppets = new Conspirapuppets(
            "Conspirapuppets",
            "CPUP",
            allowedSeaDrop,
            address(tinfoilToken),
            AERODROME_ROUTER
        );
        console.log("Conspirapuppets deployed at:", address(conspirapuppets));
        
        // 3. Link contracts
        console.log("\nStep 3: Linking contracts...");
        tinfoilToken.setNFTContract(address(conspirapuppets));
        console.log("NFT contract linked to TinfoilToken");
        
        // 4. Configure Seadrop
        console.log("\nStep 4: Configuring Seadrop...");
        uint48 startTime = uint48(block.timestamp);
        uint48 endTime = uint48(startTime + 30 days);
        
        PublicDrop memory publicDrop = PublicDrop({
            mintPrice: 0.005 ether,
            startTime: startTime,
            endTime: endTime,
            maxTotalMintableByWallet: 10,
            feeBps: 0,
            restrictFeeRecipients: true
        });
        
        conspirapuppets.configurePublicDrop(SEADROP_ADDRESS, publicDrop);
        console.log("Public drop configured");
        
        // 5. Set up fee recipients
        console.log("\nStep 5: Setting up fee recipients...");
        conspirapuppets.updateAllowedFeeRecipient(SEADROP_ADDRESS, deployer, true);
        console.log("Fee recipient configured");
        
        vm.stopBroadcast();
        
        // 6. Deployment Summary
        console.log("\n=================================================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("=================================================================");
        console.log("Contract Addresses:");
        console.log("  TinfoilToken:", address(tinfoilToken));
        console.log("  Conspirapuppets:", address(conspirapuppets));
        console.log("  Seadrop:", SEADROP_ADDRESS);
        console.log("  Aerodrome Router:", AERODROME_ROUTER);
        
        console.log("\nConfiguration:");
        console.log("  Mint Price: 0.005 ETH");
        console.log("  Max per wallet: 10 NFTs");
        console.log("  Total supply: 3,333 NFTs");
        console.log("  Tokens per NFT: 1,000,000 TINFOIL");
        
        console.log("\nEconomics:");
        console.log("  Total potential revenue: ~$66,600 (at 3,333 mints * 0.005 ETH * $4,000 ETH)");
        console.log("  LP lock: ~$33,300 ETH + 1.665B TINFOIL (LP tokens burned)");
        console.log("  Operations: ~$33,300 ETH");
        console.log("  Circulating tokens: 1.665B TINFOIL");
        
        console.log("\nNext Steps:");
        console.log("  1. Verify contracts on Basescan");
        console.log("  2. Collection appears on OpenSea automatically");
        console.log("  3. Monitor mint progress");
        console.log("  4. When 3,333rd NFT mints -> automatic explosive finale");
        
        console.log("\nVerification Commands:");
        console.log("  forge verify-contract", address(tinfoilToken), "src/TinfoilToken.sol:TinfoilToken --chain base");
        console.log("  forge verify-contract", address(conspirapuppets), "src/Conspirapuppets.sol:Conspirapuppets --chain base");
    }
}