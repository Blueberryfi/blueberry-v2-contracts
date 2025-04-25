// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {HyperVaultRouter} from "../src/vaults/hyperliquid/HyperVaultRouter.sol";

// Minimal interface for the ProxyAdmin contract
interface IProxyAdmin {
    function upgrade(address proxy, address implementation) external;

    function getProxyImplementation(address proxy) external view returns (address);

    function owner() external view returns (address);
}

contract UpgradeRouterScript is Script {
    bytes32 internal constant EIP1967_ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);

    address constant ROUTER_PROXY_ADDRESS = 0x1921B49134eb53D6eac58abFd12A47f5Dbd8b5b7;

    address constant L1_VAULT_ADDRESS = 0xa15099a30BBf2e68942d6F4c43d70D04FAEab0A0;

    address constant SHARE_TOKEN_ADDRESS = 0xAe37f27C009725237369c334bC14d755Bc2a97d3;

    function run() public {
        require(
            ROUTER_PROXY_ADDRESS != address(0),
            "UpgradeRouter: ROUTER_PROXY_ADDRESS cannot be zero address. Please configure the script."
        );

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        require(deployerPrivateKey != 0, "UpgradeRouter: PRIVATE_KEY environment variable not set.");

        // Start transaction broadcast
        vm.startBroadcast(deployerPrivateKey);

        HyperVaultRouter router = new HyperVaultRouter(SHARE_TOKEN_ADDRESS);

        // Use vm.load to read the storage slot of the external proxyAddress
        bytes32 slotValue = vm.load(ROUTER_PROXY_ADDRESS, EIP1967_ADMIN_SLOT);

        // Convert the bytes32 value to an address (lower 20 bytes)
        address adminAddress = address(uint160(uint256(slotValue)));
        IProxyAdmin proxyAdmin = IProxyAdmin(adminAddress);

        proxyAdmin.upgrade(ROUTER_PROXY_ADDRESS, address(router));

        vm.stopBroadcast();
    }

    function getAdminAddress() internal view returns (address adminAddress) {
        bytes32 slot = EIP1967_ADMIN_SLOT;
        assembly {
            // Load the 32-byte value from storage at the position specified by 'slot'
            let slotValue := sload(slot)
            // Addresses are 20 bytes (160 bits). They are stored right-aligned in the 32-byte slot.
            // Mask the lower 160 bits to isolate the address.
            // 0xffffffffffffffffffffffffffffffffffffffff is a 160-bit mask (20 bytes of 1s)
            adminAddress := and(slotValue, 0xffffffffffffffffffffffffffffffffffffffff)

            // Alternative using bit shift (shr(offset, value)):
            // Shifts 'slotValue' right by 96 bits (32 bytes * 8 bits/byte - 20 bytes * 8 bits/byte = 96 bits)
            // Effectively zeroing out the upper 12 bytes and leaving the lower 20 bytes (the address).
            // adminAddress := shr(96, slotValue)
        }
    }
}
