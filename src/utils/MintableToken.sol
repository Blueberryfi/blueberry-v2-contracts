// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";

/**
 * @title MintableToken
 * @notice An ERC20 token with minting and burning capabilities, protected by role-based access control
 */
contract MintableToken is ERC20, ERC20Burnable, AccessControl, ERC20Permit {
    /*//////////////////////////////////////////////////////////////
                            Constants & Immutables
    //////////////////////////////////////////////////////////////*/

    /// @notice The MINTER_ROLE will be able to freely mint tokens as they see fit
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice The BURNER_ROLE will be able to burn tokens from any address
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /// @notice The number of decimals the token uses
    uint8 private immutable _decimals;

    /*//////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(string memory name, string memory symbol, uint8 decimals_, address admin)
        ERC20(name, symbol)
        ERC20Permit(name)
    {
        _decimals = decimals_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /*//////////////////////////////////////////////////////////////
                                Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints new tokens to a specific address
     * @dev Only addresses with MINTER_ROLE can mint tokens
     * @param to Address receiving the minted tokens
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        require(to != address(0), Errors.ADDRESS_ZERO());
        _mint(to, amount);
    }

    /**
     * @notice Burns tokens from a specific address
     * @dev Only addresses with BURNER_ROLE can burn tokens
     * @param from Address whose tokens will be burned
     * @param amount Amount of tokens to burn
     */
    function burnFrom(address from, uint256 amount) public override onlyRole(BURNER_ROLE) {
        super.burnFrom(from, amount);
    }

    /**
     * @notice Allows token holders to burn their own tokens
     * @dev Overrides ERC20Burnable's burn to add role check to prevent people from burning their own tokens
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) public override onlyRole(BURNER_ROLE) {
        super.burn(amount);
    }

    /// @inheritdoc ERC20
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
