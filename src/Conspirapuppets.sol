// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC721SeaDropStructsErrorsAndEvents} from "seadrop/src/lib/ERC721SeaDropStructsErrorsAndEvents.sol";
import {ERC721SeaDrop} from "seadrop/src/ERC721SeaDrop.sol";
import {PublicDrop} from "seadrop/src/lib/ERC721SeaDropStructsErrorsAndEvents.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";

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

// FIXED: Added ReentrancyGuard inheritance
contract Conspirapuppets is ERC721SeaDrop, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    uint256 public constant MAX_SUPPLY = 3333;
    uint256 public constant TOKENS_PER_NFT = 499_549 * 10**18;
    uint256 public constant TOTAL_TOKEN_SUPPLY = 3_330_000_000 * 10**18;
    uint256 public constant LP_TOKEN_AMOUNT = 1_665_000_000 * 10**18;
    uint256 public constant NFT_TOKEN_ALLOCATION = 1_664_996_817 * 10**18;
    uint256 public constant TOKEN_REMAINDER = 3_183 * 10**18;
    
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    bool public mintCompleted = false;
    bool public lpCreated = false;
    uint256 public operationalFunds = 0;
    uint256 public totalEthReceived = 0;
    
    address public immutable tinfoilToken;
    address public immutable aerodromeRouter;
    address public immutable aerodromeFactory;
    
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
            
            if (totalSupply() + quantity >= MAX_SUPPLY) {
                _completeMint();
            }
        }
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function completeMint() external onlyOwner nonReentrant {
        require(!mintCompleted, "Mint already completed");
        _completeMint();
    }

    // FIXED: Removed nonReentrant from internal function (called from _beforeTokenTransfers)
    function _completeMint() internal {
        // CHECKS
        if (mintCompleted) return;
        require(address(this).balance > 0, "No ETH to allocate");
        
        // EFFECTS - All state changes before external interactions
        mintCompleted = true;
        
        uint256 totalEth = address(this).balance;
        uint256 lpEthAmount = totalEth / 2;
        operationalFunds = totalEth - lpEthAmount;
        
        emit FundsAllocated(lpEthAmount, operationalFunds);
        emit MintCompleted(totalSupply());
        
        // INTERACTIONS - External calls last
        if (TOKEN_REMAINDER > 0) {
            ITinfoilToken(tinfoilToken).mint(owner(), TOKEN_REMAINDER);
            emit RemainderMinted(owner(), TOKEN_REMAINDER);
        }
        
        _createAndBurnLP(lpEthAmount);
        
        if (lpCreated) {
            ITinfoilToken(tinfoilToken).enableTrading();
            emit TradingEnabled();
        } else {
            emit LPCreationFailed("LP creation failed during mint completion");
        }
    }

    // FIXED: Removed pair existence check to allow Aerodrome to handle it naturally
    function _createAndBurnLP(uint256 ethAmount) internal {
        if (ethAmount == 0) return;
        if (lpCreated) return;
        
        ITinfoilToken(tinfoilToken).mint(address(this), LP_TOKEN_AMOUNT);
        
        IERC20(tinfoilToken).approve(aerodromeRouter, LP_TOKEN_AMOUNT);
        
        // Increased slippage tolerance to 10% for initial LP creation
        uint256 minTokens = LP_TOKEN_AMOUNT * 90 / 100;
        uint256 minETH = ethAmount * 90 / 100;
        
        try IAerodromeRouter(aerodromeRouter).addLiquidityETH{value: ethAmount}(
            tinfoilToken,
            false,
            LP_TOKEN_AMOUNT,
            minTokens,
            minETH,
            address(this),
            block.timestamp + 300
        ) returns (uint256 amountToken, uint256 amountETH, uint256) {
            
            address lpTokenAddress = IAerodromeFactory(aerodromeFactory).getPair(tinfoilToken, WETH, false);
            require(lpTokenAddress != address(0), "LP pair not found");
            
            emit LiquidityCreated(lpTokenAddress, amountETH, amountToken);
            
            uint256 lpBalance = IERC20(lpTokenAddress).balanceOf(address(this));
            require(lpBalance > 0, "No LP tokens to burn");
            
            // Use SafeERC20 for LP token transfer
            IERC20(lpTokenAddress).safeTransfer(BURN_ADDRESS, lpBalance);
            
            emit LPTokensBurned(lpTokenAddress, lpBalance);
            lpCreated = true;
            
        } catch Error(string memory reason) {
            emit LPCreationFailed(reason);
        } catch (bytes memory) {
            emit LPCreationFailed("Unknown error");
        }
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
        require(address(this).balance > operationalFunds, "No ETH available for LP");
        
        uint256 lpEthAmount = address(this).balance - operationalFunds;
        _createAndBurnLP(lpEthAmount);
        
        if (lpCreated) {
            ITinfoilToken(tinfoilToken).enableTrading();
            emit TradingEnabled();
        }
    }
    
    function emergencyLPCreation(
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 slippageBps
    ) external onlyOwner nonReentrant {
        require(mintCompleted, "Mint not completed yet");
        require(!lpCreated, "LP already created");
        require(slippageBps <= 2000, "Slippage too high");
        
        // Check token balance (tokens might have been minted in failed LP attempt)
        uint256 contractTokenBalance = IERC20(tinfoilToken).balanceOf(address(this));
        require(tokenAmount <= contractTokenBalance, "Insufficient token balance");
        require(ethAmount <= address(this).balance - operationalFunds, "Insufficient ETH balance");
        
        IERC20(tinfoilToken).approve(aerodromeRouter, tokenAmount);
        
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
            
            address lpTokenAddress = IAerodromeFactory(aerodromeFactory).getPair(tinfoilToken, WETH, false);
            require(lpTokenAddress != address(0), "LP pair not found");
            
            emit LiquidityCreated(lpTokenAddress, amountETH, amountToken);
            
            uint256 lpBalance = IERC20(lpTokenAddress).balanceOf(address(this));
            if (lpBalance > 0) {
                IERC20(lpTokenAddress).safeTransfer(BURN_ADDRESS, lpBalance);
                emit LPTokensBurned(lpTokenAddress, lpBalance);
                lpCreated = true;
                
                ITinfoilToken(tinfoilToken).enableTrading();
                emit TradingEnabled();
            }
            
        } catch Error(string memory reason) {
            emit LPCreationFailed(reason);
        } catch (bytes memory) {
            emit LPCreationFailed("Unknown error");
        }
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

    receive() external payable {
        totalEthReceived += msg.value;
        emit ETHReceived(msg.sender, msg.value, totalEthReceived);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}