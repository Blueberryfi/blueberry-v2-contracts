// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20, ERC20} from "../mocks/MockERC20.sol";
import {HyperEvmVault} from "../../src/vaults/hyperliquid/HyperEvmVault.sol";
import {VaultEscrow} from "../../src/vaults/hyperliquid/VaultEscrow.sol";
import {BlueberryErrors} from "../../src/helpers/BlueberryErrors.sol";
import {console2} from "forge-std/console2.sol";

contract VaultUnitTest is Test {
    HyperEvmVault public vault;
    MockERC20 public asset;
    address public owner;
    address public l1Vault;

    event EscrowDeployed(address indexed escrow);

    function setUp() public {
        vm.createSelectFork("https://rpc.hyperliquid-testnet.xyz/evm");

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
            ERC20(address(asset)),
            1,
            6,
            l1Vault,
            owner
        );

        assertEq(vault.name(), "Blueberry HLP");
        assertEq(vault.symbol(), "blHLP");
        assertEq(address(vault.asset()), address(asset));
        assertEq(vault.l1Vault(), l1Vault);
        assertEq(vault.owner(), owner);
    }

    function test_RevertConstructor_ZeroL1Vault() public {
        vm.expectRevert(abi.encodeWithSignature("ADDRESS_ZERO()"));
        vault = new HyperEvmVault(
            "blHLP",
            "blHLP",
            7,
            ERC20(address(asset)),
            1,
            6,
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

        vault = new HyperEvmVault("blHLP", "blHLP", escrowCount, ERC20(address(asset)), 1, 6, l1Vault, owner);
    }

    function test_OwnershipTransfer() public {
        vault = new HyperEvmVault("blHLP", "blHLP", 7, ERC20(address(asset)), 1, 6, l1Vault, owner);

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

    // function test_Deposit() public {
    //     vault = new HyperEvmVault("blHLP", "blHLP", 7, address(asset), l1Vault, owner);

    //     asset.mint(owner, 100e6);
    //     vm.prank(owner);
    //     vault.deposit(100e6, owner);
    // }

    // function _faucet(address user, uint256 amount) internal {
    //     asset.mint(user, amount);
    // }

    function test_IndexCalculation() public {
        vault = new HyperEvmVault("blHLP", "blHLP", 7, ERC20(address(asset)), 1, 6, l1Vault, owner);

        uint256 initialTimestamp = 1740645825;
        // Sets the block timestamp to make current Index == 0
        vm.warp(initialTimestamp);
        console2.log("block.timestamp", block.timestamp);
        assertEq(vault.depositEscrowIndex(), 0);
        assertEq(vault.redeemEscrowIndex(), 1);

        vm.warp(initialTimestamp + 1 days);
        assertEq(vault.depositEscrowIndex(), 1);
        assertEq(vault.redeemEscrowIndex(), 2);

        vm.warp(initialTimestamp + 2 days);
        assertEq(vault.depositEscrowIndex(), 2);
        assertEq(vault.redeemEscrowIndex(), 3);

        vm.warp(initialTimestamp + 3 days);
        assertEq(vault.depositEscrowIndex(), 3);
        assertEq(vault.redeemEscrowIndex(), 4);

        vm.warp(initialTimestamp + 4 days);
        assertEq(vault.depositEscrowIndex(), 4);
        assertEq(vault.redeemEscrowIndex(), 5);

        vm.warp(initialTimestamp + 5 days);
        assertEq(vault.depositEscrowIndex(), 5);
        assertEq(vault.redeemEscrowIndex(), 6);

        vm.warp(initialTimestamp + 6 days);
        assertEq(vault.depositEscrowIndex(), 6);
        assertEq(vault.redeemEscrowIndex(), 0);

        vm.warp(initialTimestamp + 7 days);
        assertEq(vault.depositEscrowIndex(), 0);
        assertEq(vault.redeemEscrowIndex(), 1);
    }
}
