# VYQNO Stablecoin Protocol

<div align="center">


**Decentralized. Over-Collateralized. Algorithmically Stable.**

</div>

---

## 🎯 Overview

VYQNO is a decentralized stablecoin protocol that enables users to mint **VSC** (VYQNO StableCoin) tokens pegged to USD by depositing cryptocurrency collateral.

**Key Features:**
- 🔒 Over-collateralized (200% minimum)
- 💎 Exogenous collateral (WETH, WBTC)
- ⚡ Automated liquidation engine
- 📊 Chainlink price oracles
- 🎯 Algorithmic USD peg

---

## 🏗️ Architecture

### Core Contracts

**VyqnoStableCoin.sol**
- ERC20 stablecoin token (VSC)
- Controlled minting/burning
- Pegged to $1 USD

**VyqnoEngine.sol** *(Coming Soon)*
- Collateral management
- Mint/burn logic
- Liquidation engine
- Health factor calculations

---

## 🛠️ Tech Stack

- **Smart Contracts:** Solidity ^0.8.26
- **Framework:** Foundry
- **Oracles:** Chainlink Price Feeds
- **Testing:** Foundry (Unit, Integration, Fuzz)
- **Libraries:** OpenZeppelin

---

## 📦 Installation

```bash
# Clone the repository
git clone https://github.com/vyqno/vyqno-stablecoin
cd vyqno-stablecoin

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test
```

---

## 🗺️ Roadmap

- [x] VyqnoStableCoin token
- [ ] VyqnoEngine core logic
- [ ] Liquidation mechanism
- [ ] Chainlink integration
- [ ] Comprehensive test suite
- [ ] Mainnet deployment

---

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

---

<div align="center">

**⭐ Star this repo if you find it helpful!**

Made with ❤️ by VYQNO

</div>