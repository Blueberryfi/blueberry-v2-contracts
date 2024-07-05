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

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {BBErrors as Errors} from "./BBErrors.sol";

// TODO:
// 1. Scale shares to 18 decimals
// 2. bToken contract
// 3. Permissioned Setter for creating/adding markets

/**
 * @title BlueberryMarket
 * @dev This contract simplifies all market accounting and user interactions to
 *      a single vault, allowing for efficient and gas-minimized interactions. ERC4626 bTokens are minted/burned representing
 *      a user's share of the underlying assets in the vault. These receipt tokens also contain an additioanl entrypoint to
 *      the money market for an added layer of composability.
 * @notice The money market for Blueberry Finance.
 */
abstract contract BlueberryMarket {
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
     * @notice Emit when a user withdraws assets from the money market.
     * @param asset The underlying asset being withdrawn.
     * @param account The address of the user withdrawing the assets.
     * @param recipient The address of the user receiving the assets.
     * @param amounts The amount of assets withdrawn.
     * @param shares The number of shares of bToken's burned.
     */
    event Withdraw(
        address indexed asset,
        address indexed account,
        address indexed recipient,
        uint256 amounts,
        uint256 shares
    );

    /**
     * @notice Emit when a bToken's are transferred
     * @param market The address of the bToken being transferred.
     * @param from The address of the sender.
     * @param to The address of the receiver.
     * @param amount Amount of bToken's being transferred.
     */
    event Transfer(
        address indexed market,
        address indexed from,
        address indexed to,
        uint256 amount
    );
    /*///////////////////////////////////////////////////////////////
                                Storage
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps an underlying asset to its bToken.
    mapping(address => address) private _bTokens;

    /// @notice Maps an underlying asset to its current balance in the money market.
    mapping(address => uint256) private _totalAssets;

    /// @notice Maps a bToken to its totalSupply.
    mapping(address => uint256) private _bTokenSupply;

    /// @notice Maps a user's address to their balance's of a specific bToken.
    mapping(address => mapping(address => uint256)) private _userBalance;

    /// @notice Maps a user's address to their allowance of a specific bToken (owner -> spender -> allowance).
    mapping(address => mapping(address => mapping(address => uint256)))
        private _allowances;

    /*///////////////////////////////////////////////////////////////
                                Modifiers
    //////////////////////////////////////////////////////////////*/
    modifier validRecipient(address recipient) {
        require(recipient != address(0), Errors.AddressZero());
        _;
    }

    /*///////////////////////////////////////////////////////////////
                                Functions
    //////////////////////////////////////////////////////////////*/

    function lend(
        address asset,
        uint256 amount,
        address receiver
    ) external validRecipient(receiver) returns (uint256 shares) {
        address bToken = getMarket(asset);

        // Since we dont have interest rates, bToken shares are 1:1 with assets lent
        shares = amount;

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        _mintBToken(bToken, receiver, shares);

        // Total supply of bToken's will always be greater than assets supplied
        //      so no need to check for overflow.
        unchecked {
            _totalAssets[asset] += amount;
        }

        emit Lend(asset, msg.sender, receiver, amount, amount);
    }

    function withdraw(
        address asset,
        address receiver,
        uint256 amount
    ) external validRecipient(receiver) returns (uint256 shares) {
        address bToken = getMarket(asset);

        // Since we dont have interest rates, bToken shares are 1:1 with assets lent
        shares = amount;
        if (shares == type(uint256).max) {
            shares = _userBalance[bToken][msg.sender];
            amount = shares;
        }

        require(
            _userBalance[bToken][msg.sender] >= shares,
            Errors.InsufficientBalance()
        );

        _burnBToken(bToken, msg.sender, shares);

        // Total supply of bToken's will always be greater than assets supplied
        //      so no need to check for underflow.
        unchecked {
            _totalAssets[asset] -= amount;
        }

        IERC20(asset).safeTransfer(receiver, amount);

        emit Withdraw(asset, msg.sender, receiver, amount, shares);
    }

    function getMarket(address asset) public view returns (address bToken) {
        bToken = _bTokens[asset];
        require(bToken != address(0), Errors.INVALID_MARKET());
        return bToken;
    }

    function bTokenSupply(address market) external view returns (uint256) {
        return _bTokenSupply[market];
    }

    function bTokenBalance(
        address market,
        address account
    ) external view returns (uint256) {
        return _userBalance[market][account];
    }

    function assetsSupplied(address asset) public view returns (uint256) {
        return _totalAssets[asset];
    }

    function allowance(
        address asset,
        address owner,
        address spender
    ) external view returns (uint256) {
        return _allowances[asset][owner][spender];
    }

    function _mintBToken(
        address bToken,
        address recipient,
        uint256 shares
    ) internal {
        _bTokenSupply[bToken] += shares;

        // Overflow cannot occur because totalSupply is capped at max uint256
        //   and totalSupply is always greater than or equal to a users balance.
        unchecked {
            _userBalance[bToken][recipient] += shares;
        }

        emit Transfer(bToken, msg.sender, recipient, shares);
    }

    function _burnBToken(
        address bToken,
        address account,
        uint256 shares
    ) internal {
        _userBalance[bToken][account] -= shares;

        // Underflow cannot occur because a users balance will always be
        //     less than or equal to total supply.
        unchecked {
            _bTokenSupply[bToken] -= shares;
        }

        emit Transfer(bToken, account, address(0), shares);
    }
}
