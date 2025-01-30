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

    function setUp() public {
        underlying = new MockERC20("Underlying", "UND", 6);
        receipt = new MintableToken("Receipt", "REC", ADMIN);

        address implementation = address(new NonAtomicMinter(address(underlying), address(receipt)));
        nonAtomicMinter = NonAtomicMinter(
            address(new ERC1967Proxy(implementation, abi.encodeCall(NonAtomicMinter.initialize, (ADMIN))))
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
        nonAtomicMinter.initialize(ALICE);
    }

    function test_deposit() public {
        underlying.mint(ALICE, 100e6);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), 100e6);

        // Invalid deposit
        vm.expectRevert(Errors.AMOUNT_ZERO.selector);
        nonAtomicMinter.deposit(0);

        // Validate Token balances
        assertEq(underlying.balanceOf(ALICE), 100e6);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), 0);

        // Valid deposit
        vm.expectEmit(true, true, true, true);
        emit INonAtomicMinter.Deposit(ALICE, 100e6);
        nonAtomicMinter.deposit(100e6);
        vm.stopPrank();

        // Validate Token balances
        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), 100e6);
        assertEq(receipt.balanceOf(ALICE), 0); // receipt tokens should not be minted yet

        // Validate deposit storage
        INonAtomicMinter.DepositRequest memory request = nonAtomicMinter.currentRequest(ALICE);
        assertEq(request.amount, 100e6);
        assertEq(request.lastUpdated, block.timestamp);

        // Validate total deposits
        assertEq(nonAtomicMinter.totalDeposits(), 100e6);
    }

    function test_process_deposit() public {
        underlying.mint(ALICE, 100e6);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), 100e6);
        nonAtomicMinter.deposit(100e6);
        vm.stopPrank();

        vm.startPrank(PROCESSOR);
        vm.expectEmit(true, true, true, true);
        emit INonAtomicMinter.InFlight(ALICE, 100e6);
        nonAtomicMinter.processDeposit(ALICE, 100e6);
        vm.stopPrank();

        // Validate Token balances
        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), 0);
        assertEq(underlying.balanceOf(PROCESSOR), 100e6);
        assertEq(receipt.balanceOf(ALICE), 0); // receipt tokens should still not be minted yet

        // Validate deposit storage
        INonAtomicMinter.DepositRequest memory request = nonAtomicMinter.currentRequest(ALICE);
        assertEq(request.amount, 0);
        assertEq(request.lastUpdated, block.timestamp);

        // Validate in flight accounting
        INonAtomicMinter.DepositInFlight memory inFlight = nonAtomicMinter.currentInFlight(ALICE);
        assertEq(inFlight.amount, 100e6);
        assertEq(inFlight.lastUpdated, block.timestamp);

        // Validate total deposits
        assertEq(nonAtomicMinter.totalDeposits(), 0);
        assertEq(nonAtomicMinter.totalInFlight(), 100e6);
    }

    function test_invalid_process_deposit() public {
        underlying.mint(ALICE, 100e6);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), 100e6);
        nonAtomicMinter.deposit(100e6);
        vm.stopPrank();

        vm.startPrank(PROCESSOR);
        vm.expectRevert(Errors.AMOUNT_EXCEEDS_BALANCE.selector);
        nonAtomicMinter.processDeposit(ALICE, 101e6);
    }

    function test_invalid_batch_process() public {
        address[] memory users = new address[](2);
        users[0] = ALICE;
        users[1] = BOB;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 50e6;

        vm.startPrank(PROCESSOR);
        vm.expectRevert(Errors.ARRAY_LENGTH_MISMATCH.selector);
        nonAtomicMinter.batchProcessDeposit(users, amounts);
        vm.stopPrank();
    }

    function test_mint() public {
        underlying.mint(ALICE, 100e6);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), 100e6);
        nonAtomicMinter.deposit(100e6);
        vm.stopPrank();

        // Fail to mint if there is nothing in flight for alice
        vm.startPrank(MINTER);
        vm.expectRevert(Errors.AMOUNT_EXCEEDS_BALANCE.selector);
        nonAtomicMinter.mint(ALICE, 100e6, 100e18);
        vm.stopPrank();

        // Process alices deposit
        vm.startPrank(PROCESSOR);
        nonAtomicMinter.processDeposit(ALICE, 100e6);
        vm.stopPrank();

        // Valid mint
        vm.startPrank(MINTER);
        vm.expectEmit(true, true, true, true);
        emit INonAtomicMinter.Mint(ALICE, 100e6, 100e18);
        nonAtomicMinter.mint(ALICE, 100e6, 100e18);
        vm.stopPrank();

        // Validate Token balances
        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), 0);
        assertEq(receipt.balanceOf(ALICE), 100e18);

        // Validate deposit storage
        INonAtomicMinter.DepositRequest memory request = nonAtomicMinter.currentRequest(ALICE);
        assertEq(request.amount, 0);
        assertEq(request.lastUpdated, block.timestamp);

        // Validate in flight accounting
        INonAtomicMinter.DepositInFlight memory inFlight = nonAtomicMinter.currentInFlight(ALICE);
        assertEq(inFlight.amount, 0);
        assertEq(inFlight.lastUpdated, block.timestamp);

        // Validate total deposits
        assertEq(nonAtomicMinter.totalDeposits(), 0);
        assertEq(nonAtomicMinter.totalInFlight(), 0);
    }

    function test_batch_process_deposit() public {
        underlying.mint(ALICE, 100e6);
        underlying.mint(BOB, 200e6);
        underlying.mint(RANDO, 300e6);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), 100e6);
        nonAtomicMinter.deposit(100e6);
        vm.stopPrank();

        vm.startPrank(BOB);
        underlying.approve(address(nonAtomicMinter), 200e6);
        nonAtomicMinter.deposit(200e6);
        vm.stopPrank();

        vm.startPrank(RANDO);
        underlying.approve(address(nonAtomicMinter), 300e6);
        nonAtomicMinter.deposit(300e6);
        vm.stopPrank();

        address[] memory users = new address[](3);
        users[0] = ALICE;
        users[1] = BOB;
        users[2] = RANDO;

        // Leave 50e6 from each user
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 50e6;
        amounts[1] = 150e6;
        amounts[2] = 250e6;

        vm.startPrank(PROCESSOR);
        nonAtomicMinter.batchProcessDeposit(users, amounts);
        vm.stopPrank();

        // Validate Deposit storage
        INonAtomicMinter.DepositRequest memory request = nonAtomicMinter.currentRequest(ALICE);
        assertEq(request.amount, 50e6);
        assertEq(request.lastUpdated, block.timestamp);

        INonAtomicMinter.DepositRequest memory request2 = nonAtomicMinter.currentRequest(BOB);
        assertEq(request2.amount, 50e6);
        assertEq(request2.lastUpdated, block.timestamp);

        INonAtomicMinter.DepositRequest memory request3 = nonAtomicMinter.currentRequest(RANDO);
        assertEq(request3.amount, 50e6);
        assertEq(request3.lastUpdated, block.timestamp);

        // Validate in flight accounting
        INonAtomicMinter.DepositInFlight memory inFlight = nonAtomicMinter.currentInFlight(ALICE);
        assertEq(inFlight.amount, 50e6);
        assertEq(inFlight.lastUpdated, block.timestamp);

        INonAtomicMinter.DepositInFlight memory inFlight2 = nonAtomicMinter.currentInFlight(BOB);
        assertEq(inFlight2.amount, 150e6);
        assertEq(inFlight2.lastUpdated, block.timestamp);

        INonAtomicMinter.DepositInFlight memory inFlight3 = nonAtomicMinter.currentInFlight(RANDO);
        assertEq(inFlight3.amount, 250e6);
        assertEq(inFlight3.lastUpdated, block.timestamp);

        // Validate total deposits
        assertEq(nonAtomicMinter.totalDeposits(), 150e6);
        assertEq(nonAtomicMinter.totalInFlight(), 450e6);
    }

    function test_batch_mint() public {
        underlying.mint(ALICE, 100e6);
        underlying.mint(BOB, 200e6);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), 100e6);
        nonAtomicMinter.deposit(100e6);
        vm.stopPrank();

        vm.startPrank(BOB);
        underlying.approve(address(nonAtomicMinter), 200e6);
        nonAtomicMinter.deposit(200e6);
        vm.stopPrank();

        vm.startPrank(PROCESSOR);
        nonAtomicMinter.processDeposit(ALICE, 100e6);
        nonAtomicMinter.processDeposit(BOB, 200e6);
        vm.stopPrank();

        // Invalid array lengths
        vm.startPrank(MINTER);
        vm.expectRevert(Errors.ARRAY_LENGTH_MISMATCH.selector);
        nonAtomicMinter.batchMint(new address[](2), new uint256[](1), new uint256[](1));

        address[] memory users = new address[](2);
        users[0] = ALICE;
        users[1] = BOB;

        uint256[] memory processedAmounts = new uint256[](2);
        processedAmounts[0] = 100e6;
        processedAmounts[1] = 200e6;

        uint256[] memory mintedAmounts = new uint256[](2);
        mintedAmounts[0] = 100e18;
        mintedAmounts[1] = 200e18;

        // Valid batch mint
        vm.expectEmit(true, true, true, true);
        emit INonAtomicMinter.Mint(ALICE, 100e6, 100e18);
        emit INonAtomicMinter.Mint(BOB, 200e6, 200e18);
        nonAtomicMinter.batchMint(users, processedAmounts, mintedAmounts);

        // Validate Token balances
        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(BOB), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), 0);
        assertEq(receipt.balanceOf(ALICE), 100e18);
        assertEq(receipt.balanceOf(BOB), 200e18);

        // Validate deposit storage
        INonAtomicMinter.DepositRequest memory request = nonAtomicMinter.currentRequest(ALICE);
        assertEq(request.amount, 0);
        assertEq(request.lastUpdated, block.timestamp);

        INonAtomicMinter.DepositRequest memory request2 = nonAtomicMinter.currentRequest(BOB);
        assertEq(request2.amount, 0);
        assertEq(request2.lastUpdated, block.timestamp);

        // Validate in flight accounting
        INonAtomicMinter.DepositInFlight memory inFlight = nonAtomicMinter.currentInFlight(ALICE);
        assertEq(inFlight.amount, 0);
        assertEq(inFlight.lastUpdated, block.timestamp);

        INonAtomicMinter.DepositInFlight memory inFlight2 = nonAtomicMinter.currentInFlight(BOB);
        assertEq(inFlight2.amount, 0);
        assertEq(inFlight2.lastUpdated, block.timestamp);

        // Validate total deposits
        assertEq(nonAtomicMinter.totalDeposits(), 0);
        assertEq(nonAtomicMinter.totalInFlight(), 0);
    }

    function test_invalid_batch_mint() public {
        address[] memory users = new address[](2);
        users[0] = ALICE;
        users[1] = BOB;

        uint256[] memory processedAmounts = new uint256[](2);
        processedAmounts[0] = 100e6;
        processedAmounts[1] = 200e6;

        uint256[] memory mintedAmounts = new uint256[](1);
        mintedAmounts[0] = 100e18;

        vm.startPrank(MINTER);
        vm.expectRevert(Errors.ARRAY_LENGTH_MISMATCH.selector);
        nonAtomicMinter.batchMint(users, processedAmounts, mintedAmounts);
        vm.stopPrank();
    }
}
