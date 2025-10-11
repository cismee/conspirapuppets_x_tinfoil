// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/TinfoilToken.sol";
import "../src/ConspiraPuppets.sol";
import "../src/LPManager.sol";

contract DeployScript is Script {
    address constant SEADROP_ADDRESS = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5;
    address constant AERODROME_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address constant AERODROME_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=================================================================");
        console.log("DEPLOYING CONSPIRAPUPPETS TEST ON BASE");
        console.log("=================================================================");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance / 1e18, "ETH");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // =========================================================================
        // STEP 1: Deploy TinfoilToken
        // =========================================================================
        console.log("\n[STEP 1] Deploying TinfoilToken");
        TinfoilToken tinfoilToken = new TinfoilToken();
        console.log("  TinfoilToken deployed at:", address(tinfoilToken));
        
        // =========================================================================
        // STEP 2: Deploy ConspiraPuppets with ZERO address for LPManager (temporary)
        // =========================================================================
        console.log("\n[STEP 2] Deploying ConspiraPuppets (with placeholder LPManager)");
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = SEADROP_ADDRESS;
        
        ConspiraPuppets conspiraPuppets = new ConspiraPuppets(
            "ConspiraPuppets",
            "CONSPIRA",
            allowedSeaDrop,
            address(tinfoilToken),
            address(0) // Placeholder - will be set in step 4
        );
        console.log("  ConspiraPuppets deployed at:", address(conspiraPuppets));
        
        // =========================================================================
        // STEP 3: Deploy LPManager with correct NFT address
        // =========================================================================
        console.log("\n[STEP 3] Deploying LPManager");
        LPManager lpManager = new LPManager(
            address(conspiraPuppets), // Now we know the NFT address!
            address(tinfoilToken),
            AERODROME_ROUTER,
            AERODROME_FACTORY
        );
        console.log("  LPManager deployed at:", address(lpManager));
        
        // =========================================================================
        // STEP 4: Update ConspiraPuppets with real LPManager address
        // =========================================================================
        console.log("\n[STEP 4] Setting LPManager in ConspiraPuppets");
        conspiraPuppets.setLPManager(address(lpManager));
        console.log("  [GOOD] LPManager address set in ConspiraPuppets");
        
        // =========================================================================
        // STEP 5: Transfer LPManager ownership to NFT contract
        // =========================================================================
        console.log("\n[STEP 5] Configuring LPManager");
        lpManager.transferOwnership(address(conspiraPuppets));
        console.log("  [GOOD] LPManager ownership transferred to NFT contract");
        
        // =========================================================================
        // STEP 6: Link contracts
        // =========================================================================
        console.log("\n[STEP 6] Linking contracts");
        
        tinfoilToken.setNFTContract(address(conspiraPuppets));
        console.log("  [GOOD] NFT contract linked to TinfoilToken");
        
        require(
            tinfoilToken.nftContract() == address(conspiraPuppets),
            "NFT contract link failed!"
        );
        console.log("  [GOOD] Link verified");
        
        // =========================================================================
        // STEP 7: Configure transfer whitelist
        // =========================================================================
        console.log("\n[STEP 7] Configuring transfer whitelist");
        
        tinfoilToken.setTransferWhitelist(address(conspiraPuppets), true);
        require(tinfoilToken.transferWhitelist(address(conspiraPuppets)), "NFT whitelist failed!");
        console.log("  [1/3] NFT contract whitelisted");
        
        tinfoilToken.setTransferWhitelist(AERODROME_ROUTER, true);
        require(tinfoilToken.transferWhitelist(AERODROME_ROUTER), "Router whitelist failed!");
        console.log("  [2/3] Router whitelisted");
        
        tinfoilToken.setTransferWhitelist(address(lpManager), true);
        require(tinfoilToken.transferWhitelist(address(lpManager)), "LP Manager whitelist failed!");
        console.log("  [3/3] LP Manager whitelisted");
        
        // =========================================================================
        // STEP 8: Configure Fee Recipient
        // =========================================================================
        console.log("\n[STEP 8] Configuring fee recipient");
        conspiraPuppets.updateAllowedFeeRecipient(SEADROP_ADDRESS, deployer, true);
        console.log("  [GOOD] Fee recipient configured:", deployer);
        
        // =========================================================================
        // STEP 9: Final verification
        // =========================================================================
        console.log("\n[STEP 9] Final verification");
        
        require(tinfoilToken.nftContract() == address(conspiraPuppets), "Link check failed!");
        require(tinfoilToken.transferWhitelist(address(conspiraPuppets)), "NFT whitelist check failed!");
        require(tinfoilToken.transferWhitelist(AERODROME_ROUTER), "Router whitelist check failed!");
        require(tinfoilToken.transferWhitelist(address(lpManager)), "LP Manager whitelist failed!");
        require(tinfoilToken.totalSupply() == 0, "Tokens already minted!");
        require(!tinfoilToken.tradingEnabled(), "Trading already enabled!");
        require(conspiraPuppets.totalSupply() == 0, "NFTs already minted!");
        require(!conspiraPuppets.mintCompleted(), "Mint already completed!");
        require(conspiraPuppets.lpManager() == address(lpManager), "LP Manager not set correctly!");
        
        // Verify LPManager has correct NFT address
        require(lpManager.nftContract() == address(conspiraPuppets), "LPManager NFT address incorrect!");
        console.log("  [GOOD] LPManager NFT address verified");
        
        console.log("  [GOOD] All checks passed");
        
        vm.stopBroadcast();
        
        // =========================================================================
        // DEPLOYMENT SUMMARY
        // =========================================================================
        console.log("\n=================================================================");
        console.log("TEST DEPLOYMENT COMPLETE");
        console.log("=================================================================");
        console.log("TinfoilToken:", address(tinfoilToken));
        console.log("LPManager:", address(lpManager));
        console.log("ConspiraPuppets:", address(conspiraPuppets));
        console.log("");
        console.log("Save to .env:");
        console.log("TINFOIL_TOKEN_ADDRESS=%s", address(tinfoilToken));
        console.log("LP_MANAGER_ADDRESS=%s", address(lpManager));
        console.log("CONSPIRAPUPPETS_ADDRESS=%s", address(conspiraPuppets));
        console.log("");
        console.log("=================================================================");
        console.log("OPENSEA STUDIO CONFIGURATION");
        console.log("=================================================================");
        console.log("1. Go to: https://opensea.io/studio");
        console.log("2. Import your contract:", address(conspiraPuppets));
        console.log("3. Configure mint settings:");
        console.log("   - Mint price (e.g., 0.0001 ETH)");
        console.log("   - Start time (when minting begins)");
        console.log("   - End time (when minting ends)");
        console.log("   - Max per wallet (e.g., 10 NFTs)");
        console.log("   - Max supply: MUST NOT EXCEED 3333");
        console.log("4. Upload metadata and images");
        console.log("5. Enable minting when ready to launch");
        console.log("");
        console.log("[IMPORTANT] Contract enforces MAX_SUPPLY = 3333 as safety cap");
        console.log("[NOTE] This is a TEST deployment - not production!");
        console.log("=================================================================");
        console.log("POST-LAUNCH WORKFLOW");
        console.log("=================================================================");
        console.log("1. Set payout FIRST:");
        console.log("   cast send %s 'updatePayoutAddress(address,address)' %s %s --private-key $PRIVATE_KEY --rpc-url $BASE_RPC_URL", address(conspiraPuppets), SEADROP_ADDRESS, address(conspiraPuppets));
        console.log("");
        console.log("2. Configure drop:");
        console.log("   cast send %s 'updatePublicDrop(address,(uint80,uint48,uint48,uint16,uint16,bool))' %s '(100000000000000,$(date +%%s),2000000000,3333,10,false)' --private-key $PRIVATE_KEY --rpc-url $BASE_RPC_URL", address(conspiraPuppets), SEADROP_ADDRESS);
        console.log("");
        console.log("3. Monitor: forge script script/CheckStatus.s.sol --rpc-url $BASE_RPC_URL");
        console.log("4. After sellout + 5min: cast send %s 'createLP()' --private-key $PRIVATE_KEY --rpc-url $BASE_RPC_URL", address(conspiraPuppets));
        console.log("5. Verify LP: Re-run CheckStatus.s.sol");
        console.log("6. Withdraw: cast send %s 'withdrawOperationalFunds()' --private-key $PRIVATE_KEY --rpc-url $BASE_RPC_URL", address(conspiraPuppets));
        console.log("=================================================================");
    }
}