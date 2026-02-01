// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/AI500.sol";

contract AI500Test is Test {
    AI500 public ai500;

    address public owner = address(this);
    address public vault = address(0x1);
    address public user = address(0x2);

    function setUp() public {
        ai500 = new AI500();
    }

    function test_InitialState() public view {
        assertEq(ai500.name(), "AI 500 Index");
        assertEq(ai500.symbol(), "AI500");
        assertEq(ai500.decimals(), 18);
        assertEq(ai500.totalSupply(), 0);
        assertEq(ai500.vault(), address(0));
        assertEq(ai500.owner(), owner);
    }

    function test_SetVault() public {
        ai500.setVault(vault);
        assertEq(ai500.vault(), vault);
    }

    function test_SetVault_RevertZeroAddress() public {
        vm.expectRevert(AI500.ZeroAddress.selector);
        ai500.setVault(address(0));
    }

    function test_SetVault_RevertNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        ai500.setVault(vault);
    }

    function test_Mint() public {
        ai500.setVault(vault);

        vm.prank(vault);
        ai500.mint(user, 1000e18);

        assertEq(ai500.balanceOf(user), 1000e18);
        assertEq(ai500.totalSupply(), 1000e18);
    }

    function test_Mint_RevertNotVault() public {
        ai500.setVault(vault);

        vm.prank(user);
        vm.expectRevert(AI500.OnlyVault.selector);
        ai500.mint(user, 1000e18);
    }

    function test_BurnFrom() public {
        ai500.setVault(vault);

        vm.prank(vault);
        ai500.mint(user, 1000e18);

        vm.prank(vault);
        ai500.burnFrom(user, 400e18);

        assertEq(ai500.balanceOf(user), 600e18);
        assertEq(ai500.totalSupply(), 600e18);
    }

    function test_BurnFrom_RevertNotVault() public {
        ai500.setVault(vault);

        vm.prank(vault);
        ai500.mint(user, 1000e18);

        vm.prank(user);
        vm.expectRevert(AI500.OnlyVault.selector);
        ai500.burnFrom(user, 400e18);
    }

    function test_Transfer() public {
        ai500.setVault(vault);

        vm.prank(vault);
        ai500.mint(user, 1000e18);

        vm.prank(user);
        ai500.transfer(address(0x3), 100e18);

        assertEq(ai500.balanceOf(user), 900e18);
        assertEq(ai500.balanceOf(address(0x3)), 100e18);
    }

    function test_VaultUpdatedEvent() public {
        vm.expectEmit(true, true, false, false);
        emit AI500.VaultUpdated(address(0), vault);
        ai500.setVault(vault);
    }

    function testFuzz_Mint(uint256 amount) public {
        vm.assume(amount < type(uint256).max / 2);

        ai500.setVault(vault);

        vm.prank(vault);
        ai500.mint(user, amount);

        assertEq(ai500.balanceOf(user), amount);
    }
}
