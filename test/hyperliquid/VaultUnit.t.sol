// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20, ERC20} from "../mocks/MockERC20.sol";
import {HyperEvmVault, IHyperEvmVault} from "../../src/vaults/hyperliquid/HyperEvmVault.sol";
import {VaultEscrow} from "../../src/vaults/hyperliquid/VaultEscrow.sol";
import {BlueberryErrors} from "../../src/helpers/BlueberryErrors.sol";
import {
    MockWritePrecompile,
    MockL1BlockNumberPrecompile,
    MockVaultEquityPrecompile
} from "../mocks/MockHyperliquidPrecompiles.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

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

        asset = new MockERC20("USDC", "USDC", 8);

        address implementation = address(new HyperEvmVault(l1Vault));
        wrapper = HyperEvmVault(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(
                        HyperEvmVault.initialize.selector, "Wrapped HLP", "wHLP", address(asset), 0, 6, 10e8, 7, owner
                    )
                )
            )
        );

        vm.startPrank(owner);
        wrapper.setManagementFeeBps(150); // 1.5%
    }

    function test_deposit() public {
        uint256 amount = 100e8;

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
        uint256 amount = 100e8;

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
        uint256 amount = 100e8;

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
        uint256 amount = 100e8;

        asset.mint(alice, amount);
        asset.mint(bob, amount);

        vm.startPrank(alice);
        asset.approve(address(wrapper), amount);
        wrapper.deposit(amount, alice);

        address escrow = wrapper.escrows(wrapper.depositEscrowIndex());
        _updateL1BlockNumber(2);
        _updateVaultEquity(escrow, 101e8);
        vm.roll(2);

        assertEq(wrapper.totalAssets(), 101e8);
        assertEq(wrapper.totalSupply(), 100e8);
        assertEq(wrapper.balanceOf(alice), 100e8);

        assertEq(wrapper.convertToAssets(100e8), 101e8);
        assertEq(wrapper.convertToShares(101e8), 100e8);

        // Skip 1/4 year
        uint256 quarterYear = 90 days;
        vm.warp(block.number + quarterYear - 1);
        uint256 fee = 101e8 * 150 * (quarterYear) / 10000 / 360 days;

        assertEq(wrapper.totalAssets(), 101e8 - fee);
        // Second deposit | Bob
        vm.startPrank(bob);
        asset.approve(address(wrapper), amount);
        uint256 expectedShares = wrapper.previewDeposit(amount);
        wrapper.deposit(amount, bob);

        assertEq(wrapper.totalAssets(), 201e8 - fee);
        assertEq(wrapper.totalSupply(), amount + expectedShares);
        assertEq(wrapper.balanceOf(bob), expectedShares);

        assertApproxEqAbs(wrapper.convertToAssets(expectedShares), amount, 1);
    }

    function test_redeem() public {
        asset.mint(alice, 100e8);
        asset.mint(bob, 100e8);

        vm.startPrank(alice);
        asset.approve(address(wrapper), 100e8);
        wrapper.deposit(100e8, alice);

        vm.startPrank(bob);
        asset.approve(address(wrapper), 100e8);
        wrapper.deposit(100e8, bob);

        _updateL1BlockNumber(2);
        address escrow = wrapper.escrows(wrapper.depositEscrowIndex());
        // 50% yield 200e8 -> 300e8
        _updateVaultEquity(escrow, 300e8);
        vm.warp(block.timestamp + 360 days);

        // 1.5% of 300e8 = 4.5e8
        uint64 fee = 4.5e8;

        assertEq(wrapper.totalAssets(), 295.5e8);
        assertEq(wrapper.totalSupply(), 200e8);

        vm.startPrank(alice);
        wrapper.requestRedeem(100e8);
        uint256 aliceAssetsToRedeem = wrapper.previewRedeem(100e8);

        IHyperEvmVault.RedeemRequest memory aliceRequest = wrapper.redeemRequests(alice);
        assertEq(aliceRequest.shares, 100e8);
        assertEq(aliceRequest.assets, aliceAssetsToRedeem);
        assertEq(aliceRequest.assets, 147.75e8);

        vm.startPrank(bob);
        wrapper.requestRedeem(100e8);
        uint256 bobAssetsToRedeem = wrapper.previewRedeem(100e8);

        IHyperEvmVault.RedeemRequest memory bobRequest = wrapper.redeemRequests(bob);
        assertEq(bobRequest.shares, 100e8);
        assertEq(bobRequest.assets, bobAssetsToRedeem);
        assertEq(bobRequest.assets, 147.75e8);

        /// Update escrow and vault state to reflect precompile calls
        vm.startPrank(HYPERLIQUID_SPOT_BRIDGE);
        asset.mint(HYPERLIQUID_SPOT_BRIDGE, 95.5e8);
        /// MINT REMAINDER OF TOKENS TO BRIDGE
        asset.transfer(address(escrow), 295.5e8);

        // Update escrow vault equity to just reflect the fee
        _updateVaultEquity(escrow, fee);

        vm.startPrank(alice);
        wrapper.redeem(100e8, alice, alice);

        vm.startPrank(bob);
        wrapper.redeem(100e8, bob, bob);

        assertEq(wrapper.balanceOf(alice), 0);
        assertEq(wrapper.balanceOf(bob), 0);
        assertEq(wrapper.totalAssets(), 0);
        assertEq(wrapper.totalSupply(), 0);

        assertEq(asset.balanceOf(alice), 147.75e8);
        assertEq(asset.balanceOf(bob), 147.75e8);
    }

    function _updateL1BlockNumber(uint64 blockNumber_) internal {
        vm.store(L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS, bytes32(uint256(0)), bytes32(uint256(blockNumber_)));
    }

    function _updateVaultEquity(address escrow_, uint64 equity_) internal {
        bytes32 slot = keccak256(abi.encode(escrow_, 0));
        // scale to perps decimals
        uint256 perpDecimals = VaultEscrow(escrow_).assetPerpDecimals();
        uint256 assetDecimals = VaultEscrow(escrow_).assetDecimals();
        uint256 scaledEquity = perpDecimals > assetDecimals
            ? equity_ * 10 ** (perpDecimals - assetDecimals)
            : equity_ / 10 ** (assetDecimals - perpDecimals);

        vm.store(VAULT_EQUITY_PRECOMPILE_ADDRESS, slot, bytes32(uint256(scaledEquity)));
    }
}
