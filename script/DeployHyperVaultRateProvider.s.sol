// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {HyperVaultRateProvider} from "../src/vaults/hyperliquid/HyperVaultRateProvider.sol";

contract DeployHyperVaultRateProvider is Script {
    // bbHLP HyperEvm Mainnet Token Address
    address public constant TOKEN = 0x4bB19336C973506B9405Db586b7AEE302a7CbCFc;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the HyperVaultRateProvider contract
        HyperVaultRateProvider rateProvider = new HyperVaultRateProvider(TOKEN);
        console.log("Rate Provider deployed at:", address(rateProvider));
    }
}
