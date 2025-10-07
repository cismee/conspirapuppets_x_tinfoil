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
    address constant WETH = 0x4200000000000000000000000000000000000006;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=================================================================");
        console.log("DEPLOYING CONSPIRAPUPPETS WITH SEADROP ON BASE");
        console.log("=================================================================");
        console.log("Deployer:", deployer);
        console.log("Current Balance:", deployer.balance / 1e18, "ETH");
        console.log("Block:", block.number);
        console.log("Timestamp:", block.timestamp);
        
        // =========================================================================
        // PRE-FLIGHT: Enhanced Funding Check with Gas Price Discovery
        // =========================================================================
        console.log("\n=================================================================");
        console.log("[PRE-FLIGHT] FUNDING ANALYSIS");
        console.log("=================================================================");
        
        // Try to get accurate gas price from RPC
        uint256 gasPrice;
        bool gasPriceFromRPC = false;
        
        try vm.parseBytes(vm.toString(abi.encode(block.basefee))) returns (bytes memory) {
            // Use block.basefee as a proxy for current gas price on Base L2
            gasPrice = block.basefee > 0 ? block.basefee : 0.001 gwei;
            if (block.basefee > 0) {
                gasPriceFromRPC = true;
                console.log("  Current base fee:", gasPrice / 1e9, "gwei");
            }
        } catch {
            // Fallback to tx.gasprice or conservative estimate
            gasPrice = tx.gasprice > 0 ? tx.gasprice : 0.01 gwei;
        }
        
        if (!gasPriceFromRPC) {
            console.log("  Estimated gas price (fallback):", gasPrice / 1e9, "gwei");
            console.log("  [INFO] Using conservative estimate");
        }
        
        // Estimate deployment costs with margin
        uint256 estimatedDeployGas = 15000000; // ~15M gas for deployment
        uint256 deploymentGasCost = estimatedDeployGas * gasPrice;
        
        // Add priority fee buffer for Base L2 (Base uses EIP-1559)
        uint256 priorityFeeBuffer = gasPrice * 2000000; // Extra 2M gas worth for priority
        uint256 totalDeploymentCost = deploymentGasCost + priorityFeeBuffer;
        
        // Future LP creation costs (owner will pay later)
        uint256 lpCreationGas = 1000000; // ~1M gas for LP transaction
        uint256 lpCreationCost = lpCreationGas * gasPrice * 2; // 2x buffer for uncertainty
        
        // Safety margin for retries and unexpected costs
        uint256 safetyMargin = 0.05 ether;
        
        // Total recommended
        uint256 recommendedMinimum = totalDeploymentCost + lpCreationCost + safetyMargin;
        
        console.log("");
        console.log("  DEPLOYMENT ESTIMATE:");
        console.log("    Gas needed:", estimatedDeployGas);
        console.log("    Base cost:", deploymentGasCost / 1e18, "ETH");
        console.log("    Priority fee buffer:", priorityFeeBuffer / 1e18, "ETH");
        console.log("    Subtotal:", totalDeploymentCost / 1e18, "ETH");
        console.log("");
        console.log("  LP CREATION ESTIMATE:");
        console.log("    Gas needed:", lpCreationGas);
        console.log("    Estimated cost:", lpCreationCost / 1e18, "ETH");
        console.log("");
        console.log("  SAFETY MARGIN:", safetyMargin / 1e18, "ETH");
        console.log("  ---");
        console.log("  TOTAL RECOMMENDED:", recommendedMinimum / 1e18, "ETH");
        console.log("  YOUR BALANCE:", deployer.balance / 1e18, "ETH");
        
        if (deployer.balance < recommendedMinimum) {
            uint256 shortfall = recommendedMinimum - deployer.balance;
            console.log("");
            console.log("  [CRITICAL] INSUFFICIENT BALANCE!");
            console.log("  [CRITICAL] Short by:", shortfall / 1e18, "ETH");
            console.log("");
            console.log("  ACTION REQUIRED:");
            console.log("  1. Send", shortfall / 1e18, "ETH to:", deployer);
            console.log("  2. Wait for confirmation");
            console.log("  3. Re-run this deployment script");
            console.log("");
            console.log("=================================================================");
            revert("Insufficient deployer balance - add more ETH and retry");
        } else {
            uint256 surplus = deployer.balance - recommendedMinimum;
            console.log("");
            console.log("  [OK] SUFFICIENT BALANCE");
            console.log("  [OK] Surplus after deployment:", surplus / 1e18, "ETH");
            
            if (surplus < 0.1 ether) {
                console.log("  [WARNING] Surplus is low");
                console.log("  [WARNING] Consider adding 0.1 ETH more for safety");
            } else {
                console.log("  [OK] Comfortable surplus for retries");
            }
        }
        
        console.log("=================================================================");
        
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
        
        // Check timing edge cases
        (bool isEdgeCase, string memory edgeReason) = conspirapuppets.isTimingEdgeCase();
        if (isEdgeCase) {
            console.log("  [WARNING] Timing edge case detected:", edgeReason);
        } else {
            console.log("  [GOOD] No timing edge cases detected");
        }
        
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
        console.log("SAVE THESE TO .env:");
        console.log("---");
        console.log("TINFOIL_TOKEN_ADDRESS=%s", address(tinfoilToken));
        console.log("CONSPIRAPUPPETS_ADDRESS=%s", address(conspirapuppets));
        console.log("LP_PAIR_ADDRESS=%s", lpPair);
        console.log("---");
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
        console.log("[GOOD] Timing safeguards in place");
        console.log("");
        console.log("=================================================================");
        console.log("MINT SCHEDULE");
        console.log("=================================================================");
        console.log("Current time:", block.timestamp);
        console.log("Mint starts:", startTime, "(in ~60 seconds)");
        console.log("Mint ends:", endTime);
        console.log("");
        console.log("=================================================================");
        console.log("POST-LAUNCH MONITORING");
        console.log("=================================================================");
        console.log("1. Monitor mint with CheckStatus.s.sol");
        console.log("2. After sell-out, wait 5 minutes for LP creation delay");
        console.log("3. Call createLP() to create liquidity pool");
        console.log("4. If issues arise, use RetryLP.s.sol");
        console.log("5. For diagnostics, use EmergencyRecover.s.sol");
        console.log("6. Withdraw operational funds after LP is live");
        console.log("");
        console.log("Commands:");
        console.log("  forge script script/CheckStatus.s.sol --rpc-url $BASE_RPC_URL");
        console.log("  cast send $CONSPIRAPUPPETS 'createLP()' --private-key $PRIVATE_KEY");
        console.log("=================================================================");
    }
}