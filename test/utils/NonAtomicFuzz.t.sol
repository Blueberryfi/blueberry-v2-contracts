// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {Faucet} from "../faucets/faucet.sol";
import {MainnetFaucet} from "../faucets/mainnet.sol";

import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";

import {MintableToken} from "@blueberry-v2/utils/MintableToken.sol";
import {NonAtomicMinter} from "@blueberry-v2/utils/NonAtomicMinter.sol";
import {INonAtomicMinter} from "@blueberry-v2/utils/NonAtomicMinter.sol";

contract NonAtomicFuzz is Faucet {
    uint256 internal mainnetFork;

    NonAtomicMinter public nonAtomicMinter;

    ERC20 public underlying;
    MintableToken public receipt;

    address internal immutable ADMIN = makeAddr("ADMIN");
    address internal immutable PROCESSOR = makeAddr("PROCESSOR");
    address internal immutable MINTER = makeAddr("MINTER");

    address internal immutable ALICE = makeAddr("ALICE");
    address internal immutable BOB = makeAddr("BOB");
    address internal immutable RANDO = makeAddr("RANDO");

    uint256 internal immutable MIN_DEPOSIT = 5e6;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        underlying = ERC20(MainnetFaucet.USDC);
        receipt = new MintableToken("Receipt", "REC", 18, ADMIN);

        address implementation = address(new NonAtomicMinter(address(underlying), address(receipt)));
        nonAtomicMinter = NonAtomicMinter(
            address(new ERC1967Proxy(implementation, abi.encodeCall(NonAtomicMinter.initialize, (ADMIN, MIN_DEPOSIT))))
        );

        vm.startPrank(ADMIN);
        receipt.grantRole(receipt.MINTER_ROLE(), address(nonAtomicMinter));
        nonAtomicMinter.grantRole(nonAtomicMinter.MINTER_ROLE(), MINTER);
        nonAtomicMinter.grantRole(nonAtomicMinter.PROCESSOR_ROLE(), PROCESSOR);
        vm.stopPrank();
    }

    function test_deposit(uint256 amount) public {
        amount = bound(amount, 10e6, 1_000_000e6);
        _dripToken("USDC", ALICE, amount);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), amount);

        // Valid deposit
        vm.expectEmit(true, true, true, true);
        emit INonAtomicMinter.OrderPending(0, ALICE, amount);
        nonAtomicMinter.deposit(amount);
        vm.stopPrank();

        // Validate Token balances
        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), amount);
        assertEq(receipt.balanceOf(ALICE), 0); // receipt tokens should not be minted yet

        // Validate deposit storage
        INonAtomicMinter.OrderInfo memory order = nonAtomicMinter.info(0);
        assertEq(order.amount, amount);
        assertEq(order.lastUpdated, block.timestamp);

        // Validate total deposits
        assertEq(nonAtomicMinter.nextId(), 1);

        // Validate order ownership
        assertEq(nonAtomicMinter.isUserOrder(ALICE, 0), true);
        assertEq(nonAtomicMinter.isUserOrder(BOB, 0), false);
    }

    function test_secondDeposit(uint256 deposit1, uint256 deposit2, uint256 timeBetweenDeposits) public {
        deposit1 = bound(deposit1, 10e6, 1_000_000e6);
        deposit2 = bound(deposit2, 10e6, 1_000_000e6);
        timeBetweenDeposits = bound(timeBetweenDeposits, 1, 360 days);

        // Mint underlying tokens to Alice
        uint256 totalAmount = deposit1 + deposit2;
        _dripToken("USDC", ALICE, totalAmount);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), totalAmount);

        // First deposit
        nonAtomicMinter.deposit(deposit1);
        INonAtomicMinter.OrderInfo memory firstOrder = nonAtomicMinter.info(0);

        // Skip in time by timeBetweenDeposits
        vm.warp(firstOrder.lastUpdated + timeBetweenDeposits);

        // Second deposit
        nonAtomicMinter.deposit(deposit2);

        // Validate second deposit storage
        INonAtomicMinter.OrderInfo memory secondOrder = nonAtomicMinter.info(1);
        assertEq(secondOrder.amount, deposit2);
        assertEq(secondOrder.lastUpdated, block.timestamp);

        // Validate that the first order still has not changed
        assertEq(firstOrder.amount, deposit1);
        assertEq(firstOrder.lastUpdated, block.timestamp - timeBetweenDeposits);

        // Validate total deposits
        assertEq(nonAtomicMinter.nextId(), 2);

        // Validate Token balances
        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), totalAmount);

        // Validate order ownership
        assertEq(nonAtomicMinter.isUserOrder(ALICE, 0), true);
        assertEq(nonAtomicMinter.isUserOrder(BOB, 0), false);
        assertEq(nonAtomicMinter.isUserOrder(ALICE, 1), true);
        assertEq(nonAtomicMinter.isUserOrder(BOB, 1), false);
    }

    function test_sweepOrder(uint256 amount) public {
        amount = bound(amount, 10e6, 1_000_000e6);

        _dripToken("USDC", ALICE, amount);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), amount);
        nonAtomicMinter.deposit(amount);
        vm.stopPrank();

        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(receipt.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), amount);
        assertEq(underlying.balanceOf(PROCESSOR), 0);

        vm.startPrank(PROCESSOR);
        vm.expectEmit(true, true, true, true);
        emit INonAtomicMinter.OrderSwept(0, amount);
        nonAtomicMinter.sweepOrder(0);
        vm.stopPrank();

        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(receipt.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), 0);
        assertEq(underlying.balanceOf(PROCESSOR), amount);

        // Validate deposit storage
        INonAtomicMinter.OrderInfo memory order = nonAtomicMinter.info(0);
        assertEq(order.amount, amount);
        assertEq(order.lastUpdated, block.timestamp);
        assertTrue(order.status == INonAtomicMinter.OrderStatus.IN_FLIGHT);

        // Validate total deposits
        assertEq(nonAtomicMinter.nextId(), 1);

        // Validate order ownership
        assertEq(nonAtomicMinter.isUserOrder(ALICE, 0), true);
        assertEq(nonAtomicMinter.isUserOrder(BOB, 0), false);
    }

    function test_mint(uint256 depositAmount, uint256 mintedAmount) public {
        depositAmount = bound(depositAmount, 10e6, 1_000_000e6);
        mintedAmount = bound(mintedAmount, 10e6, 1_000_000e6);

        _dripToken("USDC", ALICE, depositAmount);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), depositAmount);
        nonAtomicMinter.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(PROCESSOR);
        nonAtomicMinter.sweepOrder(0);
        vm.stopPrank();

        vm.startPrank(MINTER);
        vm.expectEmit(true, true, true, true);
        emit INonAtomicMinter.OrderCompleted(0, ALICE, mintedAmount);
        nonAtomicMinter.mint(0, ALICE, mintedAmount);

        assertEq(nonAtomicMinter.nextId(), 1);

        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), 0);
        assertEq(receipt.balanceOf(ALICE), mintedAmount);

        // Validate deposit storage
        INonAtomicMinter.OrderInfo memory order = nonAtomicMinter.info(0);
        assertEq(order.amount, depositAmount);
        assertEq(order.lastUpdated, block.timestamp);
        assertTrue(order.status == INonAtomicMinter.OrderStatus.COMPLETED);
    }
}
