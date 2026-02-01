// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPriceFeed
 * @notice Interface for price feed oracle
 */
interface IPriceFeed {
    /**
     * @notice Get the USD price of a token (18 decimals)
     * @param token Address of the token
     * @return price Price in USD with 18 decimals
     */
    function getPrice(address token) external view returns (uint256 price);

    /**
     * @notice Get multiple token prices
     * @param tokens Array of token addresses
     * @return prices Array of prices in USD with 18 decimals
     */
    function getPrices(address[] calldata tokens) external view returns (uint256[] memory prices);

    /**
     * @notice Check if a price feed exists for a token
     * @param token Address of the token
     * @return exists True if feed exists
     */
    function hasFeed(address token) external view returns (bool exists);
}
