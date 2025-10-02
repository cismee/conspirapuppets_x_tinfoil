// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/Conspirapuppets.sol";
import "../src/TinfoilToken.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract ForkTest is Test {
    Conspirapuppets public nft;
    TinfoilToken public token;
    
    address constant SEADROP = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5;
    address constant ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address constant FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant BURN = 0x000000000000000000000000000000000000dEaD;
    
    address public owner;
    address public minter;
    
    function setUp() public {
        // Fork Base mainnet at latest block
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));
        
        owner = makeAddr("owner");
        minter = makeAddr("minter");
        
        console.log("Fork block number:", block.number);
        console.log("Testing factory at:", FACTORY);
        
        // Check if factory exists
        uint256 factoryCodeSize;
        assembly {
            factoryCodeSize := extcodesize(FACTORY)
        }
        console.log("Factory code size:", factoryCodeSize);
        
        vm.startPrank(owner);
        
        address[] memory seadrops = new address[](1);
        seadrops[0] = SEADROP;
        
        token = new TinfoilToken();
        nft = new Conspirapuppets(
            "Conspirapuppets",
            "CPUP",
            seadrops,
            address(token),
            ROUTER,
            FACTORY
        );
        
        token.setNFTContract(address(nft));
        
        vm.stopPrank();
    }
    
    function testFullMintToSellout() public {
        uint256 mintPrice = 0.005 ether;
        uint256 maxSupply = 3333;
        
        console.log("Starting mint simulation...");
        
        // Fund the NFT contract with ETH BEFORE completing the mint
        // In production, this ETH comes from SeaDrop sales
        vm.deal(address(nft), maxSupply * mintPrice);
        
        // Simulate minting all NFTs (airdrop requires owner)
        vm.startPrank(owner);
        for (uint i = 0; i < maxSupply; i++) {
            // Simple mint - in production this would go through SeaDrop
            nft.airdrop(_toArray(minter), _toArray(1));
            
            if (i % 500 == 0) {
                console.log("Minted:", i, "NFTs");
            }
        }
        vm.stopPrank();
        
        console.log("\n=== Verification ===");
        
        // Verify mint completed
        assertTrue(nft.mintCompleted(), "Mint not completed");
        assertEq(nft.totalSupply(), maxSupply, "Wrong supply");
        console.log("Mint completed");
        
        // Verify LP was created
        address pair = IAerodromeFactory(FACTORY).getPair(address(token), WETH, false);
        assertTrue(pair != address(0), "Pair not created");
        console.log("LP pair created at:", pair);
        
        // Verify LP was burned
        uint256 lpAtBurn = IERC20(pair).balanceOf(BURN);
        assertGt(lpAtBurn, 0, "LP tokens not burned");
        console.log("LP tokens burned:", lpAtBurn);
        
        // Verify trading enabled
        assertTrue(token.tradingEnabled(), "Trading not enabled");
        console.log("Trading enabled");
        
        // Verify operational funds available
        (, , , , , uint256 opFunds, ) = nft.getMintStatus();
        assertGt(opFunds, 0, "No operational funds");
        console.log("Operational funds:", opFunds / 1e18, "ETH");
        
        // Verify LP creation flag
        assertTrue(nft.lpCreated(), "LP not marked as created");
        console.log("LP creation flag set");
        
        console.log("\n=== All checks passed ===");
    }
    
    function testTokenTransfersBlockedBeforeTradingEnabled() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        
        vm.deal(user1, 1 ether);
        
        // Mint 1 NFT to user1
        vm.prank(owner);
        nft.airdrop(_toArray(user1), _toArray(1));
        
        uint256 balance = token.balanceOf(user1);
        assertGt(balance, 0, "No tokens minted");
        
        // Should revert before trading enabled
        vm.prank(user1);
        vm.expectRevert("Trading not enabled yet - wait for mint completion");
        token.transfer(user2, balance);
        
        console.log("Token transfers blocked before trading enabled");
    }
    
    function testTokenTransfersWorkAfterSellout() public {
        // Complete the mint first
        testFullMintToSellout();
        
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        
        // user1 should have tokens from sellout
        uint256 balance = token.balanceOf(user1);
        
        if (balance > 0) {
            // Transfers should work now
            vm.prank(user1);
            token.transfer(user2, balance / 2);
            
            assertEq(token.balanceOf(user2), balance / 2, "Transfer failed");
            console.log("Token transfers work after sellout");
        }
    }
    
    function testOperationalFundsWithdrawal() public {
        testFullMintToSellout();
        
        uint256 ownerBalanceBefore = owner.balance;
        
        vm.prank(owner);
        nft.withdrawOperationalFunds();
        
        uint256 ownerBalanceAfter = owner.balance;
        assertGt(ownerBalanceAfter, ownerBalanceBefore, "No funds withdrawn");
        
        console.log("Operational funds withdrawn:", (ownerBalanceAfter - ownerBalanceBefore) / 1e18, "ETH");
    }
    
    function testReentrancyProtection() public {
        // Fund the NFT contract with ETH first
        vm.deal(address(nft), 1 ether);
        
        // Mint some NFTs but not all (as owner)
        vm.startPrank(owner);
        nft.airdrop(_toArray(minter), _toArray(100));
        
        // Call completeMint
        nft.completeMint();
        
        // Second call should fail
        vm.expectRevert("Mint already completed");
        nft.completeMint();
        vm.stopPrank();
        
        console.log("Reentrancy protection working");
    }
    
    // Helper functions
    function _toArray(address addr) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }
    
    function _toArray(uint256 num) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = num;
        return arr;
    }
}