// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/DoubloonToken.sol";
import "../src/PixelPirates.sol";
import "../src/LPManager.sol";

contract DeployScript is Script {
    address constant SEADROP_ADDRESS = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5;
    address constant AERODROME_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address constant AERODROME_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=================================================================");
        console.log("DEPLOYING PIXELPIRATES TEST ON BASE");
        console.log("=================================================================");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance / 1e18, "ETH");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // =========================================================================
        // STEP 1: Deploy DoubloonToken
        // =========================================================================
        console.log("\n[STEP 1] Deploying DoubloonToken");
        DoubloonToken doubloonToken = new DoubloonToken();
        console.log("  DoubloonToken deployed at:", address(doubloonToken));
        
        // =========================================================================
        // STEP 2: Deploy PixelPirates with ZERO address for LPManager (temporary)
        // =========================================================================
        console.log("\n[STEP 2] Deploying PixelPirates (with placeholder LPManager)");
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = SEADROP_ADDRESS;
        
        PixelPirates pixelPirates = new PixelPirates(
            "PixelPirates",
            "PIXX",
            allowedSeaDrop,
            address(doubloonToken),
            address(0) // Placeholder - will be set in step 4
        );
        console.log("  PixelPirates deployed at:", address(pixelPirates));
        
        // =========================================================================
        // STEP 3: Deploy LPManager with correct NFT address
        // =========================================================================
        console.log("\n[STEP 3] Deploying LPManager");
        LPManager lpManager = new LPManager(
            address(pixelPirates), // Now we know the NFT address!
            address(doubloonToken),
            AERODROME_ROUTER,
            AERODROME_FACTORY
        );
        console.log("  LPManager deployed at:", address(lpManager));
        
        // =========================================================================
        // STEP 4: Update PixelPirates with real LPManager address
        // =========================================================================
        console.log("\n[STEP 4] Setting LPManager in PixelPirates");
        pixelPirates.setLPManager(address(lpManager));
        console.log("  [GOOD] LPManager address set in PixelPirates");
        
        // =========================================================================
        // STEP 5: Transfer LPManager ownership to NFT contract
        // =========================================================================
        console.log("\n[STEP 5] Configuring LPManager");
        lpManager.transferOwnership(address(pixelPirates));
        console.log("  [GOOD] LPManager ownership transferred to NFT contract");
        
        // =========================================================================
        // STEP 6: Link contracts
        // =========================================================================
        console.log("\n[STEP 6] Linking contracts");
        
        doubloonToken.setNFTContract(address(pixelPirates));
        console.log("  [GOOD] NFT contract linked to DoubloonToken");
        
        require(
            doubloonToken.nftContract() == address(pixelPirates),
            "NFT contract link failed!"
        );
        console.log("  [GOOD] Link verified");
        
        // =========================================================================
        // STEP 7: Configure transfer whitelist
        // =========================================================================
        console.log("\n[STEP 7] Configuring transfer whitelist");
        
        doubloonToken.setTransferWhitelist(address(pixelPirates), true);
        require(doubloonToken.transferWhitelist(address(pixelPirates)), "NFT whitelist failed!");
        console.log("  [1/3] NFT contract whitelisted");
        
        doubloonToken.setTransferWhitelist(AERODROME_ROUTER, true);
        require(doubloonToken.transferWhitelist(AERODROME_ROUTER), "Router whitelist failed!");
        console.log("  [2/3] Router whitelisted");
        
        doubloonToken.setTransferWhitelist(address(lpManager), true);
        require(doubloonToken.transferWhitelist(address(lpManager)), "LP Manager whitelist failed!");
        console.log("  [3/3] LP Manager whitelisted");
        
        // =========================================================================
        // STEP 8: Configure Fee Recipient
        // =========================================================================
        console.log("\n[STEP 8] Configuring fee recipient");
        pixelPirates.updateAllowedFeeRecipient(SEADROP_ADDRESS, deployer, true);
        console.log("  [GOOD] Fee recipient configured:", deployer);
        
        // =========================================================================
        // STEP 9: Final verification
        // =========================================================================
        console.log("\n[STEP 9] Final verification");
        
        require(doubloonToken.nftContract() == address(pixelPirates), "Link check failed!");
        require(doubloonToken.transferWhitelist(address(pixelPirates)), "NFT whitelist check failed!");
        require(doubloonToken.transferWhitelist(AERODROME_ROUTER), "Router whitelist check failed!");
        require(doubloonToken.transferWhitelist(address(lpManager)), "LP Manager whitelist failed!");
        require(doubloonToken.totalSupply() == 0, "Tokens already minted!");
        require(!doubloonToken.tradingEnabled(), "Trading already enabled!");
        require(pixelPirates.totalSupply() == 0, "NFTs already minted!");
        require(!pixelPirates.mintCompleted(), "Mint already completed!");
        require(pixelPirates.lpManager() == address(lpManager), "LP Manager not set correctly!");
        
        // Verify LPManager has correct NFT address
        require(lpManager.nftContract() == address(pixelPirates), "LPManager NFT address incorrect!");
        console.log("  [GOOD] LPManager NFT address verified");
        
        console.log("  [GOOD] All checks passed");
        
        vm.stopBroadcast();
        
        // =========================================================================
        // DEPLOYMENT SUMMARY
        // =========================================================================
        console.log("\n=================================================================");
        console.log("TEST DEPLOYMENT COMPLETE");
        console.log("=================================================================");
        console.log("DoubloonToken:", address(doubloonToken));
        console.log("LPManager:", address(lpManager));
        console.log("PixelPirates:", address(pixelPirates));
        console.log("");
        console.log("Save to .env:");
        console.log("DOUBLOON_TOKEN_ADDRESS=%s", address(doubloonToken));
        console.log("LP_MANAGER_ADDRESS=%s", address(lpManager));
        console.log("PIXELPIRATES_ADDRESS=%s", address(pixelPirates));
        console.log("");
        console.log("=================================================================");
        console.log("OPENSEA STUDIO CONFIGURATION");
        console.log("=================================================================");
        console.log("1. Go to: https://opensea.io/studio");
        console.log("2. Import your contract:", address(pixelPirates));
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
        console.log("   cast send %s 'updatePayoutAddress(address,address)' %s %s --private-key $PRIVATE_KEY --rpc-url $BASE_RPC_URL", address(pixelPirates), SEADROP_ADDRESS, address(pixelPirates));
        console.log("");
        console.log("2. Configure drop:");
        console.log("   cast send %s 'updatePublicDrop(address,(uint80,uint48,uint48,uint16,uint16,bool))' %s '(100000000000000,$(date +%%s),2000000000,3333,10,false)' --private-key $PRIVATE_KEY --rpc-url $BASE_RPC_URL", address(pixelPirates), SEADROP_ADDRESS);
        console.log("");
        console.log("3. Monitor: forge script script/CheckStatus.s.sol --rpc-url $BASE_RPC_URL");
        console.log("4. After sellout + 5min: cast send %s 'createLP()' --private-key $PRIVATE_KEY --rpc-url $BASE_RPC_URL", address(pixelPirates));
        console.log("5. Verify LP: Re-run CheckStatus.s.sol");
        console.log("6. Withdraw: cast send %s 'withdrawOperationalFunds()' --private-key $PRIVATE_KEY --rpc-url $BASE_RPC_URL", address(pixelPirates));
        console.log("=================================================================");
    }
}