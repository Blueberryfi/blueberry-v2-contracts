// SPDX-License-Identifier: BUSL-1.1
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/
pragma solidity ^0.8.0;

import {BBErrors as Errors} from "@blueberry-v2/helpers/BBErrors.sol";

import {BlueberryGarden} from "@blueberry-v2/BlueberryGarden.sol";
import {BlueberryGovernor} from "@blueberry-v2/Blueberrygarden.sol";

import {Helpers} from "../Helpers.t.sol";
import {MockERC20} from "../Mocks/MockERC20.sol";

contract GovernorUnitTests is Helpers {
    /// @notice Full Access Role
    bytes32 public constant FULL_ACCESS = keccak256("FULL_ACCESS");

    /// @notice Irrelevant Role
    bytes32 public constant IRRELAVENT = keccak256("IRRELAVENT");

    function setUp() public override {
        super.setUp();
    }

    function test_DeployAddressZeroAdmin() public {
        vm.expectRevert(Errors.ADDRESS_ZERO.selector);
        new BlueberryGarden(address(0));
    }

    function test_AddMarket() public {
        MockERC20 token = new MockERC20(18);

        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true);
        emit NewMarket(address(token), "bToken", "bTKN");
        address bToken = garden.addMarket(address(token), "bToken", "bTKN");

        assertEq(bToken, garden.market(address(token)));
        assertEq(address(token), garden.asset(bToken));
    }

    function test_AddExistingMarket() public {
        MockERC20 token = new MockERC20(18);

        vm.startPrank(admin);
        garden.addMarket(address(token), "bToken", "bTKN");

        vm.expectRevert(Errors.MARKET_ALREADY_EXISTS.selector);
        garden.addMarket(address(token), "bToken", "bTKN");
    }

    function test_AddMarketAddressZero() public {
        vm.startPrank(admin);
        vm.expectRevert(Errors.ADDRESS_ZERO.selector);
        garden.addMarket(address(0), "bToken", "bTKN");
    }

    function test_AddMarketNotApproved() public {
        MockERC20 token = new MockERC20(18);

        vm.startPrank(rando);
        vm.expectRevert(Errors.UNAUTHORIZED.selector);
        garden.addMarket(address(token), "bToken", "bTKN");
    }

    function test_SetAliceRole() public {
        vm.startPrank(admin);

        vm.expectEmit(true, true, true, true);
        emit RoleSet(alice, FULL_ACCESS);
        garden.setRole(alice, FULL_ACCESS);

        assertEq(garden.fullAccess(), FULL_ACCESS);
        assertEq(garden.role(alice), FULL_ACCESS);
    }

    function test_SetBobIrrelaventRole() public {
        // Give bob the irrelavent role.
        vm.startPrank(admin);
        garden.setRole(bob, IRRELAVENT);

        // He will not be able to set anything.
        vm.startPrank(bob);
        vm.expectRevert(Errors.UNAUTHORIZED.selector);
        garden.setRole(rando, FULL_ACCESS);
    }
}
