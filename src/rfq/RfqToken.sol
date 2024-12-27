// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {AccessControlDefaultAdminRules} from "@openzeppelin/access/extensions/AccessControlDefaultAdminRules.sol";
import {ERC20, IERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title Token
 * @notice A basic flat token with minting and burning capabilities.
 */
contract RfqToken is AccessControlDefaultAdminRules, ERC20, ERC20Burnable, ERC20Permit {
    /// @notice Bytes32 representation of the minter role.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(string memory name, string memory symbol, address asset, address admin)
        AccessControlDefaultAdminRules(2 days, admin)
        ERC20(name, symbol)
        ERC20Permit(name)
    {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Mints tokens to a specified address.
     * @dev Only users with an approved MINTER_ROLE can call this function.
     * @param to The address to mint tokens to.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }
}
