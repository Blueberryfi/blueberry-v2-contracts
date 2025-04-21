// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {HyperVaultRouter} from "../src/vaults/hyperliquid/HyperVaultRouter.sol";
import {HyperliquidEscrow} from "../src/vaults/hyperliquid/HyperliquidEscrow.sol";
import {MintableToken} from "../src/utils/MintableToken.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {LibRLP} from "@solady/utils/LibRLP.sol";

contract DeployRouterTestnet is Script {
    address public constant L1_VAULT = 0xa15099a30BBf2e68942d6F4c43d70D04FAEab0A0;
    address public constant ASSET = 0xd9CBEC81df392A88AEff575E962d149d57F4d6bc;
    address public constant OWNER = 0x263c0a1ff85604f0ee3f4160cAa445d0bad28dF7;

    uint256 escrowCounts = 2;

    address[] public escrows;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);

        //// Deployment steps ////

        // 1. Deploy Share Token & Mock Asset
        MintableToken shareToken = new MintableToken("Wrapped HLP", "wHLP", 18, deployer);

        MockERC20 asset = new MockERC20("Dumbass Memecoin", "DAMEME", 6);

        // 2. Deploy the VaultEscrow via the Beacon Proxy Pattern
        // 2(a). Compute the expected address of the vault wrapper
        address expectedRouter = LibRLP.computeAddress(deployer, vm.getNonce(deployer) + 3 + escrowCounts);

        // 2(b). Deploy Escrow Implementation Contract
        address escrowImplementation = address(
            new HyperliquidEscrow(
                L1_VAULT, // L1 Vault
                expectedRouter // vault router address
            )
        );

        // 1(c). Deploy the Beacon and set the Implementation & Owner
        UpgradeableBeacon beacon = new UpgradeableBeacon(escrowImplementation, OWNER);
        console.log("Beacon deployed at", address(beacon));

        // 1(d). Deploy all escrow proxies
        for (uint256 i = 0; i < escrowCounts; i++) {
            address escrowProxy = address(
                new BeaconProxy(
                    address(beacon), abi.encodeWithSelector(HyperliquidEscrow.initialize.selector, deployer)
                )
            );
            escrows.push(escrowProxy);
        }

        // 2. Deploy the HyperVaultRouter via the UUPS Proxy Pattern
        // 2(a). Deploy the Implementation Contract
        address implementation = address(new HyperVaultRouter(L1_VAULT, address(shareToken)));
        console.log("Implementation deployed at", address(implementation));

        // 2(b). Deploy the Proxy Contract
        HyperVaultRouter vault = HyperVaultRouter(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(
                        HyperVaultRouter.initialize.selector,
                        escrows,
                        10e18, // Min Deposit Amount
                        OWNER // Owner
                    )
                )
            )
        );

        require(address(vault) == expectedRouter, "Vault address mismatch");

        console.log("Vault Proxy deployed at", address(vault));

        console.log("Escrow 0", address(vault.escrows(0)));
        console.log("Escrow 1", address(vault.escrows(1)));
    }
}
