// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {VaultEscrow} from "../src/vaults/hyperliquid/VaultEscrow.sol"; // Ensure this path points to the *NEW* VaultEscrow code
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UpdateVaultEscrow is Script {
    // --- Configuration ---
    // !!! MUST BE UPDATED with your deployed addresses !!!
    address public constant EXISTING_BEACON_ADDRESS = 0x13dEA73688C595041FD0bD7617f1629eAbcD7Df5; // <--- Replace with the actual Beacon address
    address public constant HYPER_EVM_VAULT_PROXY = 0x182a1E1d7Ee2DEC6331cDF6a668BdD85D9Ad86CE; // <--- Replace with the actual Vault Proxy address

    // Constants used during original deployment - needed if constructor sets immutables
    // Ensure these match the original deployment environment if required by the *new* implementation's constructor
    address public constant L1_VAULT = 0xa15099a30BBf2e68942d6F4c43d70D04FAEab0A0; // Or your specific L1 Vault
    address public constant ASSET = 0xd9CBEC81df392A88AEff575E962d149d57F4d6bc; // Or your specific Asset
    address public constant OWNER = 0x263c0a1ff85604f0ee3f4160cAa445d0bad28dF7; // The address that OWNS the Beacon and can upgrade it

    // Constants from VaultEscrow constructor (assuming they are needed for deployment)
    uint256 public constant ASSET_INDEX = 0;
    uint8 public constant ASSET_PERP_DECIMALS = 6;
    // --- End Configuration ---

    function run() public {
        // Input validation
        require(EXISTING_BEACON_ADDRESS != address(0), "UpdateVaultEscrow: EXISTING_BEACON_ADDRESS cannot be zero address. Please configure the script.");
        require(HYPER_EVM_VAULT_PROXY != address(0), "UpdateVaultEscrow: HYPER_EVM_VAULT_PROXY cannot be zero address. Please configure the script.");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        require(deployerPrivateKey != 0, "UpdateVaultEscrow: PRIVATE_KEY environment variable not set.");

        address upgrader = vm.addr(deployerPrivateKey);

        // Verify the private key corresponds to the expected owner address
        // This assumes the OWNER constant holds the address that owns the beacon.
        require(upgrader == OWNER, "UpdateVaultEscrow: The provided PRIVATE_KEY does not correspond to the expected OWNER address configured in the script.");

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
        VaultEscrow newEscrowImplementation = new VaultEscrow(
            HYPER_EVM_VAULT_PROXY, // Existing vault wrapper address
            L1_VAULT,             // L1 Vault address
            ASSET,                // Asset address
            uint64(ASSET_INDEX),          // Asset Index
            ASSET_PERP_DECIMALS   // Asset Perp Decimals
        );

        address newImplementationAddress = address(newEscrowImplementation);
        console.log("New VaultEscrow implementation deployed at:", newImplementationAddress);

        require(newImplementationAddress != address(0), "UpdateVaultEscrow: Failed to deploy new implementation.");
        require(newImplementationAddress != currentImplementation, "UpdateVaultEscrow: New implementation address is the same as the old one. Did you forget to update the code?");

        // 2. Upgrade the Beacon to point to the new implementation.
        //    This transaction MUST be sent by the current owner of the Beacon (checked above).
        console.log("Calling upgradeTo on Beacon", address(beacon), "to set implementation to", newImplementationAddress);
        beacon.upgradeTo(newImplementationAddress);
        console.log("Beacon upgrade transaction broadcasted.");

        // Stop transaction broadcast
        vm.stopBroadcast();

        // Verification (reads state *after* broadcast simulation or execution)
        address finalImplementation = beacon.implementation();
        console.log("Verifying implementation address in Beacon post-upgrade...");
        console.log("Final Implementation in Beacon:", finalImplementation);

        require(finalImplementation == newImplementationAddress, "UpdateVaultEscrow: Beacon implementation address did NOT update correctly after broadcast!");

        console.log("VaultEscrow implementation successfully updated for Beacon:", EXISTING_BEACON_ADDRESS);
        console.log("All VaultEscrow proxies pointing to this beacon will now use the new implementation at:", newImplementationAddress);
    }
}