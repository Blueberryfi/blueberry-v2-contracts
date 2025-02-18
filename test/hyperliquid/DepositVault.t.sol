// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {DepositVault} from "../../src/vaults/hyperliquid/DepositVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DepositVaultTest is Test {
    DepositVault public depositVault;
    MockERC20 public asset;

    function setUp() public {
        asset = new MockERC20("Test USDC", "USDC", 6);
        depositVault = new DepositVault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(depositVault),
            address(this),
            abi.encodeWithSelector(
                DepositVault.initialize.selector,
                address(asset)
            )
        );
        depositVault = DepositVault(address(proxy));
    }

    function testFuzz_Deposit(uint256 amount) public {
        amount = bound(amount, 1, 10000000000000e6);
        asset.mint(address(this), amount);
        asset.approve(address(depositVault), amount);
        depositVault.deposit(amount);
        assertEq(depositVault.balanceOf(address(this)), amount);
        uint256 balance = asset.balanceOf(address(depositVault));
        assertEq(balance, amount);
    }
}
