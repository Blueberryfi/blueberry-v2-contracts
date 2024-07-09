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

import {IERC4626MultiToken} from "@blueberry-v2/interfaces/IERC4626MultiToken.sol";
import {BToken} from "./BToken.sol";

/**
 * @title ERC4626MultiToken
 * @notice Simplified multi-token contract that allows bToken accounting to be abstracted out
 *         into a single contract. This creates more efficient interaction with the Blueberry
 *         money market, while still creating a composable system through ERC4626 complient
 *         receipt tokens.
 */
abstract contract ERC4626MultiToken is IERC4626MultiToken {
    /*///////////////////////////////////////////////////////////////
                                Storage
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps underlying assets to a given bToken.
    mapping(address => address) internal _bTokens;

    /// @notice Maps a bToken to its underlying asset.
    mapping(address => address) internal _assets;

    /// @notice Maps a bToken to its totalSupply.
    mapping(address => uint256) internal _totalSupply;

    /// @notice Maps an underlying asset to its current balance in the money market.
    mapping(address => uint256) internal _totalAssets;

    /// @notice Maps a user's address to their balance's of a specific bToken.
    mapping(address => mapping(address => uint256)) internal _balance;

    /// @notice Maps a user's address to their allowance of a specific bToken (owner -> spender -> allowance).
    mapping(address => mapping(address => mapping(address => uint256)))
        internal _allowances;

    /*///////////////////////////////////////////////////////////////
                          Valid bToken
    //////////////////////////////////////////////////////////////*/
    modifier validMarket(address bToken) {
        require(_bTokens[bToken] != address(0), Errors.INVALID_MARKET());
        _;
    }

    /*///////////////////////////////////////////////////////////////
                          Minting & Burning
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints bToken's for lenders depositing into the money market
     * @param bToken The address of the bToken that will be minted
     * @param recipient The address of the recipient of the bToken
     * @param shares The number of bToken shares that will be minted
     */
    function _mint(address bToken, address recipient, uint256 shares) internal {
        _totalSupply[bToken] += shares;

        // Overflow cannot occur because totalSupply is capped at max uint256
        //   and totalSupply is always greater than or equal to a users balance.
        unchecked {
            _balance[bToken][recipient] += shares;
        }

        BToken(bToken).emitTransfer(address(0), recipient, shares);
    }

    /**
     * @notice Burns bToken's for lenders withdrawing their capital from the
     *         money market.
     * @param bToken The address of the bToken that will be burned.
     * @param account The address that the bToken;s will be burned from.
     * @param shares The number of bToken shares that will be burned.
     */
    function _burn(address bToken, address account, uint256 shares) internal {
        _balance[bToken][account] -= shares;

        // Underflow cannot occur because a users balance will always be
        //     less than or equal to total supply.
        unchecked {
            _totalSupply[bToken] -= shares;
        }

        BToken(bToken).emitTransfer(account, address(0), shares);
    }

    /*///////////////////////////////////////////////////////////////
                            ERC20 Accounting
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC4626MultiToken
    function approve(
        address bToken,
        address owner,
        address spender,
        uint256 amount
    ) public override validMarket(bToken) returns (bool) {
        require(
            owner != address(0) && spender != address(0),
            Errors.ADDRESS_ZERO()
        );

        _allowances[bToken][owner][spender] = amount;

        BToken(bToken).emitApproval(owner, spender, amount);

        return true;
    }

    /// @inheritdoc IERC4626MultiToken
    function transfer(
        address bToken,
        address from,
        address to,
        uint256 amount
    ) external override validMarket(bToken) returns (bool) {
        return _transfer(bToken, from, to, amount);
    }

    /// @inheritdoc IERC4626MultiToken
    function transferFrom(
        address bToken,
        address spender,
        address from,
        address to,
        uint256 amount
    ) external override validMarket(bToken) returns (bool) {
        _spendAllowance(bToken, from, spender, amount);
        return _transfer(bToken, from, to, amount);
    }

    /// @inheritdoc IERC4626MultiToken
    function totalSupply(address bToken) external view returns (uint256) {
        return _totalSupply[bToken];
    }

    /// @inheritdoc IERC4626MultiToken
    function balanceOf(
        address bToken,
        address account
    ) external view returns (uint256) {
        return _balance[bToken][account];
    }

    /// @inheritdoc IERC4626MultiToken
    function allowance(
        address bToken,
        address owner,
        address spender
    ) public view returns (uint256) {
        return _allowances[bToken][owner][spender];
    }

    /*///////////////////////////////////////////////////////////////
                          ERC4626 Token Info
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC4626MultiToken
    function asset(
        address bToken
    ) public view override returns (address token) {
        token = _assets[bToken];
        require(token != address(0), Errors.INVALID_MARKET());
    }

    /// @inheritdoc IERC4626MultiToken
    function totalAssets(
        address asset_
    ) public view override returns (uint256) {
        return _totalAssets[asset_];
    }

    /*///////////////////////////////////////////////////////////////
                          Internal Helpers
    //////////////////////////////////////////////////////////////*/

    /// @notice Logic for transfering bTokens
    function _transfer(
        address bToken,
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        require(from != address(0) && to != address(0), Errors.ADDRESS_ZERO());

        uint256 fromBalance = _balance[bToken][from];
        require(fromBalance >= amount, Errors.INSUFFICIENT_BALANCE());

        unchecked {
            // Already checked to prevent overflow on line 248
            _balance[bToken][from] = fromBalance - amount;
            // Overflow is not possible because the sum of all user
            // balances cannot be greater that max uint256
            _balance[bToken][to] += amount;
        }

        BToken(bToken).emitTransfer(from, to, amount);

        return true;
    }

    /// @notice Logic for spending token allowance.
    function _spendAllowance(
        address bToken,
        address owner,
        address spender,
        uint256 amount
    ) internal returns (bool) {
        uint256 userAllowance = _allowances[bToken][owner][spender];
        if (userAllowance != type(uint256).max) {
            require(userAllowance >= amount, Errors.INSUFFICIENT_ALLOWANCE());
        }

        unchecked {
            approve(bToken, owner, spender, userAllowance - amount);
        }

        return true;
    }
}
