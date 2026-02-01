// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/AGIX.sol";

contract AGIXTest is Test {
    AGIX public agix;

    address public owner = address(this);
    address public vault = address(0x1);
    address public user = address(0x2);

    function setUp() public {
        agix = new AGIX();
    }

    function test_InitialState() public view {
        assertEq(agix.name(), "Agent Index");
        assertEq(agix.symbol(), "AGIX");
        assertEq(agix.decimals(), 18);
        assertEq(agix.totalSupply(), 0);
        assertEq(agix.vault(), address(0));
        assertEq(agix.owner(), owner);
    }

    function test_SetVault() public {
        agix.setVault(vault);
        assertEq(agix.vault(), vault);
    }

    function test_SetVault_RevertZeroAddress() public {
        vm.expectRevert(AGIX.ZeroAddress.selector);
        agix.setVault(address(0));
    }

    function test_SetVault_RevertNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        agix.setVault(vault);
    }

    function test_Mint() public {
        agix.setVault(vault);

        vm.prank(vault);
        agix.mint(user, 1000e18);

        assertEq(agix.balanceOf(user), 1000e18);
        assertEq(agix.totalSupply(), 1000e18);
    }

    function test_Mint_RevertNotVault() public {
        agix.setVault(vault);

        vm.prank(user);
        vm.expectRevert(AGIX.OnlyVault.selector);
        agix.mint(user, 1000e18);
    }

    function test_BurnFrom() public {
        agix.setVault(vault);

        vm.prank(vault);
        agix.mint(user, 1000e18);

        vm.prank(vault);
        agix.burnFrom(user, 400e18);

        assertEq(agix.balanceOf(user), 600e18);
        assertEq(agix.totalSupply(), 600e18);
    }

    function test_BurnFrom_RevertNotVault() public {
        agix.setVault(vault);

        vm.prank(vault);
        agix.mint(user, 1000e18);

        vm.prank(user);
        vm.expectRevert(AGIX.OnlyVault.selector);
        agix.burnFrom(user, 400e18);
    }

    function test_Transfer() public {
        agix.setVault(vault);

        vm.prank(vault);
        agix.mint(user, 1000e18);

        vm.prank(user);
        agix.transfer(address(0x3), 100e18);

        assertEq(agix.balanceOf(user), 900e18);
        assertEq(agix.balanceOf(address(0x3)), 100e18);
    }

    function test_VaultUpdatedEvent() public {
        vm.expectEmit(true, true, false, false);
        emit AGIX.VaultUpdated(address(0), vault);
        agix.setVault(vault);
    }

    function testFuzz_Mint(uint256 amount) public {
        vm.assume(amount < type(uint256).max / 2);

        agix.setVault(vault);

        vm.prank(vault);
        agix.mint(user, amount);

        assertEq(agix.balanceOf(user), amount);
    }
}
