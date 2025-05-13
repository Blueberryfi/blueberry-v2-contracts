// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {HyperVaultRouter} from "../src/vaults/hyperliquid/HyperVaultRouter.sol";
import {HyperliquidEscrow} from "../src/vaults/hyperliquid/HyperliquidEscrow.sol";
import {MintableToken} from "../src/utils/MintableToken.sol";
import {WrappedVaultShare} from "../src/vaults/hyperliquid/WrappedVaultShare.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {LibRLP} from "@solady/utils/LibRLP.sol";

contract DeployRouterTestnet is Script {
    address public constant L1_VAULT = 0xa15099a30BBf2e68942d6F4c43d70D04FAEab0A0;
    address public constant ASSET = 0xd9CBEC81df392A88AEff575E962d149d57F4d6bc;
    address public constant OWNER = 0x263c0a1ff85604f0ee3f4160cAa445d0bad28dF7;

    // Testnet assets to support
    address public constant PURR = 0xa9056c15938f9aff34CD497c722Ce33dB0C2fD57;
    uint32 public constant PURR_INDEX = 1;

    address public constant LIQUIDITY_ADMIN = 0x263c0a1ff85604f0ee3f4160cAa445d0bad28dF7;

    uint256 escrowCounts = 2;

    address[] public escrows;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);
        require(deployer == OWNER, "Deployer must match OWNER");

        // //// Deployment steps ////

        // 1. Compute the expected address of the vault wrapper
        address expectedRouter = LibRLP.computeAddress(deployer, vm.getNonce(deployer) + 4 + escrowCounts);

        // 2. Deploy Share Token & Mock Asset
        WrappedVaultShare shareToken = new WrappedVaultShare("Wrapped HLP", "wHLP", expectedRouter, deployer);
        console.log("wHLP deployed at", address(shareToken));

        // 3. Deploy the HyperliquidEscrow via the Beacon Proxy Pattern
        // 3(a). Deploy Escrow Implementation Contract
        address escrowImplementation = address(
            new HyperliquidEscrow(
                L1_VAULT, // L1 Vault
                expectedRouter // vault router address
            )
        );

        // 3(b). Deploy the Beacon and set the Implementation & Owner
        UpgradeableBeacon beacon = new UpgradeableBeacon(escrowImplementation, OWNER);
        console.log("Beacon deployed at", address(beacon));

        // 3(c). Deploy all escrow proxies
        require(LIQUIDITY_ADMIN != address(0), "Liquidity admin role cannot be zero");
        for (uint256 i = 0; i < escrowCounts; i++) {
            address escrowProxy = address(
                new BeaconProxy(
                    address(beacon), abi.encodeWithSelector(HyperliquidEscrow.initialize.selector, deployer)
                )
            );
            escrows.push(escrowProxy);

            bytes32 role = keccak256("LIQUIDITY_ADMIN_ROLE");
            HyperliquidEscrow(escrowProxy).grantRole(role, LIQUIDITY_ADMIN);
        }

        // 4. Deploy the HyperVaultRouter via the UUPS Proxy Pattern
        // 4(a). Deploy the Implementation Contract
        address implementation = address(new HyperVaultRouter(address(shareToken)));
        console.log("Implementation deployed at", address(implementation));

        // 4(b). Deploy the Proxy Contract
        HyperVaultRouter router = HyperVaultRouter(
            address(
                new TransparentUpgradeableProxy(
                    implementation,
                    OWNER,
                    abi.encodeWithSelector(
                        HyperVaultRouter.initialize.selector,
                        escrows,
                        10e18, // Min Deposit Amount
                        OWNER // Owner
                    )
                )
            )
        );

        require(address(router) == expectedRouter, "Router address mismatch");

        //ERC20(PURR).approve(address(router), type(uint256).max);

        console.log("Router Proxy deployed at", address(router));

        console.log("Escrow 0", address(router.escrows(0)));
        console.log("Escrow 1", address(router.escrows(1)));
    }
}
