// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC721SeaDrop} from "seadrop/src/ERC721SeaDrop.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "./interfaces/Interfaces.sol";

contract Conspirapuppets is ERC721SeaDrop {
    uint256 public constant MAX_SUPPLY = 3333;
    uint256 public constant TOKENS_PER_NFT = 499_549 * 10**18;
    uint256 public constant LP_TOKEN_AMOUNT = 1_665_000_000 * 10**18;
    uint256 public constant TOKEN_REMAINDER = 3_183 * 10**18;
    uint256 public constant LP_CREATION_DELAY = 5 minutes;
    uint256 public constant DEFAULT_SLIPPAGE_BPS = 5000;
    
    bool public mintCompleted = false;
    bool public lpCreationScheduled = false;
    uint256 public lpCreationTimestamp = 0;
    uint256 public operationalFunds = 0;
    uint256 public totalEthReceived = 0;
    
    address public immutable tinfoilToken;
    address public immutable lpManager;
    
    event MintCompleted(uint256 totalSupply, uint256 scheduledLPCreation);
    event ETHReceived(address indexed from, uint256 amount, uint256 totalReceived);
    event FundsAllocated(uint256 lpAmount, uint256 operationalAmount);
    event TokensDistributed(address indexed recipient, uint256 amount);
    event RemainderMinted(address indexed recipient, uint256 amount);
    event OperationalFundsWithdrawn(address indexed recipient, uint256 amount);
    event LPCreationScheduled(uint256 timestamp);
    event TradingEnabled();
    event LPCreationAttempted(bool success);

    constructor(
        string memory name,
        string memory symbol,
        address[] memory allowedSeaDrop,
        address _tinfoilToken,
        address _lpManager
    ) ERC721SeaDrop(name, symbol, allowedSeaDrop) {
        require(_tinfoilToken != address(0), "Invalid token address");
        require(_lpManager != address(0), "Invalid LP manager address");
        
        tinfoilToken = _tinfoilToken;
        lpManager = _lpManager;
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
            
            if (!mintCompleted && totalSupply() + quantity >= MAX_SUPPLY) {
                _scheduleMintCompletion();
            }
        }
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function _scheduleMintCompletion() internal {
        if (mintCompleted) return;
        require(address(this).balance >= 0, "No ETH to allocate");
        
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
        require(!ILPManager(lpManager).lpCreated(), "LP already created");
        require(address(this).balance >= operationalFunds, "No ETH available for LP");
        
        uint256 lpEthAmount = address(this).balance - operationalFunds;
        require(lpEthAmount > 0, "No ETH for LP");
        
        ITinfoilToken(tinfoilToken).mint(lpManager, LP_TOKEN_AMOUNT);
        
        bool success = ILPManager(lpManager).createAndBurnLP{value: lpEthAmount}(
            LP_TOKEN_AMOUNT,
            DEFAULT_SLIPPAGE_BPS
        );
        
        emit LPCreationAttempted(success);
        
        if (success) {
            ITinfoilToken(tinfoilToken).enableTrading();
            emit TradingEnabled();
        }
    }

    function createLPImmediate() external onlyOwner nonReentrant {
        require(mintCompleted, "Mint not completed yet");
        require(!ILPManager(lpManager).lpCreated(), "LP already created");
        require(address(this).balance >= operationalFunds, "No ETH available for LP");
        
        uint256 lpEthAmount = address(this).balance - operationalFunds;
        
        ITinfoilToken(tinfoilToken).mint(lpManager, LP_TOKEN_AMOUNT);
        
        bool success = ILPManager(lpManager).createAndBurnLP{value: lpEthAmount}(
            LP_TOKEN_AMOUNT,
            DEFAULT_SLIPPAGE_BPS
        );
        
        emit LPCreationAttempted(success);
        
        if (success) {
            ITinfoilToken(tinfoilToken).enableTrading();
            emit TradingEnabled();
        }
    }

    function retryLPCreation() external onlyOwner nonReentrant {
        require(mintCompleted, "Mint not completed yet");
        require(!ILPManager(lpManager).lpCreated(), "LP already created");
        require(address(this).balance >= operationalFunds, "No ETH available for LP");
        
        uint256 lpEthAmount = address(this).balance - operationalFunds;
        
        uint256 currentBalance = IERC20(tinfoilToken).balanceOf(lpManager);
        if (currentBalance < LP_TOKEN_AMOUNT) {
            ITinfoilToken(tinfoilToken).mint(lpManager, LP_TOKEN_AMOUNT - currentBalance);
        }
        
        bool success = ILPManager(lpManager).createAndBurnLP{value: lpEthAmount}(
            LP_TOKEN_AMOUNT,
            DEFAULT_SLIPPAGE_BPS
        );
        
        emit LPCreationAttempted(success);
        
        if (success) {
            ITinfoilToken(tinfoilToken).enableTrading();
            emit TradingEnabled();
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
            ILPManager(lpManager).lpCreated(),
            totalEthReceived
        );
    }

    function getLPCreationStatus() external view returns (
        bool _lpCreationScheduled,
        uint256 _lpCreationTimestamp,
        bool _canCreateLP,
        uint256 _timeRemaining
    ) {
        bool canCreate = lpCreationScheduled && 
                        block.timestamp >= lpCreationTimestamp && 
                        !ILPManager(lpManager).lpCreated();
        uint256 timeRemaining = 0;
        
        if (lpCreationScheduled && block.timestamp < lpCreationTimestamp) {
            timeRemaining = lpCreationTimestamp - block.timestamp;
        }
        
        return (lpCreationScheduled, lpCreationTimestamp, canCreate, timeRemaining);
    }

    function getExpectedLPPair() external view returns (address) {
        return ILPManager(lpManager).getExpectedLPPair();
    }

    function forceScheduleLPCreation() external onlyOwner {
        require(mintCompleted, "Mint not completed");
        require(!lpCreationScheduled, "Already scheduled");
        require(!ILPManager(lpManager).lpCreated(), "LP already created");
        
        lpCreationTimestamp = block.timestamp + LP_CREATION_DELAY;
        lpCreationScheduled = true;
        
        emit LPCreationScheduled(lpCreationTimestamp);
    }

    receive() external payable {
        totalEthReceived += msg.value;
        emit ETHReceived(msg.sender, msg.value, totalEthReceived);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}