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

    address internal immutable OWNER = makeAddr("OWNER");
    address internal immutable ALICE = makeAddr("ALICE");
    address internal immutable BOB = makeAddr("BOB");
    address internal immutable RANDO = makeAddr("RANDO");

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        underlying = ERC20(MainnetFaucet.USDC);
        receipt = new MintableToken("Receipt", "REC", OWNER);

        address implementation = address(new NonAtomicMinter(address(underlying), address(receipt)));
        nonAtomicMinter = NonAtomicMinter(
            address(new ERC1967Proxy(implementation, abi.encodeCall(NonAtomicMinter.initialize, (OWNER))))
        );

        vm.startPrank(OWNER);
        receipt.grantRole(receipt.MINTER_ROLE(), address(nonAtomicMinter));
        vm.stopPrank();
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

        // Validate total deposits
        assertEq(nonAtomicMinter.totalDeposits(), amount);
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

        // Validate total deposits
        assertEq(nonAtomicMinter.totalDeposits(), totalAmount);

        // Validate Token balances
        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), totalAmount);
    }

    function test_process_deposit(uint256 initialAmount, uint256 amountToProcess) public {
        initialAmount = bound(initialAmount, 1e6, 1_000_000e6);
        amountToProcess = bound(amountToProcess, 1e6, 1_000_000e6);
        vm.assume(initialAmount >= amountToProcess);

        _dripToken("USDC", ALICE, initialAmount);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), initialAmount);
        nonAtomicMinter.deposit(initialAmount);
        vm.stopPrank();

        vm.startPrank(OWNER);
        nonAtomicMinter.processDeposit(ALICE, amountToProcess);
        vm.stopPrank();

        uint256 remainingAmount = initialAmount - amountToProcess;
        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(receipt.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), remainingAmount);
        assertEq(underlying.balanceOf(OWNER), amountToProcess);

        // Validate deposit storage
        INonAtomicMinter.DepositRequest memory request = nonAtomicMinter.currentRequest(ALICE);
        assertEq(request.amount, remainingAmount);
        assertEq(request.lastUpdated, block.timestamp);

        INonAtomicMinter.DepositInFlight memory inFlight = nonAtomicMinter.currentInFlight(ALICE);
        assertEq(inFlight.amount, amountToProcess);
        assertEq(inFlight.lastUpdated, block.timestamp);

        // Validate total deposits
        assertEq(nonAtomicMinter.totalDeposits(), remainingAmount);
        assertEq(nonAtomicMinter.totalInFlight(), amountToProcess);
    }

    function test_mint(uint256 depositAmount, uint256 processedAmount, uint256 processedUsed, uint256 mintedAmount)
        public
    {
        depositAmount = bound(depositAmount, 10e6, 1_000_000e6);
        processedAmount = bound(processedAmount, 10e6, 1_000_000e6);
        mintedAmount = bound(mintedAmount, 10e6, 1_000_000e6);
        processedUsed = bound(processedUsed, 1e6, processedAmount);

        vm.assume(depositAmount >= processedAmount);
        vm.assume(processedAmount >= mintedAmount);

        uint256 endTotalDeposits = depositAmount - processedAmount;
        uint256 endTotalInFlight = processedAmount - processedUsed;

        _dripToken("USDC", ALICE, depositAmount);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), depositAmount);
        nonAtomicMinter.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(OWNER);
        nonAtomicMinter.processDeposit(ALICE, processedAmount);

        vm.expectEmit(true, true, true, true);
        emit INonAtomicMinter.Mint(ALICE, processedUsed, mintedAmount);
        nonAtomicMinter.mint(ALICE, processedUsed, mintedAmount);

        assertEq(nonAtomicMinter.totalDeposits(), endTotalDeposits);
        assertEq(nonAtomicMinter.totalInFlight(), endTotalInFlight);

        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), endTotalDeposits);
        assertEq(underlying.balanceOf(OWNER), processedAmount);
        assertEq(receipt.balanceOf(ALICE), mintedAmount);

        // Validate deposit storage
        INonAtomicMinter.DepositRequest memory request = nonAtomicMinter.currentRequest(ALICE);
        assertEq(request.amount, endTotalDeposits);
        assertEq(request.lastUpdated, block.timestamp);

        INonAtomicMinter.DepositInFlight memory inFlight = nonAtomicMinter.currentInFlight(ALICE);
        assertEq(inFlight.amount, endTotalInFlight);
        assertEq(inFlight.lastUpdated, block.timestamp);

        // Validate total deposits
        assertEq(nonAtomicMinter.totalDeposits(), endTotalDeposits);
        assertEq(nonAtomicMinter.totalInFlight(), endTotalInFlight);
    }

    function test_batchMint(
        uint256 deposit1,
        uint256 mint1,
        uint256 deposit2,
        uint256 mint2,
        uint256 deposit3,
        uint256 mint3
    ) public {
        deposit1 = bound(deposit1, 10e6, 1_000_000e6);
        mint1 = bound(mint1, 10e6, 1_000_000e6);
        vm.assume(deposit1 >= mint1);

        deposit2 = bound(deposit2, 10e6, 1_000_000e6);
        mint2 = bound(mint2, 10e6, 1_000_000e6);
        vm.assume(deposit2 >= mint2);

        deposit3 = bound(deposit3, 10e6, 1_000_000e6);
        mint3 = bound(mint3, 10e6, 1_000_000e6);
        vm.assume(deposit3 >= mint3);

        _dripToken("USDC", ALICE, deposit1);
        _dripToken("USDC", BOB, deposit2);
        _dripToken("USDC", RANDO, deposit3);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), deposit1);
        nonAtomicMinter.deposit(deposit1);

        vm.startPrank(BOB);
        underlying.approve(address(nonAtomicMinter), deposit2);
        nonAtomicMinter.deposit(deposit2);
        vm.stopPrank();

        vm.startPrank(RANDO);
        underlying.approve(address(nonAtomicMinter), deposit3);
        nonAtomicMinter.deposit(deposit3);
        vm.stopPrank();

        vm.startPrank(OWNER);
        nonAtomicMinter.processDeposit(ALICE, deposit1);
        nonAtomicMinter.processDeposit(BOB, deposit2);
        nonAtomicMinter.processDeposit(RANDO, deposit3);

        address[] memory users = new address[](3);
        users[0] = ALICE;
        users[1] = BOB;
        users[2] = RANDO;

        // We will mint receipt tokens 1:1 for underlying tokens.
        uint256[] memory processedAmounts = new uint256[](3);
        processedAmounts[0] = mint1;
        processedAmounts[1] = mint2;
        processedAmounts[2] = mint3;

        uint256[] memory mintedAmounts = new uint256[](3);
        mintedAmounts[0] = mint1;
        mintedAmounts[1] = mint2;
        mintedAmounts[2] = mint3;

        nonAtomicMinter.batchMint(users, processedAmounts, mintedAmounts);

        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(BOB), 0);
        assertEq(underlying.balanceOf(RANDO), 0);
        assertEq(underlying.balanceOf(OWNER), deposit1 + deposit2 + deposit3);

        assertEq(receipt.balanceOf(ALICE), mint1);
        assertEq(receipt.balanceOf(BOB), mint2);
        assertEq(receipt.balanceOf(RANDO), mint3);

        // Validate in flight accounting
        INonAtomicMinter.DepositInFlight memory inFlight = nonAtomicMinter.currentInFlight(ALICE);
        uint256 inFlightAmount1 = deposit1 - mint1;
        assertEq(inFlight.amount, inFlightAmount1);
        assertEq(inFlight.lastUpdated, block.timestamp);

        INonAtomicMinter.DepositInFlight memory inFlight2 = nonAtomicMinter.currentInFlight(BOB);
        uint256 inFlightAmount2 = deposit2 - mint2;
        assertEq(inFlight2.amount, inFlightAmount2);
        assertEq(inFlight2.lastUpdated, block.timestamp);

        INonAtomicMinter.DepositInFlight memory inFlight3 = nonAtomicMinter.currentInFlight(RANDO);
        uint256 inFlightAmount3 = deposit3 - mint3;
        assertEq(inFlight3.amount, inFlightAmount3);
        assertEq(inFlight3.lastUpdated, block.timestamp);

        // Validate total deposits
        assertEq(nonAtomicMinter.totalDeposits(), 0);
        assertEq(nonAtomicMinter.totalInFlight(), inFlightAmount1 + inFlightAmount2 + inFlightAmount3);
    }
}
