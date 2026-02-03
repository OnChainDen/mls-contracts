# Deployment Guide

This guide covers deploying the Multi-layer Security (MLS) Wallet platform contracts to a new chain.

## Table of Contents

1. [Deployment Quickstart Guide](#deployment-quickstart-guide)
2. [Core Concepts](#core-concepts)
   - [CREATE2 Deterministic Deployment](#create2-deterministic-deployment)
   - [Library Linking](#library-linking)
   - [Two-Stage Library Deployment](#two-stage-library-deployment)
3. [Prerequisites](#prerequisites)
   - [Required Tools](#required-tools)
   - [Project Setup](#project-setup)
   - [Signer Setup](#signer-setup)
4. [Safe 1.4.1 Deployment](#safe-141-deployment)
   - [Why Safe Uses a Separate Profile](#why-safe-uses-a-separate-profile)
   - [Safe Deployment Commands](#safe-deployment-commands)
5. [BatchedTransaction Contract](#batchedtransaction-contract)
   - [Why BatchedTransaction?](#why-batchedtransaction)
   - [Transaction Encoding Format](#transaction-encoding-format)
   - [BatchedTransaction Deployment Commands](#batchedtransaction-deployment-commands)
6. [Safe Executor Module](#safe-executor-module)
   - [Module Overview](#module-overview)
   - [Module Deployment Commands](#module-deployment-commands)
   - [Adding a Module to a Safe](#adding-a-module-to-a-safe)
7. [Deployment Examples](#deployment-examples)
   - [Example 1: Deploy via Arachnid Factory](#example-1-deploy-via-arachnid-factory)
   - [Example 2: Deploy via Den Singleton Factory](#example-2-deploy-via-den-singleton-factory)
8. [Verifying Deployments](#verifying-deployments)
9. [Troubleshooting](#troubleshooting)
10. [Make Reference](#make-reference)
    - [Configuration Variables](#configuration-variables)
    - [Core Commands](#core-commands)
    - [CREATE2 Factory Deployment](#create2-factory-deployment)
    - [Safe 1.4.1 Deployment](#safe-141-deployment-1)
    - [Guardian Safe Executor Module](#guardian-safe-executor-module)
    - [Platform Deployment](#platform-deployment)
    - [Utilities](#utilities)
11. [Contract Addresses](#contract-addresses)

---

## Deployment Quickstart Guide

This quickstart guide walks you through deploying the platform locally for development and testing.

### Prerequisites

Before starting, ensure you have the following installed:
- Node.js >= 18 
- Python 3 (for Slither)

### 1. Install Dependencies

Install the required tools (macOS example):

```bash
# Install Foundry (includes forge and cast)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install solhint globally
npm install -g solhint

# Install Slither (requires Python 3)
pip3 install slither-analyzer

# Install jq and yq
brew install jq yq
```

### 2. Install Git Submodules (Foundry Dependencies)
Run the full setup suite to ensure a clean setup, install dependenices, and build the project:

```bash
make all
```



### 3. Verify Project Setup

Run the full check suite to verify everything is set up correctly:

```bash
make check
```

This runs formatting, linting, static analysis, and the test suite.

### 4. Set Up Foundry Managed Accounts

If testing locally or in a staging environment, you need to set up Foundry managed accounts.

The `test_deploy_scripts_locally.sh` script expects these accounts to be imported into Foundry's keystore:

| Index | Account Name | Address |
|-------|--------------|---------|
| 0 | `test-deployer` | `0x901cab5fdb93571f0f6cd6d643f8b2532f00d2a3` |
| 1 | `test-den-factory-deployer` | `0xfda43c00ba0589bb10bc3b75c3d8e1046e73e328` |
| 2 | `test-guardian-safe-owner` | `0x22002e8661a780d61ef4c86f4a9ffa843a6fea20` |
| 3 | `test-admin-safe-owner` | `0x8da06ab9bbb0736d36c92e10b1d6e23a890fd32f` |
| 4 | `test-guardian-executor` | `0x66fb51bf8c7a973a278578a2e381fb5e89796de1` |


> [!IMPORTANT]
> 1Password has setup instructions for setting up these EOAs to use during development and testing for the Den team.

To import accounts from a mnemonic, use the `cast wallet import` command from Foundry: 

```bash
# Import each account at the appropriate derivation index
cast wallet import test-deployer --mnemonic "your twelve word mnemonic phrase here" --mnemonic-index 0
cast wallet import test-den-factory-deployer --mnemonic "your twelve word mnemonic phrase here" --mnemonic-index 1
cast wallet import test-guardian-safe-owner --mnemonic "your twelve word mnemonic phrase here" --mnemonic-index 2
cast wallet import test-admin-safe-owner --mnemonic "your twelve word mnemonic phrase here" --mnemonic-index 3
cast wallet import test-guardian-executor --mnemonic "your twelve word mnemonic phrase here" --mnemonic-index 4
```

### 5. Run Local Deployment

Deploy locally using the test deployment script:

```bash
# Deploy using the Arachnid factory
script/sh/test_deploy_scripts_locally.sh arachnid

# Or deploy using the Den non-prod factory
script/sh/test_deploy_scripts_locally.sh den-nonprod
```

This script will:
1. Start a local Anvil instance
2. Fund the test accounts
3. Deploy the CREATE2 factory
4. Deploy Safe infrastructure and multisigs
5. Deploy platform libraries (in two stages)
6. Deploy platform contracts
7. Deploy BatchedTransaction
8. Deploy the Guardian Safe Executor Module
9. Add the module to the Guardian Safe

> [!IMPORTANT]
> For production deployment, refer to the script to see the deployment order, and run the same Makefile targets with different networks, accounts (Ledgers), and other configuration as needed.

> [!WARNING]
> If you do not have access to the EOAs that the `script/sh/test_deploy_scripts_locally.sh` script expects, you'll need to import accounts with the same names and update the expected addressess in `deployment.toml` to deploy locally.



---

### CREATE2 Deterministic Deployment

All platform contracts are deployed **deterministically** using CREATE2, ensuring the same contract addresses across all chains. This is critical for cross-chain operations.

The CREATE2 address formula is:
```
address = keccak256(0xff ++ factory ++ salt ++ keccak256(initCode))[12:]
```

This means: **Same salt + same factory + same bytecode = same address on every chain**.

---

## CREATE2 Factories
In order to ensure all contracts are deployed at the same addresses across chains, all contracts must be deployed using a CREATE2 Factory that's deployed at the same address across all chains.

In most cases we'll use the  [Arachnid Deterministic Deployer](#arachnid-deterministic-deployer-preferred) factory, as it's designed to be deployable at the same address across most chains.

On rare occasion, a chain may not support the Arachnid Deterministic Deployer. In those cases, we fall back to using the [Den Singleton Factory](#den-singleton-factory-fallback), which is deployed via CREATE using a heavily guarded EOA to ensure deployment at the same address across chains.

This means that in production, we have two separate sets of addresses for all contracts: one for Arachnid and one for Den Singleton Factory. 

### Arachnid Deterministic Deployer (Preferred)

The [Arachnid Deterministic Deployment Proxy](https://github.com/Arachnid/deterministic-deployment-proxy) is available on most EVM chains and is our preferred factory. It is automatically included in OP Stack chains and is by default deployed to Arbitrum Orbit chains, although Orbit chains can optionally choose to not include it in their initial state.

- **Factory Address:** `0x4e59b44847b379578588920cA78FbF26c0B4956C`
- **How it works:** Uses a pre-signed keyless transaction (Nick's Method) to deploy the factory at a deterministic address without requiring a specific EOA.

### Den Singleton Factory (Fallback)

Some chains enforce strict **EIP-155 replay protection** and reject the pre-signed keyless transaction used by Arachnid. For these chains, we deploy the **Den Singleton Factory** instead.

The Den Singleton Factory is functionally identical to the Arachnid factory, but is deployed by a specific EOA at **nonce 0** rather than via a pre-signed transaction.

> **CRITICAL:** Because the Den Singleton Factory must be deployed at nonce 0, you must **never accidentally use or burn the nonce** on the deployer EOA. Our deployment scripts have safeguards to prevent this.

#### Production vs Non-Production Deployers

We maintain **two separate EOAs** for deploying the Den Singleton Factory: one for production environments and one for non-production environments. This is done to prevent risk of accidentally burning the deployer EOA's nonce 0 during development. 

This means the Den Singleton Factory address will be **different** in prod vs non-prod environments.

| Environment | Deployer EOA | Factory Address |
|-------------|--------------|-----------------|
| **Non-Production** | `0x22002e8661A780d61EF4c86F4a9fFa843A6fea20` | `0xC6123B1C95825f98939C76c8cBCEFDBB1C0D94db` |
| **Production** | *Not yet available - update this doc when ready* | *Not yet available* |

> **Important:** When deploying the Den Singleton Factory, you **must** use the correct deployer EOA for your environment. The non-prod deployer should only be used on testnets and local development chains.

---

## External Libraries & Library Linking

The EVM enforces a strict limit on the bytecode size of smart contracts. 

To circumvent this limitation, some of the libraries used by `OrganizationImplementation.sol` have `public` functions and are deployed as separate contracts onchain. 

The Solidity compiler compiles these libraries as **external libraries**, and inserts `DELEGATECALL` operations into the bytecode of contracts that use those external libraries. 

These external libraries must be:

1. **Deployed before contracts/libraries that use them** via CREATE2 (to get deterministic addresses)
2. **Linked at compile time** when deploying contracts/libraries that depend on them

Note that our external libraries can be broken down into two groups:
- **Independent libraries** – External libraries that do not rely on any other external libraries
- **Dependent libraries** – External libraries that rely on other external libraries (must be deployed after their dependencies) 

The four external libraries that require linking are:

| Library | Purpose | Dependencies |
|---------|---------|--------------|
| `LibOrganizationPolicy` | Policy validation and enforcement | None (independent) |
| `LibOrganizationAdmin` | Admin operations | None (independent) |
| `LibOrganizationInitialization` | Organization setup | Depends on `LibOrganizationAdmin` |
| `LibOrganizationAccountSignature` | Account signature verification | Depends on `LibOrganizationPolicy` |

### Why Linking Matters

Without explicit library linking:
- Foundry auto-deploys libraries using regular `CREATE` (nonce-dependent)
- Library addresses differ across chains
- Contracts that reference libraries have different bytecode on each chain

With explicit library linking:
- Libraries are deployed via CREATE2 with deterministic addresses
- The compiler links to these known addresses
- Contract bytecode is identical across all chains

### Two-Stage Library Deployment

Due to inter-library dependencies, libraries must be deployed in **two stages**:

**Stage 1 - Independent Libraries (Policy and Admin):**
These libraries have no dependencies on other platform libraries. They can be deployed without any `--libraries` flags.

**Stage 2 - Dependent Libraries (Init and AccountSig):**
These libraries depend on the independent libraries being linked into their bytecode:
- `LibOrganizationInitialization` imports and uses `LibOrganizationAdmin`
- `LibOrganizationAccountSignature` imports and uses `LibOrganizationPolicy`

They must be deployed with a `--libraries` flag that informs the compiler to link the external libraries they're dependent on.

When compiling dependent libraries, the Solidity compiler embeds the addresses of the libraries they depend on directly into their bytecode. This means the CREATE2 address of a dependent library is affected by the addresses of its dependencies.

**Why this matters for CREATE2:**

The CREATE2 address formula is:
```
address = keccak256(0xff ++ factory ++ salt ++ keccak256(initCode))[12:]
```

If `LibOrganizationInitialization` is compiled without `LibOrganizationAdmin` being linked, the initCode will have placeholder bytes. When compiled with the correct `--libraries` flag, the Admin address is embedded in the initCode, producing a different hash and therefore a different CREATE2 address.

The Makefile handles this automatically with the `deploy-libraries` target (which runs both stages), or you can run them separately:

```bash
# Deploy independent libraries (Policy, Admin)
make deploy-independent-libs ACCOUNT=my-deployer

# Deploy dependent libraries (Init, AccountSig) - requires --libraries flags
make deploy-dependent-libs ACCOUNT=my-deployer
```

The library addresses depend on which CREATE2 factory is used. Our Makefile handles this automatically via Foundry profiles configured in `foundry.toml`.

---

## Ledger Hardware Wallets (used in production)

To deploy contracts using a ledger: 
1. connect your Ledger and unlock it
2. Set `SIGNER=ledger` and `SENDER=0xYourLedgerAddress` for all `makefile` deployment targets
3. Optionally set `HD_PATH=YourDeriviationPath` for `makefile` deployment targets to use a different deriviation path (The default HD path is `m/44'/60'/0'/0/0`)

Example:

```bash
make deploy-libraries SIGNER=ledger SENDER=0xYourLedgerAddress HD_PATH="m/44'/60'/1'/0/0"
```

---

## Safe 1.4.1 Deployment

The platform uses Safe (Gnosis Safe) multisig wallets for the **Guardian Safe** and **Admin Safe**. These Safes must be deployed before deploying the platform contracts.

### Why Safe Uses a Separate Profile

Safe 1.4.1 contracts were originally compiled with **Solidity 0.7.6**, and their official deployments use this compiler version. To ensure our Safe deployments produce **identical bytecode** (and therefore identical CREATE2 addresses) to the official Safe deployments, we compile Safe contracts with the same settings.

However, our platform contracts use **Solidity 0.8.33**. Since Foundry can only use one Solidity version per compilation, we maintain a **separate Foundry profile** for Safe deployment:

| Profile | Solidity Version | EVM Target | Purpose |
|---------|------------------|------------|---------|
| `default` | 0.8.33 | Paris | Platform contracts and libraries |
| `safe` | 0.7.6 | Istanbul | Safe 1.4.1 infrastructure and multisigs |

The Safe profile is defined in `foundry.toml` under `[profile.safe]`.

### Safe Deployment Commands

Safe deployment is split into **two separate steps** for security. This prevents deploying Safe proxy wallets if the Safe Singleton (implementation) deployment fails, which could allow attackers to frontrun initialization.

#### Step 1: Deploy Safe Infrastructure

```bash
# Deploy Safe infrastructure to a local Anvil instance
make deploy-safe-infra ACCOUNT=my-deployer

# Deploy Safe infrastructure to Sepolia testnet
make deploy-safe-infra NETWORK=sepolia ACCOUNT=my-deployer

# Deploy Safe infrastructure using Den non-prod factory
make deploy-safe-infra FACTORY=den-nonprod NETWORK=sepolia ACCOUNT=my-deployer

# Deploy Safe infrastructure using a Ledger
make deploy-safe-infra NETWORK=mainnet SIGNER=ledger SENDER=0xYourLedgerAddress
```

This deploys the Safe infrastructure contracts:
- GnosisSafe singleton (master copy)
- GnosisSafeProxyFactory
- CompatibilityFallbackHandler
- MultiSend
- MultiSendCallOnly
- CreateCall
- SimulateTxAccessor

#### Step 2: Deploy Safe Multisigs

After infrastructure is deployed, deploy the Guardian and Admin Safe multisigs:

```bash
# Deploy Safe multisigs to a local Anvil instance
make deploy-safe-multisigs ACCOUNT=my-deployer

# Deploy Safe multisigs to Sepolia testnet
make deploy-safe-multisigs NETWORK=sepolia ACCOUNT=my-deployer

# Deploy Safe multisigs using Den non-prod factory
make deploy-safe-multisigs FACTORY=den-nonprod NETWORK=sepolia ACCOUNT=my-deployer

# Deploy Safe multisigs using a Ledger
make deploy-safe-multisigs NETWORK=mainnet SIGNER=ledger SENDER=0xYourLedgerAddress
```

This script:
1. **Verifies** that Safe infrastructure is deployed at expected addresses
2. Deploys the Guardian Safe and Admin Safe multisig proxies

> **Security Note**: The multisig deployment script will **fail** if Safe infrastructure is not deployed. This prevents the dangerous scenario where Safe proxies are deployed without the Singleton, which would allow attackers to call `setup()` and take control of the multisigs.

#### Preview Safe Addresses (Dry Run)

```bash
# Simulate infrastructure deployment without broadcasting
make deploy-safe-infra-dry-run NETWORK=sepolia

# Simulate multisig deployment without broadcasting
make deploy-safe-multisigs-dry-run NETWORK=sepolia
```

#### Compute Expected Safe Addresses

Preview the expected Safe addresses without deploying. This is useful for verifying addresses before deployment or updating configuration files.

```bash
# Compute addresses for Arachnid factory
make compute-addresses FACTORY=arachnid

# Compute addresses for Den non-prod factory
make compute-addresses FACTORY=den-nonprod
```

### Safe Deployment Workflow

Safe deployment only needs to happen **once per chain per factory**. After the first deployment:

1. The deployed addresses are **hardcoded** in `deployment.toml`
2. The `DeployContracts.s.sol` script **verifies** that Safes are deployed before proceeding
3. Running deploy commands again will **skip** already-deployed contracts (idempotent)

The full deployment order is:

```text
1. Deploy CREATE2 Factory (if not already deployed)
   └── make deploy-arachnid-factory  OR  make deploy-den-factory

2a. Deploy Safe Infrastructure
    └── make deploy-safe-infra

2b. Deploy Safe Multisigs (verifies infra is deployed first)
    └── make deploy-safe-multisigs

3. Deploy Platform Libraries (two stages due to inter-library dependencies)
   ├── Stage 1: make deploy-independent-libs  (Policy, Admin)
   └── Stage 2: make deploy-dependent-libs    (Init, AccountSig)
   └── Or: make deploy-libraries              (runs both stages)

4. Deploy Platform Contracts
   └── make deploy-contracts
```

Or use the convenience target that runs steps 2a-4:

```bash
make deploy-platform NETWORK=sepolia ACCOUNT=my-deployer
```

---

## BatchedTransaction Contract

The `BatchedTransaction` contract is a security-focused alternative to `MultiSendCallOnly` that provides secure batched transaction execution when delegatecalled from a Safe.

### Why BatchedTransaction?

When `SafeExecutorModule` delegatecalls to a batching contract, sub-transactions can potentially:
1. Transfer ETH via non-zero `value` fields
2. Call the Safe address to modify owners/modules
3. Perform other malicious operations

`BatchedTransaction` addresses these vulnerabilities with:

- **No value field**: ETH value is hardcoded to 0 in the encoding, preventing ETH transfers
- **address(this) validation**: When delegatecalled, `address(this)` is the Safe, and calls to `address(this)` are blocked
- **Efficient encoding**: `28 + N bytes` per transaction (vs `85 + N bytes` for MultiSendCallOnly)

### Transaction Encoding Format

Transactions are packed sequentially with no padding:

```
[to (20 bytes)][dataLength (8 bytes)][data (N bytes)][to (20 bytes)][dataLength (8 bytes)][data (N bytes)]...
```

| Field | Size | Description |
|-------|------|-------------|
| `to` | 20 bytes | Target contract address |
| `dataLength` | 8 bytes | Length of calldata (uint64) |
| `data` | N bytes | Calldata to execute |

### BatchedTransaction Deployment Commands

#### Deploy BatchedTransaction

```bash
# Deploy to local Anvil instance
make deploy-batched-transaction ACCOUNT=my-deployer

# Deploy to Sepolia testnet
make deploy-batched-transaction NETWORK=sepolia ACCOUNT=my-deployer

# Deploy using Den non-prod factory
make deploy-batched-transaction FACTORY=den-nonprod NETWORK=sepolia ACCOUNT=my-deployer

# Deploy using a Ledger
make deploy-batched-transaction NETWORK=mainnet SIGNER=ledger SENDER=0xYourLedgerAddress
```

#### Compute Expected Address

Preview the expected address without deploying:

```bash
make compute-batched-transaction-address NETWORK=sepolia
make compute-batched-transaction-address FACTORY=den-nonprod NETWORK=mainnet
```

### Deployment Order

**IMPORTANT**: BatchedTransaction must be deployed BEFORE SafeExecutorModules.

```
1. Deploy CREATE2 Factory (if not already deployed)
2. Deploy Safe Infrastructure and Multisigs
3. Deploy Platform Libraries
4. Deploy Platform Contracts
5. Deploy BatchedTransaction     ← Must be before modules
6. Deploy SafeExecutorModules    ← Depends on BatchedTransaction
7. Add Modules to Safes
```

---

## Safe Executor Module

The Safe Executor Module allows a designated EOA (the "Safe Executor EOA") to execute contract calls on behalf of a Safe multisig without requiring multisig signatures for every transaction.

### Module Overview

The `SafeExecutorModule` is a minimal Safe module with the following properties:

- **Single Safe Executor EOA**: Only one EOA can execute transactions via the module
- **Immutable configuration**: The Safe Executor EOA cannot be changed after deployment
- **Restricted operations**:
  - Uses `CALL` for all targets, except `DELEGATECALL` is allowed ONLY to `BatchedTransaction`
  - No ETH transfers (value must always be zero)
  - No calls to the Safe itself (prevents ownership/module modifications)

The `DELEGATECALL` exception for `BatchedTransaction` enables batching multiple calls into a single transaction, which is essential for complex operations that need to be atomic.

To rotate the Safe Executor EOA, deploy a new module instance and have Safe owners swap modules via multisig transaction.

### Module Deployment Commands

#### Deploy the Guardian Safe Module

Deploy a SafeExecutorModule for the Guardian Safe:

```bash
# Deploy module for Guardian Safe
make deploy-guardian-safe-module EXECUTOR=0xYourExecutorAddress NETWORK=sepolia ACCOUNT=my-deployer

# Deploy using Den non-prod factory
make deploy-guardian-safe-module EXECUTOR=0xYourExecutorAddress FACTORY=den-nonprod NETWORK=sepolia ACCOUNT=my-deployer

# Deploy with Ledger
make deploy-guardian-safe-module EXECUTOR=0xYourExecutorAddress NETWORK=mainnet SIGNER=ledger SENDER=0x...
```

The script validates:
1. The executor address matches the expected address in `deployment.toml`
2. The Guardian Safe is deployed at the expected address
3. The `BatchedTransaction` contract is deployed at the expected address
4. The CREATE2 factory is deployed

### Adding the Module to the Guardian Safe

After deploying the module, Guardian Safe owners must approve adding it. This is a multisig operation that requires threshold approvals.

#### Approve Adding the Module

Each Guardian Safe owner runs this command to submit their approval:

```bash
# Approve adding module to Guardian Safe (execute if threshold is met)
make guardian-safe-add-module EXECUTE=true NETWORK=sepolia ACCOUNT=safe-owner-1

# Approve without auto-executing (just submit approval)
make guardian-safe-add-module EXECUTE=false NETWORK=mainnet SIGNER=ledger SENDER=0x...
```

When `EXECUTE=true` and the approval threshold is met, the transaction is automatically executed.

#### Check Approval Status

Check how many approvals exist for a module transaction:

```bash
# Check status for adding Guardian module
make check-guardian-module-status ACTION=add NETWORK=sepolia

# Check status for removing Guardian module
make check-guardian-module-status ACTION=remove NETWORK=mainnet
```

#### Remove the Module

If you need to remove the module (e.g., to rotate the authorized executor):

```bash
# Approve removing module from Guardian Safe
make guardian-safe-remove-module EXECUTE=true NETWORK=sepolia ACCOUNT=safe-owner-1
```

### Module Deployment Workflow

The typical workflow for deploying and enabling the module is:

```
1. Deploy the module
   └── make deploy-guardian-safe-module EXECUTOR=0x... ...

2. Each Guardian Safe owner approves adding the module
   └── make guardian-safe-add-module EXECUTE=true ...
   └── (repeat for each owner until threshold is met)

3. Module is now active and the executor can use it
```

To rotate an executor:

```
1. Deploy a new module with the new executor address
   └── make deploy-guardian-safe-module EXECUTOR=0xNewExecutor ...

2. Guardian Safe owners approve adding the new module
   └── make guardian-safe-add-module EXECUTE=true ...

3. Guardian Safe owners approve removing the old module
   └── make guardian-safe-remove-module EXECUTE=true ...
```

---

## Deployment Examples

### Example 1: Deploy via Arachnid Factory

This example deploys the full platform to a local Anvil instance using the Arachnid factory.

```bash
#!/bin/bash
# =============================================================================
# Example: Full deployment using Arachnid Deterministic Deployer
# =============================================================================

# Configuration
PORT="8545"
RPC_URL="http://127.0.0.1:$PORT"
ACCOUNT="my-deployer"  # Name of your Foundry keystore account

# -----------------------------------------------------------------------------
# Step 1: Start local Anvil instance
# -----------------------------------------------------------------------------
# Uses default chain ID 31337 (local development)
# --disable-default-create2-deployer: Don't deploy Anvil's default CREATE2 factory
#   (we want to deploy Arachnid ourselves to match production behavior)
pkill anvil  # Kill any existing Anvil instances
anvil --disable-default-create2-deployer -p $PORT &

# Wait for Anvil to start
sleep 3

# -----------------------------------------------------------------------------
# Step 2: Fund the deployer account
# -----------------------------------------------------------------------------
# Get the deployer address from our Foundry keystore
SENDER=$(cast wallet address --account $ACCOUNT)

# Fund the deployer with ETH (Anvil-specific RPC call)
cast rpc anvil_setBalance $SENDER 0xffffffffffffffffffffffffffffffff --rpc-url $RPC_URL

# -----------------------------------------------------------------------------
# Step 3: Fund and deploy the Arachnid factory
# -----------------------------------------------------------------------------
# The Arachnid factory uses a pre-signed keyless transaction.
# We first fund the pre-determined deployer address, then broadcast the pre-signed tx.

make fund-arachnid-deployer ACCOUNT=$ACCOUNT

make deploy-arachnid-factory ACCOUNT=$ACCOUNT

# -----------------------------------------------------------------------------
# Step 4: Deploy Safe infrastructure and multisigs
# -----------------------------------------------------------------------------
# Safe 1.4.1 must be deployed BEFORE platform contracts.
# This uses FOUNDRY_PROFILE=safe internally (Solidity 0.7.6).
# Safe deployment is split into two steps for security:
#   - Step 4a: Infrastructure (singleton, proxy factory, handlers)
#   - Step 4b: Multisigs (verifies infra is deployed first)

make deploy-safe-infra ACCOUNT=$ACCOUNT
make deploy-safe-multisigs ACCOUNT=$ACCOUNT

# -----------------------------------------------------------------------------
# Step 5: Deploy platform libraries (two stages)
# -----------------------------------------------------------------------------
# FACTORY=arachnid is the default, so we don't need to specify it
# Libraries must be deployed in two stages due to inter-library dependencies:
#   Stage 1: Independent libraries (Policy, Admin) - no dependencies
#   Stage 2: Dependent libraries (Init, AccountSig) - depend on Policy/Admin

make deploy-independent-libs ACCOUNT=$ACCOUNT
make deploy-dependent-libs ACCOUNT=$ACCOUNT

# Or use the convenience target that runs both stages:
# make deploy-libraries ACCOUNT=$ACCOUNT

# -----------------------------------------------------------------------------
# Step 6: Deploy platform contracts
# -----------------------------------------------------------------------------
# Contracts are deployed with library linking via FOUNDRY_PROFILE

make deploy-contracts ACCOUNT=$ACCOUNT

# Or use the convenience target (includes Safe deployment + both library stages):
# make deploy-platform ACCOUNT=$ACCOUNT

# -----------------------------------------------------------------------------
# Deployment complete!
# -----------------------------------------------------------------------------
echo "Deployment complete. Contracts deployed via Arachnid factory."
```

### Example 2: Deploy via Den Singleton Factory

This example deploys to a local Anvil instance using the Den Singleton Factory. Use this approach when deploying to chains that don't support the Arachnid pre-signed transaction.

```bash
#!/bin/bash
# =============================================================================
# Example: Full deployment using Den Singleton Factory (Non-Production)
# =============================================================================
# Use this when the target chain enforces strict EIP-155 and rejects
# the Arachnid keyless transaction.

# Configuration
PORT="8545"
RPC_URL="http://127.0.0.1:$PORT"

# IMPORTANT: For Den Singleton Factory, you need TWO accounts:
# 1. A funder account (any account with ETH to fund the deployer)
# 2. The specific Den factory deployer account (MUST be at nonce 0)
FUNDER_ACCOUNT="my-deployer"

# The Den factory deployer for non-production environments
# This MUST match NON_PROD_DEN_FACTORY_DEPLOYER_ADDRESS in DeploymentConfig.sol
DEN_DEPLOYER_ACCOUNT="den-nonprod-deployer"
DEN_DEPLOYER_ADDRESS="0x22002e8661A780d61EF4c86F4a9fFa843A6fea20"

# -----------------------------------------------------------------------------
# Step 1: Start local Anvil instance
# -----------------------------------------------------------------------------
# Uses default chain ID 31337 (local development)
pkill anvil
anvil --disable-default-create2-deployer -p $PORT &

sleep 3

# -----------------------------------------------------------------------------
# Step 2: Fund accounts
# -----------------------------------------------------------------------------
# Fund the funder account
FUNDER_ADDRESS=$(cast wallet address --account $FUNDER_ACCOUNT)
cast rpc anvil_setBalance $FUNDER_ADDRESS 0xffffffffffffffffffffffffffffffff --rpc-url $RPC_URL

# Fund the Den factory deployer account
cast rpc anvil_setBalance $DEN_DEPLOYER_ADDRESS 0xffffffffffffffffffffffffffffffff --rpc-url $RPC_URL

# -----------------------------------------------------------------------------
# Step 3: Deploy the Den Singleton Factory
# -----------------------------------------------------------------------------
# CRITICAL: This must be run from the Den deployer account at nonce 0!
# The deployment script will verify the nonce is 0 and fail if not.

make deploy-den-factory ACCOUNT=$DEN_DEPLOYER_ACCOUNT

# -----------------------------------------------------------------------------
# Step 4: Deploy Safe infrastructure and multisigs
# -----------------------------------------------------------------------------
# Safe 1.4.1 must be deployed BEFORE platform contracts.
# This uses FOUNDRY_PROFILE=safe internally (Solidity 0.7.6).
# Safe deployment is split into two steps for security:
#   - Step 4a: Infrastructure (singleton, proxy factory, handlers)
#   - Step 4b: Multisigs (verifies infra is deployed first)
# IMPORTANT: Use FACTORY=den-nonprod to target the correct factory address.

make deploy-safe-infra ACCOUNT=$FUNDER_ACCOUNT FACTORY=den-nonprod
make deploy-safe-multisigs ACCOUNT=$FUNDER_ACCOUNT FACTORY=den-nonprod

# -----------------------------------------------------------------------------
# Step 5: Deploy platform libraries (two stages)
# -----------------------------------------------------------------------------
# IMPORTANT: Use FACTORY=den-nonprod to:
# - Target the correct factory address
# - Use the correct library addresses (library addresses differ per factory)
#
# Libraries must be deployed in two stages due to inter-library dependencies

make deploy-independent-libs ACCOUNT=$FUNDER_ACCOUNT FACTORY=den-nonprod
make deploy-dependent-libs ACCOUNT=$FUNDER_ACCOUNT FACTORY=den-nonprod

# Or use the convenience target that runs both stages:
# make deploy-libraries ACCOUNT=$FUNDER_ACCOUNT FACTORY=den-nonprod

# -----------------------------------------------------------------------------
# Step 6: Deploy platform contracts
# -----------------------------------------------------------------------------
make deploy-contracts ACCOUNT=$FUNDER_ACCOUNT FACTORY=den-nonprod

# Or use the convenience target (includes Safe deployment + both library stages):
# make deploy-platform ACCOUNT=$FUNDER_ACCOUNT FACTORY=den-nonprod

# -----------------------------------------------------------------------------
# Deployment complete!
# -----------------------------------------------------------------------------
echo "Deployment complete. Contracts deployed via Den Singleton Factory (non-prod)."
```

---

## Verifying Deployments

### Compute All Expected Addresses

Before deploying, you can preview all expected CREATE2 addresses for all contracts across all three factories:

```bash
# Compute addresses for all factories (arachnid, den-nonprod, den-prod)
make compute-all-addresses

# Compute addresses for a specific factory
make compute-addresses FACTORY=arachnid
make compute-addresses FACTORY=den-nonprod
```

This runs the `compute_all_addresses.sh` script which orchestrates calls to all deployment scripts' `computeAddresses()` functions, handles library linking correctly, and outputs all expected addresses in a formatted table.

### Check Factory Deployment

Verify which CREATE2 factories are deployed on a network:

```bash
# Check all factories on a network
make check-all-factories NETWORK=sepolia

# Check a specific factory
make check-factory FACTORY=arachnid NETWORK=mainnet
```

### Check Contract Deployment

Use `cast code` to verify a contract is deployed at an address:

```bash
# Check if bytecode exists at an address (returns "0x" if not deployed)
cast code 0x4e59b44847b379578588920cA78FbF26c0B4956C --rpc-url $RPC_URL

# Check Arachnid factory on mainnet
cast code 0x4e59b44847b379578588920cA78FbF26c0B4956C --rpc-url mainnet

# Check Den non-prod factory on sepolia
cast code 0xC6123B1C95825f98939C76c8cBCEFDBB1C0D94db --rpc-url sepolia
```

### Compute Expected Library Addresses

Before deploying, compute the expected library addresses for a factory:

```bash
# Compute addresses for Arachnid factory
make compute-lib-addresses FACTORY=arachnid NETWORK=mainnet

# Compute addresses for all factories
make compute-all-lib-addresses NETWORK=sepolia
```

### Verify a Specific Contract

Verify a contract on Etherscan:

```bash
make verify CONTRACT_ADDRESS=0x1234... CONTRACT_NAME=OrganizationImplementation NETWORK=mainnet
```

### Check Deployer Nonce (Den Factory Only)

Before deploying the Den Singleton Factory, verify the deployer nonce is 0:

```bash
# Check nonce of the non-prod Den deployer
cast nonce 0x22002e8661A780d61EF4c86F4a9fFa843A6fea20 --rpc-url $RPC_URL
```

If the nonce is not 0, the Den Singleton Factory **cannot** be deployed at its deterministic address on this chain. Use the Arachnid factory instead (if supported), or contact the team.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `Factory address cannot be zero` | Pass the CREATE2 factory address as an argument: `--sig "run(address)" <factory-address>` |
| `CREATE2 factory not deployed` | Run factory deployment first, or use `make check-factory` to verify |
| `Deployer nonce is not 0` | The Den Singleton Factory cannot be deployed at its deterministic address on this chain. Use Arachnid factory instead. |
| `Already deployed` messages | Normal—the script skips contracts that already exist at their deterministic addresses |
| Library address mismatch | Ensure you're using the correct `FACTORY` value. Each factory has different library addresses. |
| `ACCOUNT is required` | Set `ACCOUNT=<keystore-name>` when using `SIGNER=account` |
| `SENDER is required` | Set `SENDER=<your-address>` when using `SIGNER=ledger` |
| `Invalid FACTORY value` | Use one of: `arachnid`, `den-prod`, `den-nonprod` |
| Den factory library addresses are 0x0 | Library addresses for Den prod are not yet configured. Update `foundry.toml` after deploying. |
| `Safe multisigs not deployed` | Run `make deploy-safe` before `make deploy-contracts`. Safe infrastructure must be deployed first. |
| Safe compilation errors with 0.8.x | Safe deployment uses `FOUNDRY_PROFILE=safe` (Solidity 0.7.6). Use `make deploy-safe`, not direct `forge script`. |
| Safe addresses differ from expected | Each CREATE2 factory produces different addresses. Ensure you're using the correct `FACTORY` value. |

---

## Make Reference

This section provides a complete reference for all Makefile commands and configuration options.

Run `make help` to see the full list of available commands and examples.

### Configuration Variables

All deployment commands support the following configuration variables:

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `NETWORK` | Target network (local, mainnet, sepolia, polygon, arbitrum, optimism, base) or custom RPC URL | `local` | `NETWORK=sepolia` |
| `SIGNER` | Signing method: `account` (Foundry keystore) or `ledger` (hardware wallet) | `account` | `SIGNER=ledger` |
| `ACCOUNT` | Foundry keystore account name (required for `SIGNER=account`) | - | `ACCOUNT=my-deployer` |
| `SENDER` | EOA address (auto-derived from `ACCOUNT`, required for `SIGNER=ledger`) | - | `SENDER=0x1234...` |
| `FACTORY` | CREATE2 factory: `arachnid`, `den-prod`, or `den-nonprod` | `arachnid` | `FACTORY=den-nonprod` |
| `HD_PATH` | Ledger HD derivation path | `m/44'/60'/0'/0/0` | `HD_PATH="m/44'/60'/1'/0/0"` |
| `VERBOSITY` | Forge verbosity level | `-vvvv` | `VERBOSITY=-vvv` |
| `EXECUTOR` | Guardian Executor EOA address (for `deploy-guardian-safe-module`) | - | `EXECUTOR=0x5678...` |
| `EXECUTE` | Execute transaction if threshold met: `true` or `false` | - | `EXECUTE=true` |
| `ACTION` | Action to check status for: `add` or `remove` (for `check-guardian-module-status`) | - | `ACTION=add` |

**Factory Addresses:**

| Value | Factory Address | Use Case |
|-------|-----------------|----------|
| `arachnid` | `0x4e59b44847b379578588920cA78FbF26c0B4956C` | Most chains (preferred) |
| `den-nonprod` | `0xC6123B1C95825f98939C76c8cBCEFDBB1C0D94db` | Non-prod chains that don't support Arachnid |
| `den-prod` | *Not yet available* | Production chains that don't support Arachnid |

You can pass a custom RPC URL directly via `NETWORK`:

```bash
make deploy-libraries NETWORK=https://my-custom-rpc.example.com ACCOUNT=my-deployer
```

### Core Commands

| Command | Description |
|---------|-------------|
| `make all` | Clean, reinstall dependencies, and build (default) |
| `make build` | Compile contracts |
| `make test` | Run tests |
| `make check` | Run all checks (format, lint, analyze, sizes, test) |
| `make format` | Fix code formatting |
| `make lint` | Check code style (no fixes) |
| `make check-headers` | Verify SPDX license and copyright headers |
| `make analyze` | Run Slither static analysis |
| `make sizes` | Show contract sizes |
| `make coverage` | Generate test coverage report |
| `make snapshot` | Generate gas snapshot |
| `make gas-report` | Run tests with gas reporting |
| `make clean` | Remove build artifacts |
| `make remove` | Remove dependencies (lib/) |
| `make install` | Install dependencies |
| `make update` | Update dependencies |

### CREATE2 Factory Deployment

| Command | Description |
|---------|-------------|
| `make fund-arachnid-deployer` | Fund the Arachnid factory deployer |
| `make deploy-arachnid-factory` | Deploy the Arachnid CREATE2 factory |
| `make fund-den-deployer` | Fund a Den factory deployer (requires `DEN_DEPLOYER_ADDRESS`) |
| `make deploy-den-factory` | Deploy the Den Singleton Factory |

### Safe 1.4.1 Deployment

| Command | Description |
|---------|-------------|
| `make deploy-safe-infra` | Deploy Safe 1.4.1 infrastructure contracts |
| `make deploy-safe-infra-dry-run` | Simulate Safe infrastructure deployment (no broadcast) |
| `make deploy-safe-multisigs` | Deploy Guardian and Admin Safe multisigs |
| `make deploy-safe-multisigs-dry-run` | Simulate Safe multisig deployment (no broadcast) |

### Guardian Safe Executor Module

| Command | Description |
|---------|-------------|
| `make deploy-batched-transaction` | Deploy BatchedTransaction contract |
| `make deploy-guardian-safe-module` | Deploy SafeExecutorModule for the Guardian Safe (requires `EXECUTOR`) |
| `make guardian-safe-add-module` | Approve adding the module to Guardian Safe (requires `EXECUTE`) |
| `make guardian-safe-remove-module` | Approve removing the module from Guardian Safe (requires `EXECUTE`) |
| `make check-guardian-module-status` | Check approval status for Guardian Safe module transaction (requires `ACTION`) |

### Platform Deployment

| Command | Description |
|---------|-------------|
| `make deploy-independent-libs` | Deploy independent libraries (Policy, Admin) via CREATE2 |
| `make deploy-dependent-libs` | Deploy dependent libraries (Init, AccountSig) via CREATE2 |
| `make deploy-libraries` | Deploy all platform libraries (runs both stages) |
| `make deploy-contracts` | Deploy platform contracts with library linking |
| `make deploy-platform` | Full deployment (Safe infra + multisigs + libraries + contracts) |
| `make deploy-independent-libs-dry-run` | Simulate independent library deployment (no broadcast) |
| `make deploy-dependent-libs-dry-run` | Simulate dependent library deployment (no broadcast) |
| `make deploy-libraries-dry-run` | Simulate all library deployment (no broadcast) |
| `make deploy-contracts-dry-run` | Simulate contract deployment (no broadcast) |
| `make deploy-platform-dry-run` | Simulate full platform deployment (no broadcast) |

### Utilities

| Command | Description |
|---------|-------------|
| `make check-factory` | Check if a factory is deployed |
| `make check-all-factories` | Check all factories on a network |
| `make compute-addresses` | Compute all CREATE2 addresses for a factory |
| `make compute-all-addresses` | Compute all CREATE2 addresses for all factories |
| `make verify` | Verify a contract on Etherscan (requires `CONTRACT_ADDRESS`, `CONTRACT_NAME`) |

**Examples:**

```bash
# Deploy libraries to Sepolia using a Foundry keystore account
make deploy-libraries NETWORK=sepolia ACCOUNT=my-deployer

# Deploy full platform to mainnet using Ledger
make deploy-platform FACTORY=arachnid NETWORK=mainnet SIGNER=ledger SENDER=0x...

# Check all factories on mainnet
make check-all-factories NETWORK=mainnet

# Deploy Guardian Safe module
make deploy-guardian-safe-module EXECUTOR=0x... NETWORK=sepolia ACCOUNT=my-deployer

# Approve adding Guardian module (Safe owner operation)
make guardian-safe-add-module EXECUTE=true NETWORK=sepolia ACCOUNT=safe-owner

# Verify a contract on Etherscan
make verify CONTRACT_ADDRESS=0x1234... CONTRACT_NAME=OrganizationImplementation NETWORK=mainnet
```

---

## Contract Addresses

### Key Addresses

| Resource | Address |
|----------|---------|
| Arachnid Factory | `0x4e59b44847b379578588920cA78FbF26c0B4956C` |
| Arachnid Deployer (for funding) | `0x3fAB184622Dc19b6109349B94811493BF2a45362` |

### Deployed Contract Addresses

All deployed contract addresses (libraries, Safe infrastructure, platform contracts) are stored in the **`deployment.toml`** configuration file at the repository root.

The file is organized by factory (`[factory.arachnid]`, `[factory.den-nonprod]`, `[factory.den-prod]`), with each section containing all contract addresses for that factory.

```bash
# View all addresses for a specific factory
grep -A 50 '\[factory.arachnid\]' deployment.toml
```

To compute expected addresses before deployment, use:

```bash
# Compute all addresses for all factories
make compute-all-addresses

# Compute addresses for a specific factory
make compute-addresses FACTORY=arachnid
```
