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

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {BBErrors as Errors} from "@blueberry-v2/helpers/BBErrors.sol";

import {IBlueberryMarket} from "@blueberry-v2/interfaces/IBlueberryMarket.sol";
import {ERC4626MultiToken} from "./ERC4626MultiToken.sol";

// TODO:
// 1. Scale shares to 18 decimals
// 2. Permissioned Setter for creating/adding markets

/**
 * @title BlueberryMarket
 * @dev This contract simplifies all market accounting and user interactions to
 *      a single vault, allowing for efficient and gas-minimized interactions. ERC4626 bTokens are minted/burned representing
 *      a user's share of the underlying assets in the vault. These receipt tokens also contain an additioanl entrypoint to
 *      the money market for an added layer of composability.
 * @notice The money market for Blueberry Finance.
 */
abstract contract BlueberryMarket is IBlueberryMarket, ERC4626MultiToken {
    using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;

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
                                Storage
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps underlying assets to a given bToken.
    mapping(address => address) private _bTokens;

    /*///////////////////////////////////////////////////////////////
                                Modifiers
    //////////////////////////////////////////////////////////////*/

    /// @notice validates that the recipient isnt address 0.
    modifier validRecipient(address recipient) {
        require(recipient != address(0), Errors.ADDRESS_ZERO());
        _;
    }

    /*///////////////////////////////////////////////////////////////
                        Money Market Actions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Lend into the Blueberry Money Market
     * @param asset The underlying asset to lend into the money market
     * @param onBehalfOf User address, if the lend action is taken
     *        on behalf of another user. Note that only a valid bToken can do this.
     * @param receiver The recipient of the bToken that gets minted.
     * @param amount The amount of underlying asset to lend
     * @return shares The number of bToken shares minted for the receiver.
     */
    function _lend(
        address asset,
        address onBehalfOf,
        address receiver,
        uint256 amount
    ) internal validRecipient(receiver) returns (uint256 shares) {
        address bToken = getMarket(asset);

        // Round down in favor of the pool
        shares = amount.mulWadDown(exchangeRate(bToken));

        address account = _getAccount(bToken, msg.sender, onBehalfOf);
        IERC20(asset).safeTransferFrom(account, address(this), amount);

        _mint(bToken, receiver, shares);

        // Total supply of bToken's will always be greater than assets supplied
        //      so no need to check for overflow.
        unchecked {
            _totalAssets[asset] += amount;
        }

        emit Lend(asset, account, receiver, amount, amount);
    }

    // TODO: Validation check on bToken market
    /**
     * @notice Redeems the market's bToken, therefor removing the deposited underlying asset.
     * @param bToken The bToken that we are redeeming underlying assets from.
     * @param onBehalfOf User address, if the lend action is taken
     *        on behalf of another user. Note that only a valid bToken can do this.
     * @param receiver The recipient of the underlying tokens.
     * @param shares The amount of bTokens to redeem.
     * @return amount The number of underlying assets returned to the receiver.
     */
    function _redeem(
        address bToken,
        address onBehalfOf,
        address receiver,
        uint256 shares
    ) internal validRecipient(receiver) returns (uint256 amount) {
        address asset = asset(bToken);
        address account = _getAccount(bToken, msg.sender, onBehalfOf);

        if (shares == type(uint256).max) {
            shares = _balance[bToken][account];
        }
        require(
            _balance[bToken][account] >= shares,
            Errors.INSUFFICIENT_BALANCE()
        );

        _burn(bToken, account, shares);

        // Round up in favor of the pool
        amount = shares.divWadUp(exchangeRate(bToken));

        // Total supply of bToken's will always be greater than or equal to
        // assets supplied so no need to check for underflow.
        unchecked {
            _totalAssets[asset] -= amount;
        }

        IERC20(asset).safeTransfer(receiver, amount);

        emit Redeem(asset, account, receiver, amount, shares);
    }

    /**
     * @notice Get the associated bToken for a given asset.
     * @param asset The address of the underlying asset for the market.
     * @return bToken The address of the market (bToken).
     */
    function getMarket(address asset) public view returns (address bToken) {
        bToken = _bTokens[asset];
        require(bToken != address(0), Errors.INVALID_MARKET());
    }

    /**
     * @notice Returns the exchange rate of underlying asset to its respective market.
     * @dev Since we dont have interest rates at this stage of development,
     *      bToken shares are 1:1 with assets.
     * @param asset The address of the underlying asset.
     */
    function exchangeRate(
        address asset
    ) public view override returns (uint256) {
        address bToken = getMarket(asset);
        uint256 supply = _totalSupply[bToken];
        return supply == 0 ? 1e18 : (_totalAssets[asset] * 1e18) / supply;
    }

    /**
     * @notice Sets the account that the lend or withdraw will be processed for.
     * @dev Only the bToken can deposit on behalf of another user, so if the
     *      caller is not a valid bToken market, the account will default to
     *      msg.sender.
     * @param bToken The address of the bToken market.
     * @param from The caller of the lend or redeem functions.
     * @param onBehalfOf The source address of the funds being spent in the market.
     */
    function _getAccount(
        address bToken,
        address from,
        address onBehalfOf
    ) internal pure returns (address) {
        return bToken != from ? from : onBehalfOf;
    }
}
