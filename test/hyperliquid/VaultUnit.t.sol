// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {HyperEvmVault} from "../../src/vaults/hyperliquid/HyperEvmVault.sol";
import {VaultEscrow} from "../../src/vaults/hyperliquid/VaultEscrow.sol";
import {BlueberryErrors} from "../../src/helpers/BlueberryErrors.sol";

contract VaultUnitTest is Test {
    HyperEvmVault public vault;
    MockERC20 public asset;
    address public owner;
    address public l1Vault;

    event EscrowDeployed(address indexed escrow);

    function setUp() public {
        owner = makeAddr("owner");
        l1Vault = makeAddr("l1Vault");

        // Deploy mock asset
        asset = new MockERC20("Test USDC", "USDC", 6);
    }

    /*//////////////////////////////////////////////////////////////
                            Setup Tests
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public {
        vault = new HyperEvmVault(
            "Blueberry HLP",
            "blHLP",
            7, // escrow count
            address(asset),
            l1Vault,
            owner
        );

        assertEq(vault.name(), "Blueberry HLP");
        assertEq(vault.symbol(), "blHLP");
        assertEq(vault.asset(), address(asset));
        assertEq(vault.l1Vault(), l1Vault);
        assertEq(vault.owner(), owner);
    }

    function test_RevertConstructor_ZeroAsset() public {
        vm.expectRevert(abi.encodeWithSignature("ADDRESS_ZERO()"));
        vault = new HyperEvmVault(
            "blHLP",
            "blHLP",
            7,
            address(0), // zero address for asset
            l1Vault,
            owner
        );
    }

    function test_RevertConstructor_ZeroL1Vault() public {
        vm.expectRevert(abi.encodeWithSignature("ADDRESS_ZERO()"));
        vault = new HyperEvmVault(
            "blHLP",
            "blHLP",
            7,
            address(asset),
            address(0), // zero address for l1Vault
            owner
        );
    }

    function test_EscrowDeployment() public {
        uint8 escrowCount = 3;

        // Expect EscrowDeployed events
        for (uint8 i = 0; i < escrowCount; i++) {
            vm.expectEmit(false, false, false, false);
            emit EscrowDeployed(address(0)); // Ignore the address
        }

        vault = new HyperEvmVault("blHLP", "blHLP", escrowCount, address(asset), l1Vault, owner);
    }

    function test_OwnershipTransfer() public {
        vault = new HyperEvmVault("blHLP", "blHLP", 7, address(asset), l1Vault, owner);

        address newOwner = makeAddr("newOwner");

        // Transfer ownership
        vm.prank(owner);
        vault.transferOwnership(newOwner);

        // Accept ownership
        vm.prank(newOwner);
        vault.acceptOwnership();

        assertEq(vault.owner(), newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                            Deposit Tests
    //////////////////////////////////////////////////////////////*/
}
