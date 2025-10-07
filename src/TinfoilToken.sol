// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/access/Ownable.sol";

contract TinfoilToken is ERC20, Ownable {
    uint256 public constant MAX_SUPPLY = 3_330_000_000 * 10**18;
    
    address public nftContract;
    uint256 public totalBurned = 0;
    bool public tradingEnabled = false;
    
    // FIXED: Added whitelist for LP creation before trading enabled
    mapping(address => bool) public transferWhitelist;
    
    event TokensBurned(uint256 amount);
    event NFTContractSet(address indexed nftContract);
    event TradingEnabled();
    event TransferWhitelistUpdated(address indexed account, bool allowed);

    constructor() ERC20("Tinfoil", "TINFOIL") {
    }

    modifier onlyNFTContract() {
        require(msg.sender == nftContract, "Only NFT contract can call this");
        _;
    }

    function setNFTContract(address _nftContract) external onlyOwner {
        require(nftContract == address(0), "NFT contract already set");
        require(_nftContract != address(0), "Invalid NFT contract address");
        nftContract = _nftContract;
        emit NFTContractSet(_nftContract);
    }

    // FIXED: Added whitelist management function
    function setTransferWhitelist(address account, bool allowed) external onlyOwner {
        require(account != address(0), "Invalid address");
        transferWhitelist[account] = allowed;
        emit TransferWhitelistUpdated(account, allowed);
    }

    function mint(address to, uint256 amount) external onlyNFTContract {
        require(to != address(0), "Cannot mint to zero address");
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount);
    }

    function enableTrading() external onlyNFTContract {
        require(!tradingEnabled, "Trading already enabled");
        tradingEnabled = true;
        emit TradingEnabled();
    }

    function burn(uint256 amount) external {
        require(amount > 0, "Cannot burn 0 tokens");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        _burn(msg.sender, amount);
        totalBurned += amount;
        
        emit TokensBurned(amount);
    }

    // FIXED: Added whitelist check to allow LP creation before trading enabled
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        require(
            tradingEnabled || transferWhitelist[msg.sender] || transferWhitelist[to],
            "Trading not enabled yet - wait for mint completion"
        );
        return super.transfer(to, amount);
    }

    // FIXED: Added whitelist check to allow LP creation before trading enabled
    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        require(
            tradingEnabled || transferWhitelist[msg.sender] || transferWhitelist[to],
            "Trading not enabled yet - wait for mint completion"
        );
        return super.transferFrom(from, to, amount);
    }

    function circulatingSupply() external view returns (uint256) {
        return totalSupply();
    }

    function maxSupplyReached() external view returns (bool) {
        return totalSupply() == MAX_SUPPLY;
    }

    function burnPercentage() external view returns (uint256) {
        uint256 totalMinted = totalSupply() + totalBurned;
        if (totalMinted == 0) return 0;
        return (totalBurned * 100) / totalMinted;
    }

    function getTokenInfo() external view returns (
        uint256 _totalSupply,
        uint256 _maxSupply,
        uint256 _totalBurned,
        uint256 _circulatingSupply,
        bool _tradingEnabled,
        bool _maxSupplyReached
    ) {
        return (
            totalSupply(),
            MAX_SUPPLY,
            totalBurned,
            totalSupply(),
            tradingEnabled,
            totalSupply() == MAX_SUPPLY
        );
    }

    function getTradingStatus() external view returns (
        bool _tradingEnabled,
        string memory _statusMessage
    ) {
        if (tradingEnabled) {
            return (true, "Trading is live!");
        } else {
            return (false, "Trading disabled until NFT collection sells out");
        }
    }
}