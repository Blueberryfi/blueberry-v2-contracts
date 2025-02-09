// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {MintableToken} from "@blueberry-v2/utils/MintableToken.sol";

contract DeployMintableTokenScript is Script {
    // PLEASE SET THESE VALUES BEFORE RUNNING THE SCRIPT
    string public constant NAME = "Blueberry wrapped HLP";
    string public constant SYMBOL = "blHLP";
    uint8 public constant DECIMALS = 6;

    address public constant ADMIN = 0x263c0a1ff85604f0ee3f4160cAa445d0bad28dF7;
    address public constant MINTER = 0x263c0a1ff85604f0ee3f4160cAa445d0bad28dF7;
    address public constant BURNER = 0x263c0a1ff85604f0ee3f4160cAa445d0bad28dF7;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);

        // Validate the inputs
        require(bytes(NAME).length != 0, "NAME is not set");
        require(bytes(SYMBOL).length != 0, "SYMBOL is not set");
        require(DECIMALS != 0, "DECIMALS is not set");
        require(ADMIN != address(0), "ADMIN is not set");

        // Deploy a UUPS upgradeable contract
        MintableToken token = new MintableToken(NAME, SYMBOL, DECIMALS, ADMIN);
        console.log("Token deployed at:", address(token));

        // Grant all the roles if they are not set to 0x0
        if (MINTER != address(0)) {
            token.grantRole(token.MINTER_ROLE(), MINTER);
        }

        if (BURNER != address(0)) {
            token.grantRole(token.BURNER_ROLE(), BURNER);
        }

        // Set the new admin role and renounce the old one if the ADMIN is different from the deployer.
        if (ADMIN != deployer) {
            token.grantRole(token.DEFAULT_ADMIN_ROLE(), ADMIN);
            token.renounceRole(token.DEFAULT_ADMIN_ROLE(), deployer);
        }

        vm.stopBroadcast();
    }
}
