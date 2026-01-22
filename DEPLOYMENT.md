# Deployment Guide

This guide covers deploying the Multi-layer Security (MLS) Wallet platform contracts to a new chain.

## Overview

All platform contracts are deployed **deterministically** using CREATE2, ensuring the same contract addresses across all chains. This is critical for cross-chain operations.

The deployment follows a **3-step process**:

1. **Deploy CREATE2 Factory** (if not already deployed on the chain)
2. **Deploy Platform Libraries** via CREATE2
3. **Deploy Contracts** with library linking

## Prerequisites

### Required Tools

- [Foundry](https://getfoundry.sh) (`forge` and `cast`)
- `jq` for JSON parsing: `brew install jq` (macOS) or `apt install jq` (Linux)

### Signer Setup

The deployment scripts use Foundry's signer flags. You have two options:

#### Option A: Foundry Keystore (Recommended for dev/staging)

Import a wallet from mnemonic into Foundry's encrypted keystore:

```bash
# Import from mnemonic at a specific derivation index (e.g., index 0)
cast wallet import my-deployer --mnemonic "your twelve word mnemonic phrase here" --mnemonic-index 0

# You'll be prompted to create a password to encrypt the keystore
```

Then use it in scripts:
```bash
--account my-deployer --sender <address-of-imported-wallet>
```

#### Option B: Ledger Hardware Wallet (Recommended for production)

```bash
--ledger --hd-paths "m/44'/60'/0'/0/0" --sender <ledger-address>
```

> **Note:** The `--sender` flag is required when using `--account` or `--ledger` to specify which address is signing.

### Environment Variables

```bash
export RPC_URL=<target-chain-rpc-endpoint>

# Only required for factory deployment (Step 1)
export CONFIRM_DEPLOYMENT=true
```

## Quick Start: Local Testing

For local testing with Anvil:

```bash
./test_deploy_scripts_locally.sh
```

This script:
1. Starts an Anvil instance on port 8001 with chain ID 420
2. Funds the deployer
3. Deploys the Arachnid CREATE2 factory
4. Deploys libraries via CREATE2
5. Deploys all contracts with library linking

## Deployment via Makefile (Recommended)

The Makefile provides convenient commands for deployment with configurable networks, signers, and CREATE2 factories.

### Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NETWORK` | `local` | Target network: `local`, `mainnet`, `polygon`, `arbitrum`, `optimism`, `base`, or any RPC URL |
| `SIGNER` | `account` | Signing method: `account` (Foundry keystore) or `ledger` |
| `ACCOUNT` | - | Foundry keystore account name (required when `SIGNER=account`) |
| `SENDER` | - | EOA address (auto-derived from `ACCOUNT`, required for `ledger`) |
| `FACTORY` | `arachnid` | CREATE2 factory: `arachnid`, `den-prod`, or `den-nonprod` |
| `HD_PATH` | `m/44'/60'/0'/0/0` | Ledger HD derivation path (when `SIGNER=ledger`) |

> **Note:** When using `SIGNER=account`, `SENDER` is automatically derived from your Foundry account. You'll be prompted for your keystore password. You can still provide `SENDER` explicitly to skip the password prompt.

### Make Commands Reference

#### Factory Deployment

| Command | Description |
|---------|-------------|
| `make fund-arachnid-deployer` | Fund the Arachnid factory deployer address |
| `make deploy-arachnid-factory` | Deploy the Arachnid CREATE2 factory |
| `make fund-den-deployer` | Fund a Den Singleton Factory deployer (requires `DEN_DEPLOYER_ADDRESS`) |
| `make deploy-den-factory` | Deploy the Den Singleton Factory |

#### Platform Deployment

| Command | Description |
|---------|-------------|
| `make deploy-libraries` | Deploy the 4 platform libraries via CREATE2 |
| `make deploy-contracts` | Deploy all contracts with library linking |
| `make deploy-platform` | Full deployment (libraries + contracts) |

#### Utilities

| Command | Description |
|---------|-------------|
| `make check-factory` | Check if CREATE2 factories exist on target network |
| `make compute-lib-addresses` | Compute expected library addresses for a factory |

### Example: Local Deployment with Foundry Account

```bash
# Start Anvil in a separate terminal
anvil --chain-id 420 --disable-default-create2-deployer

# Fund and deploy the Arachnid factory (password will be prompted)
make fund-arachnid-deployer ACCOUNT=my-deployer
make deploy-arachnid-factory ACCOUNT=my-deployer

# Deploy libraries and contracts
make deploy-libraries ACCOUNT=my-deployer
make deploy-contracts ACCOUNT=my-deployer

# Or use the combined command
make deploy-platform ACCOUNT=my-deployer
```

### Example: Testnet Deployment with Ledger

```bash
# Check if factory already exists
make check-factory NETWORK=sepolia

# Deploy libraries and contracts using Ledger
make deploy-libraries NETWORK=sepolia SIGNER=ledger SENDER=0x1234...
make deploy-contracts NETWORK=sepolia SIGNER=ledger SENDER=0x1234...
```

### Example: Using Den Singleton Factory

If the Arachnid factory cannot be deployed (e.g., chain enforces EIP-155):

```bash
# Fund and deploy Den Singleton Factory
make fund-den-deployer DEN_DEPLOYER_ADDRESS=0xE1CB04A0fA36DdD16a06ea828007E35e1a3cBC37 \
    NETWORK=mychain ACCOUNT=funder

make deploy-den-factory NETWORK=mychain ACCOUNT=den-deployer

# Deploy using the Den factory
make deploy-libraries FACTORY=den-prod NETWORK=mychain ACCOUNT=my-deployer
make deploy-contracts FACTORY=den-prod NETWORK=mychain ACCOUNT=my-deployer
```

### Library Addresses by Factory

The library addresses differ based on which CREATE2 factory is used. These are configured in the Makefile.

**Arachnid Factory (`FACTORY=arachnid`):**

| Library | Address |
|---------|---------|
| LibOrganizationPolicy | `0x0c39cb4F67AA70D53ceE37d4c88f11ffDb07E314` |
| LibOrganizationAdmin | `0x744CaFa607273AF5664073d05BE066C6bDbf8201` |
| LibOrganizationInitialization | `0x95A9CDA2a67E48b154d8EFa3B147f31eC6e8147E` |
| LibOrganizationAccountSignature | `0x6A6709A2c898E719A6Ee7635a3963122059655eB` |

**Den Singleton Factory (`FACTORY=den-prod` or `FACTORY=den-nonprod`):**

Library addresses for Den factories must be computed after deploying the factory. Use `make compute-lib-addresses` to get the expected addresses, then update them in the Makefile before running `deploy-contracts`.

## Step-by-Step Deployment (Manual)

The following sections describe manual deployment using `forge script` directly. For most use cases, the [Makefile commands](#deployment-via-makefile-recommended) above are easier to use.

### Step 1: Deploy CREATE2 Factory

First, check if a CREATE2 factory already exists on your target chain:

```bash
# Check for Arachnid factory
cast code 0x4e59b44847b379578588920cA78FbF26c0B4956C --rpc-url $RPC_URL

# Check for Den Singleton factory
cast code 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7 --rpc-url $RPC_URL
```

If either returns bytecode (not `0x`), skip to Step 2 and use that factory address.

#### Deploy Arachnid Factory (Preferred)

The Arachnid factory uses a pre-signed keyless transaction and works on most EVM chains.

```bash
# Fund the Arachnid deployer address first
forge script script/DeployArachnidFactory.s.sol:DeployArachnidFactory \
  --sig "fundDeployer()" \
  --rpc-url $RPC_URL \
  --account <your-keystore-name> --sender <your-address> \
  --broadcast -vvvv

# Deploy the factory
CONFIRM_DEPLOYMENT=true forge script script/DeployArachnidFactory.s.sol:DeployArachnidFactory \
  --sig "run()" \
  --rpc-url $RPC_URL \
  --account <your-keystore-name> --sender <your-address> \
  --broadcast -vvvv
```

Factory will be deployed at: `0x4e59b44847b379578588920cA78FbF26c0B4956C`

#### Deploy Den Singleton Factory (Fallback)

Only use this if Arachnid deployment fails (e.g., chain enforces EIP-155).

> **CRITICAL:** The Den Singleton Factory must be deployed from a specific EOA at nonce 0. The production deployer is `0xE1CB04A0fA36DdD16a06ea828007E35e1a3cBC37`. If this address has already sent any transaction on the target chain, the factory cannot be deployed at its deterministic address.

```bash
# Fund the Den Singleton deployer
forge script script/DeployDenSingletonFactory.s.sol:DeployDenSingletonFactory \
  --sig "fundDeployer(address)" 0xE1CB04A0fA36DdD16a06ea828007E35e1a3cBC37 \
  --rpc-url $RPC_URL \
  --account <your-keystore-name> --sender <your-address> \
  --broadcast -vvvv

# Deploy the factory
CONFIRM_DEPLOYMENT=true forge script script/DeployDenSingletonFactory.s.sol:DeployDenSingletonFactory \
  --rpc-url $RPC_URL \
  --account <your-keystore-name> --sender <your-address> \
  --broadcast -vvvv
```

Factory will be deployed at: `0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7`

### Step 2: Deploy Platform Libraries

Deploy the four platform libraries via CREATE2. These libraries have deterministic addresses that are hardcoded in `script/config/DeploymentConfig.sol`.

```bash
# Using Arachnid factory
forge script script/DeployLibraries.s.sol:DeployLibraries \
  --sig "run(address)" 0x4e59b44847b379578588920cA78FbF26c0B4956C \
  --rpc-url $RPC_URL \
  --account <your-keystore-name> --sender <your-address> \
  --broadcast -vvvv

# Or using Den Singleton factory
forge script script/DeployLibraries.s.sol:DeployLibraries \
  --sig "run(address)" 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7 \
  --rpc-url $RPC_URL \
  --account <your-keystore-name> --sender <your-address> \
  --broadcast -vvvv
```

The script will output the deployed library addresses. When using the Arachnid factory, the addresses are:

| Library | Address |
|---------|---------|
| LibOrganizationPolicy | `0x0c39cb4F67AA70D53ceE37d4c88f11ffDb07E314` |
| LibOrganizationAdmin | `0x744CaFa607273AF5664073d05BE066C6bDbf8201` |
| LibOrganizationInitialization | `0x95A9CDA2a67E48b154d8EFa3B147f31eC6e8147E` |
| LibOrganizationAccountSignature | `0x6A6709A2c898E719A6Ee7635a3963122059655eB` |

### Step 3: Deploy Contracts

Deploy all remaining contracts with library linking. The `--libraries` flags are **required** to ensure deterministic bytecode across chains.

```bash
# Using Arachnid factory with its library addresses
forge script script/DeployContracts.s.sol:DeployContracts \
  --sig "run(address)" 0x4e59b44847b379578588920cA78FbF26c0B4956C \
  --rpc-url $RPC_URL \
  --account <your-keystore-name> --sender <your-address> \
  --broadcast \
  -vvvv \
  --libraries src/organization/libraries/LibOrganizationPolicy.sol:LibOrganizationPolicy:0x0c39cb4F67AA70D53ceE37d4c88f11ffDb07E314 \
  --libraries src/organization/libraries/LibOrganizationAdmin.sol:LibOrganizationAdmin:0x744CaFa607273AF5664073d05BE066C6bDbf8201 \
  --libraries src/organization/libraries/LibOrganizationInitialization.sol:LibOrganizationInitialization:0x95A9CDA2a67E48b154d8EFa3B147f31eC6e8147E \
  --libraries src/organization/libraries/LibOrganizationAccountSignature.sol:LibOrganizationAccountSignature:0x6A6709A2c898E719A6Ee7635a3963122059655eB
```

This deploys:

1. **Safe Infrastructure**: Safe Singleton, SafeProxyFactory, CompatibilityFallbackHandler, MultiSend, MultiSendCallOnly, CreateCall, SimulateTxAccessor
2. **Governance Safes**: Guardian Safe and Deployer Safe (configurations are chain-dependent, see below)
3. **Implementation Contracts**: OrganizationImplementation, AccountImplementation, ImplementationWhitelistImplementation
4. **Factory Contracts**: OrganizationFactory
5. **Proxy Contracts**: ImplementationWhitelistProxy (initialized with implementations whitelisted)

## Guardian and Deployer Safe Configuration

The Guardian Safe and Deployer Safe are multisig wallets that control critical platform operations:

- **Guardian Safe**: Acts as the guardian for all organizations, required to approve all transactions
- **Deployer Safe**: Owns the OrganizationFactory and ImplementationWhitelist, controls deployments

### How Configuration Works

Safe configurations are **hardcoded** in `script/config/DeploymentConfig.sol`. The deployment script automatically selects the appropriate configuration based on `block.chainid`:

**Production chains** (Mainnet, Optimism, BNB Chain, Polygon, Base, Arbitrum, Avalanche):
- Guardian Safe: 2-of-2 multisig
- Deployer Safe: 2-of-3 multisig

**Non-production chains** (all other chain IDs):
- Guardian Safe: 1-of-1 multisig
- Deployer Safe: 1-of-1 multisig

### Modifying Safe Configuration

To change the Safe owners or thresholds, edit `script/config/DeploymentConfig.sol`:

```solidity
// Production Guardian Safe
address internal constant PROD_GUARDIAN_SAFE_OWNER_1 = address(0x1111...);
address internal constant PROD_GUARDIAN_SAFE_OWNER_2 = address(0x2222...);
uint256 internal constant PROD_GUARDIAN_SAFE_THRESHOLD = 2;

// Non-production Guardian Safe
address internal constant NON_PROD_GUARDIAN_SAFE_OWNER_1 = address(0xFdA4...);
uint256 internal constant NON_PROD_GUARDIAN_SAFE_THRESHOLD = 1;
```

> **Important:** After modifying these values, the deployed Safe addresses will be different. The salts ensure deterministic addresses, but the initialization data (owners, threshold) affects the final address computation.

## Contract Verification

To verify contracts on block explorers:

```bash
# Add these flags to your deployment command
--verify --etherscan-api-key <your-api-key>
```

Example:
```bash
forge script script/DeployContracts.s.sol:DeployContracts \
  --sig "run(address)" 0x4e59b44847b379578588920cA78FbF26c0B4956C \
  --rpc-url $RPC_URL \
  --account <your-keystore-name> --sender <your-address> \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --libraries ...
```

## Why Library Linking Matters

`OrganizationImplementation` uses external libraries with `public` functions, which Solidity compiles as separate contracts called via `DELEGATECALL`.

Without the `--libraries` flag:
- Foundry auto-deploys libraries using regular `CREATE` (nonce-dependent)
- Library addresses differ across chains
- `OrganizationImplementation` bytecode includes library addresses, so it also differs

With the `--libraries` flag:
- Libraries are deployed via CREATE2 with deterministic addresses
- The compiler links to these known addresses
- `OrganizationImplementation` bytecode is identical across all chains

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Factory address cannot be zero" | Pass the CREATE2 factory address as an argument: `--sig "run(address)" <factory-address>` |
| "CREATE2 factory not deployed" | Run Step 1 to deploy a factory first, or use `make check-factory` to verify |
| "Deployer nonce is not 0" | The Den Singleton Factory cannot be deployed at its deterministic address on this chain. Use Arachnid factory instead. |
| "Already deployed" messages | Normal - the script skips contracts that already exist at their deterministic addresses |
| Library address mismatch | You ran without `--libraries` flag. Use `make deploy-contracts` which includes the flags automatically. |
| "ACCOUNT is required" | Set `ACCOUNT=<keystore-name>` when using `SIGNER=account` |
| "SENDER is required" | Always set `SENDER=<your-address>` with deployment commands |
| "Invalid FACTORY value" | Use one of: `arachnid`, `den-prod`, `den-nonprod` |
| Den factory library addresses are 0x0 | Update the library addresses in `Makefile` after deploying libraries via Den factory |

## Script Reference

| Script | Purpose |
|--------|---------|
| `script/DeployArachnidFactory.s.sol` | Deploy Arachnid CREATE2 factory (keyless transaction) |
| `script/DeployDenSingletonFactory.s.sol` | Deploy Den Singleton Factory (fallback for EIP-155 chains) |
| `script/DeployLibraries.s.sol` | Deploy 4 platform libraries via CREATE2 |
| `script/DeployContracts.s.sol` | Deploy Safe infrastructure, Safes, implementations, factories, proxies |
| `script/config/DeploymentConfig.sol` | Deterministic salts, factory addresses, Safe configurations |
| `script/sh/deploy_all.sh` | Automated script that runs all steps (uses `PRIVATE_KEY` env var) |
| `test_deploy_scripts_locally.sh` | Local testing script for Anvil |
| `Makefile` | Deployment commands with configurable networks, signers, and factories |

## Deterministic Addresses

All contracts use pre-defined salts following the ERC-7201 naming convention. Salts are defined in `script/config/DeploymentConfig.sol`:

```solidity
bytes32 internal constant SAFE_SINGLETON_SALT = keccak256("den.external.safe.singleton.v1");
bytes32 internal constant ORG_IMPL_SALT = keccak256("den.mls-wallet.organization.implementation.v1");
// ... etc
```

The CREATE2 address formula is: `keccak256(0xff ++ factory ++ salt ++ keccak256(initCode))[12:]`

This means:
- Same salt + same factory + same bytecode = same address on every chain
- Changing any of these changes the deployed address
