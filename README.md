# Onchain Custody Smart Contracts

A comprehensive smart contract system for B2B cryptocurrency custody with an onchain policy engine built using the Diamond Proxy pattern (EIP-2535).

## Overview

Onchain Custody provides enterprise-grade cryptocurrency custody solutions with the following key features:

- **Diamond Proxy Architecture**: Upgradeable modular contract system using EIP-2535
- **Policy Engine**: Sophisticated rule-based transaction approval system
- **Multi-signature Support**: Enterprise-grade transaction approval workflows  
- **EIP-7201 Storage**: Collision-free namespaced storage for maximum safety
- **Gas Optimized**: Efficient storage patterns and optimized operations
- **Comprehensive Testing**: Unit and fuzz tests with high coverage

## Core Concepts

The system implements six core abstractions:

1. **Organizations**: Root entities representing customer companies
2. **Accounts**: Smart accounts/wallets that hold funds and execute transactions
3. **Groups**: Collections of members for permission management
4. **Members**: Individual users who can initiate and approve transactions
5. **Policies**: Rules engine determining transaction approval/rejection
6. **Address Whitelist**: Trusted addresses for interaction

## Architecture

### Diamond Proxy Pattern

The system uses the Diamond Proxy pattern (EIP-2535) for maximum upgradeability:

- **Diamond Contract**: Main proxy contract (`CustodyDiamond.sol`)
- **Facets**: Modular functionality contracts
- **EIP-7201 Storage**: Namespaced storage to prevent collisions
- **SolidState Integration**: Production-ready diamond implementation

### Facets

- **OrganizationFacet**: Organization management and admin controls ✅
- **AccountFacet**: Smart account creation and management (planned)
- **MemberFacet**: Member and group management (planned)  
- **PolicyFacet**: Policy creation and evaluation engine (planned)
- **TransactionFacet**: Transaction submission and execution (planned)
- **WhitelistFacet**: Address whitelist management (planned)

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 16+ (for additional tooling)

### Installation

```bash
git clone <repository-url>
cd onchain-custody-contracts
forge install
```

### Build

```bash
forge build
```

### Test

```bash
# Run all tests
forge test

# Run with verbose output
forge test -vvv

# Run specific test file
forge test --match-contract OrganizationFacetTest

# Run with gas reporting
forge test --gas-report
```

### Deploy

```bash
# Set environment variables
export PRIVATE_KEY=<your-private-key>
export OWNER=<owner-address>
export SYSTEM_ADMIN=<system-admin-address>

# Deploy to local network
forge script script/Deploy.s.sol --fork-url http://localhost:8545 --broadcast

# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

## Development

### Project Structure

```
├── src/
│   ├── core/           # Core diamond contract
│   ├── facets/         # Diamond facets
│   ├── interfaces/     # Contract interfaces
│   └── libraries/      # Shared libraries
├── test/
│   ├── unit/           # Unit tests
│   ├── integration/    # Integration tests
│   └── fuzz/           # Fuzz tests
├── script/             # Deployment scripts
└── deployments/        # Deployment artifacts
```

### Key Files

- `src/core/CustodyDiamond.sol` - Main diamond proxy contract
- `src/libraries/CustodyStorage.sol` - EIP-7201 storage library
- `src/facets/OrganizationFacet.sol` - Organization management facet
- `test/unit/` - Comprehensive unit tests

## Policy Engine (Planned)

The policy engine will support complex conditional logic:

### Policy Types
- **Auto Approve**: Automatically approve matching transactions
- **Auto Reject**: Automatically reject matching transactions  
- **Require Approval**: Require manual approval from designated approvers

### Policy Attributes
- Transaction source accounts and initiators
- Transaction types (token transfers vs contract interactions)
- Token and amount filtering
- Destination address controls (whitelist/blacklist)
- Function-level permissions for contract calls
- Time-based rate limiting and intervals

## Security

### Security Features
- **EIP-7201 Storage**: Prevents storage collisions in diamond pattern
- **Reentrancy Protection**: All state-changing functions protected
- **Access Control**: Role-based permissions with admin separation
- **Input Validation**: Comprehensive validation of all inputs
- **Emergency Controls**: System-wide pause functionality

## Current Status

### ✅ Completed (Phase 1)
- Diamond proxy architecture setup with SolidState
- EIP-7201 storage implementation  
- Organization management facet with full functionality
- Comprehensive testing framework with 15 passing tests
- Gas-optimized storage patterns
- Deployment scripts and documentation

### 🔄 In Progress  
- Additional facet implementations
- Policy engine development
- Smart account integration

### 📋 Roadmap
- ERC-4337 account abstraction integration
- Advanced policy engine with time-based rules
- Production deployment and security audit

## Gas Benchmarks (Current)

- Organization creation: ~200k gas
- Organization admin updates: ~35k gas
- Setting admin preferences: ~45k gas

## Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass: `forge test`
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.

# Onchain Custody Smart Contracts

## Overview: What is Onchain Custody?
Onchain Custody is a new category of cryptocurrency custody. It provides all the benefits of self-custody while being significanlty more secure than all other forms of custody (custody, self-custody, and MPC).

At the heart of Onchain Custody is the **policy engine**, which allows users to specify rules that dictate what types of transactions can be executed and by whom. An example policy might allow a group to transfer up to $10,000 of USDC per month and require 2 out of 3 of the group members to approve those transactions.

Onchain Custody is signficantly more secure than all other existing forms of custody, because it uses multiple redundant layers of security:
1. onchain smart contracts
2. offchain Guardian
3. mobile signing application

Onchain Custody combines onchain smart accounts with an offchain "guardian", an application that must explicitly approve transactions alongside the owners of a smart account. Owners must use the dedicated mobile signing application to approve transactions. The onchain smart contracts, the offchain Guardian, and the mobile signing app all run the policy engine independently and redundantly. In order to bypass the rules of the policy engine, all three must be compromised at the same time: the smart contracts must have an exploitable vulnerability, the offchain Guardian must be compromised, and the approving users' local mobile signing applications must all be compromised. These multiple redundant layers of security keep funds secure.

## Smart contracts
### Overview
There are two main abstrations represented as smart contracts in Onchain Custody:
1. Organizations (`src/organization/OnchainCustodyOrganizationDiamond.sol`)
2. Accounts (`src/account/OnchainCustodyAccountDiamond.sol`)

Each real world organization that uses Onchain Custody is represented onchain by a dedicated Organization contract. Each organization may have one or more Accounts (i.e. "smart accounts" or "smart contract wallets"), which are smart contracts that holds funds on behalf of the organization. 

The contracts representing organizations and accounts are both ERC-2535 Diamond proxies, and all functionalities are implemented in facets.

### Organizations
#### Files
```
src/organization
├── facets
│   ├── OrganizationAccountFactoryFacet.sol
│   ├── OrganizationAdminFacet.sol
│   ├── OrganizationGroupsFacet.sol
│   ├── OrganizationGuardianFacet.sol
│   ├── OrganizationInitializationFacet.sol
│   ├── OrganizationMembersFacet.sol
│   ├── OrganizationPolicyFacet.sol
│   └── OrganizationWhitelistFacet.sol
├── interfaces
│   ├── IOrganizationGroupsFacet.sol
│   ├── IOrganizationGuardianFacet.sol
│   └── IOrganizationMembersFacet.sol
├── OnchainCustodyOrganizationDiamond.sol
├── OnchainCustodyOrganizationFactory.sol
├── OrganizationInit.sol
└── OrganizationStorage.sol
```