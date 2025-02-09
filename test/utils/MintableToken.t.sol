// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {MintableToken} from "@blueberry-v2/utils/MintableToken.sol";

contract MintableTokenTest is Test {
    MintableToken public mintableToken;

    address public immutable ADMIN = makeAddr("ADMIN");
    address public immutable MINTER = makeAddr("MINTER");
    address public immutable BURNER = makeAddr("BURNER");
    address public immutable USER = makeAddr("USER");

    function setUp() public {
        mintableToken = new MintableToken("Test Token", "TEST", 8, ADMIN);
    }

    function test_decimals() public view {
        assertEq(mintableToken.decimals(), 8);
    }

    function test_grant_roles() public {
        _grantRoles();

        assertEq(mintableToken.hasRole(mintableToken.MINTER_ROLE(), MINTER), true);
        assertEq(mintableToken.hasRole(mintableToken.BURNER_ROLE(), BURNER), true);
    }

    function test_mint(uint256 amount) public {
        _grantRoles();

        // Fails to mint if not admin
        vm.expectRevert();
        mintableToken.mint(ADMIN, amount);

        vm.startPrank(MINTER);
        mintableToken.mint(USER, amount);

        // Cant mint to 0 address
        vm.expectRevert();
        mintableToken.mint(address(0), amount);

        // Mints token
        assertEq(mintableToken.balanceOf(USER), amount);
        assertEq(mintableToken.totalSupply(), amount);
        vm.stopPrank();
    }

    function test_burnFrom(uint256 startingAmount, uint256 burnAmount) public {
        _grantRoles();

        vm.assume(startingAmount >= burnAmount);

        // Mint token to user
        vm.startPrank(MINTER);
        mintableToken.mint(USER, startingAmount);
        vm.stopPrank();

        // Fails to burn if not burner
        vm.expectRevert();
        mintableToken.burnFrom(USER, burnAmount);

        // Approves BURNER to burn USER's tokens
        vm.startPrank(USER);
        mintableToken.approve(BURNER, burnAmount);
        vm.stopPrank();

        // Burns token
        vm.startPrank(BURNER);
        mintableToken.burnFrom(USER, burnAmount);

        uint256 expectedBalance = startingAmount - burnAmount;
        assertEq(mintableToken.balanceOf(USER), expectedBalance);
        assertEq(mintableToken.totalSupply(), expectedBalance);
        vm.stopPrank();
    }

    function test_burn(uint256 amount) public {
        vm.assume(amount < type(uint256).max / 2);

        _grantRoles();

        vm.startPrank(MINTER);
        mintableToken.mint(USER, amount);
        mintableToken.mint(BURNER, amount);
        vm.stopPrank();

        // Fails to burn if not burner
        vm.startPrank(USER);
        vm.expectRevert();
        mintableToken.burn(amount);
        vm.stopPrank();

        // BURNER_ROLE can burn their own tokens
        vm.startPrank(BURNER);
        mintableToken.burn(amount);
        vm.stopPrank();
    }

    function _grantRoles() internal {
        vm.startPrank(ADMIN);
        mintableToken.grantRole(mintableToken.MINTER_ROLE(), MINTER);
        mintableToken.grantRole(mintableToken.BURNER_ROLE(), BURNER);
        vm.stopPrank();
    }
}
