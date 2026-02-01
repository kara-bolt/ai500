// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/AI500.sol";
import "../src/IndexVaultV2.sol";
import "../src/PriceFeed.sol";
import "../src/BatchRebalancer.sol";

/**
 * @title DeployV2Script
 * @notice Deployment script for AI500 v2 contracts on Base Sepolia
 */
contract DeployV2Script is Script {
    // Base addresses
    address constant WETH = 0x4200000000000000000000000000000000000006;  // Base WETH
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;  // Base USDC
    address constant UNISWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;  // Uniswap V3

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== AI500 V2 Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy PriceFeed
        PriceFeed priceFeed = new PriceFeed();
        console.log("PriceFeed deployed:", address(priceFeed));

        // 2. Deploy AI500 token
        AI500 ai500 = new AI500();
        console.log("AI500 deployed:", address(ai500));

        // 3. Deploy IndexVaultV2
        IndexVaultV2 vault = new IndexVaultV2(
            address(ai500),
            address(priceFeed),
            WETH,
            USDC
        );
        console.log("IndexVaultV2 deployed:", address(vault));

        // 4. Deploy BatchRebalancer
        BatchRebalancer rebalancer = new BatchRebalancer(
            address(vault),
            address(priceFeed),
            UNISWAP_ROUTER,
            WETH
        );
        console.log("BatchRebalancer deployed:", address(rebalancer));

        // 5. Configure contracts
        ai500.setVault(address(vault));
        console.log("AI500 vault set");

        vault.setRebalancer(address(rebalancer));
        console.log("Vault rebalancer set");

        vault.setIndexer(deployer);  // Start with deployer as indexer
        console.log("Vault indexer set to deployer");

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("AI500:           ", address(ai500));
        console.log("IndexVaultV2:    ", address(vault));
        console.log("PriceFeed:       ", address(priceFeed));
        console.log("BatchRebalancer: ", address(rebalancer));
        console.log("\nNext steps:");
        console.log("1. Set up Chainlink price feeds in PriceFeed");
        console.log("2. Queue initial merkle root via indexer");
        console.log("3. Add keeper addresses to BatchRebalancer");
    }
}

/**
 * @title SetupMerkleRootScript
 * @notice Example script to set initial merkle root
 */
contract SetupMerkleRootScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");

        IndexVaultV2 vault = IndexVaultV2(vaultAddr);

        // This would normally come from the off-chain indexer
        bytes32 merkleRoot = vm.envBytes32("MERKLE_ROOT");

        vm.startBroadcast(deployerPrivateKey);

        vault.queueMerkleRoot(merkleRoot);
        console.log("Merkle root queued. Activation time:", vault.pendingRootActivation());

        vm.stopBroadcast();
    }
}

/**
 * @title SetupPriceFeedsScript
 * @notice Set up price feeds for Base tokens
 */
contract SetupPriceFeedsScript is Script {
    // Base Sepolia Chainlink feeds (example addresses)
    address constant ETH_USD_FEED = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address priceFeedAddr = vm.envAddress("PRICE_FEED_ADDRESS");

        PriceFeed priceFeed = PriceFeed(priceFeedAddr);

        vm.startBroadcast(deployerPrivateKey);

        // Set Chainlink feeds
        priceFeed.setChainlinkFeed(
            0x4200000000000000000000000000000000000006,  // WETH
            ETH_USD_FEED
        );

        // For tokens without Chainlink, use manual prices initially
        // priceFeed.setManualPrice(tokenAddress, priceIn18Decimals);

        vm.stopBroadcast();

        console.log("Price feeds configured");
    }
}
