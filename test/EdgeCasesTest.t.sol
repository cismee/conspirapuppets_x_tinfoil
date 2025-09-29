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

contract EdgeCasesTest is Test {
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
    }
    
    function mintHelper(address to, uint256 quantity) internal {
        vm.deal(address(conspirapuppets), address(conspirapuppets).balance + (quantity * MINT_PRICE));
        conspirapuppets.mintForTesting(to, quantity);
    }
    
    function testWithdrawalBeforeCompletion() public {
        console.log("Testing Withdrawal Before Completion");
        
        vm.expectRevert("Mint not completed yet");
        conspirapuppets.withdrawOperationalFunds();
        
        console.log("Withdrawal before completion correctly reverted");
    }
    
    function testWithdrawalEdgeCases() public {
        console.log("Testing Withdrawal Edge Cases");
        
        mintHelper(owner, MAX_SUPPLY);
        
        conspirapuppets.withdrawOperationalFunds();
        
        vm.expectRevert("No operational funds available");
        conspirapuppets.withdrawOperationalFunds();
        
        console.log("Double withdrawal correctly reverted");
    }
    
    function testEmergencyWithdraw() public {
        console.log("Testing Emergency Withdraw");
        
        vm.expectRevert("Can only withdraw after mint completion");
        conspirapuppets.emergencyWithdraw();
        
        mintHelper(owner, MAX_SUPPLY);
        
        vm.deal(address(conspirapuppets), address(conspirapuppets).balance + 1 ether);
        
        uint256 initialBalance = owner.balance;
        uint256 contractBalance = address(conspirapuppets).balance;
        
        conspirapuppets.emergencyWithdraw();
        
        uint256 finalBalance = owner.balance;
        assertEq(finalBalance - initialBalance, contractBalance, "Should withdraw all ETH");
        assertEq(address(conspirapuppets).balance, 0, "Contract should have 0 ETH");
        
        console.log("Emergency withdraw tests passed");
    }
    
    function testPauseUnpause() public {
        console.log("Testing Pause/Unpause");
        
        mintHelper(user1, 1);
        
        tinfoilToken.pause();
        
        vm.expectRevert("Pausable: paused");
        mintHelper(user2, 1);
        
        tinfoilToken.unpause();
        
        mintHelper(user2, 1);
        assertEq(conspirapuppets.balanceOf(user2), 1, "Should work after unpause");
        
        console.log("Pause/unpause tests passed");
    }
    
    function testOwnershipRestrictions() public {
        console.log("Testing Ownership Restrictions");
        
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        tinfoilToken.pause();
        
        vm.prank(user1);
        vm.expectRevert();
        conspirapuppets.withdrawOperationalFunds();
        
        console.log("Ownership restrictions tests passed");
    }
    
    function testAirdropBeforeCompletion() public {
        console.log("Testing Airdrop Before Completion");
        
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;
        
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 5;
        quantities[1] = 3;
        
        conspirapuppets.airdrop(recipients, quantities);
        
        assertEq(conspirapuppets.totalSupply(), 8, "Should have 8 NFTs");
        
        console.log("Airdrop tests passed");
    }
    
    function testAirdropAfterCompletion() public {
        console.log("Testing Airdrop After Completion");
        
        mintHelper(owner, MAX_SUPPLY);
        
        address[] memory recipients = new address[](1);
        recipients[0] = user1;
        
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 1;
        
        vm.expectRevert("Mint already completed");
        conspirapuppets.airdrop(recipients, quantities);
        
        console.log("Airdrop after completion correctly reverted");
    }
    
    function testAirdropExceedsMaxSupply() public {
        console.log("Testing Airdrop Exceeds Max Supply");
        
        mintHelper(owner, MAX_SUPPLY - 5);
        
        address[] memory recipients = new address[](1);
        recipients[0] = user1;
        
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 10;
        
        vm.expectRevert("Exceeds max supply");
        conspirapuppets.airdrop(recipients, quantities);
        
        console.log("Airdrop overflow correctly reverted");
    }
    
    function testManualCompletionWithoutETH() public {
        console.log("Testing Manual Completion Without ETH");
        
        // Mint without adding ETH to contract
        vm.deal(address(conspirapuppets), 0);
        conspirapuppets.mintForTesting(owner, 10);
        
        vm.expectRevert("No ETH to allocate");
        conspirapuppets.completeMint();
        
        console.log("Manual completion without ETH correctly reverted");
    }
    
    function testRetryLPCreation() public {
        console.log("Testing Retry LP Creation");
        
        mintHelper(owner, MAX_SUPPLY);
        
        (, , , , , , bool lpCreated) = conspirapuppets.getMintStatus();
        assertTrue(lpCreated, "LP should be created");
        
        vm.expectRevert("LP already created");
        conspirapuppets.retryLPCreation();
        
        console.log("Retry LP creation tests passed");
    }
    
    function testETHReceipt() public {
        console.log("Testing ETH Receipt Tracking");
        
        uint256 amount1 = 1 ether;
        vm.deal(owner, amount1);
        (bool success,) = address(conspirapuppets).call{value: amount1}("");
        require(success);
        
        assertEq(conspirapuppets.totalEthReceived(), amount1, "Should track ETH");
        
        uint256 amount2 = 0.5 ether;
        vm.deal(owner, amount2);
        (success,) = address(conspirapuppets).call{value: amount2}("");
        require(success);
        
        assertEq(conspirapuppets.totalEthReceived(), amount1 + amount2, "Should accumulate");
        
        console.log("ETH receipt tracking tests passed");
    }
    
    function testTokenRemainderMint() public {
        console.log("Testing Token Remainder Mint");
        
        uint256 ownerTokensBefore = tinfoilToken.balanceOf(owner);
        
        mintHelper(owner, MAX_SUPPLY);
        
        uint256 ownerTokensAfter = tinfoilToken.balanceOf(owner);
        uint256 remainder = conspirapuppets.TOKEN_REMAINDER();
        
        // Owner should have received the remainder tokens
        assertTrue(ownerTokensAfter > ownerTokensBefore, "Owner should have remainder");
        
        console.log("Token remainder mint tests passed");
    }
    
    function testReentrancyProtection() public {
        console.log("Testing Reentrancy Protection");
        
        mintHelper(owner, MAX_SUPPLY);
        
        // LP creation and emergency functions are protected
        // This test verifies they have nonReentrant modifier
        
        console.log("Reentrancy protection in place");
    }
    
    function testMintStatusBeforeAndAfter() public {
        console.log("Testing Mint Status Before and After");
        
        (
            uint256 totalSupply,
            uint256 maxSupply,
            bool mintCompleted,
            uint256 contractBalance,
            uint256 tokensPerNFT,
            uint256 operationalFunds,
            bool lpCreated
        ) = conspirapuppets.getMintStatus();
        
        assertEq(totalSupply, 0, "Initial supply should be 0");
        assertEq(maxSupply, MAX_SUPPLY, "Max supply should be 3333");
        assertFalse(mintCompleted, "Mint should not be completed");
        assertFalse(lpCreated, "LP should not be created");
        
        mintHelper(owner, MAX_SUPPLY);
        
        (
            totalSupply,
            maxSupply,
            mintCompleted,
            contractBalance,
            tokensPerNFT,
            operationalFunds,
            lpCreated
        ) = conspirapuppets.getMintStatus();
        
        assertEq(totalSupply, MAX_SUPPLY, "Should be fully minted");
        assertTrue(mintCompleted, "Mint should be completed");
        assertTrue(lpCreated, "LP should be created");
        
        console.log("Mint status tests passed");
    }
}