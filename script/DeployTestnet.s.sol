// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {HyperEvmVault} from "../src/vaults/hyperliquid/HyperEvmVault.sol";
import {VaultEscrow} from "../src/vaults/hyperliquid/VaultEscrow.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployTestnet is Script {
    address public constant L1_VAULT = 0xa15099a30BBf2e68942d6F4c43d70D04FAEab0A0;
    address public constant ASSET = 0xd9CBEC81df392A88AEff575E962d149d57F4d6bc;
    address public constant OWNER = 0x263c0a1ff85604f0ee3f4160cAa445d0bad28dF7;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address implementation = address(new HyperEvmVault(L1_VAULT));
        console.log("Implementation deployed at", address(implementation));
        HyperEvmVault vault = HyperEvmVault(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(
                        HyperEvmVault.initialize.selector,
                        "Wrapped HLP",
                        "wHLP",
                        ASSET,
                        0, // Asset Index
                        6, // Asset Perp Decimals
                        10e8, // Min Deposit Amount
                        7, // Number of escrows
                        OWNER // Owner
                    )
                )
            )
        );

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
