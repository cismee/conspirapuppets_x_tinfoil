// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/TinfoilToken.sol";
import "../src/Conspirapuppets.sol";
import "../src/LPManager.sol";

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
        
        // =========================================================================
        // STEP 1: Deploy TinfoilToken
        // =========================================================================
        console.log("\n[STEP 1] Deploying TinfoilToken");
        TinfoilToken tinfoilToken = new TinfoilToken();
        console.log("  TinfoilToken deployed at:", address(tinfoilToken));
        
        // =========================================================================
        // STEP 2: Deploy LPManager (placeholder NFT address for now)
        // =========================================================================
        console.log("\n[STEP 2] Deploying LPManager");
        LPManager lpManager = new LPManager(
            address(0), // Will update after NFT deployment
            address(tinfoilToken),
            AERODROME_ROUTER,
            AERODROME_FACTORY
        );
        console.log("  LPManager deployed at:", address(lpManager));
        
        // =========================================================================
        // STEP 3: Deploy Conspirapuppets NFT
        // =========================================================================
        console.log("\n[STEP 3] Deploying Conspirapuppets");
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = SEADROP_ADDRESS;
        
        Conspirapuppets conspirapuppets = new Conspirapuppets(
            "Conspirapuppets",
            "CPUP",
            allowedSeaDrop,
            address(tinfoilToken),
            address(lpManager)
        );
        console.log("  Conspirapuppets deployed at:", address(conspirapuppets));
        
        // =========================================================================
        // STEP 4: Update LPManager with NFT contract address
        // =========================================================================
        console.log("\n[STEP 4] Configuring LPManager");
        lpManager.transferOwnership(address(conspirapuppets));
        console.log("  [GOOD] LPManager ownership transferred to NFT contract");
        
        // =========================================================================
        // STEP 5: Link contracts
        // =========================================================================
        console.log("\n[STEP 5] Linking contracts");
        
        tinfoilToken.setNFTContract(address(conspirapuppets));
        console.log("  [GOOD] NFT contract linked to TinfoilToken");
        
        require(
            tinfoilToken.nftContract() == address(conspirapuppets),
            "NFT contract link failed!"
        );
        console.log("  [GOOD] Link verified");
        
        // =========================================================================
        // STEP 6: Configure transfer whitelist
        // =========================================================================
        console.log("\n[STEP 6] Configuring transfer whitelist");
        
        tinfoilToken.setTransferWhitelist(address(conspirapuppets), true);
        require(tinfoilToken.transferWhitelist(address(conspirapuppets)), "NFT whitelist failed!");
        console.log("  [1/3] NFT contract whitelisted");
        
        tinfoilToken.setTransferWhitelist(AERODROME_ROUTER, true);
        require(tinfoilToken.transferWhitelist(AERODROME_ROUTER), "Router whitelist failed!");
        console.log("  [2/3] Router whitelisted");
        
        tinfoilToken.setTransferWhitelist(address(lpManager), true);
        require(tinfoilToken.transferWhitelist(address(lpManager)), "LP Manager whitelist failed!");
        console.log("  [3/3] LP Manager whitelisted");
        
        // =========================================================================
        // STEP 7: Configure Fee Recipient
        // =========================================================================
        console.log("\n[STEP 7] Configuring fee recipient");
        conspirapuppets.updateAllowedFeeRecipient(SEADROP_ADDRESS, deployer, true);
        console.log("  [GOOD] Fee recipient configured:", deployer);
        
        // =========================================================================
        // STEP 8: Final verification
        // =========================================================================
        console.log("\n[STEP 8] Final verification");
        
        require(tinfoilToken.nftContract() == address(conspirapuppets), "Link check failed!");
        require(tinfoilToken.transferWhitelist(address(conspirapuppets)), "NFT whitelist check failed!");
        require(tinfoilToken.transferWhitelist(AERODROME_ROUTER), "Router whitelist check failed!");
        require(tinfoilToken.transferWhitelist(address(lpManager)), "LP Manager whitelist check failed!");
        require(tinfoilToken.totalSupply() == 0, "Tokens already minted!");
        require(!tinfoilToken.tradingEnabled(), "Trading already enabled!");
        require(conspirapuppets.totalSupply() == 0, "NFTs already minted!");
        require(!conspirapuppets.mintCompleted(), "Mint already completed!");
        
        console.log("  [GOOD] All checks passed");
        
        vm.stopBroadcast();
        
        // =========================================================================
        // DEPLOYMENT SUMMARY
        // =========================================================================
        console.log("\n=================================================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("=================================================================");
        console.log("TinfoilToken:", address(tinfoilToken));
        console.log("LPManager:", address(lpManager));
        console.log("Conspirapuppets:", address(conspirapuppets));
        console.log("");
        console.log("Save to .env:");
        console.log("TINFOIL_TOKEN_ADDRESS=%s", address(tinfoilToken));
        console.log("LP_MANAGER_ADDRESS=%s", address(lpManager));
        console.log("CONSPIRAPUPPETS_ADDRESS=%s", address(conspirapuppets));
        console.log("");
        console.log("=================================================================");
        console.log("OPENSEA STUDIO CONFIGURATION");
        console.log("=================================================================");
        console.log("1. Go to: https://opensea.io/studio");
        console.log("2. Import your contract:", address(conspirapuppets));
        console.log("3. Configure mint settings:");
        console.log("   - Mint price (e.g., 0.005 ETH)");
        console.log("   - Start time (when minting begins)");
        console.log("   - End time (when minting ends)");
        console.log("   - Max per wallet (e.g., 10 NFTs)");
        console.log("   - Max supply: MUST NOT EXCEED 3333");
        console.log("4. Upload metadata and images");
        console.log("5. Enable minting when ready to launch");
        console.log("");
        console.log("[IMPORTANT] Contract enforces MAX_SUPPLY = 3333 as safety cap");
        console.log("=================================================================");
        console.log("POST-LAUNCH WORKFLOW");
        console.log("=================================================================");
        console.log("1. Monitor: forge script script/CheckStatus.s.sol --rpc-url $BASE_RPC_URL");
        console.log("2. After sellout + 5min: cast send $CONSPIRAPUPPETS 'createLP()' --private-key $PK");
        console.log("3. Verify LP: Re-run CheckStatus.s.sol");
        console.log("4. Withdraw: cast send $CONSPIRAPUPPETS 'withdrawOperationalFunds()' --private-key $PK");
        console.log("=================================================================");
    }
}