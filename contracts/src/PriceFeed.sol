// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPriceFeed.sol";
import "./interfaces/IChainlinkAggregator.sol";

/**
 * @title PriceFeed
 * @notice Oracle aggregator for token prices
 * @dev Uses Chainlink feeds with Uniswap TWAP fallback
 */
contract PriceFeed is IPriceFeed, Ownable {
    /// @notice Maximum staleness for Chainlink prices (1 hour)
    uint256 public constant MAX_STALENESS = 1 hours;

    /// @notice Price precision (18 decimals)
    uint256 public constant PRICE_PRECISION = 1e18;

    /// @notice Chainlink feed for each token
    mapping(address => address) public chainlinkFeeds;

    /// @notice Uniswap V3 pool for TWAP fallback
    mapping(address => address) public uniswapPools;

    /// @notice TWAP observation window (30 minutes)
    uint32 public twapWindow = 1800;

    /// @notice Manual price override (for testing/emergency)
    mapping(address => uint256) public manualPrices;

    event ChainlinkFeedSet(address indexed token, address indexed feed);
    event UniswapPoolSet(address indexed token, address indexed pool);
    event ManualPriceSet(address indexed token, uint256 price);
    event TwapWindowUpdated(uint32 oldWindow, uint32 newWindow);

    error StalePrice();
    error NegativePrice();
    error NoFeedAvailable();
    error ZeroAddress();

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Set Chainlink price feed for a token
     * @param token Token address
     * @param feed Chainlink aggregator address
     */
    function setChainlinkFeed(address token, address feed) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        chainlinkFeeds[token] = feed;
        emit ChainlinkFeedSet(token, feed);
    }

    /**
     * @notice Set multiple Chainlink feeds at once
     * @param tokens Array of token addresses
     * @param feeds Array of Chainlink aggregator addresses
     */
    function setChainlinkFeeds(
        address[] calldata tokens,
        address[] calldata feeds
    ) external onlyOwner {
        require(tokens.length == feeds.length, "Length mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert ZeroAddress();
            chainlinkFeeds[tokens[i]] = feeds[i];
            emit ChainlinkFeedSet(tokens[i], feeds[i]);
        }
    }

    /**
     * @notice Set Uniswap pool for TWAP fallback
     * @param token Token address
     * @param pool Uniswap V3 pool address
     */
    function setUniswapPool(address token, address pool) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        uniswapPools[token] = pool;
        emit UniswapPoolSet(token, pool);
    }

    /**
     * @notice Set manual price override (for testing/emergency)
     * @param token Token address
     * @param price Price in USD (18 decimals), 0 to clear
     */
    function setManualPrice(address token, uint256 price) external onlyOwner {
        manualPrices[token] = price;
        emit ManualPriceSet(token, price);
    }

    /**
     * @notice Update TWAP observation window
     * @param newWindow New window in seconds
     */
    function setTwapWindow(uint32 newWindow) external onlyOwner {
        uint32 oldWindow = twapWindow;
        twapWindow = newWindow;
        emit TwapWindowUpdated(oldWindow, newWindow);
    }

    /**
     * @notice Get the USD price of a token (18 decimals)
     * @param token Address of the token
     * @return price Price in USD with 18 decimals
     */
    function getPrice(address token) public view override returns (uint256 price) {
        // 1. Check manual override first
        if (manualPrices[token] > 0) {
            return manualPrices[token];
        }

        // 2. Try Chainlink
        address feed = chainlinkFeeds[token];
        if (feed != address(0)) {
            price = _getChainlinkPrice(feed);
            if (price > 0) return price;
        }

        // 3. Try Uniswap TWAP
        address pool = uniswapPools[token];
        if (pool != address(0)) {
            price = _getUniswapTwap(pool, token);
            if (price > 0) return price;
        }

        revert NoFeedAvailable();
    }

    /**
     * @notice Get multiple token prices
     * @param tokens Array of token addresses
     * @return prices Array of prices in USD with 18 decimals
     */
    function getPrices(
        address[] calldata tokens
    ) external view override returns (uint256[] memory prices) {
        prices = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            prices[i] = getPrice(tokens[i]);
        }
    }

    /**
     * @notice Check if a price feed exists for a token
     * @param token Address of the token
     * @return exists True if any feed exists
     */
    function hasFeed(address token) external view override returns (bool exists) {
        return manualPrices[token] > 0 ||
               chainlinkFeeds[token] != address(0) ||
               uniswapPools[token] != address(0);
    }

    /**
     * @dev Get price from Chainlink feed
     */
    function _getChainlinkPrice(address feed) internal view returns (uint256) {
        IChainlinkAggregator aggregator = IChainlinkAggregator(feed);

        (
            ,
            int256 answer,
            ,
            uint256 updatedAt,
        ) = aggregator.latestRoundData();

        // Check staleness
        if (block.timestamp - updatedAt > MAX_STALENESS) {
            return 0; // Fall through to next oracle
        }

        // Check for negative/zero price
        if (answer <= 0) {
            return 0;
        }

        // Normalize to 18 decimals
        uint8 feedDecimals = aggregator.decimals();
        if (feedDecimals < 18) {
            return uint256(answer) * 10 ** (18 - feedDecimals);
        } else if (feedDecimals > 18) {
            return uint256(answer) / 10 ** (feedDecimals - 18);
        }
        return uint256(answer);
    }

    /**
     * @dev Get TWAP price from Uniswap V3 pool
     * @notice Simplified implementation - in production use OracleLibrary
     */
    function _getUniswapTwap(address pool, address token) internal view returns (uint256) {
        // Placeholder for Uniswap TWAP logic
        // In production, use Uniswap's OracleLibrary.consult()
        // For v1, we rely primarily on Chainlink + manual prices
        pool; token; // Silence unused warnings
        return 0;
    }
}
