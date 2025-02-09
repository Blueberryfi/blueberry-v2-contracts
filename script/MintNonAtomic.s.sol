// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {NonAtomicMinter} from "@blueberry-v2/utils/NonAtomicMinter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MintNonAtomicScript is Script {
    NonAtomicMinter public minter;
    IERC20 asset = IERC20(0x1baAbB04529D43a73232B713C0FE471f7c7334d5);

    function setUp() public {
        // Replace with your deployed NonAtomicMinter address
        minter = NonAtomicMinter(0x47a9Bda94082D2402D24AD852814227f2c829BaE);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        asset.approve(address(minter), 5e6);
        minter.deposit(5e6);

        vm.stopBroadcast();
    }
}
