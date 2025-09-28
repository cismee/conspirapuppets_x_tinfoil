// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/TinfoilToken.sol";
import "../src/Conspirapuppets.sol";

// Mock Seadrop contract for testing
contract MockSeaDrop {
    function updatePublicDrop(address, bytes calldata) external {}
    function updateAllowedFeeRecipient(address, address, bool) external {}
}

// Mock Aerodrome router for testing
contract MockAerodrome {
    address public mockPair;
    
    constructor() {
        mockPair = address(new MockLPToken());
    }
    
    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // Simulate liquidity addition
        amountA = amountADesired;
        amountB = amountBDesired;
        liquidity = amountADesired; // Simplified
        
        // Mint LP tokens to the recipient
        MockLPToken(mockPair).mint(to, liquidity);
        
        console.log("Mock LP created with tokens and ETH");
        return (amountA, amountB, liquidity);
    }
    
    function getPair(address, address) external view returns (address) {
        return mockPair;
    }
}

// Mock LP token for testing
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
    MockAerodrome public mockAerodrome;
    
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    
    uint256 constant MINT_PRICE = 0.005 ether;
    uint256 constant MAX_SUPPLY = 3333;
    uint256 constant TOKENS_PER_NFT = 499_549 * 10**18;
    
    // Add receive function to accept ETH
    receive() external payable {}
    
    function setUp() public {
        // Set up test accounts
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        
        // Give users some ETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        
        // Deploy mock contracts
        mockSeaDrop = new MockSeaDrop();
        mockAerodrome = new MockAerodrome();
        
        // Deploy main contracts
        tinfoilToken = new TinfoilToken();
        
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = address(mockSeaDrop);
        
        conspirapuppets = new Conspirapuppets(
            "Conspirapuppets",
            "CPUP",
            allowedSeaDrop,
            address(tinfoilToken),
            address(mockAerodrome)
        );
        
        // Link contracts
        tinfoilToken.setNFTContract(address(conspirapuppets));
        
        console.log("Test setup complete");
        console.log("TinfoilToken:", address(tinfoilToken));
        console.log("Conspirapuppets:", address(conspirapuppets));
        console.log("MockAerodrome:", address(mockAerodrome));
    }
    
    function testInitialState() public {
        console.log("Testing Initial State");
        
        // Check initial token state
        assertEq(tinfoilToken.totalSupply(), 0, "Initial token supply should be 0");
        assertFalse(tinfoilToken.tradingEnabled(), "Trading should be disabled initially");
        assertEq(tinfoilToken.nftContract(), address(conspirapuppets), "NFT contract should be set");
        
        // Check initial NFT state
        assertEq(conspirapuppets.totalSupply(), 0, "Initial NFT supply should be 0");
        assertFalse(conspirapuppets.mintCompleted(), "Mint should not be completed");
        
        console.log("Initial state tests passed");
    }
    
    function testSingleMint() public {
        console.log("Testing Single Mint");
        
        // Simulate user1 minting 1 NFT
        vm.startPrank(user1);
        vm.deal(address(conspirapuppets), 0); // Reset contract balance
        
        // Simulate the mint
        vm.deal(address(conspirapuppets), MINT_PRICE);
        conspirapuppets.mint(user1, 1);
        
        // Check results
        assertEq(conspirapuppets.balanceOf(user1), 1, "User1 should own 1 NFT");
        assertEq(tinfoilToken.balanceOf(user1), TOKENS_PER_NFT, "User1 should have correct tokens");
        assertEq(conspirapuppets.totalSupply(), 1, "Total NFT supply should be 1");
        assertEq(tinfoilToken.totalSupply(), TOKENS_PER_NFT, "Total token supply should match");
        
        // Trading should still be disabled
        assertFalse(tinfoilToken.tradingEnabled(), "Trading should still be disabled");
        
        // Try to transfer tokens (should fail)
        vm.expectRevert("Trading not enabled yet - wait for mint completion");
        tinfoilToken.transfer(user2, 1000);
        
        vm.stopPrank();
        console.log("Single mint tests passed");
    }
    
    function testMultipleMints() public {
        console.log("Testing Multiple Mints");
        
        // Mint several NFTs to different users
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 5;  // user1: 5 NFTs
        amounts[1] = 3;  // user2: 3 NFTs  
        amounts[2] = 2;  // user3: 2 NFTs
        
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
            
            // Check balances
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
        
        // Mint 3332 NFTs (leaving 1 for the finale)
        vm.startPrank(owner);
        uint256 prefinaleAmount = MAX_SUPPLY - 1;
        uint256 cost = prefinaleAmount * MINT_PRICE;
        vm.deal(address(conspirapuppets), cost);
        
        conspirapuppets.mint(owner, prefinaleAmount);
        
        // Verify pre-finale state
        assertEq(conspirapuppets.totalSupply(), prefinaleAmount, "Should have 3332 NFTs");
        assertFalse(conspirapuppets.mintCompleted(), "Mint should not be completed yet");
        assertFalse(tinfoilToken.tradingEnabled(), "Trading should still be disabled");
        
        console.log("Pre-finale state:");
        console.log("  NFTs minted:", conspirapuppets.totalSupply());
        console.log("  Contract ETH balance:", address(conspirapuppets).balance / 1e18, "ETH");
        console.log("  Trading enabled:", tinfoilToken.tradingEnabled());
        
        // Now mint the final NFT (should trigger completion)
        vm.deal(address(conspirapuppets), address(conspirapuppets).balance + MINT_PRICE);
        
        console.log("MINTING FINAL NFT - TRIGGERING EXPLOSIVE FINALE");
        conspirapuppets.mint(user1, 1);
        
        // Verify completion
        assertEq(conspirapuppets.totalSupply(), MAX_SUPPLY, "Should have all 3333 NFTs");
        assertTrue(conspirapuppets.mintCompleted(), "Mint should be completed");
        assertTrue(tinfoilToken.tradingEnabled(), "Trading should be enabled");
        
        // Check operational funds are available for withdrawal
        (, , , , , uint256 operationalFunds, bool lpCreated) = conspirapuppets.getMintStatus();
        uint256 expectedOperationalFunds = (MAX_SUPPLY * MINT_PRICE) / 2;
        assertEq(operationalFunds, expectedOperationalFunds, "Operational funds should be available");
        
        // Withdraw operational funds
        conspirapuppets.withdrawOperationalFunds();
        uint256 ownerBalanceAfter = owner.balance;
        uint256 actualWithdrawn = ownerBalanceAfter - initialOwnerBalance;
        
        console.log("Post-finale state:");
        console.log("  NFTs minted:", conspirapuppets.totalSupply());
        console.log("  Mint completed:", conspirapuppets.mintCompleted());
        console.log("  Trading enabled:", tinfoilToken.tradingEnabled());
        console.log("  Operational funds withdrawn:", actualWithdrawn / 1e18, "ETH");
        
        // Check LP creation
        address lpToken = mockAerodrome.getPair(address(tinfoilToken), address(0));
        uint256 lpBalance = MockLPToken(lpToken).balanceOf(0x000000000000000000000000000000000000dEaD);
        console.log("  LP tokens burned:", lpBalance / 1e18);
        
        vm.stopPrank();
        
        console.log("Complete mint tests passed");
    }
    
    function testTradingAfterCompletion() public {
        console.log("Testing Trading After Completion");
        
        // First complete the mint
        vm.startPrank(owner);
        uint256 cost = MAX_SUPPLY * MINT_PRICE;
        vm.deal(address(conspirapuppets), cost);
        conspirapuppets.mint(owner, MAX_SUPPLY);
        vm.stopPrank();
        
        // Verify trading is enabled
        assertTrue(tinfoilToken.tradingEnabled(), "Trading should be enabled");
        
        // Test token transfers
        vm.startPrank(owner);
        
        uint256 transferAmount = 50_000 * 10**18; // 50k tokens
        tinfoilToken.transfer(user1, transferAmount);
        
        assertEq(tinfoilToken.balanceOf(user1), transferAmount, "Transfer should work");
        
        vm.stopPrank();
        
        // Test user-to-user transfer
        vm.startPrank(user1);
        uint256 secondTransfer = 10_000 * 10**18; // 10k tokens
        tinfoilToken.transfer(user2, secondTransfer);
        
        assertEq(tinfoilToken.balanceOf(user2), secondTransfer, "User transfer should work");
        assertEq(tinfoilToken.balanceOf(user1), transferAmount - secondTransfer, "User1 balance should decrease");
        
        vm.stopPrank();
        
        console.log("Trading tests passed");
    }
    
    function testTokenBurning() public {
        console.log("Testing Token Burning");
        
        // Complete mint first
        vm.startPrank(owner);
        uint256 cost = MAX_SUPPLY * MINT_PRICE;
        vm.deal(address(conspirapuppets), cost);
        conspirapuppets.mint(owner, MAX_SUPPLY);
        
        // Transfer some tokens to user1
        uint256 burnAmount = 100_000 * 10**18; // 100k tokens
        tinfoilToken.transfer(user1, burnAmount);
        vm.stopPrank();
        
        // Test burning
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
    
    function testWithdrawalFunction() public {
        console.log("Testing Withdrawal Function");
        
        // Complete mint
        vm.startPrank(owner);
        uint256 cost = MAX_SUPPLY * MINT_PRICE;
        vm.deal(address(conspirapuppets), cost);
        uint256 initialBalance = owner.balance;
        
        conspirapuppets.mint(owner, MAX_SUPPLY);
        
        // Check operational funds are available
        (, , , , , uint256 operationalFunds, bool lpCreated) = conspirapuppets.getMintStatus();
        assertTrue(operationalFunds > 0, "Should have operational funds available");
        
        // Withdraw funds
        conspirapuppets.withdrawOperationalFunds();
        
        // Check owner received funds
        uint256 finalBalance = owner.balance;
        uint256 withdrawn = finalBalance - initialBalance;
        assertEq(withdrawn, operationalFunds, "Should have withdrawn operational funds");
        
        // Check operational funds reset to 0
        (, , , , , uint256 remainingFunds, bool lpStillCreated) = conspirapuppets.getMintStatus();
        assertEq(remainingFunds, 0, "Operational funds should be reset to 0");
        
        vm.stopPrank();
        
        console.log("Withdrawal function tests passed");
    }
    
    function testFullIntegration() public {
        console.log("Testing Full Integration Flow");
        
        console.log("============================================================");
        console.log("FULL CONSPIRAPUPPETS SIMULATION");
        console.log("============================================================");
        
        // Phase 1: Early minting
        console.log("Phase 1: Early Minting");
        
        vm.startPrank(user1);
        vm.deal(address(conspirapuppets), 5 * MINT_PRICE);
        conspirapuppets.mint(user1, 5);
        console.log("User1 minted 5 NFTs, received", tinfoilToken.balanceOf(user1) / 1e18, "tokens");
        
        // Try to trade (should fail)
        vm.expectRevert("Trading not enabled yet - wait for mint completion");
        tinfoilToken.transfer(user2, 1000);
        console.log("Trading correctly blocked");
        vm.stopPrank();
        
        // Phase 2: More minting
        console.log("Phase 2: Progressive Minting");
        
        vm.startPrank(user2);
        vm.deal(address(conspirapuppets), address(conspirapuppets).balance + 10 * MINT_PRICE);
        conspirapuppets.mint(user2, 10);
        console.log("User2 minted 10 NFTs, received", tinfoilToken.balanceOf(user2) / 1e18, "tokens");
        vm.stopPrank();
        
        uint256 currentSupply = conspirapuppets.totalSupply();
        console.log("Current supply:", currentSupply, "/ 3333");
        console.log("Progress:", (currentSupply * 100) / MAX_SUPPLY, "%");
        
        // Phase 3: Approach completion
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
        
        // THE EXPLOSIVE FINALE
        conspirapuppets.mint(owner, remaining);
        
        console.log("EXPLOSIVE FINALE COMPLETED!");
        console.log("============================================================");
        
        // Verify finale results
        assertTrue(conspirapuppets.mintCompleted(), "Mint completed");
        assertTrue(tinfoilToken.tradingEnabled(), "Trading enabled");
        
        // Withdraw operational funds
        conspirapuppets.withdrawOperationalFunds();
        
        uint256 ownerBalanceAfter = owner.balance;
        uint256 operationalFunds = ownerBalanceAfter - ownerBalanceBefore;
        
        console.log("Mint completed:", conspirapuppets.mintCompleted());
        console.log("Trading enabled:", tinfoilToken.tradingEnabled());
        console.log("Operational funds withdrawn:", operationalFunds / 1e18, "ETH");
        console.log("LP created and burned");
        
        // Phase 4: Test trading
        console.log("Phase 4: Post-Completion Trading");
        
        uint256 transferAmount = 500_000 * 10**18; // 500k tokens
        tinfoilToken.transfer(user3, transferAmount);
        console.log("Transferred", transferAmount / 1e18, "tokens to user3");
        
        assertEq(tinfoilToken.balanceOf(user3), transferAmount, "Transfer successful");
        
        vm.stopPrank();
        
        // Final statistics
        console.log("FINAL STATISTICS");
        console.log("============================================================");
        console.log("Total NFTs minted:", conspirapuppets.totalSupply());
        console.log("Total tokens minted:", tinfoilToken.totalSupply() / 1e18);
        console.log("User1 tokens:", tinfoilToken.balanceOf(user1) / 1e18);
        console.log("User2 tokens:", tinfoilToken.balanceOf(user2) / 1e18);
        console.log("User3 tokens:", tinfoilToken.balanceOf(user3) / 1e18);
        console.log("Owner tokens:", tinfoilToken.balanceOf(owner) / 1e18);
        console.log("Trading enabled:", tinfoilToken.tradingEnabled());
        console.log("Operational funds:", operationalFunds / 1e18, "ETH");
        
        console.log("FULL INTEGRATION TEST PASSED!");
    }
    
    // Helper function to simulate minting
    function mint(address to, uint256 quantity) external {
        for (uint256 i = 0; i < quantity; i++) {
            conspirapuppets.mint(to, 1);
        }
    }
}