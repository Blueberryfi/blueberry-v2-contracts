// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {HyperliquidEscrow} from "../src/vaults/hyperliquid/HyperliquidEscrow.sol"; // Ensure this path points to the *NEW* VaultEscrow code
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UpgradeProxy is Script {
    // --- Configuration ---
    // !!! MUST BE UPDATED with your deployed addresses !!!
    address public constant EXISTING_BEACON_ADDRESS = 0x912E16E7CACCB08a5004EbEE4BBfCf168DD2B76E; // <--- Replace with the actual Beacon address
    address public constant HYPERLIQUID_ROUTER_PROXY = 0x1921B49134eb53D6eac58abFd12A47f5Dbd8b5b7; // <--- Replace with the actual Vault Proxy address

    // Constants used during original deployment - needed if constructor sets immutables
    // Ensure these match the original deployment environment if required by the *new* implementation's constructor
    address public constant L1_VAULT = 0xa15099a30BBf2e68942d6F4c43d70D04FAEab0A0; // Or your specific L1 Vault
    address public constant OWNER = 0x263c0a1ff85604f0ee3f4160cAa445d0bad28dF7; // The address that OWNS the Beacon and can upgrade it

    // --- End Configuration ---

    function run() public {
        // Input validation
        require(
            EXISTING_BEACON_ADDRESS != address(0),
            "UpdateVaultEscrow: EXISTING_BEACON_ADDRESS cannot be zero address. Please configure the script."
        );
        require(
            HYPERLIQUID_ROUTER_PROXY != address(0),
            "UpdateVaultEscrow: HYPER_EVM_VAULT_PROXY cannot be zero address. Please configure the script."
        );

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        require(deployerPrivateKey != 0, "UpdateVaultEscrow: PRIVATE_KEY environment variable not set.");

        address upgrader = vm.addr(deployerPrivateKey);

        // Verify the private key corresponds to the expected owner address
        // This assumes the OWNER constant holds the address that owns the beacon.
        require(
            upgrader == OWNER,
            "UpdateVaultEscrow: The provided PRIVATE_KEY does not correspond to the expected OWNER address configured in the script."
        );

        // Get reference to the existing beacon
        UpgradeableBeacon beacon = UpgradeableBeacon(EXISTING_BEACON_ADDRESS);
        address currentImplementation = beacon.implementation();
        console.log("Target Beacon:", EXISTING_BEACON_ADDRESS);
        console.log("Beacon Owner (expected):", OWNER);
        console.log("Upgrader Address (from PRIVATE_KEY):", upgrader);
        console.log("Current VaultEscrow Implementation:", currentImplementation);

        // Start transaction broadcast
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying NEW VaultEscrow implementation contract...");

        // 1. Deploy the NEW implementation contract.
        //    NOTE: Ensure the VaultEscrow source code being compiled is the *UPDATED* version.
        //    We pass the arguments required by the constructor. If the constructor sets
        //    immutable variables, these *must* be correct for the intended environment.
        //    If the constructor is empty or doesn't set critical state used post-upgrade,
        //    these might be placeholder values, but it's safer to provide the real ones.
        HyperliquidEscrow newEscrowImplementation = new HyperliquidEscrow(
            L1_VAULT, // L1 Vault address
            HYPERLIQUID_ROUTER_PROXY // Existing vault wrapper address
        );

        address newImplementationAddress = address(newEscrowImplementation);
        console.log("New VaultEscrow implementation deployed at:", newImplementationAddress);

        require(newImplementationAddress != address(0), "UpdateVaultEscrow: Failed to deploy new implementation.");
        require(
            newImplementationAddress != currentImplementation,
            "UpdateVaultEscrow: New implementation address is the same as the old one. Did you forget to update the code?"
        );

        // 2. Upgrade the Beacon to point to the new implementation.
        //    This transaction MUST be sent by the current owner of the Beacon (checked above).
        console.log(
            "Calling upgradeTo on Beacon", address(beacon), "to set implementation to", newImplementationAddress
        );
        beacon.upgradeTo(newImplementationAddress);
        console.log("Beacon upgrade transaction broadcasted.");

        // Stop transaction broadcast
        vm.stopBroadcast();

        // Verification (reads state *after* broadcast simulation or execution)
        address finalImplementation = beacon.implementation();
        console.log("Verifying implementation address in Beacon post-upgrade...");
        console.log("Final Implementation in Beacon:", finalImplementation);

        require(
            finalImplementation == newImplementationAddress,
            "UpdateVaultEscrow: Beacon implementation address did NOT update correctly after broadcast!"
        );

        console.log("VaultEscrow implementation successfully updated for Beacon:", EXISTING_BEACON_ADDRESS);
        console.log(
            "All VaultEscrow proxies pointing to this beacon will now use the new implementation at:",
            newImplementationAddress
        );
    }
}
