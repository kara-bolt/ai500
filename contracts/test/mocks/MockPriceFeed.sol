// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../src/interfaces/IPriceFeed.sol";

contract MockPriceFeed is IPriceFeed {
    mapping(address => uint256) public prices;

    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    function getPrice(address token) external view override returns (uint256) {
        return prices[token];
    }

    function getPrices(address[] calldata tokens) external view override returns (uint256[] memory result) {
        result = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            result[i] = prices[tokens[i]];
        }
    }

    function hasFeed(address token) external view override returns (bool) {
        return prices[token] > 0;
    }
}
