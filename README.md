
![Blueberry Logo](./blueberry-logo.png)
## Blueberry V2 Smart Contracts
Core smart contracts for the Blueberry V2 protocol.

### Overview
Blueberry is a decentralized leverage lending protocol that allows users to lend and borrow assets with up to 25x leverage. Blueberry serves as the prime brokerage of DeFi allowing users to build and execute various trading strategies with or without leverage. This second version of Blueberry is a complete rewrite of the original protocol, keeping the core concepts of V1, while focusing on design improvements, security, and scalability. The goal is to increase the accessability of leverage trading to the masses in a decentralized and trustless manner. 

### Documentation
For more information on Blueberry V2, please refer to our [documentation](https://docs.blueberry.garden/).

### Repository Structure
- `src/BlueberryGarden.sol`: The entry point and main contract of the Blueberry protocol. This contract serves as the money market for lending and borrowing assets, as well as routing those borrowed funds to the appropriate trading strategies.
- `src/BToken.sol`: The ERC20 token contract that represents the user's share of the Blueberry money market. Users receive BToken when they deposit assets into the `BlueberryGarden`.

### Repository Setup
1. Clone the repository

2. Install dependencies
```bash
forge install
```

3. Compile the contracts
```bash
forge compile
```

4. Run the tests
```bash
forge test
```

### Contribution Guidelines
We welcome and appreciate all contributions to the Blueberry protocol. While the core logic of the protocol is set, we are always looking for new trading strategies to implement within our system. If you have a trading strategy that you would like to add or want to partner with us, please reach out to us on our [Discord](https://discord.gg/blueberry).