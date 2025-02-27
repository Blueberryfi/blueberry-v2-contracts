// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20, ERC20} from "../mocks/MockERC20.sol";
import {HyperEvmVault} from "../../src/vaults/hyperliquid/HyperEvmVault.sol";
import {VaultEscrow} from "../../src/vaults/hyperliquid/VaultEscrow.sol";
import {BlueberryErrors} from "../../src/helpers/BlueberryErrors.sol";
import {
    MockWritePrecompile,
    MockL1BlockNumberPrecompile,
    MockVaultEquityPrecompile
} from "../mocks/MockHyperliquidPrecompiles.sol";

contract VaultUnitTest is Test {
    HyperEvmVault public wrapper;
    MockERC20 public asset;
    address public l1Vault = makeAddr("L1 Vault");

    address public alice = makeAddr("Alice");
    address public bob = makeAddr("Bob");
    address public random = makeAddr("Random");
    address public owner = makeAddr("Owner");

    MockWritePrecompile public writePrecompile;
    MockL1BlockNumberPrecompile public l1BlockNumberPrecompile;
    MockVaultEquityPrecompile public vaultEquityPrecompile;

    address public constant L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000809;
    uint64 initialL1BlockNumber = 1;

    address public constant VAULT_EQUITY_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000802;
    address public constant WRITE_PRECOMPILE_ADDRESS = 0x3333333333333333333333333333333333333333;
    address public constant HYPERLIQUID_SPOT_BRIDGE = 0x2222222222222222222222222222222222222222;

    function setUp() public {
        // Set up precompiles
        l1BlockNumberPrecompile = new MockL1BlockNumberPrecompile();
        vm.etch(L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS, address(l1BlockNumberPrecompile).code);
        l1BlockNumberPrecompile.setL1BlockNumber(initialL1BlockNumber);

        vaultEquityPrecompile = new MockVaultEquityPrecompile();
        vm.etch(VAULT_EQUITY_PRECOMPILE_ADDRESS, address(vaultEquityPrecompile).code);

        writePrecompile = new MockWritePrecompile();
        vm.etch(WRITE_PRECOMPILE_ADDRESS, address(writePrecompile).code);

        asset = new MockERC20("USDC", "USDC", 6);

        wrapper = new HyperEvmVault("wHLP", "Wrapped HLP", 7, ERC20(address(asset)), 0, 8, l1Vault, owner);
    }

    function test_deposit() public {
        uint256 amount = 100e6;

        asset.mint(alice, amount);

        vm.startPrank(alice);
        asset.approve(address(wrapper), amount);
        wrapper.deposit(amount, alice);

        assertEq(wrapper.balanceOf(alice), amount);
        assertEq(wrapper.totalAssets(), amount);
        assertEq(wrapper.totalSupply(), amount);

        uint256 escrowIndex = wrapper.depositEscrowIndex();
        VaultEscrow escrow = VaultEscrow(wrapper.escrows(escrowIndex));

        assertEq(asset.balanceOf(address(escrow)), 0);
        assertEq(asset.balanceOf(address(wrapper)), 0);
        assertEq(asset.balanceOf(HYPERLIQUID_SPOT_BRIDGE), amount);
    }

    function test_mint() public {
        uint256 amount = 100e6;

        asset.mint(alice, amount);
        asset.mint(bob, amount);

        vm.startPrank(alice);
        asset.approve(address(wrapper), amount);
        wrapper.deposit(amount, alice);

        uint256 expectedShares = wrapper.previewMint(amount);

        vm.startPrank(bob);
        asset.approve(address(wrapper), amount);
        wrapper.mint(expectedShares, bob);

        assertEq(wrapper.balanceOf(bob), expectedShares);
        assertEq(wrapper.totalAssets(), amount * 2);
        assertEq(wrapper.totalSupply(), amount * 2);

        uint256 escrowIndex = wrapper.depositEscrowIndex();
        VaultEscrow escrow = VaultEscrow(wrapper.escrows(escrowIndex));

        assertEq(asset.balanceOf(address(escrow)), 0);
        assertEq(asset.balanceOf(address(wrapper)), 0);
        assertEq(asset.balanceOf(HYPERLIQUID_SPOT_BRIDGE), amount * 2);
    }
}
