# LimitX
Automatic Cross Chain Limit Order and Swap Protocol

### Introducing LimitX Powered by Axelar and Chainlink

## Inspiration
We have developed LimitX, an automation module that empowers account abstraction or EOA wallets to create limit orders from any token on any source chain to another token on any destination chain within the EVM ecosystem.

## Key Features we considered during development:

Trustless Nature - LimitX operates as a decentralized smart contract module, ensuring full decentralization, composability, and trustlessness in its functionality.

Cross-chain Capability - The LimitX module can be deployed on various EVM-compatible chains, enabling seamless trading across multiple chains.

Automation Integration - Leveraging the power of Chainlink Upkeeps, LimitX automates the execution of limit orders. Once a user sets a limit order, continuous market monitoring is unnecessary, as the trade execution happens automatically.

Composability Support - LimitX seamlessly integrates with DeFi protocols and AA modules, enhancing composability and enabling developers to craft intricate trading strategies.

The module is designed to be genuinely composable and trustless, enabling developers to build upon it and facilitate cross-chain DeFi automation across their preferred EVM chains. This flexibility allows them to interact with chosen protocols as desired.

## What it does & How we built it
LimitX is currently deployed on both the Binance and Polygon Chains.

When users create a limit order, they specify the token pair, target price, and trade volume. The limit order is added to the LimitX order book. Chainlink Upkeeps are harnessed to create proxy tasks using call data based on user-specified limit orders, whether from EOAs or account abstractions. When the token pair's price aligns with the user's defined price, the Chainlink Upkeep triggers automatic trade execution. Tokens are seamlessly swapped at the specified price on the desired chain. Axelar Protocol facilitates liquidity bridging and call data transfer from source to destination chains for cross-chain swaps. Our module empowers anyone to create limit orders and DCAs across various tokens on any EVM chain.



## Deployed Contract Addresses
Polygon Mumbai: 0xaa846A3F7aAdCB7BE67aA0Fea79f454Fff883F92
Binance Testnet: 0xBB24DeF7aB385B841e57FDC6F581eEd6D5bCBCb7

## Challenges Overcome
- Integration across Multiple Chains
- Addressing Fees and Liquidity Challenges
- Resolving Pool Issues on Test Nets
