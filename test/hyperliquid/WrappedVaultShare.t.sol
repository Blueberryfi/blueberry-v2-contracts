// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/test.sol";
import {WrappedVaultShare} from "@blueberry-v2/vaults/hyperliquid/WrappedVaultShare.sol";

contract MockRouter {
    uint256 public pokeCount;

    function pokeFees() external {
        pokeCount++;
    }
}

contract WrappedVaultShareTest is Test {
    WrappedVaultShare public wHlp;
    MockRouter public router;

    // EOAs
    address admin = makeAddr("admin");
    address recipient = makeAddr("recipient");
    address rando = makeAddr("rando");

    function setUp() public virtual {
        router = new MockRouter();
        wHlp = new WrappedVaultShare("Wrapped HLP", "wHLP", address(router), admin);
    }

    function test_Constructor() public view {
        assertEq(wHlp.name(), "Wrapped HLP");
        assertEq(wHlp.symbol(), "wHLP");
        assertEq(wHlp.decimals(), 18);
        assertEq(wHlp.ROUTER(), address(router));
    }

    function test_AdminCannotMint() public {
        vm.startPrank(admin);
        vm.expectRevert();
        wHlp.mint(recipient, 100e18);
        vm.stopPrank();
    }

    function test_PokeFeesCalledOnTransfer() public {
        vm.startPrank(address(router));
        wHlp.mint(recipient, 100e18);
        vm.stopPrank();

        uint256 count = router.pokeCount();
        vm.startPrank(recipient);
        wHlp.transfer(rando, 10e18);
        assertEq(router.pokeCount(), count + 1);
    }

    function test_RouterCanMint() public {
        vm.startPrank(address(router));
        wHlp.mint(recipient, 100e18);
        assertEq(wHlp.balanceOf(recipient), 100e18);
        vm.stopPrank();
    }

    function test_RouterCanBurn() public {
        vm.startPrank(recipient);
        wHlp.approve(address(router), 100e18);

        vm.startPrank(address(router));
        wHlp.mint(recipient, 100e18);
        wHlp.burnFrom(recipient, 100e18);
        assertEq(wHlp.balanceOf(recipient), 0);
    }
}
