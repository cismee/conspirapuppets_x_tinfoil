// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC721SeaDropStructsErrorsAndEvents} from "seadrop/src/lib/ERC721SeaDropStructsErrorsAndEvents.sol";
import {ERC721SeaDrop} from "seadrop/src/ERC721SeaDrop.sol";
import {PublicDrop} from "seadrop/src/lib/ERC721SeaDropStructsErrorsAndEvents.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

interface ITinfoilToken {
    function mint(address to, uint256 amount) external;
    function enableTrading() external;
}

// EXACT Aerodrome Router interface from Base mainnet
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
    
    function defaultFactory() external view returns (address);
}

// EXACT Aerodrome Factory interface
interface IAerodromeFactory {
    function getPair(address tokenA, address tokenB, bool stable) external view returns (address pair);
    function createPair(address tokenA, address tokenB, bool stable) external returns (address pair);
}

contract Conspirapuppets is ERC721SeaDrop {
    using SafeERC20 for IERC20;
    
    uint256 public constant MAX_SUPPLY = 3333;
    uint256 public constant TOKENS_PER_NFT = 499_549 * 10**18;
    uint256 public constant TOTAL_TOKEN_SUPPLY = 3_330_000_000 * 10**18;
    uint256 public constant LP_TOKEN_AMOUNT = 1_665_000_000 * 10**18;
    uint256 public constant NFT_TOKEN_ALLOCATION = 1_664_996_817 * 10**18;
    uint256 public constant TOKEN_REMAINDER = 3_183 * 10**18;
    uint256 public constant LP_CREATION_DELAY = 5 minutes;
    
    // CRITICAL: Must use `stable = false` consistently everywhere
    bool public constant POOL_IS_STABLE = false;
    
    // SAFEGUARD: Very loose slippage tolerance (50%)
    uint256 public constant DEFAULT_SLIPPAGE_BPS = 5000;
    uint256 public constant ROUNDING_BUFFER = 1000;
    
    // EXACT addresses from Base mainnet
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    bool public mintCompleted = false;
    bool public lpCreated = false;
    bool public lpCreationScheduled = false;
    uint256 public lpCreationTimestamp = 0;
    uint256 public operationalFunds = 0;
    uint256 public totalEthReceived = 0;
    
    address public immutable tinfoilToken;
    address public immutable aerodromeRouter;
    address public immutable aerodromeFactory;
    
    event MintCompleted(uint256 totalSupply, uint256 scheduledLPCreation);
    event ETHReceived(address indexed from, uint256 amount, uint256 totalReceived);
    event FundsAllocated(uint256 lpAmount, uint256 operationalAmount);
    event LiquidityCreated(address indexed lpToken, uint256 ethAmount, uint256 tokenAmount);
    event LPTokensBurned(address indexed lpToken, uint256 amount);
    event TokensDistributed(address indexed recipient, uint256 amount);
    event RemainderMinted(address indexed recipient, uint256 amount);
    event OperationalFundsWithdrawn(address indexed recipient, uint256 amount);
    event LPCreationFailed(string reason);
    event LPCreationScheduled(uint256 timestamp);
    event TradingEnabled();
    event DebugLPCreation(
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 minTokens,
        uint256 minETH,
        address pair,
        bool stable
    );
    event LPCreationComplete(
        address indexed lpPair,
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 lpBurned,
        bool tradingEnabled,
        uint256 timestamp
    );

    constructor(
        string memory name,
        string memory symbol,
        address[] memory allowedSeaDrop,
        address _tinfoilToken,
        address _aerodromeRouter,
        address _aerodromeFactory
    ) ERC721SeaDrop(name, symbol, allowedSeaDrop) {
        require(_tinfoilToken != address(0), "Invalid token address");
        require(_aerodromeRouter != address(0), "Invalid router address");
        require(_aerodromeFactory != address(0), "Invalid factory address");
        
        tinfoilToken = _tinfoilToken;
        aerodromeRouter = _aerodromeRouter;
        aerodromeFactory = _aerodromeFactory;
        
        // SAFEGUARD: Verify router and factory match
        address routerFactory = IAerodromeRouter(_aerodromeRouter).defaultFactory();
        require(routerFactory == _aerodromeFactory, "Router/Factory mismatch");
    }

    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        super._beforeTokenTransfers(from, to, startTokenId, quantity);
        
        if (from == address(0) && to != address(0)) {
            uint256 tokensToMint = quantity * TOKENS_PER_NFT;
            ITinfoilToken(tinfoilToken).mint(to, tokensToMint);
            
            emit TokensDistributed(to, tokensToMint);
            
            // SAFEGUARD: Idempotent - multiple mints in same block handled
            if (!mintCompleted && totalSupply() + quantity >= MAX_SUPPLY) {
                _scheduleMintCompletion();
            }
        }
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function _scheduleMintCompletion() internal {
        // SAFEGUARD: Idempotent guard for race conditions at sell-out
        if (mintCompleted) return;
        require(address(this).balance >= 0, "No ETH to allocate");
        
        // CRITICAL: Set flag FIRST to prevent race conditions
        mintCompleted = true;
        
        uint256 totalEth = address(this).balance;
        uint256 lpEthAmount = totalEth / 2;
        operationalFunds = totalEth - lpEthAmount;
        
        emit FundsAllocated(lpEthAmount, operationalFunds);
        
        if (TOKEN_REMAINDER > 0) {
            ITinfoilToken(tinfoilToken).mint(owner(), TOKEN_REMAINDER);
            emit RemainderMinted(owner(), TOKEN_REMAINDER);
        }
        
        lpCreationTimestamp = block.timestamp + LP_CREATION_DELAY;
        lpCreationScheduled = true;
        
        emit MintCompleted(totalSupply(), lpCreationTimestamp);
        emit LPCreationScheduled(lpCreationTimestamp);
    }

    function completeMint() external onlyOwner nonReentrant {
        require(!mintCompleted, "Mint already completed");
        require(totalSupply() >= MAX_SUPPLY, "Not sold out yet");
        _scheduleMintCompletion();
    }

    function createLP() external onlyOwner nonReentrant {
        require(mintCompleted, "Mint not completed yet");
        require(lpCreationScheduled, "LP creation not scheduled");
        require(block.timestamp >= lpCreationTimestamp, "LP creation delay not passed");
        require(!lpCreated, "LP already created");
        require(address(this).balance >= operationalFunds, "No ETH available for LP");
        
        uint256 lpEthAmount = address(this).balance - operationalFunds;
        require(lpEthAmount > 0, "No ETH for LP");
        
        _createAndBurnLP(lpEthAmount, DEFAULT_SLIPPAGE_BPS);
        
        if (lpCreated) {
            ITinfoilToken(tinfoilToken).enableTrading();
            emit TradingEnabled();
        } else {
            emit LPCreationFailed("LP creation failed - safe to retry");
        }
    }

    function createLPImmediate() external onlyOwner nonReentrant {
        require(mintCompleted, "Mint not completed yet");
        require(!lpCreated, "LP already created");
        require(address(this).balance >= operationalFunds, "No ETH available for LP");
        
        uint256 lpEthAmount = address(this).balance - operationalFunds;
        _createAndBurnLP(lpEthAmount, DEFAULT_SLIPPAGE_BPS);
        
        if (lpCreated) {
            ITinfoilToken(tinfoilToken).enableTrading();
            emit TradingEnabled();
        }
    }

    function _createAndBurnLP(uint256 ethAmount, uint256 slippageBps) internal {
        if (ethAmount == 0) return;
        if (lpCreated) return;
        
        // CRITICAL: Verify pair doesn't exist or get existing pair
        address existingPair = IAerodromeFactory(aerodromeFactory).getPair(
            tinfoilToken,
            WETH,
            POOL_IS_STABLE  // CRITICAL: Use constant everywhere
        );
        
        uint256 contractTokenBalance = IERC20(tinfoilToken).balanceOf(address(this));
        
        // Only mint if we don't already have tokens
        if (contractTokenBalance < LP_TOKEN_AMOUNT) {
            ITinfoilToken(tinfoilToken).mint(address(this), LP_TOKEN_AMOUNT);
            contractTokenBalance = LP_TOKEN_AMOUNT;
        }
        
        require(contractTokenBalance >= LP_TOKEN_AMOUNT - ROUNDING_BUFFER, "Insufficient token balance");
        
        // Use actual balance
        uint256 tokenAmountToUse = contractTokenBalance;
        
        // Clear and set approval
        IERC20(tinfoilToken).approve(aerodromeRouter, 0);
        IERC20(tinfoilToken).approve(aerodromeRouter, tokenAmountToUse);
        
        // Calculate minimums with generous buffer
        uint256 minTokens;
        uint256 minETH;
        
        if (slippageBps >= 10000) {
            minTokens = 1;
            minETH = 1;
        } else {
            minTokens = (tokenAmountToUse * (10000 - slippageBps)) / 10000;
            minETH = (ethAmount * (10000 - slippageBps)) / 10000;
            
            // Extra buffer for rounding
            if (minTokens > ROUNDING_BUFFER * 100) {
                minTokens = minTokens - (ROUNDING_BUFFER * 100);
            } else {
                minTokens = 1;
            }
            
            if (minETH > ROUNDING_BUFFER) {
                minETH = minETH - ROUNDING_BUFFER;
            } else {
                minETH = 1;
            }
        }
        
        uint256 deadline = block.timestamp + 2 hours;
        
        // SAFEGUARD: Emit debug info before attempting
        emit DebugLPCreation(
            tokenAmountToUse,
            ethAmount,
            minTokens,
            minETH,
            existingPair,
            POOL_IS_STABLE
        );
        
        // CRITICAL: Match EXACT ABI signature
        try IAerodromeRouter(aerodromeRouter).addLiquidityETH{value: ethAmount}(
            tinfoilToken,        // token
            POOL_IS_STABLE,      // stable (MUST be false consistently)
            tokenAmountToUse,    // amountTokenDesired
            minTokens,           // amountTokenMin
            minETH,              // amountETHMin
            address(this),       // to
            deadline             // deadline
        ) returns (uint256 amountToken, uint256 amountETH, uint256 /* liquidity */) {
            
            // CRITICAL: Query with same `stable` flag
            address lpTokenAddress = IAerodromeFactory(aerodromeFactory).getPair(
                tinfoilToken,
                WETH,
                POOL_IS_STABLE  // CRITICAL: Must match above
            );
            
            require(lpTokenAddress != address(0), "LP pair not found after creation");
            
            emit LiquidityCreated(lpTokenAddress, amountETH, amountToken);
            
            uint256 lpBalance = IERC20(lpTokenAddress).balanceOf(address(this));
            require(lpBalance > 0, "No LP tokens received");
            
            IERC20(lpTokenAddress).safeTransfer(BURN_ADDRESS, lpBalance);
            
            emit LPTokensBurned(lpTokenAddress, lpBalance);
            lpCreated = true;
            
            IERC20(tinfoilToken).approve(aerodromeRouter, 0);
            
            // ADDED: Comprehensive completion event
            emit LPCreationComplete(
                lpTokenAddress,
                amountETH,
                amountToken,
                lpBalance,
                false, // Trading will be enabled separately
                block.timestamp
            );
            
        } catch Error(string memory reason) {
            emit LPCreationFailed(reason);
            IERC20(tinfoilToken).approve(aerodromeRouter, 0);
        } catch (bytes memory lowLevelData) {
            // Decode revert reason if possible
            string memory reason = _decodeRevertReason(lowLevelData);
            emit LPCreationFailed(reason);
            IERC20(tinfoilToken).approve(aerodromeRouter, 0);
        }
    }

    // Helper to decode revert reasons
    function _decodeRevertReason(bytes memory revertData) internal pure returns (string memory) {
        // Check for standard Error(string) selector (0x08c379a0)
        if (revertData.length >= 68 && 
            revertData[0] == 0x08 && 
            revertData[1] == 0xc3 && 
            revertData[2] == 0x79 && 
            revertData[3] == 0xa0) {
            
            assembly {
                revertData := add(revertData, 0x04)
            }
            return abi.decode(revertData, (string));
        }
        
        // Check for custom errors (4 bytes)
        if (revertData.length == 4) {
            bytes4 errorSelector;
            assembly {
                errorSelector := mload(add(revertData, 0x20))
            }
            
            // Known Aerodrome errors from ABI
            if (errorSelector == bytes4(keccak256("Expired()"))) return "Expired";
            if (errorSelector == bytes4(keccak256("InsufficientAmount()"))) return "InsufficientAmount";
            if (errorSelector == bytes4(keccak256("InsufficientAmountA()"))) return "InsufficientAmountA";
            if (errorSelector == bytes4(keccak256("InsufficientAmountB()"))) return "InsufficientAmountB";
            if (errorSelector == bytes4(keccak256("InsufficientLiquidity()"))) return "InsufficientLiquidity";
            if (errorSelector == bytes4(keccak256("PoolDoesNotExist()"))) return "PoolDoesNotExist";
            
            return "Unknown custom error";
        }
        
        return "Unknown error";
    }

    function configurePublicDrop(
        address seaDropImpl,
        PublicDrop calldata publicDrop
    ) external onlyOwner {
        this.updatePublicDrop(seaDropImpl, publicDrop);
    }

    function retryLPCreation() external onlyOwner nonReentrant {
        require(mintCompleted, "Mint not completed yet");
        require(!lpCreated, "LP already created");
        require(address(this).balance >= operationalFunds, "No ETH available for LP");
        
        uint256 lpEthAmount = address(this).balance - operationalFunds;
        _createAndBurnLP(lpEthAmount, DEFAULT_SLIPPAGE_BPS);
        
        if (lpCreated) {
            ITinfoilToken(tinfoilToken).enableTrading();
            emit TradingEnabled();
        }
    }
    
    // FIXED: Added explicit gas limit parameter for Base provider quirks
    function emergencyLPCreation(
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 slippageBps,
        uint256 gasLimit
    ) external onlyOwner nonReentrant {
        require(mintCompleted, "Mint not completed yet");
        require(!lpCreated, "LP already created");
        require(slippageBps <= 10000, "Slippage must be <= 100%");
        require(gasLimit > 0 && gasLimit <= 10000000, "Invalid gas limit");
        
        uint256 contractTokenBalance = IERC20(tinfoilToken).balanceOf(address(this));
        
        require(
            tokenAmount <= contractTokenBalance || 
            (contractTokenBalance >= tokenAmount - ROUNDING_BUFFER),
            "Insufficient token balance"
        );
        require(
            ethAmount <= address(this).balance - operationalFunds || 
            (address(this).balance >= ethAmount + operationalFunds - ROUNDING_BUFFER),
            "Insufficient ETH balance"
        );
        
        uint256 actualTokenAmount = tokenAmount > contractTokenBalance ? contractTokenBalance : tokenAmount;
        
        IERC20(tinfoilToken).approve(aerodromeRouter, 0);
        IERC20(tinfoilToken).approve(aerodromeRouter, actualTokenAmount);
        
        uint256 minTokens = (actualTokenAmount * (10000 - slippageBps)) / 10000;
        uint256 minEth = (ethAmount * (10000 - slippageBps)) / 10000;
        
        if (minTokens > ROUNDING_BUFFER * 100) {
            minTokens = minTokens - (ROUNDING_BUFFER * 100);
        } else {
            minTokens = 1;
        }
        
        if (minEth > ROUNDING_BUFFER) {
            minEth = minEth - ROUNDING_BUFFER;
        } else {
            minEth = 1;
        }
        
        // FIXED: Added explicit gas limit to handle Base provider estimation quirks
        try IAerodromeRouter(aerodromeRouter).addLiquidityETH{value: ethAmount, gas: gasLimit}(
            tinfoilToken,
            POOL_IS_STABLE,
            actualTokenAmount,
            minTokens,
            minEth,
            address(this),
            block.timestamp + 2 hours
        ) returns (uint256 amountToken, uint256 amountETH, uint256 /* liquidity */) {
            
            address lpTokenAddress = IAerodromeFactory(aerodromeFactory).getPair(
                tinfoilToken,
                WETH,
                POOL_IS_STABLE
            );
            
            require(lpTokenAddress != address(0), "LP pair not found");
            
            emit LiquidityCreated(lpTokenAddress, amountETH, amountToken);
            
            uint256 lpBalance = IERC20(lpTokenAddress).balanceOf(address(this));
            if (lpBalance > 0) {
                IERC20(lpTokenAddress).safeTransfer(BURN_ADDRESS, lpBalance);
                emit LPTokensBurned(lpTokenAddress, lpBalance);
                lpCreated = true;
                
                ITinfoilToken(tinfoilToken).enableTrading();
                emit TradingEnabled();
                
                emit LPCreationComplete(
                    lpTokenAddress,
                    amountETH,
                    amountToken,
                    lpBalance,
                    true,
                    block.timestamp
                );
            }
            
            IERC20(tinfoilToken).approve(aerodromeRouter, 0);
            
        } catch Error(string memory reason) {
            emit LPCreationFailed(reason);
            IERC20(tinfoilToken).approve(aerodromeRouter, 0);
        } catch (bytes memory lowLevelData) {
            string memory reason = _decodeRevertReason(lowLevelData);
            emit LPCreationFailed(reason);
            IERC20(tinfoilToken).approve(aerodromeRouter, 0);
        }
    }

    function enableTradingManual() external onlyOwner {
        require(mintCompleted, "Mint not completed yet");
        require(!lpCreated, "Use createLP instead");
        
        address pair = IAerodromeFactory(aerodromeFactory).getPair(
            tinfoilToken,
            WETH,
            POOL_IS_STABLE  // CRITICAL: Use constant
        );
        require(pair != address(0), "LP pair does not exist");
        
        uint256 lpBalance = IERC20(pair).balanceOf(BURN_ADDRESS);
        require(lpBalance > 0, "No LP tokens burned");
        
        lpCreated = true;
        ITinfoilToken(tinfoilToken).enableTrading();
        emit TradingEnabled();
    }

    function withdrawOperationalFunds() external onlyOwner {
        require(mintCompleted, "Mint not completed yet");
        require(operationalFunds > 0, "No operational funds available");
        
        uint256 amount = operationalFunds;
        operationalFunds = 0;
        
        (bool success,) = owner().call{value: amount}("");
        require(success, "Withdrawal failed");
        
        emit OperationalFundsWithdrawn(owner(), amount);
    }

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

    function getMintStatus() external view returns (
        uint256 _totalSupply,
        uint256 _maxSupply,
        bool _mintCompleted,
        uint256 _contractBalance,
        uint256 _tokensPerNFT,
        uint256 _operationalFunds,
        bool _lpCreated,
        uint256 _totalEthReceived
    ) {
        return (
            totalSupply(),
            MAX_SUPPLY,
            mintCompleted,
            address(this).balance,
            TOKENS_PER_NFT,
            operationalFunds,
            lpCreated,
            totalEthReceived
        );
    }

    function getLPCreationStatus() external view returns (
        bool _lpCreationScheduled,
        uint256 _lpCreationTimestamp,
        bool _canCreateLP,
        uint256 _timeRemaining
    ) {
        bool canCreate = lpCreationScheduled && block.timestamp >= lpCreationTimestamp && !lpCreated;
        uint256 timeRemaining = 0;
        
        if (lpCreationScheduled && block.timestamp < lpCreationTimestamp) {
            timeRemaining = lpCreationTimestamp - block.timestamp;
        }
        
        return (lpCreationScheduled, lpCreationTimestamp, canCreate, timeRemaining);
    }

    // HELPER: Get expected LP pair address
    function getExpectedLPPair() external view returns (address) {
        return IAerodromeFactory(aerodromeFactory).getPair(
            tinfoilToken,
            WETH,
            POOL_IS_STABLE
        );
    }

    receive() external payable {
        totalEthReceived += msg.value;
        emit ETHReceived(msg.sender, msg.value, totalEthReceived);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}