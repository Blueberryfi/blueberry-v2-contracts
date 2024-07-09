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
     * @notice Check the role of an address.
     * @param account The address of the account to check.
     * @return role The role of the account in bytes32.
     */
    function role(address account) external view returns (bytes32);

    /// @notice The FULL_ACCESS role. Which can perform any action within the BlueberryGovernor.
    function fullAccess() external pure returns (bytes32);
}
