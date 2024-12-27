// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControlDefaultAdminRules} from "@openzeppelin/access/extensions/AccessControlDefaultAdminRules.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

import {BlueberryErrors as Errors} from "../helpers/BlueberryErrors.sol";

import {RfqToken} from "./RfqToken.sol";
import {IRfqExecutor} from "./interfaces/IRfqExecutor.sol";

contract RfqExecutor is IRfqExecutor, AccessControlDefaultAdminRules {
    /*///////////////////////////////////////////////////////////////
                                Storage 
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the custodian who will be managing the funds.
    address private _custodian;

    /// @notice The address of the fee collector who receives redemption fees.
    address private _feeCollector;

    /// @notice The redemption fee numerator.
    uint256 private _redeemFeeN;

    /// @notice Mapping of collateral tokens and their approval status.
    mapping(address => bool) private _collaterals;

    /*///////////////////////////////////////////////////////////////
                                Modifiers
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates if an order is a valid order
     * @dev Checks if the collateral is supported, 
     *      the amounts of collateral and token are greater than 0,
     *      and that the users address is not empty.
     */
    modifier validOrder(Order memory order) {
        require(_collaterals[order.coll], Errors.COLLATERAL_NOT_SUPPORTED());
        require(order.collAmount > 0, Errors.AMOUNT_ZERO());
        require(order.tokenAmount > 0, Errors.AMOUNT_ZERO());
        require(order.user != address(0), Errors.ADDRESS_ZERO());
        _;
    }

    /*///////////////////////////////////////////////////////////////
                        Constants & Immutables
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRfqExecutor
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @inheritdoc IRfqExecutor
    bytes32 public constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE");
    
    /// @inheritdoc IRfqExecutor
    uint256 public constant REDEEM_FEE_D = 10_000;

    /// @inheritdoc IRfqExecutor
    RfqToken public immutable TOKEN;

    /*///////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address admin) AccessControlDefaultAdminRules(2 days, admin) {
        _grantRole(MINTER_ROLE, admin);
    }

    /*///////////////////////////////////////////////////////////////
                            External Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints receipt tokens on behalf of the user and transfers collateral to the custodian.
     * @dev Only users with an approved MINTER_ROLE can call this function.
     * @param order The order struct representing details for a users order.
     */
    function mint(Order memory order) external onlyRole(MINTER_ROLE) validOrder(order) {
        IERC20(order.coll).transferFrom(order.user, _custodian, order.collAmount);
        TOKEN.mint(order.user, order.tokenAmount);
    }


    /**
     * @notice Burns receipt tokens on behalf of the user and sends collateral back to the user.
     * @dev Only users with an approved REDEEMER_ROLE can call this function.
     * @param order The order struct representing details for a users order.
     */
    function redeem(Order memory order) external onlyRole(REDEEMER_ROLE) validOrder(order) {
        require(order.tokenAmount <= TOKEN.balanceOf(order.user), Errors.USER_BALANCE_SMOL());
        require(order.collAmount <= maxRedeem(order.coll), Errors.VAULT_BALANCE_SMOL());

        TOKEN.burnFrom(order.user, order.tokenAmount);

        uint256 fee = order.collAmount * _redeemFeeN / REDEEM_FEE_D;
        uint256 transferAmount = order.collAmount - fee;

        IERC20(order.coll).transfer(_feeCollector, fee);
        IERC20(order.coll).transfer(order.user, transferAmount);
    }

    /*///////////////////////////////////////////////////////////////
                            Admin Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the redemption fee numerator.
     * @dev Only users with an approved DEFAULT_ADMIN_ROLE can call this function.
     * @param newNumerator The new redemption fee numerator.
     */
    function setRedeemFeeNumerator(uint256 newNumerator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newNumerator < REDEEM_FEE_D, Errors.FEE_TOO_HIGH());
        _redeemFeeN = newNumerator;
    }

    /**
     * @notice Sets the custodian address.
     * @dev Only users with an approved DEFAULT_ADMIN_ROLE can call this function.
     * @param newCustodian The new custodian address.
     */
    function setCustodian(address newCustodian) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newCustodian != address(0), Errors.ADDRESS_ZERO());
        _custodian = newCustodian;
    }

    /**
     * @notice Adds a collateral token to the list of supported collateral tokens.
     * @dev Only users with an approved DEFAULT_ADMIN_ROLE can call this function.
     * @param collateral The address of the collateral token to add.
     */
    function addCollateral(address collateral) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _collaterals[collateral] = true;
    }

    /**
     * @notice Removes a collateral token from the list of supported collateral tokens.
     * @dev Only users with an approved DEFAULT_ADMIN_ROLE can call this function.
     * @param collateral The address of the collateral token to remove.
     */
    function removeCollateral(address collateral) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _collaterals[collateral] = false;
    }

    /*///////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRfqExecutor
    function custodian() external view returns (address) {
        return _custodian;
    }

    /// @inheritdoc IRfqExecutor
    function feeCollector() external view returns (address) {
        return _feeCollector;
    }

    /// @inheritdoc IRfqExecutor
    function redeemFeeNumerator() external view returns (uint256) {
        return _redeemFeeN;
    }

    /// @inheritdoc IRfqExecutor
    function maxRedeem(address collateral) public view returns (uint256) {
        return IERC20(collateral).balanceOf(address(this));
    }
}
