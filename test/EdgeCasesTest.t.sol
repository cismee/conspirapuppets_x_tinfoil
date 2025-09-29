// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/TinfoilToken.sol";
import "../src/Conspirapuppets.sol";

contract MockSeaDrop {
    function updatePublicDrop(address, bytes calldata) external {}
    function updateAllowedFeeRecipient(address, address, bool) external {}
}

contract MockAerodromeFactory {
    address public mockPair;
    
    constructor() {
        mockPair = address(new MockLPToken());
    }
    
    function getPair(address, address) external view returns (address) {
        return mockPair;
    }
}

contract MockAerodromeRouter {
    address public factory;
    
    constructor(address _factory) {
        factory = _factory;
    }
    
    function addLiquidityETH(
        address token,
        bool stable,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        amountToken = amountTokenDesired;
        amountETH = msg.value;
        liquidity = amountTokenDesired;
        
        address pair = MockAerodromeFactory(factory).getPair(token, address(0));
        MockLPToken(pair).mint(to, liquidity);
        
        console.log("Mock LP created with tokens and ETH");
        return (amountToken, amountETH, liquidity);
    }
}

contract MockLPToken {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract ConspiraPuppetsTest is Test {
    TinfoilToken public tinfoilToken;
    Conspirapuppets public conspirapuppets;
    MockSeaDrop public mockSeaDrop;
    MockAerodromeFactory public mockFactory;
    MockAerodromeRouter public mockRouter;
    
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    
    uint256 constant MINT_PRICE = 0.005 ether;
    uint256 constant MAX_SUPPLY = 3333;
    uint256 constant TOKENS_PER_NFT = 499_549 * 10**18;
    
    receive() external payable {}
    
    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        
        mockSeaDrop = new MockSeaDrop();
        mockFactory = new MockAerodromeFactory();
        mockRouter = new MockAerodromeRouter(address(mockFactory));
        
        tinfoilToken = new TinfoilToken();
        
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = address(mockSeaDrop);
        
        conspirapuppets = new Conspirapuppets(
            "Conspirapuppets",
            "CPUP",
            allowedSeaDrop,
            address(tinfoilToken),
            address(mockRouter),
            address(mockFactory)
        );
        
        tinfoilToken.setNFTContract(address(conspirapuppets));
        
        console.log("Test setup complete");
        console.log("TinfoilToken:", address(tinfoilToken));
        console.log("Conspirapuppets:", address(conspirapuppets));
        console.log("MockRouter:", address(mockRouter));
        console.log("MockFactory:", address(mockFactory));
    }
    
    function testInitialState() public {
        console.log("Testing Initial State");
        
        assertEq(tinfoilToken.totalSupply(), 0, "Initial token supply should be 0");
        assertFalse(tinfoilToken.tradingEnabled(), "Trading should be disabled initially");
        assertEq(tinfoilToken.nftContract(), address(conspirapuppets), "NFT contract should be set");
        
        assertEq(conspirapuppets.totalSupply(), 0, "Initial NFT supply should be 0");
        assertFalse(conspirapuppets.mintCompleted(), "Mint should not be completed");
        
        console.log("Initial state tests passed");
    }
    
    function testSingleMint() public {
        console.log("Testing Single Mint");
        
        vm.startPrank(user1);
        vm.deal(address(conspirapuppets), 0);
        
        vm.deal(address(conspirapuppets), MINT_PRICE);
        conspirapuppets.mint(user1, 1);
        
        assertEq(conspirapuppets.balanceOf(user1), 1, "User1 should own 1 NFT");
        assertEq(tinfoilToken.balanceOf(user1), TOKENS_PER_NFT, "User1 should have correct tokens");
        assertEq(conspirapuppets.totalSupply(), 1, "Total NFT supply should be 1");
        assertEq(tinfoilToken.totalSupply(), TOKENS_PER_NFT, "Total token supply should match");
        
        assertFalse(tinfoilToken.tradingEnabled(), "Trading should still be disabled");
        
        vm.expectRevert("Trading not enabled yet - wait for mint completion");
        tinfoilToken.transfer(user2, 1000);
        
        vm.stopPrank();
        console.log("Single mint tests passed");
    }
    
    function testMultipleMints() public {
        console.log("Testing Multiple Mints");
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 5;
        amounts[1] = 3;
        amounts[2] = 2;
        
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        
        uint256 totalMinted = 0;
        
        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            
            uint256 cost = amounts[i] * MINT_PRICE;
            vm.deal(address(conspirapuppets), address(conspirapuppets).balance + cost);
            
            conspirapuppets.mint(users[i], amounts[i]);
            
            totalMinted += amounts[i];
            
            assertEq(conspirapuppets.balanceOf(users[i]), amounts[i], "Incorrect NFT balance");
            assertEq(tinfoilToken.balanceOf(users[i]), amounts[i] * TOKENS_PER_NFT, "Incorrect token balance");
            
            vm.stopPrank();
        }
        
        assertEq(conspirapuppets.totalSupply(), totalMinted, "Incorrect total NFT supply");
        assertEq(tinfoilToken.totalSupply(), totalMinted * TOKENS_PER_NFT, "Incorrect total token supply");
        assertFalse(tinfoilToken.tradingEnabled(), "Trading should still be disabled");
        
        console.log("Multiple mints tests passed");
        console.log("Total minted:", totalMinted, "NFTs");
    }
    
    function testCompleteMint() public {
        console.log("Testing Complete Mint (The Explosive Finale)");
        
        uint256 initialOwnerBalance = owner.balance;
        
        vm.startPrank(owner);
        uint256 prefinaleAmount = MAX_SUPPLY - 1;
        uint256 cost = prefinaleAmount * MINT_PRICE;
        vm.deal(address(conspirapuppets), cost);
        
        conspirapuppets.mint(owner, prefinaleAmount);
        
        assertEq(conspirapuppets.totalSupply(), prefinaleAmount, "Should have 3332 NFTs");
        assertFalse(conspirapuppets.mintCompleted(), "Mint should not be completed yet");
        assertFalse(tinfoilToken.tradingEnabled(), "Trading should still be disabled");
        
        console.log("Pre-finale state:");
        console.log("  NFTs minted:", conspirapuppets.totalSupply());
        console.log("  Contract ETH balance:", address(conspirapuppets).balance / 1e18, "ETH");
        console.log("  Trading enabled:", tinfoilToken.tradingEnabled());
        
        vm.deal(address(conspirapuppets), address(conspirapuppets).balance + MINT_PRICE);
        
        console.log("MINTING FINAL NFT - TRIGGERING EXPLOSIVE FINALE");
        conspirapuppets.mint(user1, 1);
        
        assertEq(conspirapuppets.totalSupply(), MAX_SUPPLY, "Should have all 3333 NFTs");
        assertTrue(conspirapuppets.mintCompleted(), "Mint should be completed");
        assertTrue(tinfoilToken.tradingEnabled(), "Trading should be enabled");
        
        (, , , , , uint256 operationalFunds, bool lpCreated) = conspirapuppets.getMintStatus();
        uint256 expectedOperationalFunds = (MAX_SUPPLY * MINT_PRICE) / 2;
        assertEq(operationalFunds, expectedOperationalFunds, "Operational funds should be available");
        assertTrue(lpCreated, "LP should be created");
        
        conspirapuppets.withdrawOperationalFunds();
        uint256 ownerBalanceAfter = owner.balance;
        uint256 actualWithdrawn = ownerBalanceAfter - initialOwnerBalance;
        
        console.log("Post-finale state:");
        console.log("  NFTs minted:", conspirapuppets.totalSupply());
        console.log("  Mint completed:", conspirapuppets.mintCompleted());
        console.log("  Trading enabled:", tinfoilToken.tradingEnabled());
        console.log("  Operational funds withdrawn:", actualWithdrawn / 1e18, "ETH");
        console.log("  LP created:", lpCreated);
        
        address lpToken = mockFactory.getPair(address(tinfoilToken), conspirapuppets.WETH());
        uint256 lpBalance = MockLPToken(lpToken).balanceOf(0x000000000000000000000000000000000000dEaD);
        console.log("  LP tokens burned:", lpBalance / 1e18);
        
        vm.stopPrank();
        
        console.log("Complete mint tests passed");
    }
    
    function testTradingAfterCompletion() public {
        console.log("Testing Trading After Completion");
        
        vm.startPrank(owner);
        uint256 cost = MAX_SUPPLY * MINT_PRICE;
        vm.deal(address(conspirapuppets), cost);
        conspirapuppets.mint(owner, MAX_SUPPLY);
        vm.stopPrank();
        
        assertTrue(tinfoilToken.tradingEnabled(), "Trading should be enabled");
        
        vm.startPrank(owner);
        
        uint256 transferAmount = 50_000 * 10**18;
        tinfoilToken.transfer(user1, transferAmount);
        
        assertEq(tinfoilToken.balanceOf(user1), transferAmount, "Transfer should work");
        
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 secondTransfer = 10_000 * 10**18;
        tinfoilToken.transfer(user2, secondTransfer);
        
        assertEq(tinfoilToken.balanceOf(user2), secondTransfer, "User transfer should work");
        assertEq(tinfoilToken.balanceOf(user1), transferAmount - secondTransfer, "User1 balance should decrease");
        
        vm.stopPrank();
        
        console.log("Trading tests passed");
    }
    
    function testTokenBurning() public {
        console.log("Testing Token Burning");
        
        vm.startPrank(owner);
        uint256 cost = MAX_SUPPLY * MINT_PRICE;
        vm.deal(address(conspirapuppets), cost);
        conspirapuppets.mint(owner, MAX_SUPPLY);
        
        uint256 burnAmount = 100_000 * 10**18;
        tinfoilToken.transfer(user1, burnAmount);
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 initialSupply = tinfoilToken.totalSupply();
        uint256 initialBalance = tinfoilToken.balanceOf(user1);
        
        tinfoilToken.burn(burnAmount);
        
        assertEq(tinfoilToken.totalSupply(), initialSupply - burnAmount, "Total supply should decrease");
        assertEq(tinfoilToken.balanceOf(user1), initialBalance - burnAmount, "User balance should decrease");
        assertEq(tinfoilToken.totalBurned(), burnAmount, "Total burned should increase");
        
        vm.stopPrank();
        
        console.log("Token burning tests passed");
    }
    
    function testWithdrawalEdgeCases() public {
        console.log("Testing Withdrawal Edge Cases");
        
        vm.startPrank(owner);
        vm.expectRevert("Mint not completed yet");
        conspirapuppets.withdrawOperationalFunds();
        
        uint256 cost = MAX_SUPPLY * MINT_PRICE;
        vm.deal(address(conspirapuppets), cost);
        conspirapuppets.mint(owner, MAX_SUPPLY);
        
        conspirapuppets.withdrawOperationalFunds();
        
        vm.expectRevert("No operational funds available");
        conspirapuppets.withdrawOperationalFunds();
        
        vm.stopPrank();
        
        console.log("Withdrawal edge cases passed");
    }
    
    function testEmergencyWithdraw() public {
        console.log("Testing Emergency Withdraw");
        
        vm.startPrank(owner);
        
        vm.expectRevert("Can only withdraw after mint completion");
        conspirapuppets.emergencyWithdraw();
        
        uint256 cost = MAX_SUPPLY * MINT_PRICE;
        vm.deal(address(conspirapuppets), cost);
        conspirapuppets.mint(owner, MAX_SUPPLY);
        
        vm.deal(address(conspirapuppets), address(conspirapuppets).balance + 1 ether);
        
        uint256 initialBalance = owner.balance;
        uint256 contractBalance = address(conspirapuppets).balance;
        
        conspirapuppets.emergencyWithdraw();
        
        uint256 finalBalance = owner.balance;
        assertEq(finalBalance - initialBalance, contractBalance, "Should withdraw all contract ETH");
        assertEq(address(conspirapuppets).balance, 0, "Contract should have 0 ETH after emergency withdraw");
        
        vm.stopPrank();
        
        console.log("Emergency withdraw tests passed");
    }
    
    function testPauseUnpauseFunctionality() public {
        console.log("Testing Pause/Unpause Functionality");
        
        vm.startPrank(owner);
        
        vm.deal(address(conspirapuppets), MINT_PRICE);
        conspirapuppets.mint(user1, 1);
        
        tinfoilToken.pause();
        
        vm.deal(address(conspirapuppets), address(conspirapuppets).balance + MINT_PRICE);
        vm.expectRevert("Pausable: paused");
        conspirapuppets.mint(user2, 1);
        
        tinfoilToken.unpause();
        
        conspirapuppets.mint(user2, 1);
        assertEq(conspirapuppets.balanceOf(user2), 1, "Mint should work after unpause");
        
        vm.stopPrank();
        
        console.log("Pause/unpause tests passed");
    }
    
    function testOwnershipRestrictedFunctions() public {
        console.log("Testing Ownership Restricted Functions");
        
        vm.startPrank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        tinfoilToken.pause();
        
        vm.expectRevert();
        conspirapuppets.withdrawOperationalFunds();
        
        vm.expectRevert();
        conspirapuppets.emergencyWithdraw();
        
        vm.stopPrank();
        
        console.log("Ownership restriction tests passed");
    }
    
    function testFullIntegration() public {
        console.log("Testing Full Integration Flow");
        
        console.log("============================================================");
        console.log("FULL CONSPIRAPUPPETS SIMULATION");
        console.log("============================================================");
        
        console.log("Phase 1: Early Minting");
        
        vm.startPrank(user1);
        vm.deal(address(conspirapuppets), 5 * MINT_PRICE);
        conspirapuppets.mint(user1, 5);
        console.log("User1 minted 5 NFTs, received", tinfoilToken.balanceOf(user1) / 1e18, "tokens");
        
        vm.expectRevert("Trading not enabled yet - wait for mint completion");
        tinfoilToken.transfer(user2, 1000);
        console.log("Trading correctly blocked");
        vm.stopPrank();
        
        console.log("Phase 2: Progressive Minting");
        
        vm.startPrank(user2);
        vm.deal(address(conspirapuppets), address(conspirapuppets).balance + 10 * MINT_PRICE);
        conspirapuppets.mint(user2, 10);
        console.log("User2 minted 10 NFTs, received", tinfoilToken.balanceOf(user2) / 1e18, "tokens");
        vm.stopPrank();
        
        uint256 currentSupply = conspirapuppets.totalSupply();
        console.log("Current supply:", currentSupply, "/ 3333");
        console.log("Progress:", (currentSupply * 100) / MAX_SUPPLY, "%");
        
        console.log("Phase 3: Approaching Completion");
        
        vm.startPrank(owner);
        uint256 remaining = MAX_SUPPLY - currentSupply;
        uint256 finalCost = remaining * MINT_PRICE;
        vm.deal(address(conspirapuppets), address(conspirapuppets).balance + finalCost);
        
        uint256 ownerBalanceBefore = owner.balance;
        uint256 contractBalanceBefore = address(conspirapuppets).balance;
        
        console.log("Minting final", remaining, "NFTs to trigger completion...");
        console.log("Contract ETH before finale:", contractBalanceBefore / 1e18, "ETH");
        console.log("Owner ETH before finale:", ownerBalanceBefore / 1e18, "ETH");
        
        conspirapuppets.mint(owner, remaining);
        
        console.log("EXPLOSIVE FINALE COMPLETED!");
        console.log("============================================================");
        
        assertTrue(conspirapuppets.mintCompleted(), "Mint completed");
        assertTrue(tinfoilToken.tradingEnabled(), "Trading enabled");
        
        (, , , , , , bool lpCreated) = conspirapuppets.getMintStatus();
        assertTrue(lpCreated, "LP should be created");
        
        conspirapuppets.withdrawOperationalFunds();
        
        uint256 ownerBalanceAfter = owner.balance;
        uint256 operationalFunds = ownerBalanceAfter - ownerBalanceBefore;
        
        console.log("Mint completed:", conspirapuppets.mintCompleted());
        console.log("Trading enabled:", tinfoilToken.tradingEnabled());
        console.log("LP created:", lpCreated);
        console.log("Operational funds withdrawn:", operationalFunds / 1e18, "ETH");
        
        console.log("Phase 4: Post-Completion Trading");
        
        uint256 transferAmount = 500_000 * 10**18;
        tinfoilToken.transfer(user3, transferAmount);
        console.log("Transferred", transferAmount / 1e18, "tokens to user3");
        
        assertEq(tinfoilToken.balanceOf(user3), transferAmount, "Transfer successful");
        
        vm.stopPrank();
        
        console.log("FINAL STATISTICS");
        console.log("============================================================");
        console.log("Total NFTs minted:", conspirapuppets.totalSupply());
        console.log("Total tokens minted:", tinfoilToken.totalSupply() / 1e18);
        console.log("User1 tokens:", tinfoilToken.balanceOf(user1) / 1e18);
        console.log("User2 tokens:", tinfoilToken.balanceOf(user2) / 1e18);
        console.log("User3 tokens:", tinfoilToken.balanceOf(user3) / 1e18);
        console.log("Owner tokens:", tinfoilToken.balanceOf(owner) / 1e18);
        console.log("Trading enabled:", tinfoilToken.tradingEnabled());
        console.log("LP created:", lpCreated);
        console.log("Operational funds:", operationalFunds / 1e18, "ETH");
        
        console.log("FULL INTEGRATION TEST PASSED!");
    }
    
    function mint(address to, uint256 quantity) external {
        for (uint256 i = 0; i < quantity; i++) {
            conspirapuppets.mint(to, 1);
        }
    }
}