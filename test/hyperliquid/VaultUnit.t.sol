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
        _updateL1BlockNumber(initialL1BlockNumber);

        vaultEquityPrecompile = new MockVaultEquityPrecompile();
        vm.etch(VAULT_EQUITY_PRECOMPILE_ADDRESS, address(vaultEquityPrecompile).code);

        writePrecompile = new MockWritePrecompile();
        vm.etch(WRITE_PRECOMPILE_ADDRESS, address(writePrecompile).code);

        asset = new MockERC20("USDC", "USDC", 6);

        wrapper = new HyperEvmVault("wHLP", "Wrapped HLP", 7, ERC20(address(asset)), 0, 8, l1Vault, 10e6, owner);
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

        uint256 expectedShares = wrapper.previewDeposit(amount);

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

    function deposit_multiBlock() public {
        uint256 amount = 100e6;

        asset.mint(alice, amount * 2);

        vm.startPrank(alice);
        asset.approve(address(wrapper), amount * 2);
        wrapper.deposit(amount, alice);

        _updateL1BlockNumber(2);
        wrapper.deposit(amount, alice);

        assertEq(wrapper.currentBlockDeposits(), amount);
        assertEq(wrapper.lastL1Block(), 1);
        assertEq(wrapper.totalAssets(), amount * 2);
        assertEq(wrapper.totalSupply(), amount * 2);
        assertEq(wrapper.balanceOf(alice), amount * 2);
    }

    function test_yield_acrual() public {
        uint256 amount = 100e6;

        asset.mint(alice, amount);
        asset.mint(bob, amount);

        vm.startPrank(alice);
        asset.approve(address(wrapper), amount);
        wrapper.deposit(amount, alice);

        address escrow = wrapper.escrows(wrapper.depositEscrowIndex());
        _updateL1BlockNumber(2);
        _updateVaultEquity(escrow, 101e6);
        vm.roll(2);

        assertEq(wrapper.totalAssets(), 101e6);
        assertEq(wrapper.totalSupply(), 100e6);
        assertEq(wrapper.balanceOf(alice), 100e6);

        assertEq(wrapper.convertToAssets(100e6), 101e6);
        assertEq(wrapper.convertToShares(101e6), 100e6);

        // Skip 1/4 year
        uint256 quarterYear = 90 days;
        vm.warp(block.number + quarterYear);

        uint256 fee = 101e6 * 150 * quarterYear / 10000 / 360 days;

        // Second deposit | Bob
        vm.startPrank(bob);
        asset.approve(address(wrapper), amount);
        uint256 expectedShares = wrapper.previewDeposit(amount);
        wrapper.deposit(amount, bob);

        assertEq(wrapper.totalAssets(), 201e6 - fee);
        assertEq(wrapper.totalSupply(), amount + expectedShares);
        assertEq(wrapper.balanceOf(bob), expectedShares);

        assertApproxEqAbs(wrapper.convertToAssets(expectedShares), amount, 1);
    }

    function test_redeem() public {
        asset.mint(alice, 100e6);
        asset.mint(bob, 100e6);

        vm.startPrank(alice);
        asset.approve(address(wrapper), 100e6);
        wrapper.deposit(100e6, alice);

        vm.startPrank(bob);
        asset.approve(address(wrapper), 100e6);
        wrapper.deposit(100e6, bob);

        _updateL1BlockNumber(2);
        address escrow = wrapper.escrows(wrapper.depositEscrowIndex());
        // 50% yield 200e6 -> 300e6
        _updateVaultEquity(escrow, 300e6);
        vm.warp(block.timestamp + 360 days);

        // 1.5% of 300e6 = 4.5e6
        uint64 fee = 4.5e6;

        assertEq(wrapper.previewFeeTake(300e6), fee);
        assertEq(wrapper.totalAssets(), 295.5e6);
        assertEq(wrapper.totalSupply(), 200e6);

        vm.startPrank(alice);
        wrapper.requestRedeem(100e6);
        uint256 aliceAssetsToRedeem = wrapper.previewRedeem(100e6);

        (uint64 aliceAssets, uint256 aliceShares) = wrapper.redeemRequests(alice);
        assertEq(aliceShares, 100e6);
        assertEq(aliceAssets, aliceAssetsToRedeem);
        assertEq(aliceAssets, 147.75e6);

        vm.startPrank(bob);
        wrapper.requestRedeem(100e6);
        uint256 bobAssetsToRedeem = wrapper.previewRedeem(100e6);

        (uint64 bobAssets, uint256 bobShares) = wrapper.redeemRequests(bob);
        assertEq(bobShares, 100e6);
        assertEq(bobAssets, bobAssetsToRedeem);
        assertEq(bobAssets, 147.75e6);

        /// Update escrow and vault state to reflect precompile calls
        vm.startPrank(HYPERLIQUID_SPOT_BRIDGE);
        asset.mint(HYPERLIQUID_SPOT_BRIDGE, 95.5e6);
        /// MINT REMAINDER OF TOKENS TO BRIDGE
        asset.transfer(address(escrow), 295.5e6);

        // Update escrow vault equity to just reflect the fee
        _updateVaultEquity(escrow, fee);

        vm.startPrank(alice);
        wrapper.redeem(100e6, alice, alice);

        vm.startPrank(bob);
        wrapper.redeem(100e6, bob, bob);

        assertEq(wrapper.balanceOf(alice), 0);
        assertEq(wrapper.balanceOf(bob), 0);
        assertEq(wrapper.totalAssets(), 0);
        assertEq(wrapper.totalSupply(), 0);

        assertEq(asset.balanceOf(alice), 147.75e6);
        assertEq(asset.balanceOf(bob), 147.75e6);
    }

    function _updateL1BlockNumber(uint64 blockNumber_) internal {
        vm.store(L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS, bytes32(uint256(0)), bytes32(uint256(blockNumber_)));
    }

    function _updateVaultEquity(address escrow_, uint64 equity_) internal {
        bytes32 slot = keccak256(abi.encode(escrow_, 0));
        vm.store(VAULT_EQUITY_PRECOMPILE_ADDRESS, slot, bytes32(uint256(equity_)));
    }
}
