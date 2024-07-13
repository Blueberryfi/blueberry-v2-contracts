![Blueberry Logo](../../blueberry-logo.png)
## Blueberry Money Market

Directory containing modules relavent to the Blueberry Money Market. These files are soley used for basic lend, borrow capabilities.

### Directory Setup

- `BlueberryMarket`: A wrapper around all contracts within the directory, that allows the capibility for user's to lend assets into the Blueberry Money Market, as well as redeem bToken's for their underlying assets.
- `BToken.sol`: The ERC20 token contract that represents the user's share of the Blueberry money market. Users receive BToken when they deposit assets into the `BlueberryGarden`.
- `ERC4626MultiToken`: The core accounting logic of bTokens that allow efficient interactions with the Money Market all within a single contract.
