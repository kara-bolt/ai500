// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PriceFeed.sol";
import "./mocks/MockERC20.sol";

contract MockChainlinkAggregator {
    int256 public price;
    uint8 public decimals;
    uint256 public updatedAt;

    constructor(int256 _price, uint8 _decimals) {
        price = _price;
        decimals = _decimals;
        updatedAt = block.timestamp;
    }

    function setPrice(int256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
    }

    function setStale() external {
        updatedAt = block.timestamp - 2 hours;
    }

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 _updatedAt,
        uint80 answeredInRound
    ) {
        return (1, price, block.timestamp, updatedAt, 1);
    }
}

contract PriceFeedTest is Test {
    PriceFeed public priceFeed;
    MockChainlinkAggregator public chainlinkFeed;
    MockERC20 public token;

    address public owner = address(this);

    function setUp() public {
        priceFeed = new PriceFeed();
        token = new MockERC20("Test Token", "TEST", 18);

        // Chainlink feed with 8 decimals (standard)
        chainlinkFeed = new MockChainlinkAggregator(200000000, 8);  // $2.00
    }

    function test_InitialState() public view {
        assertEq(priceFeed.owner(), owner);
        assertEq(priceFeed.MAX_STALENESS(), 1 hours);
        assertEq(priceFeed.twapWindow(), 1800);
    }

    function test_SetChainlinkFeed() public {
        priceFeed.setChainlinkFeed(address(token), address(chainlinkFeed));
        assertEq(priceFeed.chainlinkFeeds(address(token)), address(chainlinkFeed));
    }

    function test_SetChainlinkFeeds_Batch() public {
        MockERC20 token2 = new MockERC20("Token 2", "T2", 18);
        MockChainlinkAggregator feed2 = new MockChainlinkAggregator(100000000, 8);

        address[] memory tokens = new address[](2);
        tokens[0] = address(token);
        tokens[1] = address(token2);

        address[] memory feeds = new address[](2);
        feeds[0] = address(chainlinkFeed);
        feeds[1] = address(feed2);

        priceFeed.setChainlinkFeeds(tokens, feeds);

        assertEq(priceFeed.chainlinkFeeds(address(token)), address(chainlinkFeed));
        assertEq(priceFeed.chainlinkFeeds(address(token2)), address(feed2));
    }

    function test_GetPrice_Chainlink() public {
        priceFeed.setChainlinkFeed(address(token), address(chainlinkFeed));

        uint256 price = priceFeed.getPrice(address(token));
        // $2.00 with 8 decimals -> 18 decimals
        assertEq(price, 2e18);
    }

    function test_GetPrice_ChainlinkDifferentDecimals() public {
        // 18 decimal feed
        MockChainlinkAggregator feed18 = new MockChainlinkAggregator(2e18, 18);
        priceFeed.setChainlinkFeed(address(token), address(feed18));

        uint256 price = priceFeed.getPrice(address(token));
        assertEq(price, 2e18);

        // 6 decimal feed
        MockChainlinkAggregator feed6 = new MockChainlinkAggregator(2000000, 6);
        priceFeed.setChainlinkFeed(address(token), address(feed6));

        price = priceFeed.getPrice(address(token));
        assertEq(price, 2e18);
    }

    function test_GetPrice_StaleChainlink_RevertNoFeed() public {
        // Warp to a reasonable timestamp first
        vm.warp(1000000);
        
        priceFeed.setChainlinkFeed(address(token), address(chainlinkFeed));
        chainlinkFeed.setStale();

        // Should revert since no fallback
        vm.expectRevert(PriceFeed.NoFeedAvailable.selector);
        priceFeed.getPrice(address(token));
    }

    function test_GetPrice_ManualOverride() public {
        priceFeed.setChainlinkFeed(address(token), address(chainlinkFeed));
        priceFeed.setManualPrice(address(token), 5e18);  // $5

        uint256 price = priceFeed.getPrice(address(token));
        // Manual override takes precedence
        assertEq(price, 5e18);
    }

    function test_GetPrice_NoFeed() public {
        vm.expectRevert(PriceFeed.NoFeedAvailable.selector);
        priceFeed.getPrice(address(token));
    }

    function test_GetPrices() public {
        MockERC20 token2 = new MockERC20("Token 2", "T2", 18);
        MockChainlinkAggregator feed2 = new MockChainlinkAggregator(100000000, 8);

        priceFeed.setChainlinkFeed(address(token), address(chainlinkFeed));
        priceFeed.setChainlinkFeed(address(token2), address(feed2));

        address[] memory tokens = new address[](2);
        tokens[0] = address(token);
        tokens[1] = address(token2);

        uint256[] memory prices = priceFeed.getPrices(tokens);

        assertEq(prices[0], 2e18);
        assertEq(prices[1], 1e18);
    }

    function test_HasFeed() public {
        assertFalse(priceFeed.hasFeed(address(token)));

        priceFeed.setChainlinkFeed(address(token), address(chainlinkFeed));
        assertTrue(priceFeed.hasFeed(address(token)));
    }

    function test_HasFeed_ManualPrice() public {
        priceFeed.setManualPrice(address(token), 1e18);
        assertTrue(priceFeed.hasFeed(address(token)));
    }

    function test_SetTwapWindow() public {
        priceFeed.setTwapWindow(3600);
        assertEq(priceFeed.twapWindow(), 3600);
    }

    function test_SetChainlinkFeed_RevertZeroAddress() public {
        vm.expectRevert(PriceFeed.ZeroAddress.selector);
        priceFeed.setChainlinkFeed(address(0), address(chainlinkFeed));
    }

    function test_SetUniswapPool() public {
        address pool = address(0x123);
        priceFeed.setUniswapPool(address(token), pool);
        assertEq(priceFeed.uniswapPools(address(token)), pool);
    }

    function testFuzz_ManualPrice(uint256 price) public {
        vm.assume(price > 0 && price < type(uint128).max);

        priceFeed.setManualPrice(address(token), price);
        assertEq(priceFeed.getPrice(address(token)), price);
    }
}
