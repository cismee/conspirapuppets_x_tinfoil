// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/TinfoilToken.sol";
import "../src/Conspirapuppets.sol";

// REMOVED: interface IAerodromeFactory - already imported from Conspirapuppets.sol

contract DeployScript is Script {
    address constant SEADROP_ADDRESS = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5;
    address constant AERODROME_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address constant AERODROME_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=================================================================");
        console.log("DEPLOYING CONSPIRAPUPPETS WITH SEADROP ON BASE");
        console.log("=================================================================");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance / 1e18, "ETH");
        console.log("Timestamp:", block.timestamp);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // =========================================================================
        // STEP 1: Deploy TinfoilToken
        // =========================================================================
        console.log("\n[STEP 1] Deploying TinfoilToken");
        TinfoilToken tinfoilToken = new TinfoilToken();
        console.log("  TinfoilToken deployed at:", address(tinfoilToken));
        
        // =========================================================================
        // STEP 2: Deploy Conspirapuppets NFT
        // =========================================================================
        console.log("\n[STEP 2] Deploying Conspirapuppets");
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
        console.log("  Conspirapuppets deployed at:", address(conspirapuppets));
        
        // =========================================================================
        // STEP 3: CRITICAL - Link contracts BEFORE any mint configuration
        // This MUST happen before configuring SeaDrop or any mints will revert
        // =========================================================================
        console.log("\n[STEP 3] CRITICAL: Linking contracts BEFORE mint configuration");
        
        tinfoilToken.setNFTContract(address(conspirapuppets));
        console.log("  [GOOD] NFT contract linked to TinfoilToken");
        
        // VERIFY the link worked
        address linkedNFT = tinfoilToken.nftContract();
        require(linkedNFT == address(conspirapuppets), "CRITICAL: NFT contract link failed!");
        console.log("  [GOOD] Verified: nftContract() returns", linkedNFT);
        
        // =========================================================================
        // STEP 4: Configure transfer whitelist
        // =========================================================================
        console.log("\n[STEP 4] Configuring transfer whitelist");
        
        // Whitelist NFT contract
        tinfoilToken.setTransferWhitelist(address(conspirapuppets), true);
        require(tinfoilToken.transferWhitelist(address(conspirapuppets)), "NFT whitelist failed!");
        console.log("  [1/3] NFT contract whitelisted:", address(conspirapuppets));
        
        // Whitelist Aerodrome Router
        tinfoilToken.setTransferWhitelist(AERODROME_ROUTER, true);
        require(tinfoilToken.transferWhitelist(AERODROME_ROUTER), "Router whitelist failed!");
        console.log("  [2/3] Aerodrome Router whitelisted:", AERODROME_ROUTER);
        
        // Pre-create and whitelist LP pair
        IAerodromeFactory factory = IAerodromeFactory(AERODROME_FACTORY);
        address existingPair = factory.getPair(address(tinfoilToken), WETH, false);
        
        address lpPair;
        if (existingPair == address(0)) {
            console.log("  [INFO] Creating LP pair...");
            lpPair = factory.createPair(address(tinfoilToken), WETH, false);
            console.log("  [INFO] LP pair created at:", lpPair);
        } else {
            console.log("  [WARNING] LP pair already exists at:", existingPair);
            lpPair = existingPair;
        }
        
        tinfoilToken.setTransferWhitelist(lpPair, true);
        require(tinfoilToken.transferWhitelist(lpPair), "LP pair whitelist failed!");
        console.log("  [3/3] LP Pair whitelisted:", lpPair);
        
        // =========================================================================
        // STEP 5: Configure Seadrop (AFTER linking is complete and verified)
        // =========================================================================
        console.log("\n[STEP 5] Configuring Seadrop public drop");
        
        // Set start time 1 minute in the future to ensure all setup is complete
        uint48 startTime = uint48(block.timestamp + 1 minutes);
        uint48 endTime = uint48(startTime + 30 days);
        
        console.log("  Mint start time:", startTime);
        console.log("  Mint end time:", endTime);
        console.log("  Time until mint starts:", startTime - block.timestamp, "seconds");
        
        PublicDrop memory publicDrop = PublicDrop({
            mintPrice: 0.005 ether,
            startTime: startTime,  // Delayed start
            endTime: endTime,
            maxTotalMintableByWallet: 10,
            feeBps: 0,
            restrictFeeRecipients: true
        });
        
        conspirapuppets.configurePublicDrop(SEADROP_ADDRESS, publicDrop);
        console.log("  [GOOD] Public drop configured");
        console.log("  [!] Mint price: 0.005 ETH");
        console.log("  [!] Max per wallet: 10");
        
        // =========================================================================
        // STEP 6: Configure fee recipients
        // =========================================================================
        console.log("\n[STEP 6] Setting up fee recipients");
        
        conspirapuppets.updateAllowedFeeRecipient(SEADROP_ADDRESS, deployer, true);
        console.log("  [GOOD] Fee recipient configured");
        
        // =========================================================================
        // STEP 7: Final verification before mint goes live
        // =========================================================================
        console.log("\n[STEP 7] Final pre-launch verification");
        
        // Verify TinfoilToken setup
        require(tinfoilToken.nftContract() == address(conspirapuppets), "NFT link verification failed!");
        console.log("  [GOOD] NFT contract link verified");
        
        require(tinfoilToken.transferWhitelist(address(conspirapuppets)), "NFT whitelist verification failed!");
        console.log("  [GOOD] NFT contract whitelist verified");
        
        require(tinfoilToken.transferWhitelist(AERODROME_ROUTER), "Router whitelist verification failed!");
        console.log("  [GOOD] Router whitelist verified");
        
        require(tinfoilToken.transferWhitelist(lpPair), "LP pair whitelist verification failed!");
        console.log("  [GOOD] LP pair whitelist verified");
        
        // Verify token state
        require(tinfoilToken.totalSupply() == 0, "Tokens already minted!");
        console.log("  [GOOD] No tokens minted yet");
        
        require(!tinfoilToken.tradingEnabled(), "Trading already enabled!");
        console.log("  [GOOD] Trading disabled");
        
        // Verify NFT state
        require(conspirapuppets.totalSupply() == 0, "NFTs already minted!");
        console.log("  [GOOD] No NFTs minted yet");
        
        require(!conspirapuppets.mintCompleted(), "Mint already completed!");
        console.log("  [GOOD] Mint not completed");
        
        vm.stopBroadcast();
        
        // =========================================================================
        // DEPLOYMENT SUMMARY
        // =========================================================================
        console.log("\n=================================================================");
        console.log("DEPLOYMENT COMPLETE - READY FOR LAUNCH");
        console.log("=================================================================");
        console.log("TinfoilToken:", address(tinfoilToken));
        console.log("Conspirapuppets:", address(conspirapuppets));
        console.log("LP Pair:", lpPair);
        console.log("");
        console.log("IMPORTANT: Add to .env:");
        console.log("TINFOIL_TOKEN_ADDRESS=", address(tinfoilToken));
        console.log("CONSPIRAPUPPETS_ADDRESS=", address(conspirapuppets));
        console.log("LP_PAIR_ADDRESS=", lpPair);
        console.log("");
        console.log("=================================================================");
        console.log("PRE-LAUNCH CHECKLIST");
        console.log("=================================================================");
        console.log("[GOOD] Token deployed");
        console.log("[GOOD] NFT deployed");
        console.log("[GOOD] Contracts linked (setNFTContract called)");
        console.log("[GOOD] Transfer whitelist configured (NFT + Router + LP)");
        console.log("[GOOD] SeaDrop configured");
        console.log("[GOOD] Fee recipients configured");
        console.log("[GOOD] All verifications passed");
        console.log("");
        console.log("=================================================================");
        console.log("MINT SCHEDULE");
        console.log("=================================================================");
        console.log("Current time:", block.timestamp);
        console.log("Mint starts:", startTime);
        console.log("Mint ends:", endTime);
        console.log("");
        console.log("Time until launch:", startTime - block.timestamp, "seconds");
        console.log("");
        console.log("[!] Mint will be LIVE in ~1 minute");
        console.log("[!] Verify everything is correct before minting starts");
        console.log("=================================================================");
    }
}