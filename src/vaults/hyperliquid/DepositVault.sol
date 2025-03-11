// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {ERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IArbitrumDepositor} from "./interfaces/IArbitrumDepositor.sol";

contract DepositVault is ERC20Upgradeable {
    ERC20Upgradeable public asset;
    IArbitrumDepositor public depositor;
    error OnlyDepositor();

    constructor() {
        _disableInitializers();
    }

    event Deposit(address indexed sender, uint256 amount);

    function initialize(address _asset, address _depositor) public initializer {
        __ERC20_init("HLP Deposit Vault", "HLPDV");
        asset = ERC20Upgradeable(_asset);
        depositor = IArbitrumDepositor(_depositor);
    }

    function deposit(
        uint256 amount,
        address receiver,
        bytes memory options
    ) external payable {
        asset.transferFrom(msg.sender, address(this), amount);
        depositor.depositIntoHyperEVM{value: msg.value}(
            abi.encode(amount, receiver),
            options
        );
        emit Deposit(msg.sender, amount);
    }

    function mintShares(address receiver, uint256 shares) external {
        if (msg.sender != address(depositor)) {
            revert OnlyDepositor();
        }
        _mint(receiver, shares);
    }
}
