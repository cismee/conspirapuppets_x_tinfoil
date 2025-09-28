// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC721SeaDropStructsErrorsAndEvents} from "seadrop/src/lib/ERC721SeaDropStructsErrorsAndEvents.sol";
import {ERC721SeaDrop} from "seadrop/src/ERC721SeaDrop.sol";
import {PublicDrop} from "seadrop/src/lib/ERC721SeaDropStructsErrorsAndEvents.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface ITinfoilToken {
    function mint(address to, uint256 amount) external;
    function enableTrading() external;
}

interface IAerodrome {
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
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
    
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

contract Conspirapuppets is ERC721SeaDrop {
    // Constants
    uint256 public constant MAX_SUPPLY = 3333;
    uint256 public constant TOKENS_PER_NFT = 499_549 * 10**18; // ~500K tokens with 18 decimals
    uint256 public constant TOTAL_TOKEN_SUPPLY = 3_330_000_000 * 10**18; // 3.33B tokens total
    uint256 public constant LP_TOKEN_AMOUNT = 1_665_000_000 * 10**18; // 1.665B tokens (50% for LP)
    uint256 public constant NFT_TOKEN_ALLOCATION = 1_665_000_000 * 10**18; // 1.665B tokens for NFT holders (50%)
    
    // State variables
    bool public mintCompleted = false;
    uint256 public operationalFunds = 0; // Track ETH available for withdrawal
    
    // Addresses
    address public immutable tinfoilToken;
    address public immutable aerodromeRouter;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    // Events
    event MintCompleted();
    event LiquidityCreated(address indexed lpToken, uint256 ethAmount, uint256 tokenAmount);
    event LPTokensBurned(address indexed lpToken, uint256 amount);
    event TokensDistributed(address indexed recipient, uint256 amount);
    event OperationalFundsWithdrawn(uint256 amount);

    constructor(
        string memory name,
        string memory symbol,
        address[] memory allowedSeaDrop,
        address _tinfoilToken,
        address _aerodromeRouter
    ) ERC721SeaDrop(name, symbol, allowedSeaDrop) {
        tinfoilToken = _tinfoilToken;
        aerodromeRouter = _aerodromeRouter;
    }

    /**
     * @dev Override _beforeTokenTransfers to add automatic token distribution
     */
    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        super._beforeTokenTransfers(from, to, startTokenId, quantity);
        
        // Only distribute tokens on mint (from == address(0))
        if (from == address(0) && to != address(0)) {
            // Mint TINFOIL tokens to recipient
            uint256 tokensToMint = quantity * TOKENS_PER_NFT;
            ITinfoilToken(tinfoilToken).mint(to, tokensToMint);
            
            emit TokensDistributed(to, tokensToMint);
            
            // Check if this mint completes the collection
            if (totalSupply() + quantity >= MAX_SUPPLY) {
                _completeMint();
            }
        }
    }

    /**
     * @dev Start token ID at 1
     */
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    // SeaDrop base contracts already provide maxSupply() and getMintStats()
    // Max supply will be configured through SeaDrop's mechanisms

    /**
     * @dev Test helper function - only for testing, would not be in production
     */
    function mint(address to, uint256 quantity) external {
        // This is a simplified mint for testing - in production, minting goes through SeaDrop
        _mint(to, quantity);
    }

    /**
     * @dev Complete mint process when collection sells out
     */
    function _completeMint() internal {
        if (mintCompleted) return; // Prevent multiple executions
        
        mintCompleted = true;
        
        uint256 totalEth = address(this).balance;
        uint256 lpEthAmount = totalEth / 2;        // 50% for LP
        operationalFunds = totalEth - lpEthAmount; // 50% for operations (stored for withdrawal)
        
        // Enable token trading first
        ITinfoilToken(tinfoilToken).enableTrading();
        
        // Create LP and burn LP tokens
        _createAndBurnLP(lpEthAmount);
        
        emit MintCompleted();
    }

