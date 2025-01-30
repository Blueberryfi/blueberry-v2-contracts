// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface INonAtomicMinter {
    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a user deposits underlying tokens
     * @param user The address of the user that deposited
     * @param amount The amount of underlying tokens deposited
     */
    event Deposit(address indexed user, uint256 amount);

    /**
     * @notice Emitted when underlying tokens are swept f
     * @param user The address of the user that swept
     * @param amount The amount of underlying tokens swept
     */
    event InFlight(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user is minted receipt tokens
     * @param user The address of the user that was minted
     * @param amount The amount of receipt tokens minted
     */
    event Mint(address indexed user, address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                Structs
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice A struct to store the deposit request information for a user
     * @param amount The amount of underlying tokens a user has deposited that have not been processed
     * @param lastUpdated The last time the DepositRequest was updated
     */
    struct DepositRequest {
        uint256 amount;
        uint256 lastUpdated;
    }

    /**
     * @notice A struct to store the deposit in flight information for a user
     * @dev This is used to store the amount of underlying tokens a user has deposited that have been swept but
     *      corresponding receipt tokens have not been minted
     * @param amount The amount of underlying tokens in flight
     * @param lastUpdated The last time the DepositInFlight was updated
     */
    struct DepositInFlight {
        uint256 amount;
        uint256 lastUpdated;
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
     * @notice Mints receipt tokens for a user
     * @dev This function is only callable by the MINTER_ROLE
     * @param user User to mint for
     * @param amount Amount of tokens to mint
     */
    function mint(address user, uint256 amount) external;

    /**
     * @notice Mints receipt tokens for multiple users
     * @dev This function is only callable by the MINTER_ROLE
     * @param users An array of user addresses to mint for
     * @param amounts An array of amounts of tokens to mint
     */
    function batchMint(address[] calldata users, uint256[] calldata amounts) external;

    /**
     * @notice Processes a user's deposit request
     * @dev This function is only callable by the PROCESSOR_ROLE
     * @param user User to process
     * @param amount Amount of tokens to process
     */
    function processDeposit(address user, uint256 amount) external;

    /**
     * @notice Processes multiple users' deposit requests
     * @dev This function is only callable by the PROCESSOR_ROLE
     * @param users An array of user addresses to process
     * @param amounts An array of amounts of tokens to process
     * @return amountProcessed The total amount of tokens processed during the call
     */
    function batchProcessDeposit(address[] calldata users, uint256[] calldata amounts)
        external
        returns (uint256 amountProcessed);

    /// @notice Returns the receipt token for that will be minted to depositors
    function TOKEN() external view returns (address);

    /// @notice Returns the underlying token that is being minted
    function UNDERLYING() external view returns (address);

    /// @notice Returns the storage location for the deposit requests
    function DEPOSIT_STORAGE_LOCATION() external view returns (bytes32);

    /// @notice Returns the deposit request for a given user
    function currentRequest(address user) external view returns (DepositRequest memory);

    /// @notice Returns the deposit in flight for a given user
    function currentInFlight(address user) external view returns (DepositInFlight memory);

    /// @notice Returns the total amount of underlying tokens deposited for all users
    function totalDeposits() external view returns (uint256);

    /// @notice Returns the total amount of underlying tokens in flight for all users
    function totalInFlight() external view returns (uint256);
}
