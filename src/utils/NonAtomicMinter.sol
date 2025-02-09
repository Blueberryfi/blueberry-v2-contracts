// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";
import {MintableToken} from "@blueberry-v2/utils/MintableToken.sol";
import {INonAtomicMinter} from "./interfaces/INonAtomicMinter.sol";

/**
 * @title NonAtomicMinter
 * @notice Minter contract for strategies that rely on a non-atomic mint/burn mechanism.
 * @dev Implements role-based access control.
 *      - DEFAULT_ADMIN_ROLE: Can grant and revoke all roles
 *      - UPGRADE_ROLE: Can upgrade the contract implementation
 *      - PROCESSOR_ROLE: Can process users order requests
 *      - MINTER_ROLE: Can mint receipt tokens to users
 * @dev This contract works by users depositing underlying tokens, signalling the desire to mint receipt tokens.
 *      Once the backend infrastructure processes the deposit, the user will be minted their receipt tokens.
 *      This will be a multi-stage release:
 *      - [Stage 1] Users can deposit underlying tokens and mint receipt tokens.
 *          - No withdrawal functionality or deposit cancellations.
 */
contract NonAtomicMinter is INonAtomicMinter, Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            State Variables
    //////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:order.storage
    struct OrderStorage {
        mapping(uint256 => OrderInfo) orders; // id -> order info
        mapping(address => mapping(uint256 => bool)) ownsOrder; // user -> id -> true/false
        uint256 minDeposit; // minimum deposit amount
        uint256 orderCount; // number of orders
    }

    /*//////////////////////////////////////////////////////////////
                        Constants & Immutables
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INonAtomicMinter
    address public immutable UNDERLYING;

    /// @inheritdoc INonAtomicMinter
    address public immutable TOKEN;

    /// @notice The role for the account that is able to upgrade the contract
    bytes32 public constant UPGRADE_ROLE = keccak256("UPGRADE_ROLE");

    /// @notice The role for the account that is able to process user deposits
    bytes32 public constant PROCESSOR_ROLE = keccak256("PROCESSOR_ROLE");

    /// @notice The role for the account that is able to mint receipt tokens to users
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice The location for the order storage
    bytes32 public constant ORDER_STORAGE_LOCATION =
        keccak256(abi.encode(uint256(keccak256(bytes("order.storage"))) - 1)) & ~bytes32(uint256(0xff));

    /*//////////////////////////////////////////////////////////////
                        Constructor / Initializer
    //////////////////////////////////////////////////////////////*/

    // @custom:oz-upgrades-unsafe-allow constructor
    constructor(address underlying, address token) {
        require(underlying != address(0), Errors.ADDRESS_ZERO());
        require(token != address(0), Errors.ADDRESS_ZERO());

        UNDERLYING = underlying;
        TOKEN = token;
        _disableInitializers();
    }

    function initialize(address admin, uint256 minDeposit_) public initializer {
        require(admin != address(0), Errors.ADDRESS_ZERO());
        require(minDeposit_ > 0, Errors.AMOUNT_ZERO());

        _getOrderStorage().minDeposit = minDeposit_;

        __AccessControl_init();
        __UUPSUpgradeable_init();

        // Grant the admin the DEFAULT_ADMIN_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /*//////////////////////////////////////////////////////////////
                        External Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INonAtomicMinter
    function deposit(uint256 amount) external {
        _validateAmount(amount);

        // Open a new order for the user
        OrderStorage storage $ = _getOrderStorage();
        uint256 id = _deposit($, msg.sender, amount);

        emit OrderPending(id, msg.sender, amount);

        // Transfer the underlying tokens to the contract
        IERC20(UNDERLYING).safeTransferFrom(msg.sender, address(this), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            Admin Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INonAtomicMinter
    function sweepOrder(uint256 id) external onlyRole(PROCESSOR_ROLE) {
        OrderStorage storage $ = _getOrderStorage();
        uint256 amount = _sweepOrder($, id);

        emit OrderSwept(id, amount);

        // Transfer the underlying tokens to caller
        IERC20(UNDERLYING).safeTransfer(msg.sender, amount);
    }

    /// @inheritdoc INonAtomicMinter
    function mint(uint256 id, address user, uint256 receiptAmount) external override onlyRole(MINTER_ROLE) {
        _validateAmount(receiptAmount);

        OrderStorage storage $ = _getOrderStorage();
        _completeOrder($, id, user);

        emit OrderCompleted(id, user, receiptAmount);

        // Mint the receipt tokens to the user
        MintableToken(TOKEN).mint(user, receiptAmount);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(UPGRADE_ROLE) {}

    /*//////////////////////////////////////////////////////////////
                            Internal Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Increases the user's deposit request
     * @param $ The order storage
     * @param user The address of the user depositing
     * @param amount The amount of underlying tokens to increase the request by
     * @return id The id of the order
     */
    function _deposit(OrderStorage storage $, address user, uint256 amount) internal returns (uint256 id) {
        require(amount >= $.minDeposit, Errors.BELOW_MIN_COLL());

        $.orders[$.orderCount].amount += amount;
        $.orders[$.orderCount].lastUpdated = block.timestamp;
        $.orders[$.orderCount].status = OrderStatus.PENDING;

        $.ownsOrder[user][$.orderCount] = true;
        id = $.orderCount++;
    }

    /**
     * @notice Sweeps a user's order
     * @param $ The order storage
     * @param id The id of the order to sweep
     */
    function _sweepOrder(OrderStorage storage $, uint256 id) internal returns (uint256 amount) {
        require($.orders[id].status == OrderStatus.PENDING, Errors.INVALID_OPERATION());

        $.orders[id].status = OrderStatus.IN_FLIGHT;
        $.orders[id].lastUpdated = block.timestamp;
        amount = $.orders[id].amount;
    }

    /**
     * @notice Completes a user's order by updating the order status to COMPLETED
     * @param $ The order storage
     * @param id The id of the order to complete
     * @param user The address of the user whos TOKENs are being minted
     */
    function _completeOrder(OrderStorage storage $, uint256 id, address user) internal {
        require($.orders[id].status == OrderStatus.IN_FLIGHT, Errors.INVALID_OPERATION());
        require($.ownsOrder[user][id], Errors.INVALID_USER());

        $.orders[id].status = OrderStatus.COMPLETED;
        $.orders[id].lastUpdated = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INonAtomicMinter
    function info(uint256 id) public view returns (OrderInfo memory) {
        return _getOrderStorage().orders[id];
    }

    /// @inheritdoc INonAtomicMinter
    function nextId() public view returns (uint256) {
        return _getOrderStorage().orderCount;
    }

    /// @inheritdoc INonAtomicMinter
    function minDeposit() public view returns (uint256) {
        return _getOrderStorage().minDeposit;
    }

    /// @inheritdoc INonAtomicMinter
    function isUserOrder(address user, uint256 id) external view override returns (bool) {
        return _getOrderStorage().ownsOrder[user][id];
    }

    /*//////////////////////////////////////////////////////////////
                            Pure Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Retrieves the order storage
    function _getOrderStorage() private pure returns (OrderStorage storage $) {
        bytes32 slot = ORDER_STORAGE_LOCATION;
        assembly {
            $.slot := slot
        }
    }

    /// @notice Validates the amount to make sure its greater than 0
    function _validateAmount(uint256 amount) internal pure {
        require(amount > 0, Errors.AMOUNT_ZERO());
    }
}
