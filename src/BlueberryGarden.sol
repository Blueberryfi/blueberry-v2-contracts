// SPDX-License-Identifier: BUSL-1.1
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/
pragma solidity ^0.8.26;

import {IBlueberryGarden} from "@blueberry-v2/interfaces/IBlueberryGarden.sol";
import {BlueberryMarket} from "@blueberry-v2/money-market/BlueberryMarket.sol";

/**
 * @title BlueberryGarden
 * @notice The main entrypoint for all interactions within Blueberry Finance.
 */
contract BlueberryGarden is IBlueberryGarden, BlueberryMarket {
    /// @inheritdoc IBlueberryGarden
    function lend(
        address asset,
        address onBehalfOf,
        address receiver,
        uint256 amount
    ) external override returns (uint256) {
        return _lend(asset, onBehalfOf, receiver, amount);
    }

    /// @inheritdoc IBlueberryGarden
    function redeem(
        address bToken,
        address onBehalfOf,
        address receiver,
        uint256 shares
    ) external override returns (uint256) {
        return _redeem(bToken, onBehalfOf, receiver, shares);
    }
}
