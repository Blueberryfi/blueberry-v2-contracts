// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {FixedPointMathLib as FpMath} from "@solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";

import {WrappedVaultShare} from "@blueberry-v2/vaults/hyperliquid/WrappedVaultShare.sol";
import {IHyperVaultRouter} from "@blueberry-v2/vaults/hyperliquid/interfaces/IHyperVaultRouter.sol";

/// @title HyperVaultRateProvider
/// @notice This contract is a rate provider lens for a Hyperliquid vault.
contract HyperVaultRateProvider {
    using FpMath for uint256;

    /*//////////////////////////////////////////////////////////////
                        Immutable Variables
    //////////////////////////////////////////////////////////////*/

    /// @notice Associated token for the rate provider
    address public immutable TOKEN;

    /// @notice Router address for the Hyperliquid vault
    address public immutable ROUTER;

    /*//////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address token) {
        require(token != address(0), Errors.ADDRESS_ZERO());
        address router = WrappedVaultShare(token).ROUTER();
        require(router != address(0), Errors.ADDRESS_ZERO());

        // Set immutable variables
        TOKEN = token;
        ROUTER = router;
    }
    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the rate of a given token in terms of USD scaled to 18 decimals.
    function getRate() external view returns (uint256) {
        // Get the TVL of the router (always returned in 18 decimals)
        uint256 tvl = IHyperVaultRouter(ROUTER).tvl();
        uint256 totalSupply = IERC20(TOKEN).totalSupply();

        // WrappedVaultShare tokens will always be 18 decimals, so no scaling is needed
        return totalSupply == 0 ? FpMath.WAD : tvl.divWadDown(totalSupply);
    }
}
