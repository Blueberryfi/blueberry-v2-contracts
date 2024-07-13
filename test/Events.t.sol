// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

abstract contract Events {
    /*///////////////////////////////////////////////////////////////
                                Governor
    //////////////////////////////////////////////////////////////*/

    event NewMarket(address indexed asset, string name, string symbol);

    event RoleSet(address indexed account, bytes32 indexed role_);
}
