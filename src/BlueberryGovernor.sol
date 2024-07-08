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

/**
 * @title BlueberryGovernor
 * @notice Contract containing permissioned setters for the Blueberry Protocol.
 */
contract BlueberryGovernor is IBlueberryGovernor, BlueberryMarket {
    /*///////////////////////////////////////////////////////////////
                                Admin Roles
    //////////////////////////////////////////////////////////////*/

    /// @notice A mapping of addresses to their respective roles.
    mapping(address => bytes32) private _roles;

    /*///////////////////////////////////////////////////////////////
                                Admin Roles
    //////////////////////////////////////////////////////////////*/

    /// @notice Full access role. Can perform any action within the BlueberryGovernor.
    bytes32 public constant FULL_ACCESS = "FULL_ACCESS";

    /*///////////////////////////////////////////////////////////////
                                Modifiers
    //////////////////////////////////////////////////////////////*/

    /// @notice Ensure that the caller has a specific role.
    modifier hasRole(bytes32 role_) {
        require(role(msg.sender) != role_, Errors.UNAUTHORIZED());
        _;
    }

    /*///////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address admin) {
        _roles[admin] = FULL_ACCESS;
    }

    /*///////////////////////////////////////////////////////////////
                        Governance Setters
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBlueberryGovernor
    function addMarket(
        address asset,
        string memory name,
        string memory symbol
    ) external hasRole(FULL_ACCESS) returns (address bToken) {
        require(_bTokens[asset] == address(0), Errors.MARKET_ALREADY_EXISTS());
        bToken = address(
            new BToken(IBlueberryGarden(address(this)), asset, name, symbol)
        );
        _bTokens[asset] = bToken;
        _assets[bToken] = asset;
    }

    /// @inheritdoc IBlueberryGovernor
    function role(address account) public view returns (bytes32) {
        return _roles[account];
    }
}
