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

import {BBErrors as Errors} from "@blueberry-v2/helpers/BBErrors.sol";
import {BlueberryMarket} from "@blueberry-v2/money-market/BlueberryMarket.sol";
import {BToken} from "@blueberry-v2/money-market/BToken.sol";

import {IBlueberryGarden} from "@blueberry-v2/interfaces/IBlueberryGarden.sol";
import {IBlueberryGovernor} from "@blueberry-v2/interfaces/IBlueberryGovernor.sol";
import "forge-std/console2.sol";

/**
 * @title BlueberryGovernor
 * @notice Contract containing permissioned setters for the Blueberry Protocol.
 */
contract BlueberryGovernor is IBlueberryGovernor, BlueberryMarket {
    /*///////////////////////////////////////////////////////////////
                                Storage
    //////////////////////////////////////////////////////////////*/

    /// @notice A mapping of addresses to their respective roles.
    mapping(address => bytes32) private _roles;

    /*///////////////////////////////////////////////////////////////
                                Admin Roles
    //////////////////////////////////////////////////////////////*/

    /// @notice Full access role. Can perform any action within the BlueberryGovernor.
    bytes32 private constant _FULL_ACCESS = keccak256("FULL_ACCESS");

    /*///////////////////////////////////////////////////////////////
                                Modifiers
    //////////////////////////////////////////////////////////////*/

    /// @notice Ensure that the caller has a specific role.
    modifier hasRole(bytes32 role_) {
        require(role(msg.sender) == role_, Errors.UNAUTHORIZED());
        _;
    }

    /*///////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address admin) {
        require(admin != address(0), Errors.ADDRESS_ZERO());
        _roles[admin] = _FULL_ACCESS;
        emit RoleSet(admin, _FULL_ACCESS);
    }

    /*///////////////////////////////////////////////////////////////
                         Governance Setters
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBlueberryGovernor
    function addMarket(
        address asset,
        string memory name,
        string memory symbol
    ) external hasRole(fullAccess()) returns (address bToken) {
        require(_bTokens[asset] == address(0), Errors.MARKET_ALREADY_EXISTS());
        require(asset != address(0), Errors.ADDRESS_ZERO());

        bToken = address(
            new BToken(IBlueberryGarden(address(this)), asset, name, symbol)
        );
        _bTokens[asset] = bToken;
        _assets[bToken] = asset;
        // TODO: Think about caching token decimals
        emit NewMarket(asset, name, symbol);
    }

    /// @inheritdoc IBlueberryGovernor
    function setRole(
        address account,
        bytes32 role_
    ) external hasRole(fullAccess()) {
        require(account != address(0), Errors.ADDRESS_ZERO());
        _roles[account] = role_;
        emit RoleSet(account, role_);
    }

    /*///////////////////////////////////////////////////////////////
                                Roles
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBlueberryGovernor
    function role(address account) public view returns (bytes32) {
        return _roles[account];
    }

    /// @inheritdoc IBlueberryGovernor
    function fullAccess() public pure returns (bytes32) {
        return _FULL_ACCESS;
    }
}
