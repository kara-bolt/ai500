// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/PriceFeed.sol";

contract SetupPricesScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address priceFeedAddr = vm.envAddress("PRICE_FEED_ADDRESS");
        PriceFeed priceFeed = PriceFeed(priceFeedAddr);

        vm.startBroadcast(deployerPrivateKey);

        // Prices from indexer snapshot (approximate)
        priceFeed.setManualPrice(0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b, 624800000000000000);  // VIRTUAL
        priceFeed.setManualPrice(0xacfE6019Ed1A7Dc6f7B508C02d1b04ec88cC21bf, 2170000000000000000); // VVV
        priceFeed.setManualPrice(0x4F9Fd6Be4a90f2620860d680c0d4d5Fb53d1A825, 24180000000000000);   // AIXBT
        priceFeed.setManualPrice(0x55cD6469F597452B5A7536e2CD98fDE4c1247ee4, 10830000000000000);   // LUNA
        priceFeed.setManualPrice(0x1C4CcA7C5DB003824208aDDA61Bd749e55F463a3, 9310000000000000);    // GAME
        priceFeed.setManualPrice(0xC2427Bf51d99b6ED0dA0Da103bC51235638eE868, 3759000000000000);    // BOT
        priceFeed.setManualPrice(0xE183b1A4DD59Ca732211678EcA1836EE35bCE582, 18190000000000000);   // DICK
        priceFeed.setManualPrice(0xD98832e8a59156AcBEe4744B9A94A9989a728f36, 12090000000000000);   // AGENT

        // Set WETH Price (approx $2295)
        priceFeed.setManualPrice(0x4200000000000000000000000000000000000006, 2295000000000000000000);

        vm.stopBroadcast();
        console.log("Manual prices set in PriceFeed");
    }
}
