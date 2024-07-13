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

/**
 * @title IBlueberryGarden
 * @notice Interface for the main entrypoint for all interactions within Blueberry Finance.
 */
interface IBlueberryMarket {
    /*///////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emit when a user lends assets into the money market.
     * @param asset The underlying asset being lent.
     * @param account The address of the user lending the assets.
     * @param recipient The address of the user receiving the bToken.
     * @param amounts The amount of assets lent.
     * @param shares The number of shares of bToken's minted.
     */
    event Lend(
        address indexed asset,
        address indexed account,
        address indexed recipient,
        uint256 amounts,
        uint256 shares
    );

    /**
     * @notice Emit when a user redeems all their bTokens from the money market.
     * @param asset The underlying asset being withdrawn.
     * @param account The address of the user withdrawing the assets.
     * @param recipient The address of the user receiving the assets.
     * @param amounts The amount of assets withdrawn.
     * @param shares The number of shares of bToken's burned.
     */
    event Redeem(
        address indexed asset,
        address indexed account,
        address indexed recipient,
        uint256 amounts,
        uint256 shares
    );

    /*///////////////////////////////////////////////////////////////
                              Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the associated bToken for a given asset.
     * @param asset The address of the underlying asset for the market.
     * @return bToken The address of the market (bToken).
     */
    function market(address asset) external view returns (address bToken);

    /**
     * @notice Returns the exchange rate of underlying asset to its respective market.
     * @dev Since we dont have interest rates at this stage of development,
     *      bToken shares are 1:1 with assets.
     * @param asset The address of the underlying asset.
     */
    function exchangeRate(address asset) external view returns (uint256);
}
