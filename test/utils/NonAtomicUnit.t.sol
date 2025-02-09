// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";

import {MintableToken} from "@blueberry-v2/utils/MintableToken.sol";
import {NonAtomicMinter} from "@blueberry-v2/utils/NonAtomicMinter.sol";
import {INonAtomicMinter} from "@blueberry-v2/utils/NonAtomicMinter.sol";

import {MockERC20} from "../mocks/MockERC20.sol";

contract NonAtomicUnit is Test {
    NonAtomicMinter public nonAtomicMinter;

    MockERC20 public underlying;
    MintableToken public receipt;

    address internal immutable ADMIN = makeAddr("ADMIN");
    address internal immutable PROCESSOR = makeAddr("PROCESSOR");
    address internal immutable MINTER = makeAddr("MINTER");
    address internal immutable UPGRADER = makeAddr("UPGRADER");

    address internal immutable ALICE = makeAddr("ALICE");
    address internal immutable BOB = makeAddr("BOB");
    address internal immutable RANDO = makeAddr("RANDO");

    uint256 internal immutable MIN_DEPOSIT = 5e6;

    function setUp() public {
        underlying = new MockERC20("Underlying", "UND", 6);
        receipt = new MintableToken("Receipt", "REC", 18, ADMIN);

        address implementation = address(new NonAtomicMinter(address(underlying), address(receipt)));
        nonAtomicMinter = NonAtomicMinter(
            address(new ERC1967Proxy(implementation, abi.encodeCall(NonAtomicMinter.initialize, (ADMIN, MIN_DEPOSIT))))
        );

        vm.startPrank(ADMIN);
        receipt.grantRole(receipt.MINTER_ROLE(), address(nonAtomicMinter));
        nonAtomicMinter.grantRole(nonAtomicMinter.PROCESSOR_ROLE(), PROCESSOR);
        nonAtomicMinter.grantRole(nonAtomicMinter.MINTER_ROLE(), MINTER);
        nonAtomicMinter.grantRole(nonAtomicMinter.UPGRADE_ROLE(), UPGRADER);
    }

    function test_initial_state() public view {
        assertEq(nonAtomicMinter.UNDERLYING(), address(underlying));
        assertEq(nonAtomicMinter.TOKEN(), address(receipt));
        assertEq(nonAtomicMinter.hasRole(nonAtomicMinter.DEFAULT_ADMIN_ROLE(), ADMIN), true);
    }

    function test_upgrade() public {
        address newImplementation = address(new NonAtomicMinter(address(underlying), address(receipt)));

        // Reverts if non-UPGRADER calls upgradeToAndCall
        vm.startPrank(ADMIN);
        vm.expectRevert();
        nonAtomicMinter.upgradeToAndCall(newImplementation, "");

        // Valid upgrade
        vm.startPrank(UPGRADER);
        nonAtomicMinter.upgradeToAndCall(newImplementation, "");
        vm.stopPrank();

        bytes32 implementationBytes = vm.load(address(nonAtomicMinter), ERC1967Utils.IMPLEMENTATION_SLOT);
        address implementation = address(uint160(uint256(implementationBytes)));
        assertEq(implementation, newImplementation);
    }

    function test_initialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        nonAtomicMinter.initialize(ALICE, MIN_DEPOSIT);
    }

    function test_deposit() public {
        underlying.mint(ALICE, 100e6);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), 100e6);

        // Invalid deposit
        vm.expectRevert(Errors.AMOUNT_ZERO.selector);
        nonAtomicMinter.deposit(0);

        // Invalid deposit
        vm.expectRevert(Errors.BELOW_MIN_COLL.selector);
        nonAtomicMinter.deposit(4e6);

        // Validate Token balances
        assertEq(underlying.balanceOf(ALICE), 100e6);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), 0);

        // Valid deposit
        vm.expectEmit(true, true, true, true);
        emit INonAtomicMinter.OrderPending(0, ALICE, 100e6);
        nonAtomicMinter.deposit(100e6);
        vm.stopPrank();

        // Validate Token balances
        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), 100e6);
        assertEq(receipt.balanceOf(ALICE), 0); // receipt tokens should not be minted yet

        // Validate deposit storage
        INonAtomicMinter.OrderInfo memory order = nonAtomicMinter.info(0);
        assertEq(order.amount, 100e6);
        assertEq(order.lastUpdated, block.timestamp);
        assertTrue(order.status == INonAtomicMinter.OrderStatus.PENDING);

        // Validate total deposits
        assertEq(nonAtomicMinter.nextId(), 1);
    }

    function test_sweepOrder() public {
        underlying.mint(ALICE, 100e6);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), 100e6);
        nonAtomicMinter.deposit(100e6);
        vm.stopPrank();

        vm.startPrank(PROCESSOR);
        vm.expectEmit(true, true, true, true);
        emit INonAtomicMinter.OrderSwept(0, 100e6);
        nonAtomicMinter.sweepOrder(0);
        vm.stopPrank();

        // Validate Token balances
        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), 0);
        assertEq(underlying.balanceOf(PROCESSOR), 100e6);
        assertEq(receipt.balanceOf(ALICE), 0); // receipt tokens should still not be minted yet

        // Validate deposit storage
        INonAtomicMinter.OrderInfo memory order = nonAtomicMinter.info(0);
        assertEq(order.amount, 100e6);
        assertEq(order.lastUpdated, block.timestamp);
        assertTrue(order.status == INonAtomicMinter.OrderStatus.IN_FLIGHT);

        // Validate total deposits
        assertEq(nonAtomicMinter.nextId(), 1);
    }

    function test_invalid_sweepOrder() public {
        underlying.mint(ALICE, 100e6);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), 100e6);
        nonAtomicMinter.deposit(100e6);
        vm.stopPrank();

        vm.startPrank(PROCESSOR);
        nonAtomicMinter.sweepOrder(0);
        vm.stopPrank();
    }

    function test_mint() public {
        underlying.mint(ALICE, 100e6);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), 100e6);
        nonAtomicMinter.deposit(100e6);
        vm.stopPrank();

        // Fail to mint if the order has not been swept for alice
        vm.startPrank(MINTER);
        vm.expectRevert(Errors.INVALID_OPERATION.selector);
        nonAtomicMinter.mint(0, ALICE, 100e18);
        vm.stopPrank();

        // Process alices deposit
        vm.startPrank(PROCESSOR);
        nonAtomicMinter.sweepOrder(0);
        vm.stopPrank();

        // Fail to sweep the order if the order has already been swept
        vm.startPrank(PROCESSOR);
        vm.expectRevert(Errors.INVALID_OPERATION.selector);
        nonAtomicMinter.sweepOrder(0);
        vm.stopPrank();

        // Valid mint
        vm.startPrank(MINTER);
        vm.expectEmit(true, true, true, true);
        emit INonAtomicMinter.OrderCompleted(0, ALICE, 100e18);
        nonAtomicMinter.mint(0, ALICE, 100e18);
        vm.stopPrank();

        // Validate Token balances
        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), 0);
        assertEq(receipt.balanceOf(ALICE), 100e18);

        // Validate deposit storage
        INonAtomicMinter.OrderInfo memory order = nonAtomicMinter.info(0);
        assertEq(order.amount, 100e6);
        assertEq(order.lastUpdated, block.timestamp);
        assertTrue(order.status == INonAtomicMinter.OrderStatus.COMPLETED);

        // Validate total deposits
        assertEq(nonAtomicMinter.nextId(), 1);
    }

    function test_minDeposit() public view {
        assertEq(nonAtomicMinter.minDeposit(), MIN_DEPOSIT);
    }
}
