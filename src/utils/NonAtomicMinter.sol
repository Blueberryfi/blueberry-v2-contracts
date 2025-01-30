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
 *      - PROCESSOR_ROLE: Can process users deposit requests
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

    /// @custom:storage-location erc7201:deposit.storage
    struct DepositStorage {
        mapping(address => DepositRequest) deposits;
        mapping(address => DepositInFlight) inFlight;
        uint256 totalDeposits;
        uint256 totalInFlight;
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

    /// @notice The location for the deposit storage
    bytes32 public constant DEPOSIT_STORAGE_LOCATION =
        keccak256(abi.encode(uint256(keccak256(bytes("deposit.storage"))) - 1)) & ~bytes32(uint256(0xff));

    /*//////////////////////////////////////////////////////////////
                        Constructor / Initializer
    //////////////////////////////////////////////////////////////*/

    // @custom:oz-upgrades-unsafe-allow constructor
    constructor(address underlying, address token) {
        UNDERLYING = underlying;
        TOKEN = token;
        _disableInitializers();
    }

    function initialize(address admin) public initializer {
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

        // Increase the user's deposit request
        DepositStorage storage $ = _getDepositStorage();
        _increaseRequest($, msg.sender, amount);

        emit Deposit(msg.sender, amount);

        // Transfer the underlying tokens to the contract
        IERC20(UNDERLYING).safeTransferFrom(msg.sender, address(this), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            Admin Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INonAtomicMinter
    function mint(address user, uint256 processedAmount, uint256 mintedAmount)
        external
        override
        onlyRole(MINTER_ROLE)
    {
        DepositStorage storage $ = _getDepositStorage();
        _mint($, user, processedAmount, mintedAmount);
    }

    /// @inheritdoc INonAtomicMinter
    function batchMint(address[] calldata users, uint256[] calldata processedAmounts, uint256[] calldata mintedAmounts)
        external
        override
        onlyRole(MINTER_ROLE)
    {
        uint256 len = users.length;
        require(len == processedAmounts.length, Errors.ARRAY_LENGTH_MISMATCH());
        require(len == mintedAmounts.length, Errors.ARRAY_LENGTH_MISMATCH());

        DepositStorage storage $ = _getDepositStorage();
        for (uint256 i = 0; i < len; ++i) {
            _mint($, users[i], processedAmounts[i], mintedAmounts[i]);
        }
    }

    /// @inheritdoc INonAtomicMinter
    function processDeposit(address user, uint256 amount) external onlyRole(PROCESSOR_ROLE) {
        DepositStorage storage $ = _getDepositStorage();
        _processDeposit($, user, amount);
        // Transfer the underlying tokens to caller
        IERC20(UNDERLYING).safeTransfer(msg.sender, amount);
    }

    /// @inheritdoc INonAtomicMinter
    function batchProcessDeposit(address[] calldata users, uint256[] calldata amounts)
        external
        override
        onlyRole(PROCESSOR_ROLE)
        returns (uint256 amountProcessed)
    {
        uint256 len = users.length;
        require(len == amounts.length, Errors.ARRAY_LENGTH_MISMATCH());

        DepositStorage storage $ = _getDepositStorage();

        for (uint256 i = 0; i < len; ++i) {
            _processDeposit($, users[i], amounts[i]);
            amountProcessed += amounts[i];
        }
        // Transfer the underlying tokens to caller
        IERC20(UNDERLYING).safeTransfer(msg.sender, amountProcessed);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(UPGRADE_ROLE) {}

    /*//////////////////////////////////////////////////////////////
                            Internal Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Internal logic for minting receipt tokens to a user
    function _mint(DepositStorage storage $, address user, uint256 processedAmount, uint256 mintedAmount) internal {
        _validateAmount(processedAmount);
        _validateAmount(mintedAmount);

        // Decrease the user's deposit in flight accounting
        _decreaseInFlight($, user, processedAmount);

        emit Mint(user, processedAmount, mintedAmount);

        // Mint the receipt tokens to the user
        MintableToken(TOKEN).mint(user, mintedAmount);
    }

    /**
     * @notice Internal logic for processing a user's deposit request
     * @param user The address of the user depositing
     * @param amount The amount of underlying tokens to decrease the request by
     */
    function _processDeposit(DepositStorage storage $, address user, uint256 amount) internal {
        _validateAmount(amount);

        // Decrease the user's deposit request
        _decreaseRequest($, user, amount);
        _increaseInFlight($, user, amount);

        emit InFlight(user, amount);
    }

    /**
     * @notice Increases the user's deposit request
     * @param $ The deposit storage
     * @param user The address of the user depositing
     * @param amount The amount of underlying tokens to increase the request by
     */
    function _increaseRequest(DepositStorage storage $, address user, uint256 amount) internal {
        $.deposits[user].amount += amount;
        $.deposits[user].lastUpdated = block.timestamp;
        $.totalDeposits += amount;
    }

    /**
     * @notice Increases the user's deposit in flight accounting
     * @param $ The deposit storage
     * @param user The address of the user depositing
     * @param amount The amount of underlying tokens to increase the in flight by
     */
    function _increaseInFlight(DepositStorage storage $, address user, uint256 amount) internal {
        $.inFlight[user].amount += amount;
        $.inFlight[user].lastUpdated = block.timestamp;
        $.totalInFlight += amount;
    }

    /**
     * @notice Decreases the user's deposit request
     * @param $ The deposit storage
     * @param user The address of the user depositing
     * @param amount The amount of underlying tokens to decrease the request by
     */
    function _decreaseRequest(DepositStorage storage $, address user, uint256 amount) internal {
        require(amount <= $.deposits[user].amount, Errors.AMOUNT_EXCEEDS_BALANCE());
        $.deposits[user].amount -= amount;
        $.deposits[user].lastUpdated = block.timestamp;
        $.totalDeposits -= amount;
    }

    /**
     * @notice Decreases the user's deposit in flight accounting
     * @param $ The deposit storage
     * @param user The address of the user depositing
     * @param amount The amount of underlying tokens to decrease the in flight by
     */
    function _decreaseInFlight(DepositStorage storage $, address user, uint256 amount) internal {
        require(amount <= $.inFlight[user].amount, Errors.AMOUNT_EXCEEDS_BALANCE());

        $.inFlight[user].amount -= amount;
        $.inFlight[user].lastUpdated = block.timestamp;
        $.totalInFlight -= amount;
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INonAtomicMinter
    function currentRequest(address user) public view override returns (DepositRequest memory) {
        DepositStorage storage $ = _getDepositStorage();
        return $.deposits[user];
    }

    /// @inheritdoc INonAtomicMinter
    function currentInFlight(address user) public view override returns (DepositInFlight memory) {
        return _getDepositStorage().inFlight[user];
    }

    /// @inheritdoc INonAtomicMinter
    function totalDeposits() public view override returns (uint256) {
        return _getDepositStorage().totalDeposits;
    }

    /// @inheritdoc INonAtomicMinter
    function totalInFlight() public view override returns (uint256) {
        return _getDepositStorage().totalInFlight;
    }

    /*//////////////////////////////////////////////////////////////
                            Pure Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Retrieves the deposit storage
    function _getDepositStorage() private pure returns (DepositStorage storage $) {
        bytes32 slot = DEPOSIT_STORAGE_LOCATION;
        assembly {
            $.slot := slot
        }
    }

    /// @notice Validates the amount to make sure its greater than 0
    function _validateAmount(uint256 amount) internal pure {
        require(amount > 0, Errors.AMOUNT_ZERO());
    }
}
