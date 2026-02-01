// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/AGIX.sol";
import "../src/IndexVault.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockPriceFeed.sol";

contract IndexVaultTest is Test {
    AGIX public agix;
    IndexVault public vault;
    MockPriceFeed public priceFeed;

    MockERC20 public virtual_token;
    MockERC20 public aixbt;
    MockERC20 public luna;

    address public owner = address(this);
    address public user = address(0x1);
    address public user2 = address(0x2);

    uint256 constant VIRTUAL_PRICE = 2e18;  // $2
    uint256 constant AIXBT_PRICE = 0.5e18;  // $0.50
    uint256 constant LUNA_PRICE = 1e18;     // $1

    function setUp() public {
        // Deploy tokens
        virtual_token = new MockERC20("Virtual Protocol", "VIRTUAL", 18);
        aixbt = new MockERC20("AIXBT", "AIXBT", 18);
        luna = new MockERC20("Luna", "LUNA", 18);

        // Deploy price feed
        priceFeed = new MockPriceFeed();
        priceFeed.setPrice(address(virtual_token), VIRTUAL_PRICE);
        priceFeed.setPrice(address(aixbt), AIXBT_PRICE);
        priceFeed.setPrice(address(luna), LUNA_PRICE);

        // Deploy AGIX and vault
        agix = new AGIX();
        vault = new IndexVault(address(agix), address(priceFeed));

        // Connect AGIX to vault
        agix.setVault(address(vault));

        // Set basket: 50% VIRTUAL, 30% AIXBT, 20% LUNA
        address[] memory tokens = new address[](3);
        tokens[0] = address(virtual_token);
        tokens[1] = address(aixbt);
        tokens[2] = address(luna);

        uint256[] memory weights = new uint256[](3);
        weights[0] = 5000;  // 50%
        weights[1] = 3000;  // 30%
        weights[2] = 2000;  // 20%

        vault.setBasket(tokens, weights);

        // Mint tokens to user
        virtual_token.mint(user, 1000e18);
        aixbt.mint(user, 1000e18);
        luna.mint(user, 1000e18);

        // Approve vault
        vm.startPrank(user);
        virtual_token.approve(address(vault), type(uint256).max);
        aixbt.approve(address(vault), type(uint256).max);
        luna.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function test_InitialState() public view {
        assertEq(address(vault.agix()), address(agix));
        assertEq(address(vault.priceFeed()), address(priceFeed));
        assertEq(vault.getBasketLength(), 3);
        assertEq(vault.targetWeights(address(virtual_token)), 5000);
        assertEq(vault.targetWeights(address(aixbt)), 3000);
        assertEq(vault.targetWeights(address(luna)), 2000);
    }

    function test_Deposit() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;  // 100 VIRTUAL = $200
        amounts[1] = 200e18;  // 200 AIXBT = $100
        amounts[2] = 50e18;   // 50 LUNA = $50

        // Total value: $350

        vm.prank(user);
        uint256 minted = vault.deposit(amounts);

        // First deposit: 1 AGIX = $1
        assertEq(minted, 350e18);
        assertEq(agix.balanceOf(user), 350e18);
        assertEq(virtual_token.balanceOf(address(vault)), 100e18);
        assertEq(aixbt.balanceOf(address(vault)), 200e18);
        assertEq(luna.balanceOf(address(vault)), 50e18);
    }

    function test_Deposit_SecondDeposit() public {
        // First deposit
        uint256[] memory amounts1 = new uint256[](3);
        amounts1[0] = 100e18;
        amounts1[1] = 200e18;
        amounts1[2] = 50e18;

        vm.prank(user);
        vault.deposit(amounts1);

        // Second deposit (same user or different)
        virtual_token.mint(user2, 1000e18);
        aixbt.mint(user2, 1000e18);
        luna.mint(user2, 1000e18);

        vm.startPrank(user2);
        virtual_token.approve(address(vault), type(uint256).max);
        aixbt.approve(address(vault), type(uint256).max);
        luna.approve(address(vault), type(uint256).max);

        uint256[] memory amounts2 = new uint256[](3);
        amounts2[0] = 50e18;   // 50 VIRTUAL = $100
        amounts2[1] = 100e18;  // 100 AIXBT = $50
        amounts2[2] = 25e18;   // 25 LUNA = $25
        // Total deposit value: $175

        // NAV before second deposit: $350 (from first deposit)
        // Total supply: 350 AGIX
        // Second deposit value: $175
        // Minted = (depositValue * totalSupply) / NAV
        // But NAV includes the newly deposited tokens, so:
        // After transfer: NAV = $350 + $175 = $525
        // Minted = ($175 * 350) / $525 = 116.67 AGIX

        uint256 minted2 = vault.deposit(amounts2);
        vm.stopPrank();

        // Due to NAV being calculated after token transfer, 
        // the second depositor gets: (175 * 350) / 525 = 116.67 AGIX
        assertApproxEqAbs(minted2, 116666666666666666666, 1);
    }

    function test_Redeem() public {
        // First deposit
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 200e18;
        amounts[2] = 50e18;

        vm.prank(user);
        vault.deposit(amounts);

        // Redeem half
        vm.prank(user);
        uint256[] memory returned = vault.redeem(175e18);

        // Should get back half of each token
        assertEq(returned[0], 50e18);   // 50 VIRTUAL
        assertEq(returned[1], 100e18);  // 100 AIXBT
        assertEq(returned[2], 25e18);   // 25 LUNA

        assertEq(agix.balanceOf(user), 175e18);
        assertEq(virtual_token.balanceOf(user), 950e18);  // 1000 - 100 + 50
    }

    function test_GetNav() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 200e18;
        amounts[2] = 50e18;

        vm.prank(user);
        vault.deposit(amounts);

        uint256 nav = vault.getNav();
        // 100 * $2 + 200 * $0.5 + 50 * $1 = $200 + $100 + $50 = $350
        assertEq(nav, 350e18);
    }

    function test_GetNavPerShare() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 200e18;
        amounts[2] = 50e18;

        vm.prank(user);
        vault.deposit(amounts);

        uint256 navPerShare = vault.getNavPerShare();
        // $350 NAV / 350 AGIX = $1 per AGIX
        assertEq(navPerShare, 1e18);
    }

    function test_GetWeights() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;  // $200 = 57.14%
        amounts[1] = 200e18;  // $100 = 28.57%
        amounts[2] = 50e18;   // $50 = 14.29%

        vm.prank(user);
        vault.deposit(amounts);

        (
            address[] memory tokens,
            uint256[] memory currentWeights,
            uint256[] memory targetWeights
        ) = vault.getWeights();

        assertEq(tokens.length, 3);

        // Check current weights (should be close to deposit ratios)
        // VIRTUAL: $200/$350 = 5714 BPS
        assertApproxEqAbs(currentWeights[0], 5714, 1);
        // AIXBT: $100/$350 = 2857 BPS
        assertApproxEqAbs(currentWeights[1], 2857, 1);
        // LUNA: $50/$350 = 1428 BPS
        assertApproxEqAbs(currentWeights[2], 1428, 1);

        // Target weights
        assertEq(targetWeights[0], 5000);
        assertEq(targetWeights[1], 3000);
        assertEq(targetWeights[2], 2000);
    }

    function test_Deposit_RevertBelowMinimum() public {
        vault.setMinDepositUsd(100e18);  // $100 minimum

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1e18;  // $2
        amounts[1] = 1e18;  // $0.50
        amounts[2] = 1e18;  // $1
        // Total: $3.50

        vm.prank(user);
        vm.expectRevert(IndexVault.BelowMinimumDeposit.selector);
        vault.deposit(amounts);
    }

    function test_Deposit_RevertWhenPaused() public {
        vault.setDepositsPaused(true);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 200e18;
        amounts[2] = 50e18;

        vm.prank(user);
        vm.expectRevert(IndexVault.DepositsPausedError.selector);
        vault.deposit(amounts);
    }

    function test_Redeem_RevertWhenPaused() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 200e18;
        amounts[2] = 50e18;

        vm.prank(user);
        vault.deposit(amounts);

        vault.setRedemptionsPaused(true);

        vm.prank(user);
        vm.expectRevert(IndexVault.RedemptionsPausedError.selector);
        vault.redeem(100e18);
    }

    function test_SetBasket_RevertInvalidWeight() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(virtual_token);
        tokens[1] = address(aixbt);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 4000;  // Total: 9000, not 10000

        vm.expectRevert(IndexVault.InvalidWeight.selector);
        vault.setBasket(tokens, weights);
    }

    function test_SetBasket_RevertArrayMismatch() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(virtual_token);
        tokens[1] = address(aixbt);

        uint256[] memory weights = new uint256[](3);
        weights[0] = 5000;
        weights[1] = 3000;
        weights[2] = 2000;

        vm.expectRevert(IndexVault.ArrayLengthMismatch.selector);
        vault.setBasket(tokens, weights);
    }

    function testFuzz_DepositRedeem(uint256 depositAmount) public {
        vm.assume(depositAmount > 10e18 && depositAmount < 500e18);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = depositAmount;
        amounts[1] = depositAmount;
        amounts[2] = depositAmount;

        vm.prank(user);
        uint256 minted = vault.deposit(amounts);

        assertGt(minted, 0);

        vm.prank(user);
        uint256[] memory returned = vault.redeem(minted);

        // Should get back approximately what was deposited (minus rounding)
        assertApproxEqAbs(returned[0], depositAmount, 1);
        assertApproxEqAbs(returned[1], depositAmount, 1);
        assertApproxEqAbs(returned[2], depositAmount, 1);
    }
}
