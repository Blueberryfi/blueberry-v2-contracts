// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {ERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract DepositVault is ERC20Upgradeable {
    ERC20Upgradeable public asset;

    constructor() {
        _disableInitializers();
    }

    event Deposit(address indexed sender, uint256 amount);

    function initialize(address _asset) public initializer {
        __ERC20_init("HLP Deposit Vault", "HLPDV");
        asset = ERC20Upgradeable(_asset);
    }

    function deposit(uint256 amount) external {
        asset.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
        emit Deposit(msg.sender, amount);
    }
}
