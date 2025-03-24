// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {HyperEvmVault} from "../src/vaults/hyperliquid/HyperEvmVault.sol";
import {VaultEscrow} from "../src/vaults/hyperliquid/VaultEscrow.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {LibRLP} from "@solady/utils/LibRLP.sol";

contract DeployTestnet is Script {
    address public constant L1_VAULT = 0xa15099a30BBf2e68942d6F4c43d70D04FAEab0A0;
    address public constant ASSET = 0xd9CBEC81df392A88AEff575E962d149d57F4d6bc;
    address public constant OWNER = 0x263c0a1ff85604f0ee3f4160cAa445d0bad28dF7;

    uint256 escrowCounts = 7;

    address[] public escrows;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);

        //// Deployment steps ////

        // 1. Deploy the VaultEscrow via the Beacon Proxy Pattern
        // 1(a). Compute the expected address of the vault wrapper
        address expectedWrapperAddr = LibRLP.computeAddress(deployer, vm.getNonce(deployer) + 3 + escrowCounts);

        // 1(b). Deploy Escrow Implementation Contract
        address escrowImplementation = address(new VaultEscrow(
            expectedWrapperAddr, // vault wrapper address
            L1_VAULT, // L1 Vault
            ASSET, // Asset
            0, // Asset Index
            6// Asset Perp Decimals
        ));

        // 1(c). Deploy the Beacon and set the Implementation & Owner
        UpgradeableBeacon beacon = new UpgradeableBeacon(escrowImplementation, OWNER);
        console.log("Beacon deployed at", address(beacon));

        // 1(d). Deploy all escrow proxies
        for (uint256 i = 0; i < escrowCounts; i++) {
            address escrowProxy = address(new BeaconProxy(address(beacon), abi.encodeWithSelector(VaultEscrow.initialize.selector, i)));
            escrows.push(escrowProxy);
        }

        // 2. Deploy the HyperEvmVault via the UUPS Proxy Pattern
        // 2(a). Deploy the Implementation Contract
        address implementation = address(new HyperEvmVault(L1_VAULT));
        console.log("Implementation deployed at", address(implementation));

        // 2(b). Deploy the Proxy Contract
        HyperEvmVault vault = HyperEvmVault(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(
                        HyperEvmVault.initialize.selector,
                        "Wrapped HLP",
                        "wHLP",
                        ASSET,
                        escrows,
                        10e8, // Min Deposit Amount
                        OWNER // Owner
                    )
                )
            )
        );

        require(address(vault) == expectedWrapperAddr, "Vault address mismatch");

        console.log("Vault Proxy deployed at", address(vault));

        console.log("Escrow 0", address(vault.escrows(0)));
        console.log("Escrow 1", address(vault.escrows(1)));
        console.log("Escrow 2", address(vault.escrows(2)));
        console.log("Escrow 3", address(vault.escrows(3)));
        console.log("Escrow 4", address(vault.escrows(4)));
        console.log("Escrow 5", address(vault.escrows(5)));
        console.log("Escrow 6", address(vault.escrows(6)));
    }
}
