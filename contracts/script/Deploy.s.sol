// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/AGIX.sol";
import "../src/IndexVault.sol";
import "../src/PriceFeed.sol";
import "../src/Rebalancer.sol";

/**
 * @title DeployScript
 * @notice Deployment script for Agent Index contracts on Base Sepolia
 */
contract DeployScript is Script {
    // Base Sepolia addresses
    address constant WETH = 0x4200000000000000000000000000000000000006;  // Base WETH
    address constant UNISWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;  // Uniswap V3 Router

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying from:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy PriceFeed
        PriceFeed priceFeed = new PriceFeed();
        console.log("PriceFeed deployed:", address(priceFeed));

        // 2. Deploy AGIX token
        AGIX agix = new AGIX();
        console.log("AGIX deployed:", address(agix));

        // 3. Deploy IndexVault
        IndexVault vault = new IndexVault(address(agix), address(priceFeed));
        console.log("IndexVault deployed:", address(vault));

        // 4. Deploy Rebalancer
        Rebalancer rebalancer = new Rebalancer(
            address(vault),
            address(priceFeed),
            UNISWAP_ROUTER,
            WETH
        );
        console.log("Rebalancer deployed:", address(rebalancer));

        // 5. Configure contracts
        agix.setVault(address(vault));
        console.log("AGIX vault set");

        vault.setRebalancer(address(rebalancer));
        console.log("Vault rebalancer set");

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("AGIX:        ", address(agix));
        console.log("IndexVault:  ", address(vault));
        console.log("PriceFeed:   ", address(priceFeed));
        console.log("Rebalancer:  ", address(rebalancer));
    }
}

/**
 * @title ConfigureBasketScript
 * @notice Configure the initial basket after deployment
 */
contract ConfigureBasketScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Read deployed addresses from env
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        address priceFeedAddr = vm.envAddress("PRICE_FEED_ADDRESS");

        IndexVault vault = IndexVault(vaultAddr);
        PriceFeed priceFeed = PriceFeed(priceFeedAddr);

        vm.startBroadcast(deployerPrivateKey);

        // Example basket configuration for testnet
        // In production, these would be real token addresses

        // For testnet, we'll use manual prices
        // In production, set up Chainlink feeds

        address[] memory tokens = new address[](3);
        uint256[] memory weights = new uint256[](3);

        // These are placeholder addresses for testnet
        // Replace with actual Base Sepolia token addresses
        tokens[0] = address(0x1);  // VIRTUAL placeholder
        tokens[1] = address(0x2);  // AIXBT placeholder
        tokens[2] = address(0x3);  // LUNA placeholder

        weights[0] = 5000;  // 50%
        weights[1] = 3000;  // 30%
        weights[2] = 2000;  // 20%

        // Set manual prices for testnet (18 decimals)
        priceFeed.setManualPrice(tokens[0], 2e18);    // $2.00
        priceFeed.setManualPrice(tokens[1], 0.5e18);  // $0.50
        priceFeed.setManualPrice(tokens[2], 1e18);    // $1.00

        // Set basket
        vault.setBasket(tokens, weights);

        vm.stopBroadcast();

        console.log("Basket configured with 3 tokens");
    }
}
