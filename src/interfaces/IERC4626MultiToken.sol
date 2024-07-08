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
 * @title IERC4626MultiToken
 * @notice Interface for the multi-token accounting functionality for the Blueberry Money Market.
 */
interface IERC4626MultiToken {
    /**
     *
     * @param bToken Address of the bToken that will be transfered.
     * @param owner Address of the owner for the bToken.
     * @param spender Address of the account spending the owners bToken's.
     * @param amount Amount of bToken's that the user is approving to be spent.
     * @return True if the call is successful
     */
    function approve(
        address bToken,
        address owner,
        address spender,
        uint256 amount
    ) external returns (bool);

    /**
     * @notice Transfers bToken from one account to another.
     * @param bToken Address of the bToken being transfered.
     * @param to The address of the recipient of the bToken.
     * @param amount Amount of bToken to transfer.
     * @return True if the call is successful
     */
    function transfer(
        address bToken,
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    /**
     * @notice Transfers bToken's from one specified account to another.
     * @param bToken Address of the bToken being transfered.
     * @param spender The account that will be spending the bToken.
     * @param from The origin account of the token transfer.
     * @param to The address of the recipient of the bToken.
     * @param amount The amount of bToken's being transfered.
     * @return True if the call is successful
     */
    function transferFrom(
        address bToken,
        address spender,
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    /**
     * @notice Get the associated underlying asset for a give market/bToken
     * @param bToken The address of the target bToken.
     * @return token The address of the underlying asset for a given market/bToken
     */
    function asset(address bToken) external view returns (address token);

    /**
     * @notice Returns the total underlying assets under management.
     * @param asset_ The address of the underlying asset.
     */
    function totalAssets(address asset_) external view returns (uint256);

    /**
     * @notice Returns the total supply of a bToken
     * @param bToken The address of the target bToken.
     */
    function totalSupply(address bToken) external view returns (uint256);

    /**
     * @notice Returns the bToken balance for a given account.
     * @param bToken The address of the target bToken.
     * @param account The address of the account being queried.
     */
    function balanceOf(
        address bToken,
        address account
    ) external view returns (uint256);

    /**
     * @notice The spending allowance for a given users bToken.
     * @param bToken The address of the target bToken.
     * @param owner The address of the account's allowance that is being checked.
     * @param spender The address of the account spending the bToken.
     */
    function allowance(
        address bToken,
        address owner,
        address spender
    ) external view returns (uint256);
}
