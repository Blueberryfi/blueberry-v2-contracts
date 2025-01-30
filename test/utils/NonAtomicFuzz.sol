// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {Faucet} from "../faucets/faucet.sol";
import {MainnetFaucet} from "../faucets/mainnet.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";

import {NonAtomicMinter} from "@blueberry-v2/utils/NonAtomicMinter.sol";
import {INonAtomicMinter} from "@blueberry-v2/utils/NonAtomicMinter.sol";

contract NonAtomicFuzz is Faucet {
    uint256 internal mainnetFork;

    NonAtomicMinter public nonAtomicMinter;

    ERC20 public underlying;
    MockERC20 public receipt;

    address internal immutable OWNER = makeAddr("OWNER");
    address internal immutable ALICE = makeAddr("ALICE");

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        underlying = ERC20(MainnetFaucet.USDC);
        receipt = new MockERC20("Receipt", "REC", 18);

        address implementation = address(new NonAtomicMinter(address(underlying), address(receipt)));
        nonAtomicMinter = NonAtomicMinter(
            address(new ERC1967Proxy(implementation, abi.encodeCall(NonAtomicMinter.initialize, (OWNER))))
        );
    }

    function test_deposit(uint256 amount) public {
        amount = bound(amount, 1e6, 1_000_000e6);
        _dripToken("USDC", ALICE, amount);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), amount);

        // Valid deposit
        vm.expectEmit(true, true, true, true);
        emit INonAtomicMinter.Deposit(ALICE, amount);
        nonAtomicMinter.deposit(amount);
        vm.stopPrank();

        // Validate Token balances
        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), amount);
        assertEq(receipt.balanceOf(ALICE), 0); // receipt tokens should not be minted yet

        // Validate deposit storage
        INonAtomicMinter.DepositRequest memory request = nonAtomicMinter.currentRequest(ALICE);
        assertEq(request.amount, amount);
        assertEq(request.lastUpdated, block.timestamp);
    }

    function test_secondDeposit(uint256 deposit1, uint256 deposit2, uint256 timeBetweenDeposits) public {
        deposit1 = bound(deposit1, 1e6, 1_000_000e6);
        deposit2 = bound(deposit2, 1e6, 1_000_000e6);
        timeBetweenDeposits = bound(timeBetweenDeposits, 1, 360 days);

        // Mint underlying tokens to Alice
        uint256 totalAmount = deposit1 + deposit2;
        _dripToken("USDC", ALICE, totalAmount);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), totalAmount);

        // First deposit
        nonAtomicMinter.deposit(deposit1);
        INonAtomicMinter.DepositRequest memory firstRequest = nonAtomicMinter.currentRequest(ALICE);

        // Skip in time by timeBetweenDeposits
        vm.warp(firstRequest.lastUpdated + timeBetweenDeposits);

        // Second deposit
        nonAtomicMinter.deposit(deposit2);

        INonAtomicMinter.DepositRequest memory secondRequest = nonAtomicMinter.currentRequest(ALICE);
        assertEq(secondRequest.amount, totalAmount);
        assertEq(secondRequest.lastUpdated, block.timestamp);

        uint256 depositDifference = secondRequest.amount - firstRequest.amount;
        assertEq(depositDifference, deposit2);

        // Validate Token balances
        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), totalAmount);
    }
}
