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
interface IBlueberryGovernor {
    /*///////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emits when a new market is added.
     * @param asset The underlying asset for the market.
     * @param name The bToken's name.
     * @param symbol The bToken's symbol.
     */
    event NewMarket(address indexed asset, string name, string symbol);

    /**
     * @notice Emits when a role is set for an account.
     * @param account The account that the role is being set for.
     * @param role_ The role being given to the account.
     */
    event RoleSet(address indexed account, bytes32 indexed role_);

    /*///////////////////////////////////////////////////////////////
                         Governance Setters
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a new market to the Blueberry Money Market.
     * @dev This function is only callable by a full access admin.
     * @param asset The address of the underlying asset for the new market.
     * @param name The name of the new market. (e.g. "Blueberry Wrapped Ether")
     * @param symbol The symbol of the new market. (e.g. "bWETH")
     * @return bToken The address of the newly created bToken.
     */
    function addMarket(
        address asset,
        string memory name,
        string memory symbol
    ) external returns (address);

    /**
     * @notice Sets the role for a given account.
     * @param account The account that the role is being set for.
     * @param role_ The role being given to the account.
     */
    function setRole(address account, bytes32 role_) external;

    /*///////////////////////////////////////////////////////////////
                                Roles
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check the role of an address.
     * @param account The address of the account to check.
     * @return role The role of the account in bytes32.
     */
    function role(address account) external view returns (bytes32);

    /// @notice The FULL_ACCESS role. Which can perform any action within the BlueberryGovernor.
    function fullAccess() external pure returns (bytes32);
}
