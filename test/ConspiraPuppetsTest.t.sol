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
    
    function getPair(address, address, bool) external view returns (address) {
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
        
        address pair = MockAerodromeFactory(factory).getPair(token, address(0), false);
        MockLPToken(pair).mint(to, liquidity);
        
        console.log("Mock LP created");
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
    
    // Helper function to simulate minting (owner-only for testing)
    function mintHelper(address to, uint256 quantity) internal {
        vm.deal(address(conspirapuppets), address(conspirapuppets).balance + (quantity * MINT_PRICE));
        conspirapuppets.mintForTesting(to, quantity);
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
        
        mintHelper(user1, 1);
        
        assertEq(conspirapuppets.balanceOf(user1), 1, "User1 should own 1 NFT");
        assertEq(tinfoilToken.balanceOf(user1), TOKENS_PER_NFT, "User1 should have correct tokens");
        assertEq(conspirapuppets.totalSupply(), 1, "Total NFT supply should be 1");
        assertEq(tinfoilToken.totalSupply(), TOKENS_PER_NFT, "Total token supply should match");
        
        assertFalse(tinfoilToken.tradingEnabled(), "Trading should still be disabled");
        
        vm.prank(user1);
        vm.expectRevert("Trading not enabled yet - wait for mint completion");
        tinfoilToken.transfer(user2, 1000);
        
        console.log("Single mint tests passed");
    }
    
    function testMultipleMints() public {
        console.log("Testing Multiple Mints");
        
        mintHelper(user1, 5);
        mintHelper(user2, 3);
        mintHelper(user3, 2);
        
        assertEq(conspirapuppets.balanceOf(user1), 5, "Incorrect NFT balance");
        assertEq(conspirapuppets.balanceOf(user2), 3, "Incorrect NFT balance");
        assertEq(conspirapuppets.balanceOf(user3), 2, "Incorrect NFT balance");
        
        assertEq(tinfoilToken.balanceOf(user1), 5 * TOKENS_PER_NFT, "Incorrect token balance");
        assertEq(tinfoilToken.balanceOf(user2), 3 * TOKENS_PER_NFT, "Incorrect token balance");
        assertEq(tinfoilToken.balanceOf(user3), 2 * TOKENS_PER_NFT, "Incorrect token balance");
        
        assertEq(conspirapuppets.totalSupply(), 10, "Incorrect total NFT supply");
        assertFalse(tinfoilToken.tradingEnabled(), "Trading should still be disabled");
        
        console.log("Multiple mints tests passed");
    }
    
    function testCompleteMint() public {
        console.log("Testing Complete Mint (The Explosive Finale)");
        
        uint256 initialOwnerBalance = owner.balance;
        
        uint256 prefinaleAmount = MAX_SUPPLY - 1;
        mintHelper(owner, prefinaleAmount);
        
        assertEq(conspirapuppets.totalSupply(), prefinaleAmount, "Should have 3332 NFTs");
        assertFalse(conspirapuppets.mintCompleted(), "Mint should not be completed yet");
        assertFalse(tinfoilToken.tradingEnabled(), "Trading should still be disabled");
        
        console.log("Pre-finale state:");
        console.log("  NFTs minted:", conspirapuppets.totalSupply());
        console.log("  Contract ETH balance:", address(conspirapuppets).balance / 1e18, "ETH");
        
        console.log("MINTING FINAL NFT - TRIGGERING EXPLOSIVE FINALE");
        mintHelper(user1, 1);
        
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
        console.log("  Mint completed:", conspirapuppets.mintCompleted());
        console.log("  Trading enabled:", tinfoilToken.tradingEnabled());
        console.log("  Operational funds withdrawn:", actualWithdrawn / 1e18, "ETH");
        console.log("  LP created:", lpCreated);
        
        address lpToken = mockFactory.getPair(address(tinfoilToken), conspirapuppets.WETH(), false);
        uint256 lpBalance = MockLPToken(lpToken).balanceOf(0x000000000000000000000000000000000000dEaD);
        console.log("  LP tokens burned:", lpBalance / 1e18);
        
        console.log("Complete mint tests passed");
    }
    
    function testManualCompletion() public {
        console.log("Testing Manual Completion");
        
        // Mint only half the supply
        mintHelper(owner, MAX_SUPPLY / 2);
        
        assertFalse(conspirapuppets.mintCompleted(), "Mint should not be auto-completed");
        
        // Owner manually completes
        conspirapuppets.completeMint();
        
        assertTrue(conspirapuppets.mintCompleted(), "Mint should be manually completed");
        assertTrue(tinfoilToken.tradingEnabled(), "Trading should be enabled");
        
        console.log("Manual completion tests passed");
    }
    
    function testAirdrop() public {
        console.log("Testing Airdrop Function");
        
        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;
        
        uint256[] memory quantities = new uint256[](3);
        quantities[0] = 10;
        quantities[1] = 5;
        quantities[2] = 3;
        
        conspirapuppets.airdrop(recipients, quantities);
        
        assertEq(conspirapuppets.balanceOf(user1), 10, "User1 should have 10 NFTs");
        assertEq(conspirapuppets.balanceOf(user2), 5, "User2 should have 5 NFTs");
        assertEq(conspirapuppets.balanceOf(user3), 3, "User3 should have 3 NFTs");
        assertEq(conspirapuppets.totalSupply(), 18, "Total should be 18");
        
        console.log("Airdrop tests passed");
    }
    
    function testTradingAfterCompletion() public {
        console.log("Testing Trading After Completion");
        
        mintHelper(owner, MAX_SUPPLY);
        
        assertTrue(tinfoilToken.tradingEnabled(), "Trading should be enabled");
        
        uint256 transferAmount = 50_000 * 10**18;
        tinfoilToken.transfer(user1, transferAmount);
        
        assertEq(tinfoilToken.balanceOf(user1), transferAmount, "Transfer should work");
        
        vm.prank(user1);
        uint256 secondTransfer = 10_000 * 10**18;
        tinfoilToken.transfer(user2, secondTransfer);
        
        assertEq(tinfoilToken.balanceOf(user2), secondTransfer, "User transfer should work");
        
        console.log("Trading tests passed");
    }
    
    function testTokenBurning() public {
        console.log("Testing Token Burning");
        
        mintHelper(owner, MAX_SUPPLY);
        
        uint256 burnAmount = 100_000 * 10**18;
        tinfoilToken.transfer(user1, burnAmount);
        
        vm.prank(user1);
        uint256 initialSupply = tinfoilToken.totalSupply();
        tinfoilToken.burn(burnAmount);
        
        assertEq(tinfoilToken.totalSupply(), initialSupply - burnAmount, "Total supply should decrease");
        assertEq(tinfoilToken.totalBurned(), burnAmount, "Total burned should increase");
        
        console.log("Token burning tests passed");
    }
    
    function testWithdrawalFunction() public {
        console.log("Testing Withdrawal Function");
        
        uint256 initialBalance = owner.balance;
        
        mintHelper(owner, MAX_SUPPLY);
        
        (, , , , , uint256 operationalFunds, bool lpCreated) = conspirapuppets.getMintStatus();
        assertTrue(operationalFunds > 0, "Should have operational funds");
        assertTrue(lpCreated, "LP should be created");
        
        conspirapuppets.withdrawOperationalFunds();
        
        uint256 finalBalance = owner.balance;
        uint256 withdrawn = finalBalance - initialBalance;
        assertEq(withdrawn, operationalFunds, "Should withdraw operational funds");
        
        (, , , , , uint256 remainingFunds, bool lpStillCreated) = conspirapuppets.getMintStatus();
        assertEq(remainingFunds, 0, "Operational funds should be 0");
        assertTrue(lpStillCreated, "LP should still be created");
        
        console.log("Withdrawal function tests passed");
    }
    
    function testFullIntegration() public {
        console.log("Testing Full Integration Flow");
        console.log("============================================================");
        
        console.log("Phase 1: Early Minting");
        mintHelper(user1, 5);
        console.log("User1 minted 5 NFTs");
        
        console.log("Phase 2: Progressive Minting");
        mintHelper(user2, 10);
        console.log("User2 minted 10 NFTs");
        
        console.log("Phase 3: Approaching Completion");
        uint256 remaining = MAX_SUPPLY - conspirapuppets.totalSupply();
        uint256 ownerBalanceBefore = owner.balance;
        
        mintHelper(owner, remaining);
        
        console.log("EXPLOSIVE FINALE COMPLETED!");
        console.log("============================================================");
        
        assertTrue(conspirapuppets.mintCompleted(), "Mint completed");
        assertTrue(tinfoilToken.tradingEnabled(), "Trading enabled");
        
        (, , , , , , bool lpCreated) = conspirapuppets.getMintStatus();
        assertTrue(lpCreated, "LP should be created");
        
        conspirapuppets.withdrawOperationalFunds();
        
        uint256 ownerBalanceAfter = owner.balance;
        uint256 operationalFunds = ownerBalanceAfter - ownerBalanceBefore;
        
        console.log("Phase 4: Post-Completion Trading");
        uint256 transferAmount = 500_000 * 10**18;
        tinfoilToken.transfer(user3, transferAmount);
        
        assertEq(tinfoilToken.balanceOf(user3), transferAmount, "Transfer successful");
        
        console.log("FULL INTEGRATION TEST PASSED!");
    }
}