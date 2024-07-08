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

import {IBlueberryMarket} from "./IBlueberryMarket.sol";
import {IERC4626MultiToken} from "./IERC4626MultiToken.sol";

/**
 * @title IBlueberryGarden
 * @notice Interface for the main entrypoint for all interactions within Blueberry Finance.
 */
interface IBlueberryGarden is IBlueberryMarket, IERC4626MultiToken {
    /**
     * @notice Lend into the Blueberry Money Market
     * @param asset The underlying asset to lend into the money market
     * @param onBehalfOf User address, if the lend action is taken
     *        on behalf of another user. Note that only a valid bToken can do this.
     * @param receiver The recipient of the bToken that gets minted.
     * @param amount The amount of underlying asset to lend
     * @return shares The number of bToken shares minted for the receiver.
     */
    function lend(
        address asset,
        address onBehalfOf,
        address receiver,
        uint256 amount
    ) external returns (uint256 shares);

    /**
     * @notice Redeems the market's bToken, therefor removing the deposited underlying asset.
     * @param bToken The bToken that we are redeeming underlying assets from.
     * @param onBehalfOf User address, if the lend action is taken
     *        on behalf of another user. Note that only a valid bToken can do this.
     * @param receiver The recipient of the underlying tokens.
     * @param shares The amount of bTokens to redeem.
     * @return amount The number of underlying assets returned to the receiver.
     */
    function redeem(
        address bToken,
        address onBehalfOf,
        address receiver,
        uint256 shares
    ) external returns (uint256 amount);
}
