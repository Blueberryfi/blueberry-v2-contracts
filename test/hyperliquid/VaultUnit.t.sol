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
import {HlpHelpers} from "./HlpHelpers.t.sol";

contract VaultUnitTest is HlpHelpers {
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
    address public constant USDC_SYSTEM_ADDRESS = 0x2000000000000000000000000000000000000000;

    function setUp() public override {
        // Set up precompiles
        l1BlockNumberPrecompile = new MockL1BlockNumberPrecompile();
        vm.etch(L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS, address(l1BlockNumberPrecompile).code);
        _updateL1BlockNumber(initialL1BlockNumber);

        vaultEquityPrecompile = new MockVaultEquityPrecompile();
        vm.etch(VAULT_EQUITY_PRECOMPILE_ADDRESS, address(vaultEquityPrecompile).code);

        writePrecompile = new MockWritePrecompile();
        vm.etch(WRITE_PRECOMPILE_ADDRESS, address(writePrecompile).code);

        asset = new MockERC20("USDC", "USDC", 8);

        wrapper = _deploy(address(asset), 0, l1Vault, owner, 7);

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
        assertEq(asset.balanceOf(USDC_SYSTEM_ADDRESS), amount);
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
        assertEq(asset.balanceOf(0x2000000000000000000000000000000000000000), amount * 2);
    }

    function deposit_multiBlock() public {
        uint256 amount = 100e8;

        asset.mint(alice, amount * 2);

        vm.startPrank(alice);
        asset.approve(address(wrapper), amount * 2);
        wrapper.deposit(amount, alice);

        _updateL1BlockNumber(2);
        wrapper.deposit(amount, alice);

        assertEq(wrapper.currentL1BlockDeposits(), amount);
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

        assertEq(wrapper.totalAssets(), 101e8);
        // Second deposit | Bob
        vm.startPrank(bob);
        asset.approve(address(wrapper), amount);
        uint256 expectedShares = wrapper.previewDeposit(amount);
        wrapper.deposit(amount, bob);

        uint256 ownerShares = wrapper.balanceOf(owner);

        assertEq(wrapper.totalAssets(), 201e8);
        assertEq(wrapper.totalSupply(), amount + expectedShares + ownerShares);
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
        vm.warp(block.timestamp + 363 days); // 3 days after 360 days to get to the target redeem escrow

        // 1.5% of 300e8 for 363 days = 4.5375e8
        uint64 fee = 4.5375e8;

        assertEq(wrapper.totalAssets(), 300e8);
        vm.startPrank(alice);
        wrapper.requestRedeem(100e8);
        uint256 aliceAssetsToRedeem = wrapper.previewRedeem(100e8);
        
        uint256 ownerShares = wrapper.balanceOf(owner);
        assertEq(wrapper.convertToAssets(ownerShares), fee);
        assertEq(wrapper.totalSupply(), 100e8 + ownerShares); // We should have decrimented 100e8 from the total supply

        IHyperEvmVault.RedeemRequest memory aliceRequest = wrapper.redeemRequests(alice);

        assertEq(aliceRequest.shares, 100e8);
        assertEq(aliceRequest.assets, aliceAssetsToRedeem);

        // Alices value can be 1 less than the expected value
        assertApproxEqAbs(aliceRequest.assets, 147.73125e8, 1);
        assertLe(aliceRequest.assets, 147.73125e8);

        vm.startPrank(bob);
        wrapper.requestRedeem(100e8);
        uint256 bobAssetsToRedeem = wrapper.previewRedeem(100e8);

        IHyperEvmVault.RedeemRequest memory bobRequest = wrapper.redeemRequests(bob);
        assertEq(bobRequest.shares, 100e8);
        assertEq(bobRequest.assets, bobAssetsToRedeem);
        assertApproxEqAbs(bobRequest.assets, 147.73125e8, 1);
        assertLe(bobRequest.assets, 147.73125e8);

        /// Update escrow and vault state to reflect precompile calls
        vm.startPrank(USDC_SYSTEM_ADDRESS);
        asset.mint(USDC_SYSTEM_ADDRESS, 97.5e8);
        /// MINT REMAINDER OF TOKENS TO BRIDGE
        asset.transfer(address(escrow), 297.5e8); // 295.5e8

        // Update escrow vault equity to just reflect the fee
        _updateVaultEquity(escrow, fee);

        // Redemption requests should decriment the total assets and total supply
        assertEq(wrapper.totalAssets(), wrapper.convertToAssets(ownerShares));
        assertEq(wrapper.totalSupply(), ownerShares);

        vm.startPrank(alice);
        wrapper.redeem(100e8, alice, alice);

        // Validate redeemRequest is cleared
        assertEq(wrapper.redeemRequests(alice).shares, 0);
        assertEq(wrapper.redeemRequests(alice).assets, 0);

        vm.startPrank(bob);
        wrapper.redeem(100e8, bob, bob);

        // Validate redeemRequest is cleared
        assertEq(wrapper.redeemRequests(bob).shares, 0);
        assertEq(wrapper.redeemRequests(bob).assets, 0);

        assertEq(wrapper.balanceOf(alice), 0);
        assertEq(wrapper.balanceOf(bob), 0);
        assertEq(wrapper.totalAssets(), wrapper.convertToAssets(ownerShares));
        assertEq(wrapper.totalSupply(), ownerShares);

        assertApproxEqAbs(asset.balanceOf(alice), 147.73125e8, 1);
        assertApproxEqAbs(asset.balanceOf(bob), 147.73125e8, 1);

        // Validate that the request sum struct has been decremented to 0
        assertEq(wrapper.requestSum().assets, 0);
        assertEq(wrapper.requestSum().shares, 0);
    }

    function test_redeem_inefficient() public {
        uint256 amount = 100e8;

        asset.mint(alice, amount);
        asset.mint(bob, amount);

        vm.startPrank(alice);
        asset.approve(address(wrapper), amount);
        wrapper.deposit(amount, alice);

        uint256 aliceDepositEscrowIndex = wrapper.depositEscrowIndex();

        // Skip 24 hours
        vm.warp(block.timestamp + 24 hours);
        _updateL1BlockNumber(2);
        _updateVaultEquity(wrapper.escrows(aliceDepositEscrowIndex), 100e8);

        vm.startPrank(bob);
        asset.approve(address(wrapper), amount);
        wrapper.deposit(amount, bob);

        uint256 bobDepositEscrowIndex = wrapper.depositEscrowIndex();
        assertNotEq(bobDepositEscrowIndex, aliceDepositEscrowIndex);

        // Skip 24 hours
        vm.warp(block.timestamp + 5 days);
        _updateL1BlockNumber(4);
        _updateVaultEquity(wrapper.escrows(bobDepositEscrowIndex), 100e8);

        assertEq(wrapper.redeemEscrowIndex(), aliceDepositEscrowIndex);

        vm.startPrank(alice);
        wrapper.requestRedeem(amount);

        // Because the redeem escrow only has 100e8 this redeem request should fail
        vm.startPrank(bob);
        vm.expectRevert(BlueberryErrors.INSUFFICIENT_VAULT_EQUITY.selector);
        wrapper.requestRedeem(amount);
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
        uint256 packedData = uint256(scaledEquity) | (block.timestamp + 4 days << 64);
        vm.store(VAULT_EQUITY_PRECOMPILE_ADDRESS, slot, bytes32(packedData));
    }
}
