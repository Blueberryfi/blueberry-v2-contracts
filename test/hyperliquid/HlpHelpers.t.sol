// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/test.sol";
import {MockERC20, ERC20} from "../mocks/MockERC20.sol";
import {HyperEvmVault} from "../../src/vaults/hyperliquid/HyperEvmVault.sol";
import {VaultEscrow} from "../../src/vaults/hyperliquid/VaultEscrow.sol";
import {BlueberryErrors} from "../../src/helpers/BlueberryErrors.sol";
import {MockL1BlockNumberPrecompile} from "../mocks/MockHyperliquidPrecompiles.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LibRLP} from "@solady/utils/LibRLP.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract HlpHelpers is Test {
    
    function setUp() public virtual {

    }

    function _deploy(address asset, uint64 assetIndex, address l1Vault, address deployer, uint256 escrowCounts) internal returns (HyperEvmVault wrapper) {
        address[] memory escrows = new address[](escrowCounts);
        vm.startPrank(deployer);

        //// Deployment steps ////
        
        // 1. Deploy the VaultEscrow via the Beacon Proxy Pattern
        // 1(a). Compute the expected address of the vault wrapper
        address expectedWrapperAddr = LibRLP.computeAddress(deployer, vm.getNonce(deployer) + 3 + escrowCounts);

        // 1(b). Deploy Escrow Implementation Contract
        address escrowImplementation = address(new VaultEscrow(
            expectedWrapperAddr, // vault wrapper address
            l1Vault, // L1 Vault
            asset, // Asset
            assetIndex, // Asset Index
            6// Asset Perp Decimals
        ));

        // 1(c). Deploy the Beacon and set the Implementation & Owner
        UpgradeableBeacon beacon = new UpgradeableBeacon(escrowImplementation, deployer);

        // 1(d). Deploy all escrow proxies
        for (uint256 i = 0; i < escrowCounts; i++) {
            address escrowProxy = address(new BeaconProxy(address(beacon), abi.encodeWithSelector(VaultEscrow.initialize.selector, i)));
            escrows[i] = escrowProxy;
        }

        // 2. Deploy the HyperEvmVault via the UUPS Proxy Pattern
        // 2(a). Deploy the Implementation Contract
        address implementation = address(new HyperEvmVault(l1Vault));

        // 2(b). Deploy the Proxy Contract
        HyperEvmVault vault = HyperEvmVault(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(
                        HyperEvmVault.initialize.selector,
                        "Wrapped HLP",
                        "wHLP",
                        asset,
                        escrows,
                        10e8, // Min Deposit Amount
                        deployer // Owner
                    )
                )
            )
        );

        vm.stopPrank();

        require(address(vault) == expectedWrapperAddr, "Vault address mismatch");
        return vault;
    }
}