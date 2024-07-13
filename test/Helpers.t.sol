// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {BlueberryGarden} from "@blueberry-v2/BlueberryGarden.sol";
import {BlueberryGovernor} from "@blueberry-v2/BlueberryGovernor.sol";

import {Events} from "./Events.t.sol";

abstract contract Helpers is Events, Test {
    BlueberryGarden garden;

    address admin = makeAddr("admin");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address rando = makeAddr("rando");

    function setUp() public virtual {
        garden = new BlueberryGarden(admin);
    }
}
