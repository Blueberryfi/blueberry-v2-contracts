// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";

import {MintableToken} from "@blueberry-v2/utils/MintableToken.sol";
import {BlueberryErrors as Errors} from "@blueberry-v2/helpers/BlueberryErrors.sol";
import {HyperliquidEscrow} from "@blueberry-v2/vaults/hyperliquid/HyperliquidEscrow.sol";
import {HyperVaultRouter} from "@blueberry-v2/vaults/hyperliquid/HyperVaultRouter.sol";

contract WrappedVaultShare is MintableToken {
    /*//////////////////////////////////////////////////////////////
                            Constants
    //////////////////////////////////////////////////////////////*/

    /// @notice The Router contract that will be used for deposits & redemptions of the token.
    address public immutable ROUTER;

    /*//////////////////////////////////////////////////////////////
                            Constructor    
    //////////////////////////////////////////////////////////////*/

    constructor(string memory name, string memory symbol, address router, address admin)
        MintableToken(name, symbol, 18, admin)
    {
        require(router != address(0), Errors.ADDRESS_ZERO());
        ROUTER = router;

        // Grant the minter and burner roles to the router so it can
        //     mint and burn share tokens during deposits and redemptions
        _grantRole(MINTER_ROLE, router);
        _grantRole(BURNER_ROLE, router);
    }

    /// @notice Calls the pokeFees functions on the router contract before any transfer
    function _beforeTransfer() internal {
        HyperVaultRouter(ROUTER).pokeFees();
    }

    /*//////////////////////////////////////////////////////////////
                            ERC20 Overrides
    //////////////////////////////////////////////////////////////*/

    /// @notice Overrides the ERC20 transfer function to enforce that fees are collected from the tvl
    function transfer(address to_, uint256 amount_) public override returns (bool) {
        _beforeTransfer();
        return super.transfer(to_, amount_);
    }

    /// @notice Overrides the ERC20 transferFrom function to enforce that fees are collected from the tvl
    function transferFrom(address from_, address to_, uint256 amount_) public override returns (bool) {
        _beforeTransfer();
        return super.transferFrom(from_, to_, amount_);
    }
}
