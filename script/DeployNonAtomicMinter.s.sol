// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {NonAtomicMinter} from "@blueberry-v2/utils/NonAtomicMinter.sol";

contract DeployNonAtomicMinterScript is Script {
    // PLEASE SET THESE VALUES BEFORE RUNNING THE SCRIPT
    address public constant UNDERLYING = 0x0000000000000000000000000000000000000000;
    address public constant RECEIPT_TOKEN = 0x0000000000000000000000000000000000000000;

    address public constant ADMIN = 0x0000000000000000000000000000000000000000;
    address public constant UPGRADER = 0x0000000000000000000000000000000000000000;
    address public constant PROCESSOR = 0x0000000000000000000000000000000000000000;
    address public constant MINTER = 0x0000000000000000000000000000000000000000;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);

        // Validate the inputs
        require(UNDERLYING != address(0), "UNDERLYING is not set");
        require(RECEIPT_TOKEN != address(0), "RECEIPT_TOKEN is not set");
        require(ADMIN != address(0), "ADMIN is not set");

        // Deploy a UUPS upgradeable contract
        address implementation = address(new NonAtomicMinter(address(UNDERLYING), address(RECEIPT_TOKEN)));
        NonAtomicMinter nonAtomicMinter = NonAtomicMinter(
            address(new ERC1967Proxy(implementation, abi.encodeCall(NonAtomicMinter.initialize, (deployer))))
        );

        console.log("NonAtomicMinter Proxy deployed at:", address(nonAtomicMinter));
        console.log("NonAtomicMinter Implementation deployed at:", implementation);

        // Grant all the roles if they are not set to 0x0
        if (UPGRADER != address(0)) {
            nonAtomicMinter.grantRole(nonAtomicMinter.UPGRADE_ROLE(), UPGRADER);
        }

        if (PROCESSOR != address(0)) {
            nonAtomicMinter.grantRole(nonAtomicMinter.PROCESSOR_ROLE(), PROCESSOR);
        }

        if (MINTER != address(0)) {
            nonAtomicMinter.grantRole(nonAtomicMinter.MINTER_ROLE(), MINTER);
        }

        // Set the new admin role and renounce the old one if the ADMIN is different from the deployer.
        if (ADMIN != deployer) {
            nonAtomicMinter.grantRole(nonAtomicMinter.DEFAULT_ADMIN_ROLE(), ADMIN);
            nonAtomicMinter.renounceRole(nonAtomicMinter.DEFAULT_ADMIN_ROLE(), deployer);
        }

        vm.stopBroadcast();
    }
}
