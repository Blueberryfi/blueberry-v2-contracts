// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {BlueberryErrors as Errors} from "../helpers/BlueberryErrors.sol";
import {INonAtomicMinter} from "./interfaces/INonAtomicMinter.sol";

/**
 * @title NonAtomicMinter
 * @notice Minter contract for strategies that rely on a non-atomic mint/burn mechanism.
 * @dev This contract works by users depositing underlying tokens, signalling the desire to mint receipt tokens.
 *      Once the backend infrastructure processes the deposit, the user will be minted their receipt tokens.
 *      This will be a multi-stage release:
 *      - [Stage 1] Users can deposit underlying tokens and mint receipt tokens.
 *          - No withdrawal functionality or deposit cancellation.
 */
contract NonAtomicMinter is INonAtomicMinter, Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            State Variables
    //////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:deposit.storage
    struct DepositStorage {
        mapping(address => DepositRequest) deposits;
    }

    /*//////////////////////////////////////////////////////////////
                        Constants & Immutables
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INonAtomicMinter
    address public immutable UNDERLYING;

    /// @inheritdoc INonAtomicMinter
    address public immutable TOKEN;

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

    function initialize(address owner) public initializer {
        __Ownable_init(owner);
        __UUPSUpgradeable_init();
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
        _transferUnderlying(msg.sender, address(this), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            Admin Functions
    //////////////////////////////////////////////////////////////*/

    function sweep(address user, uint256 amount) external onlyOwner {
        emit Sweep(user, amount);
    }

    function mint(address user, uint256 amount) external override onlyOwner {}

    function batchMint(address[] calldata users, uint256[] calldata amounts) external override onlyOwner {}

    function batchSweep(address[] calldata users, uint256[] calldata amounts) external override onlyOwner {}

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    /*//////////////////////////////////////////////////////////////
                            Internal Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfers underlying tokens from one address to another
    function _transferUnderlying(address from, address to, uint256 amount) internal {
        IERC20(UNDERLYING).safeTransferFrom(from, to, amount);
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
    }

    function _decreaseRequest(DepositStorage storage $, address user, uint256 amount) internal {
        require(amount <= $.deposits[user].amount, "NonAtomicMinter: Amount exceeds current request");
        $.deposits[user].amount -= amount;
        $.deposits[user].lastUpdated = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INonAtomicMinter
    function currentRequest(address user) public view override returns (DepositRequest memory) {
        DepositStorage storage $ = _getDepositStorage();
        return $.deposits[user];
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
