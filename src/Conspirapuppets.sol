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

interface IAerodromeRouter {
    function addLiquidityETH(
        address token,
        bool stable,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

interface IAerodromeFactory {
    function getPair(address tokenA, address tokenB, bool stable) external view returns (address pair);
}

contract Conspirapuppets is ERC721SeaDrop {
    // Constants
    uint256 public constant MAX_SUPPLY = 3333;
    uint256 public constant TOKENS_PER_NFT = 499_549 * 10**18;
    uint256 public constant TOTAL_TOKEN_SUPPLY = 3_330_000_000 * 10**18;
    uint256 public constant LP_TOKEN_AMOUNT = 1_665_000_000 * 10**18;
    // Actual allocation from mints: 3333 * 499_549 = 1,664,996,817 tokens
    // Remainder to match 1.665B: 3,183 tokens (will be minted to treasury)
    uint256 public constant NFT_TOKEN_ALLOCATION = 1_664_996_817 * 10**18;
    uint256 public constant TOKEN_REMAINDER = 3_183 * 10**18;
    
    // Base network addresses
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    // State variables
    bool public mintCompleted = false;
    bool public lpCreated = false;
    uint256 public operationalFunds = 0;
    uint256 public totalEthReceived = 0;
    
    // Addresses
    address public immutable tinfoilToken;
    address public immutable aerodromeRouter;
    address public immutable aerodromeFactory;
    
    // Events
    event MintCompleted(uint256 totalSupply);
    event ETHReceived(address indexed from, uint256 amount, uint256 totalReceived);
    event FundsAllocated(uint256 lpAmount, uint256 operationalAmount);
    event LiquidityCreated(address indexed lpToken, uint256 ethAmount, uint256 tokenAmount);
    event LPTokensBurned(address indexed lpToken, uint256 amount);
    event TokensDistributed(address indexed recipient, uint256 amount);
    event RemainderMinted(address indexed recipient, uint256 amount);
    event OperationalFundsWithdrawn(address indexed recipient, uint256 amount);
    event LPCreationFailed(string reason);
    event TradingEnabled();

    constructor(
        string memory name,
        string memory symbol,
        address[] memory allowedSeaDrop,
        address _tinfoilToken,
        address _aerodromeRouter,
        address _aerodromeFactory
    ) ERC721SeaDrop(name, symbol, allowedSeaDrop) {
        tinfoilToken = _tinfoilToken;
        aerodromeRouter = _aerodromeRouter;
        aerodromeFactory = _aerodromeFactory;
    }

    /**
     * @dev Override _beforeTokenTransfers to add automatic token distribution
     * This is called by SeaDrop during minting
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

    /**
     * @dev Complete mint process when collection sells out or manually triggered
     * Can be called by owner if mint doesn't sell out naturally
     */
    function completeMint() external onlyOwner {
        require(!mintCompleted, "Mint already completed");
        _completeMint();
    }

    /**
     * @dev Internal function to complete the mint
     */
    function _completeMint() internal {
        if (mintCompleted) return;
        
        mintCompleted = true;
        
        uint256 totalEth = address(this).balance;
        require(totalEth > 0, "No ETH to allocate");
        
        uint256 lpEthAmount = totalEth / 2;
        operationalFunds = totalEth - lpEthAmount;
        
        emit FundsAllocated(lpEthAmount, operationalFunds);
        
        // Mint the remainder tokens to make exact 1.665B allocation
        if (TOKEN_REMAINDER > 0) {
            ITinfoilToken(tinfoilToken).mint(owner(), TOKEN_REMAINDER);
            emit RemainderMinted(owner(), TOKEN_REMAINDER);
        }
        
        // Create LP first, THEN enable trading (critical order)
        _createAndBurnLP(lpEthAmount);
        
        // Only enable trading after LP is created and burned
        if (lpCreated) {
            ITinfoilToken(tinfoilToken).enableTrading();
            emit TradingEnabled();
        }
        
        emit MintCompleted(totalSupply());
    }

    /**
     * @dev Create liquidity pool and burn LP tokens permanently
     * Protected by nonReentrant
     */
    function _createAndBurnLP(uint256 ethAmount) internal nonReentrant {
        if (ethAmount == 0) return;
        if (lpCreated) return;
        
        // Mint tokens for LP
        ITinfoilToken(tinfoilToken).mint(address(this), LP_TOKEN_AMOUNT);
        
        // Approve router
        IERC20(tinfoilToken).approve(aerodromeRouter, LP_TOKEN_AMOUNT);
        
        // Calculate slippage protection (5%)
        uint256 minTokens = LP_TOKEN_AMOUNT * 95 / 100;
        uint256 minETH = ethAmount * 95 / 100;
        
        // Try to create LP
        try IAerodromeRouter(aerodromeRouter).addLiquidityETH{value: ethAmount}(
            tinfoilToken,
            false, // volatile pair
            LP_TOKEN_AMOUNT,
            minTokens,
            minETH,
            address(this),
            block.timestamp + 300
        ) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
            
            emit LiquidityCreated(address(this), amountETH, amountToken);
            
            // Get LP token address from factory (note the 'false' parameter for volatile pair)
            address lpTokenAddress = IAerodromeFactory(aerodromeFactory).getPair(
                tinfoilToken, 
                WETH, 
                false // volatile
            );
            require(lpTokenAddress != address(0), "LP pair not found");
            
            // Burn ALL LP tokens
            uint256 lpBalance = IERC20(lpTokenAddress).balanceOf(address(this));
            require(lpBalance > 0, "No LP tokens to burn");
            
            IERC20(lpTokenAddress).transfer(BURN_ADDRESS, lpBalance);
            
            emit LPTokensBurned(lpTokenAddress, lpBalance);
            lpCreated = true;
            
        } catch Error(string memory reason) {
            emit LPCreationFailed(reason);
        } catch (bytes memory) {
            emit LPCreationFailed("Unknown error");
        }
    }

    /**
     * @dev Configure public drop parameters
     */
    function configurePublicDrop(
        address seaDropImpl,
        PublicDrop calldata publicDrop
    ) external onlyOwner {
        this.updatePublicDrop(seaDropImpl, publicDrop);
    }

    /**
     * @dev Manual LP creation retry - callable if automatic creation failed
     * Protected by nonReentrant
     */
    function retryLPCreation() external onlyOwner nonReentrant {
        require(mintCompleted, "Mint not completed yet");
        require(!lpCreated, "LP already created");
        require(address(this).balance > operationalFunds, "No ETH available for LP");
        
        uint256 lpEthAmount = address(this).balance - operationalFunds;
        _createAndBurnLP(lpEthAmount);
        
        // Enable trading if LP creation succeeded
        if (lpCreated) {
            ITinfoilToken(tinfoilToken).enableTrading();
            emit TradingEnabled();
        }
    }
    
    /**
     * @dev Emergency LP creation with custom parameters
     * Protected by nonReentrant
     */
    function emergencyLPCreation(
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 slippageBps
    ) external onlyOwner nonReentrant {
        require(mintCompleted, "Mint not completed yet");
        require(!lpCreated, "LP already created");
        require(tokenAmount <= IERC20(tinfoilToken).balanceOf(address(this)), "Insufficient token balance");
        require(ethAmount <= address(this).balance - operationalFunds, "Insufficient ETH balance");
        require(slippageBps <= 2000, "Slippage too high"); // Max 20%
        
        // Approve tokens
        IERC20(tinfoilToken).approve(aerodromeRouter, tokenAmount);
        
        // Calculate slippage amounts
        uint256 minTokens = tokenAmount * (10000 - slippageBps) / 10000;
        uint256 minEth = ethAmount * (10000 - slippageBps) / 10000;
        
        try IAerodromeRouter(aerodromeRouter).addLiquidityETH{value: ethAmount}(
            tinfoilToken,
            false,
            tokenAmount,
            minTokens,
            minEth,
            address(this),
            block.timestamp + 300
        ) returns (uint256 amountToken, uint256 amountETH, uint256) {
            
            emit LiquidityCreated(address(this), amountETH, amountToken);
            
            // Get and burn LP tokens
            address lpTokenAddress = IAerodromeFactory(aerodromeFactory).getPair(tinfoilToken, WETH, false);
            require(lpTokenAddress != address(0), "LP pair not found");
            
            uint256 lpBalance = IERC20(lpTokenAddress).balanceOf(address(this));
            if (lpBalance > 0) {
                IERC20(lpTokenAddress).transfer(BURN_ADDRESS, lpBalance);
                emit LPTokensBurned(lpTokenAddress, lpBalance);
                lpCreated = true;
                
                // Enable trading
                ITinfoilToken(tinfoilToken).enableTrading();
                emit TradingEnabled();
            }
            
        } catch Error(string memory reason) {
            emit LPCreationFailed(reason);
        } catch (bytes memory) {
            emit LPCreationFailed("Unknown error");
        }
    }

    /**
     * @dev Withdraw operational funds
     */
    function withdrawOperationalFunds() external onlyOwner {
        require(mintCompleted, "Mint not completed yet");
        require(operationalFunds > 0, "No operational funds available");
        
        uint256 amount = operationalFunds;
        operationalFunds = 0;
        
        (bool success,) = owner().call{value: amount}("");
        require(success, "Withdrawal failed");
        
        emit OperationalFundsWithdrawn(owner(), amount);
    }

    /**
     * @dev Emergency withdraw (only after mint completion)
     */
    function emergencyWithdraw() external onlyOwner {
        require(mintCompleted, "Can only withdraw after mint completion");
        uint256 balance = address(this).balance;
        if (balance > 0) {
            operationalFunds = 0;
            (bool success,) = owner().call{value: balance}("");
            require(success, "Emergency withdrawal failed");
            emit OperationalFundsWithdrawn(owner(), balance);
        }
    }

    /**
     * @dev Owner-only airdrop function (does not bypass SeaDrop for sales)
     * Counts toward MAX_SUPPLY
     */
    function airdrop(address[] calldata recipients, uint256[] calldata quantities) external onlyOwner {
        require(recipients.length == quantities.length, "Length mismatch");
        require(!mintCompleted, "Mint already completed");
        
        uint256 totalQuantity = 0;
        for (uint256 i = 0; i < quantities.length; i++) {
            totalQuantity += quantities[i];
        }
        
        require(totalSupply() + totalQuantity <= MAX_SUPPLY, "Exceeds max supply");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], quantities[i]);
        }
    }

    /**
     * @dev Get current mint status
     */
    function getMintStatus() external view returns (
        uint256 _totalSupply,
        uint256 _maxSupply,
        bool _mintCompleted,
        uint256 _contractBalance,
        uint256 _tokensPerNFT,
        uint256 _operationalFunds,
        bool _lpCreated
    ) {
        return (
            totalSupply(),
            MAX_SUPPLY,
            mintCompleted,
            address(this).balance,
            TOKENS_PER_NFT,
            operationalFunds,
            lpCreated
        );
    }

    /**
     * @dev Receive ETH from SeaDrop sales
     */
    receive() external payable {
        totalEthReceived += msg.value;
        emit ETHReceived(msg.sender, msg.value, totalEthReceived);
    }

    /**
     * @dev Support interface override
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
    * @dev Test helper - REMOVE before production deployment
    * Only owner can call this for testing purposes
    */
    function mintForTesting(address to, uint256 quantity) external onlyOwner {
        require(totalSupply() + quantity <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, quantity);
}
}