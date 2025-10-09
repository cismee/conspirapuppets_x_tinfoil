// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ITinfoilToken {
    function mint(address to, uint256 amount) external;
    function enableTrading() external;
    function setTransferWhitelist(address account, bool allowed) external;
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
    
    function defaultFactory() external view returns (address);
}

interface IAerodromeFactory {
    function getPair(address tokenA, address tokenB, bool stable) external view returns (address pair);
}

interface ILPManager {
    function createAndBurnLP(uint256 tokenAmount, uint256 slippageBps) external payable returns (bool);
    function lpCreated() external view returns (bool);
    function getExpectedLPPair() external view returns (address);
}

