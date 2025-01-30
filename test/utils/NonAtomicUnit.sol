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

    address internal immutable OWNER = makeAddr("OWNER");
    address internal immutable ALICE = makeAddr("ALICE");
    address internal immutable BOB = makeAddr("BOB");

    function setUp() public {
        underlying = new MockERC20("Underlying", "UND", 6);
        receipt = new MintableToken("Receipt", "REC", OWNER);

        address implementation = address(new NonAtomicMinter(address(underlying), address(receipt)));
        nonAtomicMinter = NonAtomicMinter(
            address(new ERC1967Proxy(implementation, abi.encodeCall(NonAtomicMinter.initialize, (OWNER))))
        );

        vm.startPrank(OWNER);
        receipt.grantRole(receipt.MINTER_ROLE(), address(nonAtomicMinter));
        vm.stopPrank();
    }

    function test_initial_state() public view {
        assertEq(nonAtomicMinter.UNDERLYING(), address(underlying));
        assertEq(nonAtomicMinter.TOKEN(), address(receipt));
        assertEq(nonAtomicMinter.owner(), OWNER);
    }

    function test_upgrade() public {
        address newImplementation = address(new NonAtomicMinter(address(underlying), address(receipt)));

        // Reverts if non-owner calls upgradeToAndCall
        vm.prank(ALICE);
        vm.expectRevert();
        nonAtomicMinter.upgradeToAndCall(newImplementation, "");

        // Valid upgrade
        vm.prank(OWNER);
        nonAtomicMinter.upgradeToAndCall(newImplementation, "");

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

        vm.startPrank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit INonAtomicMinter.InFlight(ALICE, 100e6);
        nonAtomicMinter.processDeposit(ALICE, 100e6);
        vm.stopPrank();

        // Validate Token balances
        assertEq(underlying.balanceOf(ALICE), 0);
        assertEq(underlying.balanceOf(address(nonAtomicMinter)), 0);
        assertEq(underlying.balanceOf(OWNER), 100e6);
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

        vm.startPrank(OWNER);
        vm.expectRevert(Errors.AMOUNT_EXCEEDS_BALANCE.selector);
        nonAtomicMinter.processDeposit(ALICE, 101e6);
    }

    function test_mint() public {
        underlying.mint(ALICE, 100e6);

        vm.startPrank(ALICE);
        underlying.approve(address(nonAtomicMinter), 100e6);
        nonAtomicMinter.deposit(100e6);
        vm.stopPrank();

        vm.startPrank(OWNER);

        // Fail to mint if there is nothing in flight for alice
        vm.expectRevert(Errors.AMOUNT_EXCEEDS_BALANCE.selector);
        nonAtomicMinter.mint(ALICE, 100e6, 100e18);

        // Process alices deposit
        nonAtomicMinter.processDeposit(ALICE, 100e6);

        // Valid mint
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

        vm.startPrank(OWNER);
        nonAtomicMinter.processDeposit(ALICE, 100e6);
        nonAtomicMinter.processDeposit(BOB, 200e6);

        // Invalid array lengths
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
}
