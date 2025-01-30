// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {NonAtomicMinter} from "@blueberry-v2/utils/NonAtomicMinter.sol";
import {INonAtomicMinter} from "@blueberry-v2/utils/NonAtomicMinter.sol";

contract NonAtomicUnit is Test {
    NonAtomicMinter public nonAtomicMinter;

    MockERC20 public underlying;
    MockERC20 public receipt;

    address internal immutable OWNER = makeAddr("OWNER");
    address internal immutable ALICE = makeAddr("ALICE");

    function setUp() public {
        underlying = new MockERC20("Underlying", "UND", 6);
        receipt = new MockERC20("Receipt", "REC", 18);

        address implementation = address(new NonAtomicMinter(address(underlying), address(receipt)));
        nonAtomicMinter = NonAtomicMinter(
            address(new ERC1967Proxy(implementation, abi.encodeCall(NonAtomicMinter.initialize, (OWNER))))
        );
    }

    function test_constructor() public view {
        assertEq(nonAtomicMinter.UNDERLYING(), address(underlying));
        assertEq(nonAtomicMinter.TOKEN(), address(receipt));
    }

    function test_initialize() public view {
        assertEq(nonAtomicMinter.owner(), OWNER);
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
    }

    function test_revert_upgradeFromNonOwner() public {
        address newImplementation = address(new NonAtomicMinter(address(underlying), address(receipt)));

        vm.prank(ALICE);
        vm.expectRevert();
        nonAtomicMinter.upgradeToAndCall(newImplementation, "");
    }

    function test_upgradeFromOwner() public {
        address newImplementation = address(new NonAtomicMinter(address(underlying), address(receipt)));

        vm.prank(OWNER);
        nonAtomicMinter.upgradeToAndCall(newImplementation, "");

        bytes32 implementationBytes = vm.load(address(nonAtomicMinter), ERC1967Utils.IMPLEMENTATION_SLOT);
        address implementation = address(uint160(uint256(implementationBytes)));
        assertEq(implementation, newImplementation);
    }

    function test_Initialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        nonAtomicMinter.initialize(ALICE);
    }
}
