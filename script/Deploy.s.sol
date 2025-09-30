// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/TinfoilToken.sol";
import "../src/Conspirapuppets.sol";

contract DeployScript is Script {
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
        
        console.log("\nStep 1: Deploying TinfoilToken");
        TinfoilToken tinfoilToken = new TinfoilToken();
        console.log("TinfoilToken deployed at:", address(tinfoilToken));
        
        console.log("\nStep 2: Deploying Conspirapuppets");
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
        
        console.log("\nStep 3: Linking contracts");
        tinfoilToken.setNFTContract(address(conspirapuppets));
        console.log("NFT contract linked to TinfoilToken");
        
        console.log("\nStep 4: Configuring Seadrop");
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
        
        console.log("\nStep 5: Setting up fee recipients");
        conspirapuppets.updateAllowedFeeRecipient(SEADROP_ADDRESS, deployer, true);
        console.log("Fee recipient configured");
        
        vm.stopBroadcast();
        
        console.log("\n=================================================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("=================================================================");
        console.log("TinfoilToken:", address(tinfoilToken));
        console.log("Conspirapuppets:", address(conspirapuppets));
        console.log("\nSave these addresses for verification and status checks");
    }
}