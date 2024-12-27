// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {RfqToken} from "../RfqToken.sol";

interface IRfqExecutor {
    /*///////////////////////////////////////////////////////////////
                                Structs
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Represents an order for a collateral redemption.
     * @param user The address of the user placing the order.
     * @param coll The address of the collateral being used in the order.
     * @param collAmount The amount of collateral being used in the order.
     * @param tokenAmount The amount of tokens being used in the order.
     */
    struct Order {
        address user;
        address coll;
        uint256 collAmount;
        uint256 tokenAmount;
    }

    /*///////////////////////////////////////////////////////////////
                                Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the bytes32 representation of the minter role.
    function MINTER_ROLE() external view returns (bytes32);

    /// @notice Returns the bytes32 representation of the redeemer role.
    function REDEEMER_ROLE() external view returns (bytes32);
    
    /// @notice Returns the redemption fee denominator.
    function REDEEM_FEE_D() external view returns (uint256);

    /// @notice Returns the instance of the receipt token for the RFQ strategy.
    function TOKEN() external view returns (RfqToken);

    /// @notice Returns the custodian address.
    function custodian() external view returns (address);

    /// @notice Returns the fee collector address.
    function feeCollector() external view returns (address);

    /// @notice Returns the redemption fee numerator.
    function redeemFeeNumerator() external view returns (uint256);

    /// @notice Returns the maximum amount of collateral that can be redeemed.
    function maxRedeem(address collateral) external view returns (uint256);
}