    /**
     * @dev Create liquidity pool and burn LP tokens permanently
     */
    function _createAndBurnLP(uint256 ethAmount) internal {
        if (ethAmount == 0) return;
        
        // Mint tokens for LP (50% of total supply)
        ITinfoilToken(tinfoilToken).mint(address(this), LP_TOKEN_AMOUNT);
        
        // Approve Aerodrome router to spend tokens
        IERC20(tinfoilToken).approve(aerodromeRouter, LP_TOKEN_AMOUNT);
        
        // Add liquidity - LP tokens will be returned to this contract
        (uint256 amountA, uint256 amountB, uint256 liquidity) = IAerodrome(aerodromeRouter).addLiquidity(
            tinfoilToken,
            address(0), // ETH/WETH address on Base - update this to actual WETH address
            false, // volatile pair (not stable)
            LP_TOKEN_AMOUNT,
            ethAmount,
            LP_TOKEN_AMOUNT * 95 / 100, // 5% slippage tolerance
            ethAmount * 95 / 100,       // 5% slippage tolerance
            address(this), // LP tokens come to this contract
            block.timestamp + 300 // 5 minute deadline
        );
        
        emit LiquidityCreated(address(this), ethAmount, LP_TOKEN_AMOUNT);
        
        // Get the LP token contract address
        address lpTokenAddress = IAerodrome(aerodromeRouter).getPair(tinfoilToken, address(0));
        require(lpTokenAddress != address(0), "LP pair not found");
        
        // Burn ALL LP tokens by sending to burn address
        uint256 lpBalance = IERC20(lpTokenAddress).balanceOf(address(this));
        require(lpBalance > 0, "No LP tokens to burn");
        
        IERC20(lpTokenAddress).transfer(BURN_ADDRESS, lpBalance);
        
        emit LPTokensBurned(lpTokenAddress, lpBalance);
    }

    /**
     * @dev Configure public drop parameters
     */
    function configurePublicDrop(
        address seaDropImpl,
        PublicDrop calldata publicDrop
    ) external onlyOwner {
        require(publicDrop.mintPrice == 0.005 ether, "Mint price must be 0.005 ETH");
        require(publicDrop.maxTotalMintableByWallet <= 10, "Max per wallet too high");
        
        // Use the correct SeaDrop function name
        this.updatePublicDrop(seaDropImpl, publicDrop);
    }

    /**
     * @dev Withdraw operational funds - only callable by owner after mint completion
     */
    function withdrawOperationalFunds() external onlyOwner {
        require(mintCompleted, "Mint not completed yet");
        require(operationalFunds > 0, "No operational funds available");
        
        uint256 amount = operationalFunds;
        operationalFunds = 0; // Reset to prevent re-entrancy
        
        (bool success,) = owner().call{value: amount}("");
        require(success, "Withdrawal failed");
        
        emit OperationalFundsWithdrawn(amount);
    }

    /**
     * @dev Emergency withdraw function (only after mint completion)
     */
    function emergencyWithdraw() external onlyOwner {
        require(mintCompleted, "Can only withdraw after mint completion");
        uint256 balance = address(this).balance;
        if (balance > 0) {
            operationalFunds = 0; // Reset operational funds tracking
            (bool success,) = owner().call{value: balance}("");
            require(success, "Emergency withdrawal failed");
        }
    }

    /**
     * @dev Get current mint status for UI
     */
    function getMintStatus() external view returns (
        uint256 _totalSupply,
        uint256 _maxSupply,
        bool _mintCompleted,
        uint256 _contractBalance,
        uint256 _tokensPerNFT,
        uint256 _operationalFunds
    ) {
        return (
            totalSupply(),
            MAX_SUPPLY,
            mintCompleted,
            address(this).balance,
            TOKENS_PER_NFT,
            operationalFunds
        );
    }

    /**
     * @dev Support interface override
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Receive ETH
     */
    receive() external payable {}
}