// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface INonAtomicMinter {
    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a user deposits underlying tokens to start an order
     * @param id The id of the order
     * @param user The address of the user that deposited
     * @param amount The amount of underlying tokens deposited
     */
    event OrderPending(uint256 indexed id, address indexed user, uint256 amount);

    /**
     * @notice Emitted when underlying tokens are swept from the contract
     * @param id The id of the order
     * @param amount The amount of underlying tokens swept
     */
    event OrderSwept(uint256 indexed id, uint256 amount);

    /**
     * @notice Emitted when a user is minted receipt tokens
     * @param id The id of the order
     * @param user The address of the user that was minted
     * @param mintedAmount The amount of receipt tokens minted for the user
     */
    event OrderCompleted(uint256 indexed id, address indexed user, uint256 mintedAmount);

    /*//////////////////////////////////////////////////////////////
                                Structs
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice A struct to store the deposit information for a user
     * @param amount The amount of underlying tokens a user has deposited
     * @param status The status of the deposit
     * @param lastUpdated The last time the DepositInfo was updated
     */
    struct OrderInfo {
        uint256 amount;
        OrderStatus status;
        uint256 lastUpdated;
    }

    /*//////////////////////////////////////////////////////////////
                                Enums
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice An enum to store the status of an order
     * @dev NULL: The order does not exist
     * @dev PENDING: The order has been made but the funds are still in the contract & have not been swept
     * @dev IN_FLIGHT: The order has been swept but the receipt tokens have not been minted
     * @dev COMPLETED: The order has been fully processed and the receipt tokens have been minted
     */
    enum OrderStatus {
        NULL,
        PENDING,
        IN_FLIGHT,
        COMPLETED
    }

    /*//////////////////////////////////////////////////////////////
                                Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits underlying tokens to the minter contract
     * @param amount Amount of underlying to deposit
     */
    function deposit(uint256 amount) external;

    /**
     * @notice Sweeps a user's order request to start processing the order off-chain
     * @dev This function is only callable by the PROCESSOR_ROLE
     * @param id The id of the order
     */
    function sweepOrder(uint256 id) external;

    /**
     * @notice Mints receipt tokens for a user
     * @dev This function is only callable by the MINTER_ROLE
     * @param id The id of the order
     * @param user User to mint for
     * @param receiptAmount Amount of receipt tokens to mint for the user
     */
    function mint(uint256 id, address user, uint256 receiptAmount) external;

    /// @notice Returns the receipt token for that will be minted to depositors
    function TOKEN() external view returns (address);

    /// @notice Returns the underlying token that is being minted
    function UNDERLYING() external view returns (address);

    /// @notice Returns the storage location for the order requests
    function ORDER_STORAGE_LOCATION() external view returns (bytes32);

    /// @notice Returns the order information for a given id
    function info(uint256 id) external view returns (OrderInfo memory);

    /// @notice Returns the id for the next order
    function nextId() external view returns (uint256);

    /// @notice Returns the minimum deposit amount for an order
    function minDeposit() external view returns (uint256);

    /// @notice Returns true if the user has an order with the given id
    function isUserOrder(address user, uint256 id) external view returns (bool);
}
