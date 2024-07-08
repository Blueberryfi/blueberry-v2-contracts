// SPDX-License-Identifier: BUSL-1.1
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/
pragma solidity ^0.8.26;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "@openzeppelin/token/ERC20/extensions/IERC20Permit.sol";
import {IERC4626} from "@openzeppelin/interfaces/IERC4626.sol";

import {BBErrors as Errors} from "@blueberry-v2/helpers/BBErrors.sol";

import {IBlueberryGarden} from "@blueberry-v2/interfaces/IBlueberryGarden.sol";

/**
 * @title BToken
 * @dev The core logic of bTokens resides within the BlueberryMarket contract.
 * @notice The receipt token received for users depositing into the Blueberry Money Market.
 */
contract BToken is IERC4626, IERC20Permit {
    using FixedPointMathLib for uint256;

    /*///////////////////////////////////////////////////////////////
                                Storage
    //////////////////////////////////////////////////////////////*/
    /// @notice The Blueberry Garden contract.
    IBlueberryGarden private immutable _blueberryGarden;

    /// @notice The underlying asset for the market.
    address private immutable _asset;

    /// @notice The name of the bToken.
    string private _name;

    /// @notice The symbol of the bToken.
    string private _symbol;

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    mapping(address => uint256) private _nonces;

    /*///////////////////////////////////////////////////////////////
                                Modifiers
    //////////////////////////////////////////////////////////////*/

    /// @notice Caller must be BlueberryGarden
    modifier onlyGarden() {
        require(
            msg.sender == address(_blueberryGarden),
            Errors.CALLER_NOT_GARDEN()
        );
        _;
    }

    /*///////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(
        IBlueberryGarden blueberryGarden,
        address asset_,
        string memory name_,
        string memory symbol_
    ) {
        _blueberryGarden = blueberryGarden;
        _asset = asset_;
        _name = name_;
        _symbol = symbol_;
    }

    /*///////////////////////////////////////////////////////////////
                        Market Functionality
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Lends a specified amount of underlying tokens into the Blueberry Money Market
     * @dev This function is a direct pass-through to the BlueberryGarden. It is recommended to
     *      lend directly to the BlueberryGarden, but this function is provided for
     *      composability purposes.
     * @dev The user needs to approve the BlueberryGarden contract as the spender of the underlying
     *      asset.
     * @param assets The number of underlying asset to lend within Blueberry Finance
     * @param receiver The recipient of the minted bTokens.
     * @return shares The number of bToken shares the receiver will receive.
     */
    function deposit(
        uint256 assets,
        address receiver
    ) external override returns (uint256 shares) {
        return _blueberryGarden.lend(address(this), receiver, receiver, assets);
    }

    /**
     * @notice Lends underlyingTokens into the Blueberry Money Market based on the desired number of
     *      minted shares.
     * @dev This function passes-through to the BlueberryGarden. It is recommended to
     *      lend directly to the BlueberryGarden, but this function is provided for
     *      composability purposes.
     * @dev The user needs to approve the BlueberryGarden contract as the spender of the underlying
     *      asset.
     * @param shares The number of bToken share's the user wants to mint.
     * @param receiver The recipient of the minted bTokens.
     * @return assets The number of underlying Tokens lent into the money market
     */
    function mint(
        uint256 shares,
        address receiver
    ) external override returns (uint256 assets) {
        assets = convertToAssets(shares);
        _blueberryGarden.lend(address(this), receiver, receiver, assets);
    }

    /**
     * @notice Lends underlyingTokens into the Blueberry Money Market based on the desired number of
     *      minted shares.
     * @dev This function passes-through to the BlueberryGarden. It is recommended to
     *      lend directly to the BlueberryGarden, but this function is provided for
     *      composability purposes.
     * @dev The user needs to approve the BlueberryGarden contract as the spender of the underlying
     *      asset.
     * @param shares The number of bToken share's the user wants to mint.
     * @param receiver The recipient of the minted bTokens.
     * @return assets The number of underlying Tokens withdrawn from the money market
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external override returns (uint256 assets) {
        return _blueberryGarden.redeem(address(this), owner, receiver, shares);
    }

    /**
     * @notice Withdraws a specified amount of underlying tokens from the Blueberry Money Market
     * @dev This function is a direct pass-through to the BlueberryGarden. It is recommended to
     *      exit your lend positions directly from the BlueberryGarden, but this function is
     *      provided for composability purposes.
     * @dev The user needs to approve the BlueberryGarden contract as the spender of the bToken.
     * @param assets The number of underlying assets to withdraw from the money market
     * @param receiver The recipient of the withdrawn underlying Tokens
     * @return shares The number of bToken shares burned.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external override returns (uint256 shares) {
        shares = convertToShares(assets);
        return _blueberryGarden.redeem(address(this), owner, receiver, shares);
    }

    /*///////////////////////////////////////////////////////////////
                            ERC20 Transfers
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC20
    function transfer(address to, uint256 amount) public returns (bool) {
        _blueberryGarden.transfer(address(this), msg.sender, to, amount);
        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        _blueberryGarden.transferFrom(
            address(this),
            msg.sender,
            from,
            to,
            amount
        );
        return true;
    }

    /// @inheritdoc IERC20
    function allowance(
        address owner,
        address spender
    ) public view returns (uint256) {
        return _blueberryGarden.allowance(address(this), owner, spender);
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 amount) public returns (bool) {
        _blueberryGarden.approve(address(this), msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Emits the Transfer event.
     * @dev This function can only be called by the BlueberryGarden.
     *      Is used to keep bToken's ERC20 complient
     */
    function emitTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyGarden {
        emit Transfer(from, to, amount);
    }

    /**
     * @notice Emits the Transfer event.
     * @dev This function can only be called by the BlueberryGarden.
     *      Is used to keep bToken's ERC20 complient
     */
    function emitApproval(
        address owner,
        address spender,
        uint256 amount
    ) external onlyGarden {
        emit Approval(owner, spender, amount);
    }

    /*///////////////////////////////////////////////////////////////
                        ERC4626 Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC4626
    function convertToShares(
        uint256 assets
    ) public view override returns (uint256 shares) {
        return assets.divWadUp(_blueberryGarden.exchangeRate(address(this)));
    }

    /// @inheritdoc IERC4626
    function convertToAssets(
        uint256 shares
    ) public view override returns (uint256 assets) {
        return shares.mulWadDown(_blueberryGarden.exchangeRate(address(this)));
    }

    /// @inheritdoc IERC4626
    function maxDeposit(
        address receiver
    ) external view override returns (uint256 maxAssets) {
        return IERC20(_asset).balanceOf(receiver);
    }

    /// @inheritdoc IERC4626
    function previewDeposit(
        uint256 assets
    ) external view override returns (uint256 shares) {
        return convertToShares(assets);
    }

    /// @inheritdoc IERC4626
    function maxMint(
        address receiver
    ) external view override returns (uint256 maxShares) {
        uint256 userBalance = IERC20(_asset).balanceOf(receiver);
        return previewMint(userBalance);
    }

    /// @inheritdoc IERC4626
    function previewMint(
        uint256 shares
    ) public view override returns (uint256 assets) {
        return convertToAssets(shares);
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(
        address owner
    ) external view override returns (uint256 maxAssets) {
        uint256 userBalance = balanceOf(owner);
        return previewWithdraw(userBalance);
    }

    /// @inheritdoc IERC4626
    function previewWithdraw(
        uint256 assets
    ) public view override returns (uint256 shares) {
        return convertToShares(assets);
    }

    /// @inheritdoc IERC4626
    function maxRedeem(
        address owner
    ) external view override returns (uint256 maxShares) {
        return balanceOf(owner);
    }

    /// @inheritdoc IERC4626
    function previewRedeem(
        uint256 shares
    ) external view override returns (uint256 assets) {
        return convertToAssets(shares);
    }

    /*///////////////////////////////////////////////////////////////
                            Token Info
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC20Metadata
    function name() external view override returns (string memory) {
        return _name;
    }

    /// @inheritdoc IERC20Metadata
    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    /**
     * @notice Returns the number of decimals for the bToken
     * @dev Blueberry Finance's bTokens are always 18 decimals
     */
    function decimals() external pure override returns (uint8) {
        return 18;
    }

    /// @inheritdoc IERC4626
    function asset() external view override returns (address) {
        return _asset;
    }

    /// @inheritdoc IERC4626
    function totalAssets() public view override returns (uint256) {
        return _blueberryGarden.totalAssets(address(this));
    }

    /// @inheritdoc IERC20
    function totalSupply() public view override returns (uint256) {
        return _blueberryGarden.totalSupply(address(this));
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view override returns (uint256) {
        return _blueberryGarden.balanceOf(address(this), account);
    }

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 Logic
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC20Permit
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                value,
                                _nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            require(
                recoveredAddress != address(0) && recoveredAddress == owner,
                "INVALID_SIGNER"
            );

            _blueberryGarden.approve(address(this), owner, spender, value);
        }

        emit Approval(owner, spender, value);
    }

    /// @inheritdoc IERC20Permit
    function nonces(address owner) external view returns (uint256) {
        return _nonces[owner];
    }

    /// @inheritdoc IERC20Permit
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return
            block.chainid == INITIAL_CHAIN_ID
                ? INITIAL_DOMAIN_SEPARATOR
                : _computeDomainSeparator();
    }

    function _computeDomainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes(_name)),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }
}
