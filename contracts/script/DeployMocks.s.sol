// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/mocks/MockERC20.sol";
import "../src/IndexVault.sol";

/**
 * @title DeployMocks
 * @notice Deploy mock tokens and set up test basket
 */
contract DeployMocks is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");

        console.log("Deploying from:", deployer);
        console.log("Vault:", vaultAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy 5 mock tokens
        MockERC20 virtual_ = new MockERC20("Virtual Protocol", "VIRTUAL", 18);
        MockERC20 vvv = new MockERC20("Venice Token", "VVV", 18);
        MockERC20 aixbt = new MockERC20("aixbt", "AIXBT", 18);
        MockERC20 luna = new MockERC20("Luna AI", "LUNA", 18);
        MockERC20 game = new MockERC20("Game", "GAME", 18);

        console.log("VIRTUAL:", address(virtual_));
        console.log("VVV:", address(vvv));
        console.log("AIXBT:", address(aixbt));
        console.log("LUNA:", address(luna));
        console.log("GAME:", address(game));

        // Mint tokens to deployer for testing
        virtual_.mint(deployer, 1000000 * 1e18);
        vvv.mint(deployer, 1000000 * 1e18);
        aixbt.mint(deployer, 1000000 * 1e18);
        luna.mint(deployer, 1000000 * 1e18);
        game.mint(deployer, 1000000 * 1e18);

        // Set basket on vault (equal weights for testing)
        address[] memory tokens = new address[](5);
        tokens[0] = address(virtual_);
        tokens[1] = address(vvv);
        tokens[2] = address(aixbt);
        tokens[3] = address(luna);
        tokens[4] = address(game);

        uint256[] memory weights = new uint256[](5);
        weights[0] = 2000; // 20%
        weights[1] = 2000;
        weights[2] = 2000;
        weights[3] = 2000;
        weights[4] = 2000;

        IndexVault vault = IndexVault(vaultAddress);
        vault.setBasket(tokens, weights);

        console.log("Basket set with 5 tokens at 20% each");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Mock Tokens Deployed ===");
        console.log("VIRTUAL:", address(virtual_));
        console.log("VVV:", address(vvv));
        console.log("AIXBT:", address(aixbt));
        console.log("LUNA:", address(luna));
        console.log("GAME:", address(game));
    }
}
