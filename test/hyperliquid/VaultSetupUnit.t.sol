// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20, ERC20} from "../mocks/MockERC20.sol";
import {HyperEvmVault} from "../../src/vaults/hyperliquid/HyperEvmVault.sol";
import {VaultEscrow} from "../../src/vaults/hyperliquid/VaultEscrow.sol";
import {BlueberryErrors} from "../../src/helpers/BlueberryErrors.sol";
import {MockL1BlockNumberPrecompile} from "../mocks/MockHyperliquidPrecompiles.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract VaultSetupUnitTest is Test {
    HyperEvmVault public vault;
    MockERC20 public asset;
    address public owner;
    address public l1Vault;

    event EscrowDeployed(address indexed escrow);

    MockL1BlockNumberPrecompile public l1BlockNumberPrecompile;
    uint64 public initialL1BlockNumber = 1;

    address public constant L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000809;

    function setUp() public {
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
        address implementation = address(new HyperEvmVault(l1Vault));
        vault = HyperEvmVault(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(
                        HyperEvmVault.initialize.selector, "Wrapped HLP", "wHLP", address(asset), 0, 8, 10e8, 7, owner
                    )
                )
            )
        );

        assertEq(vault.name(), "Wrapped HLP");
        assertEq(vault.symbol(), "wHLP");
        assertEq(address(vault.asset()), address(asset));
        // assertEq(vault.assetIndex(), 0);
        // assertEq(vault.assetPerpDecimals(), 8);
        assertEq(vault.L1_VAULT(), l1Vault);
        assertEq(vault.owner(), owner);
    }

    function test_RevertInitializer_ZeroL1Vault() public {
        vm.expectRevert(abi.encodeWithSignature("ADDRESS_ZERO()"));
        address implementation = address(new HyperEvmVault(address(0)));
    }

    function test_EscrowDeployment() public {
        uint8 escrowCount = 3;

        // Expect EscrowDeployed events
        for (uint8 i = 0; i < escrowCount; i++) {
            vm.expectEmit(false, false, false, false);
            emit EscrowDeployed(address(0)); // Ignore the address
        }

        address implementation = address(new HyperEvmVault(l1Vault));
        vault = HyperEvmVault(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(
                        HyperEvmVault.initialize.selector,
                        "Wrapped HLP",
                        "wHLP",
                        address(asset),
                        0,
                        8,
                        10e8,
                        escrowCount,
                        owner
                    )
                )
            )
        );
    }

    function test_OwnershipTransfer() public {
        address implementation = address(new HyperEvmVault(l1Vault));
        vault = HyperEvmVault(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(
                        HyperEvmVault.initialize.selector, "Wrapped HLP", "wHLP", address(asset), 0, 8, 10e8, 7, owner
                    )
                )
            )
        );

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
        address implementation = address(new HyperEvmVault(l1Vault));
        vault = HyperEvmVault(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(
                        HyperEvmVault.initialize.selector, "Wrapped HLP", "wHLP", address(asset), 0, 8, 10e8, 7, owner
                    )
                )
            )
        );

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

    function _updateL1BlockNumber(uint64 blockNumber_) internal {
        vm.store(L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS, bytes32(uint256(0)), bytes32(uint256(blockNumber_)));
    }
}
