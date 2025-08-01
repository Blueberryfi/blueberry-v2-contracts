// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20, ERC20} from "../../mocks/MockERC20.sol";
import {HyperEvmVault} from "@blueberry-v2/vaults/hyperliquid/deprecated/HyperEvmVault.sol";
import {VaultEscrow} from "@blueberry-v2/vaults/hyperliquid/deprecated/VaultEscrow.sol";
import {BlueberryErrors} from "@blueberry-v2/helpers/BlueberryErrors.sol";
import {MockL1BlockNumberPrecompile} from "../../mocks/MockHyperliquidPrecompiles.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LibRLP} from "@solady/utils/LibRLP.sol";
import {HlpHelpers} from "./HlpHelpers.t.sol";

contract VaultSetupUnitTest is HlpHelpers {
    HyperEvmVault public vault;
    MockERC20 public asset;
    address public owner;
    address public l1Vault;

    event EscrowDeployed(address indexed escrow);

    MockL1BlockNumberPrecompile public l1BlockNumberPrecompile;
    uint64 public initialL1BlockNumber = 1;

    address public constant L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000809;

    function setUp() public override {
        vm.createSelectFork("https://rpc.hyperliquid-testnet.xyz/evm");

        owner = makeAddr("owner");
        l1Vault = makeAddr("l1Vault");

        // Deploy mock asset
        asset = new MockERC20("Test USDC", "USDC", 6);

        l1BlockNumberPrecompile = new MockL1BlockNumberPrecompile();
        vm.etch(L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS, address(l1BlockNumberPrecompile).code);
        _updateL1BlockNumber(initialL1BlockNumber);
    }

    /*//////////////////////////////////////////////////////////////
                            Setup Tests
    //////////////////////////////////////////////////////////////*/

    function test_Initializer() public {
        vault = _deploy(address(asset), 0, l1Vault, owner, 7);

        assertEq(vault.name(), "Wrapped HLP");
        assertEq(vault.symbol(), "wHLP");
        assertEq(address(vault.asset()), address(asset));
        assertEq(vault.L1_VAULT(), l1Vault);
        assertEq(vault.owner(), owner);
    }

    function test_OwnershipTransfer() public {
        vault = _deploy(address(asset), 0, l1Vault, owner, 7);

        address newOwner = makeAddr("newOwner");

        // Transfer ownership
        vm.prank(owner);
        vault.transferOwnership(newOwner);

        // Accept ownership
        vm.prank(newOwner);
        vault.acceptOwnership();

        assertEq(vault.owner(), newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                            Deposit Tests
    //////////////////////////////////////////////////////////////*/

    function test_IndexCalculation() public {
        vault = _deploy(address(asset), 0, l1Vault, owner, 7);

        uint256 initialTimestamp = 1740645825;
        // Sets the block timestamp to make current Index == 0
        vm.warp(initialTimestamp);

        assertEq(vault.depositEscrowIndex(), 0);
        assertEq(vault.redeemEscrowIndex(), 1);

        vm.warp(initialTimestamp + 1 days);
        assertEq(vault.depositEscrowIndex(), 1);
        assertEq(vault.redeemEscrowIndex(), 2);

        vm.warp(initialTimestamp + 2 days);
        assertEq(vault.depositEscrowIndex(), 2);
        assertEq(vault.redeemEscrowIndex(), 3);

        vm.warp(initialTimestamp + 3 days);
        assertEq(vault.depositEscrowIndex(), 3);
        assertEq(vault.redeemEscrowIndex(), 4);

        vm.warp(initialTimestamp + 4 days);
        assertEq(vault.depositEscrowIndex(), 4);
        assertEq(vault.redeemEscrowIndex(), 5);

        vm.warp(initialTimestamp + 5 days);
        assertEq(vault.depositEscrowIndex(), 5);
        assertEq(vault.redeemEscrowIndex(), 6);

        vm.warp(initialTimestamp + 6 days);
        assertEq(vault.depositEscrowIndex(), 6);
        assertEq(vault.redeemEscrowIndex(), 0);

        vm.warp(initialTimestamp + 7 days);
        assertEq(vault.depositEscrowIndex(), 0);
        assertEq(vault.redeemEscrowIndex(), 1);
    }

    function test_AssetSystemAddr() public {
        /// System address for asset index 0
        vault = _deploy(address(asset), 0, l1Vault, owner, 7);

        VaultEscrow escrow = VaultEscrow(vault.escrows(vault.depositEscrowIndex()));
        assertEq(escrow.assetSystemAddr(), address(0x2000000000000000000000000000000000000000));

        /// System address for asset index  200
        vault = _deploy(address(asset), 200, l1Vault, owner, 7);
        escrow = VaultEscrow(vault.escrows(vault.depositEscrowIndex()));
        assertEq(escrow.assetSystemAddr(), address(0x20000000000000000000000000000000000000C8));
    }

    function _updateL1BlockNumber(uint64 blockNumber_) internal {
        vm.store(L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS, bytes32(uint256(0)), bytes32(uint256(blockNumber_)));
    }
}
