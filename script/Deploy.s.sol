// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/TinfoilToken.sol";
import "../src/Conspirapuppets.sol";

contract DeployScript is Script {
    // Base network addresses
    address constant SEADROP_ADDRESS = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5;
    address constant AERODROME_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address constant AERODROME_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=================================================================");
        console.log("DEPLOYING CONSPIRAPUPPETS WITH SEADROP ON BASE");
        console.log("=================================================================");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance / 1e18, "ETH");
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("\nStep 1: Deploying TinfoilToken...");
        TinfoilToken tinfoilToken = new TinfoilToken();
        console.log("TinfoilToken deployed at:", address(tinfoilToken));
        
        console.log("\nStep 2: Deploying Conspirapuppets...");
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = SEADROP_ADDRESS;
        
        Conspirapuppets conspirapuppets = new Conspirapuppets(
            "Conspirapuppets",
            "CPUP",
            allowedSeaDrop,
            address(tinfoilToken),
            AERODROME_ROUTER,
            AERODROME_FACTORY
        );
        console.log("Conspirapuppets deployed at:", address(conspirapuppets));
        
        console.log("\nStep 3: Linking contracts...");
        tinfoilToken.setNFTContract(address(conspirapuppets));
        console.log("NFT contract linked to TinfoilToken");
        
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
        console.log("  Mint price: 0.005 ETH");
        console.log("  Max per wallet: 10");
        console.log("  Duration: 30 days");
        
        console.log("\nStep 5: Setting up fee recipients...");
        conspirapuppets.updateAllowedFeeRecipient(SEADROP_ADDRESS, deployer, true);
        console.log("Fee recipient configured");
        
        vm.stopBroadcast();
        
        console.log("\n=================================================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("=================================================================");
        console.log("Contract Addresses:");
        console.log("  TinfoilToken:", address(tinfoilToken));
        console.log("  Conspirapuppets:", address(conspirapuppets));
        console.log("  SeaDrop:", SEADROP_ADDRESS);
        console.log("  Aerodrome Router:", AERODROME_ROUTER);
        console.log("  Aerodrome Factory:", AERODROME_FACTORY);
        
        console.log("\nToken Economics:");
        console.log("  Max NFT Supply: 3,333");
        console.log("  Tokens per NFT: 499,549 TINFOIL");
        console.log("  NFT Allocation: 1,664,996,817 TINFOIL");
        console.log("  Remainder Mint: 3,183 TINFOIL (to owner)");
        console.log("  LP Allocation: 1,665,000,000 TINFOIL");
        console.log("  Total Supply: 3,330,000,000 TINFOIL");
        
        console.log("\nRevenue Split (at sellout):");
        console.log("  Total Revenue: 16.665 ETH");
        console.log("  LP (50%): 8.3325 ETH + 1.665B TINFOIL");
        console.log("  Operations (50%): 8.3325 ETH");
        console.log("  LP Tokens: BURNED (permanently locked)");
        
        console.log("\nNext Steps:");
        console.log("  1. Verify contracts on Basescan");
        console.log("  2. Collection appears on OpenSea automatically");
        console.log("  3. Monitor mint progress");
        console.log("  4. At sellout -> automatic LP creation & burn");
        console.log("  5. Trading enabled after LP burn");
        console.log("  6. Withdraw operational funds");
        
        console.log("\nIMPORTANT:");
        console.log("  - Remove mintForTesting() before mainnet deployment");
        console.log("  - Test on Base Sepolia first");
        console.log("  - Verify all contract addresses");
        
        console.log("\nVerification Commands:");
        console.log("forge verify-contract", address(tinfoilToken), "src/TinfoilToken.sol:TinfoilToken --chain base --etherscan-api-key $BASESCAN_API_KEY");
        console.log("forge verify-contract", address(conspirapuppets), "src/Conspirapuppets.sol:Conspirapuppets --chain base --etherscan-api-key $BASESCAN_API_KEY --constructor-args $(cast abi-encode 'constructor(string,string,address[],address,address,address)' 'Conspirapuppets' 'CPUP' '[0x00005EA00Ac477B1030CE78506496e8C2dE24bf5]'", address(tinfoilToken), AERODROME_ROUTER, AERODROME_FACTORY, ")");
    }
}