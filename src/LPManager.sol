// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import "./interfaces/Interfaces.sol";

contract LPManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    address public immutable nftContract;
    address public immutable tinfoilToken;
    address public immutable aerodromeRouter;
    address public immutable aerodromeFactory;
    
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    bool public constant POOL_IS_STABLE = false;
    uint256 public constant DEFAULT_SLIPPAGE_BPS = 5000;
    uint256 public constant ROUNDING_BUFFER = 1000;
    
    bool public lpCreated = false;
    
    event LiquidityCreated(address indexed lpToken, uint256 ethAmount, uint256 tokenAmount);
    event LPTokensBurned(address indexed lpToken, uint256 amount);
    event PairWhitelisted(address indexed pair);
    event LPCreationFailed(string reason);
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
        address _nftContract,
        address _tinfoilToken,
        address _aerodromeRouter,
        address _aerodromeFactory
    ) {
        require(_tinfoilToken != address(0), "Invalid token address");
        require(_aerodromeRouter != address(0), "Invalid router address");
        require(_aerodromeFactory != address(0), "Invalid factory address");
        
        nftContract = _nftContract;
        tinfoilToken = _tinfoilToken;
        aerodromeRouter = _aerodromeRouter;
        aerodromeFactory = _aerodromeFactory;
        
        if (_aerodromeRouter != address(0)) {
            address routerFactory = IAerodromeRouter(_aerodromeRouter).defaultFactory();
            require(routerFactory == _aerodromeFactory, "Router/Factory mismatch");
        }
    }
    
    modifier onlyNFTContract() {
        require(msg.sender == nftContract, "Only NFT contract");
        _;
    }
    
    function createAndBurnLP(
        uint256 tokenAmount,
        uint256 slippageBps
    ) external payable onlyNFTContract nonReentrant returns (bool success) {
        uint256 ethAmount = msg.value;
        if (ethAmount == 0) return false;
        if (lpCreated) return false;
        
        address existingPair = IAerodromeFactory(aerodromeFactory).getPair(
            tinfoilToken,
            WETH,
            POOL_IS_STABLE
        );
        
        IERC20(tinfoilToken).approve(aerodromeRouter, 0);
        IERC20(tinfoilToken).approve(aerodromeRouter, tokenAmount);
        
        uint256 minTokens;
        uint256 minETH;
        
        if (slippageBps >= 10000) {
            minTokens = 1;
            minETH = 1;
        } else {
            minTokens = (tokenAmount * (10000 - slippageBps)) / 10000;
            minETH = (ethAmount * (10000 - slippageBps)) / 10000;
            
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
        
        emit DebugLPCreation(
            tokenAmount,
            ethAmount,
            minTokens,
            minETH,
            existingPair,
            POOL_IS_STABLE
        );
        
        try IAerodromeRouter(aerodromeRouter).addLiquidityETH{value: ethAmount}(
            tinfoilToken,
            POOL_IS_STABLE,
            tokenAmount,
            minTokens,
            minETH,
            address(this),
            deadline
        ) returns (uint256 amountToken, uint256 amountETH, uint256) {
            
            address lpTokenAddress = IAerodromeFactory(aerodromeFactory).getPair(
                tinfoilToken,
                WETH,
                POOL_IS_STABLE
            );
            
            require(lpTokenAddress != address(0), "LP pair not found after creation");
            
            ITinfoilToken(tinfoilToken).setTransferWhitelist(lpTokenAddress, true);
            emit PairWhitelisted(lpTokenAddress);
            
            emit LiquidityCreated(lpTokenAddress, amountETH, amountToken);
            
            uint256 lpBalance = IERC20(lpTokenAddress).balanceOf(address(this));
            require(lpBalance > 0, "No LP tokens received");
            
            IERC20(lpTokenAddress).safeTransfer(BURN_ADDRESS, lpBalance);
            
            emit LPTokensBurned(lpTokenAddress, lpBalance);
            lpCreated = true;
            
            IERC20(tinfoilToken).approve(aerodromeRouter, 0);
            
            emit LPCreationComplete(
                lpTokenAddress,
                amountETH,
                amountToken,
                lpBalance,
                false,
                block.timestamp
            );
            
            return true;
            
        } catch Error(string memory reason) {
            emit LPCreationFailed(reason);
            IERC20(tinfoilToken).approve(aerodromeRouter, 0);
            return false;
        } catch (bytes memory lowLevelData) {
            string memory reason = _decodeRevertReason(lowLevelData);
            emit LPCreationFailed(reason);
            IERC20(tinfoilToken).approve(aerodromeRouter, 0);
            return false;
        }
    }
    
    function emergencyCreateLP(
        uint256 tokenAmount,
        uint256 slippageBps,
        uint256 gasLimit
    ) external payable onlyOwner nonReentrant returns (bool success) {
        require(!lpCreated, "LP already created");
        require(slippageBps <= 10000, "Slippage must be <= 100%");
        require(gasLimit > 0 && gasLimit <= 10000000, "Invalid gas limit");
        
        uint256 ethAmount = msg.value;
        
        IERC20(tinfoilToken).approve(aerodromeRouter, 0);
        IERC20(tinfoilToken).approve(aerodromeRouter, tokenAmount);
        
        uint256 minTokens = (tokenAmount * (10000 - slippageBps)) / 10000;
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
        
        try IAerodromeRouter(aerodromeRouter).addLiquidityETH{value: ethAmount, gas: gasLimit}(
            tinfoilToken,
            POOL_IS_STABLE,
            tokenAmount,
            minTokens,
            minEth,
            address(this),
            block.timestamp + 2 hours
        ) returns (uint256 amountToken, uint256 amountETH, uint256) {
            
            address lpTokenAddress = IAerodromeFactory(aerodromeFactory).getPair(
                tinfoilToken,
                WETH,
                POOL_IS_STABLE
            );
            
            require(lpTokenAddress != address(0), "LP pair not found");
            
            ITinfoilToken(tinfoilToken).setTransferWhitelist(lpTokenAddress, true);
            emit PairWhitelisted(lpTokenAddress);
            
            emit LiquidityCreated(lpTokenAddress, amountETH, amountToken);
            
            uint256 lpBalance = IERC20(lpTokenAddress).balanceOf(address(this));
            if (lpBalance > 0) {
                IERC20(lpTokenAddress).safeTransfer(BURN_ADDRESS, lpBalance);
                emit LPTokensBurned(lpTokenAddress, lpBalance);
                lpCreated = true;
                
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
            return true;
            
        } catch Error(string memory reason) {
            emit LPCreationFailed(reason);
            IERC20(tinfoilToken).approve(aerodromeRouter, 0);
            return false;
        } catch (bytes memory lowLevelData) {
            string memory reason = _decodeRevertReason(lowLevelData);
            emit LPCreationFailed(reason);
            IERC20(tinfoilToken).approve(aerodromeRouter, 0);
            return false;
        }
    }
    
    function _decodeRevertReason(bytes memory revertData) internal pure returns (string memory) {
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
        
        if (revertData.length == 4) {
            bytes4 errorSelector;
            assembly {
                errorSelector := mload(add(revertData, 0x20))
            }
            
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
    
    function getExpectedLPPair() external view returns (address) {
        return IAerodromeFactory(aerodromeFactory).getPair(
            tinfoilToken,
            WETH,
            POOL_IS_STABLE
        );
    }
    
    receive() external payable {}
}