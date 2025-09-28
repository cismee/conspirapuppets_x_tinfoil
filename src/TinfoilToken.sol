// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/security/Pausable.sol";

contract TinfoilToken is ERC20, Ownable, Pausable {
    // Constants
    uint256 public constant MAX_SUPPLY = 3_330_000_000 * 10**18; // 3.33B tokens total
    
    // State variables
    address public nftContract;
    uint256 public totalBurned = 0;
    bool public tradingEnabled = false;
    
    // Events
    event TokensBurned(uint256 amount);
    event NFTContractSet(address indexed nftContract);
    event TradingEnabled();

    constructor() ERC20("Tinfoil", "TINFOIL") {
        // No initial mint - tokens are only created through NFT contract
    }

    modifier onlyNFTContract() {
        require(msg.sender == nftContract, "Only NFT contract can call this");
        _;
    }

    /**
     * @dev Set the NFT contract address (only owner, only once)
     */
    function setNFTContract(address _nftContract) external onlyOwner {
        require(nftContract == address(0), "NFT contract already set");
        require(_nftContract != address(0), "Invalid NFT contract address");
        nftContract = _nftContract;
        emit NFTContractSet(_nftContract);
    }

    /**
     * @dev Mint tokens - only callable by NFT contract
     */
    function mint(address to, uint256 amount) external onlyNFTContract whenNotPaused {
        require(to != address(0), "Cannot mint to zero address");
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount);
    }

    /**
     * @dev Enable trading - only callable by NFT contract when mint completes
     */
    function enableTrading() external onlyNFTContract {
        require(!tradingEnabled, "Trading already enabled");
        tradingEnabled = true;
        emit TradingEnabled();
    }

    /**
     * @dev Public burn function for additional deflationary pressure
     */
    function burn(uint256 amount) external {
        require(amount > 0, "Cannot burn 0 tokens");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        _burn(msg.sender, amount);
        totalBurned += amount;
        
        emit TokensBurned(amount);
    }

    /**
     * @dev Emergency pause/unpause functions
     */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Override transfer to enforce trading restrictions
     */
    function transfer(address to, uint256 amount) public virtual override whenNotPaused returns (bool) {
        require(tradingEnabled, "Trading not enabled yet - wait for mint completion");
        return super.transfer(to, amount);
    }

    /**
     * @dev Override transferFrom to enforce trading restrictions
     */
    function transferFrom(address from, address to, uint256 amount) public virtual override whenNotPaused returns (bool) {
        require(tradingEnabled, "Trading not enabled yet - wait for mint completion");
        return super.transferFrom(from, to, amount);
    }

    /**
     * @dev Get circulating supply (excludes burned tokens)
     */
    function circulatingSupply() external view returns (uint256) {
        return totalSupply();
    }

    /**
     * @dev Check if max supply has been reached
     */
    function maxSupplyReached() external view returns (bool) {
        return totalSupply() == MAX_SUPPLY;
    }

    /**
     * @dev Calculate burn percentage of total minted
     */
    function burnPercentage() external view returns (uint256) {
        uint256 totalMinted = totalSupply() + totalBurned;
        if (totalMinted == 0) return 0;
        return (totalBurned * 100) / totalMinted;
    }

    /**
     * @dev Get comprehensive token information for UI
     */
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
            totalSupply(), // Circulating supply = total supply (burned tokens already removed)
            tradingEnabled,
            totalSupply() == MAX_SUPPLY
        );
    }

    /**
     * @dev Get trading status for UI
     */
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