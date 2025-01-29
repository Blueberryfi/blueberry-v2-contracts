// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {BlueberryErrors as Errors} from "../../helpers/BlueberryErrors.sol";

import {VaultEscrow} from "./VaultEscrow.sol";
import {IHyperEvmVault} from "./interfaces/IHyperEvmVault.sol";

/**
 * @title HyperEvmVault
 * @author Blueberry
 * @notice An ERC4626 compatible vault that will be deployed on Hyperliquid EVM and will be used to tokenize
 *         any vault on Hyperliquid L1.
 */
contract HyperEvmVault is IHyperEvmVault, ERC20, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                Storage
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                                Immutables
    //////////////////////////////////////////////////////////////*/

    /// @notice The underlying asset of the vault
    address private immutable _asset;

    /// @notice The L1 address of the vault being deposited into
    address private immutable _l1Vault;

    /*//////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 escrowCount_,
        address asset_,
        address l1Vault_,
        address owner_
    ) ERC20(name_, symbol_) Ownable(owner_) {
        require(asset_ != address(0), Errors.ADDRESS_ZERO());
        require(l1Vault_ != address(0), Errors.ADDRESS_ZERO());

        _asset = asset_;
        _l1Vault = l1Vault_;
        _deployEscrows(escrowCount_);
    }

    /*//////////////////////////////////////////////////////////////
                            External Functions
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver) external override returns (uint256 shares) {}

    function mint(uint256 shares, address receiver) external override returns (uint256 assets) {}

    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256 shares) {}

    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256 assets) {}

    /*//////////////////////////////////////////////////////////////
                            Internal Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploys escrow contracts for the vault
     * @param escrowCount_ The number of escrow contracts to deploy
     */
    function _deployEscrows(uint256 escrowCount_) internal {
        for (uint256 i = 0; i < escrowCount_; ++i) {
            VaultEscrow escrow = new VaultEscrow(address(this));
            emit EscrowDeployed(address(escrow));
        }
    }

    /*//////////////////////////////////////////////////////////////
                            View Functions
    //////////////////////////////////////////////////////////////*/

    function asset() external view override returns (address) {
        return _asset;
    }

    function l1Vault() external view returns (address) {
        return _l1Vault;
    }

    function totalAssets() external view override returns (uint256 totalManagedAssets) {}

    function convertToShares(uint256 assets) external view override returns (uint256 shares) {}

    function convertToAssets(uint256 shares) external view override returns (uint256 assets) {}

    function maxDeposit(address receiver) external view override returns (uint256 maxAssets) {}

    function previewDeposit(uint256 assets) external view override returns (uint256 shares) {}

    function maxMint(address receiver) external view override returns (uint256 maxShares) {}

    function previewMint(uint256 shares) external view override returns (uint256 assets) {}

    function maxWithdraw(address owner) external view override returns (uint256 maxAssets) {}

    function previewWithdraw(uint256 assets) external view override returns (uint256 shares) {}

    function maxRedeem(address owner) external view override returns (uint256 maxShares) {}

    function previewRedeem(uint256 shares) external view override returns (uint256 assets) {}
}
