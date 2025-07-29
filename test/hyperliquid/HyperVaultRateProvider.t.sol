// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {WrappedVaultShare} from "@blueberry-v2/vaults/hyperliquid/WrappedVaultShare.sol";
import {HyperVaultRateProvider} from "@blueberry-v2/vaults/hyperliquid/HyperVaultRateProvider.sol";

contract MockRouter {
    uint256 public tvl;

    function setTvl(uint256 _tvl) external {
        tvl = _tvl;
    }
}

contract HyperVaultRateProviderTest is Test {
    WrappedVaultShare public wHlp;
    MockRouter public router;
    HyperVaultRateProvider public rateProvider;

    function setUp() public virtual {
        router = new MockRouter();
        wHlp = new WrappedVaultShare("Wrapped HLP", "wHLP", address(router), address(1));
        rateProvider = new HyperVaultRateProvider(address(wHlp));
    }

    function test_Constructor() public view {
        assertEq(rateProvider.TOKEN(), address(wHlp));
        assertEq(rateProvider.ROUTER(), address(router));
    }

    function test_getRate() public {
        // No TVL or total supply, should return 1e18
        assertEq(rateProvider.getRate(), 1e18);

        // Rate 1e18 when TVL is 100e18 and total supply is 100e18
        router.setTvl(100e18);

        vm.startPrank(address(router));
        wHlp.mint(address(this), 100e18);

        assertEq(rateProvider.getRate(), 1e18);

        // Rate 2e18 when TVL is 200e18 and total supply is 100e18
        router.setTvl(200e18);
        assertEq(rateProvider.getRate(), 2e18);

        // Rate 0.5e18 when TVL is 100e18 and total supply is 200e18
        wHlp.mint(address(this), 100e18); // Total supply is now 200e18
        router.setTvl(100e18);
        assertEq(rateProvider.getRate(), 0.5e18);
        assertEq(wHlp.totalSupply(), 200e18);

        // Rate is .1e18 when TVL is 20e18 and total supply is 200e18
        router.setTvl(20e18);
        assertEq(rateProvider.getRate(), 0.1e18);
    }
}
