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

    event Sweep(address indexed user, uint256 amount);
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
     * @notice Sweeps underlying tokens for a user
     * @dev This function is only callable by the SWEEPER_ROLE
     * @param user User to sweep
     * @param amount Amount of tokens to sweep
     */
    function sweep(address user, uint256 amount) external;

    /**
     * @notice Sweeps underlying tokens for multiple users
     * @dev This function is only callable by the SWEEPER_ROLE
     * @param users An array of user addresses to sweep
     * @param amounts An array of amounts of tokens to sweep
     */
    function batchSweep(address[] calldata users, uint256[] calldata amounts) external;

    /// @notice Returns the receipt token for that will be minted to depositors
    function TOKEN() external view returns (address);

    /// @notice Returns the underlying token that is being minted
    function UNDERLYING() external view returns (address);

    /// @notice Returns the storage location for the deposit requests
    function DEPOSIT_STORAGE_LOCATION() external view returns (bytes32);

    /// @notice Returns the deposit request for a given user
    function currentRequest(address user) external view returns (DepositRequest memory);
}
