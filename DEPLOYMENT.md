# Deployment Guide

This guide covers deploying the Multi-layer Security (MLS) Wallet platform contracts to a new chain.

## Table of Contents

1. [Core Concepts](#core-concepts)
   - [CREATE2 Deterministic Deployment](#create2-deterministic-deployment)
   - [Library Linking](#library-linking)
   - [Two-Stage Library Deployment](#two-stage-library-deployment)
2. [Prerequisites](#prerequisites)
   - [Required Tools](#required-tools)
   - [Signer Setup](#signer-setup)
3. [Configuration](#configuration)
   - [Networks](#networks)
   - [Signers](#signers)
   - [Factories](#factories)
4. [Safe 1.3.0 Deployment](#safe-130-deployment)
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

---

## Core Concepts

### CREATE2 Deterministic Deployment

All platform contracts are deployed **deterministically** using CREATE2, ensuring the same contract addresses across all chains. This is critical for cross-chain operations.

The CREATE2 address formula is:
```
address = keccak256(0xff ++ factory ++ salt ++ keccak256(initCode))[12:]
```

This means: **Same salt + same factory + same bytecode = same address on every chain**.

#### Arachnid Deterministic Deployer (Preferred)

The [Arachnid Deterministic Deployment Proxy](https://github.com/Arachnid/deterministic-deployment-proxy) is available on most EVM chains and is our preferred factory. It is automatically included in OP Stack chains and is by default deployed to Arbitrum Orbit chains, although Orbit chains can optionally choose to not include it in their initial state.

- **Factory Address:** `0x4e59b44847b379578588920cA78FbF26c0B4956C`
- **How it works:** Uses a pre-signed keyless transaction (Nick's Method) to deploy the factory at a deterministic address without requiring a specific EOA.

#### Den Singleton Factory (Fallback)

Some chains enforce strict **EIP-155 replay protection** and reject the pre-signed keyless transaction used by Arachnid. For these chains, we deploy the **Den Singleton Factory** instead.

The Den Singleton Factory is functionally identical to the Arachnid factory, but is deployed by a specific EOA at **nonce 0** rather than via a pre-signed transaction.

> **CRITICAL:** Because the Den Singleton Factory must be deployed at nonce 0, you must **never accidentally use or burn the nonce** on the deployer EOA. Our deployment scripts have safeguards to prevent this.

##### Production vs Non-Production Deployers

We maintain **separate EOAs** for production and non-production environments. This means the Den Singleton Factory address will be **different** in prod vs non-prod environments.

| Environment | Deployer EOA | Factory Address |
|-------------|--------------|-----------------|
| **Non-Production** | `0x22002e8661A780d61EF4c86F4a9fFa843A6fea20` | `0xC6123B1C95825f98939C76c8cBCEFDBB1C0D94db` |
| **Production** | *Not yet available - update this doc when ready* | *Not yet available* |

> **Important:** When deploying the Den Singleton Factory, you **must** use the correct deployer EOA for your environment. The non-prod deployer should only be used on testnets and local development chains.

---

### Library Linking

Some of our libraries use `public` functions, which Solidity compiles as **external libraries** that are called via `DELEGATECALL`. These libraries must be:

1. **Deployed first** via CREATE2 (to get deterministic addresses)
2. **Linked at compile time** when deploying contracts that depend on them

The four platform libraries that require linking are:

| Library | Purpose | Dependencies |
|---------|---------|--------------|
| `LibOrganizationPolicy` | Policy validation and enforcement | None (independent) |
| `LibOrganizationAdmin` | Admin operations | None (independent) |
| `LibOrganizationInitialization` | Organization setup | Depends on `LibOrganizationAdmin` |
| `LibOrganizationAccountSignature` | Account signature verification | Depends on `LibOrganizationPolicy` |

#### Why Linking Matters

Without explicit library linking:
- Foundry auto-deploys libraries using regular `CREATE` (nonce-dependent)
- Library addresses differ across chains
- Contracts that reference libraries have different bytecode on each chain

With explicit library linking:
- Libraries are deployed via CREATE2 with deterministic addresses
- The compiler links to these known addresses
- Contract bytecode is identical across all chains

#### Two-Stage Library Deployment

Due to inter-library dependencies, libraries must be deployed in **two stages**:

**Stage 1 - Independent Libraries (Policy and Admin):**
These libraries have no dependencies on other platform libraries. They can be deployed without any `--libraries` flags.

**Stage 2 - Dependent Libraries (Init and AccountSig):**
These libraries depend on the independent libraries being linked into their bytecode:
- `LibOrganizationInitialization` imports and uses `LibOrganizationAdmin`
- `LibOrganizationAccountSignature` imports and uses `LibOrganizationPolicy`

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

## Prerequisites

### Required Tools

- [Foundry](https://getfoundry.sh) (`forge` and `cast`)
- `jq` for JSON parsing: `brew install jq` (macOS) or `apt install jq` (Linux)

### Signer Setup

The deployment scripts support two signing methods: **Foundry managed accounts** and **Ledger hardware wallets**.

#### Option A: Foundry Managed Account (Recommended for dev/staging)

Import a wallet from a mnemonic seed phrase into Foundry's encrypted keystore:

```bash
# Import from mnemonic at a specific derivation index (e.g., index 0)
cast wallet import my-deployer --mnemonic "your twelve word mnemonic phrase here" --mnemonic-index 0

# You'll be prompted to create a password to encrypt the keystore

# Example: Import the non-prod Den factory deployer at index 3
cast wallet import den-nonprod-deployer --mnemonic "your twelve word mnemonic phrase here" --mnemonic-index 3
```

To list your imported accounts:
```bash
cast wallet list
```

To get the address of an imported account:
```bash
cast wallet address --account my-deployer
```

#### Option B: Ledger Hardware Wallet (Recommended for production)

No setup required—just connect your Ledger and unlock it.

The default HD path is `m/44'/60'/0'/0/0`. To use a different derivation path, set `HD_PATH`:

```bash
make deploy-libraries SIGNER=ledger SENDER=0xYourLedgerAddress HD_PATH="m/44'/60'/1'/0/0"
```

---

## Configuration

The Makefile supports several configuration variables that control deployment behavior.

### Networks

The `NETWORK` variable specifies the target network. Default is `local` (Anvil on port 8545).

| Value | Description |
|-------|-------------|
| `local` | Local Anvil instance at `http://127.0.0.1:8545` |
| `mainnet` | Ethereum Mainnet |
| `sepolia` | Ethereum Sepolia testnet |
| `polygon` | Polygon Mainnet |
| `arbitrum` | Arbitrum One |
| `optimism` | Optimism Mainnet |
| `base` | Base Mainnet |

You can also pass a custom RPC URL directly:
```bash
make deploy-libraries NETWORK=https://my-custom-rpc.example.com
```

### Signers

The `SIGNER` variable specifies the signing method. Default is `account`.

| Value | Description | Required Variables |
|-------|-------------|-------------------|
| `account` | Foundry managed keystore | `ACCOUNT` (name of imported account) |
| `ledger` | Ledger hardware wallet | `SENDER` (your Ledger address), optionally `HD_PATH` |

When using `SIGNER=account`, the `SENDER` address is automatically derived from your keystore account (you'll be prompted for your password).

### Factories

The `FACTORY` variable specifies which CREATE2 factory to use. Default is `arachnid`.

| Value | Factory Address | Use Case |
|-------|-----------------|----------|
| `arachnid` | `0x4e59b44847b379578588920cA78FbF26c0B4956C` | Most chains (preferred) |
| `den-nonprod` | `0xC6123B1C95825f98939C76c8cBCEFDBB1C0D94db` | Non-prod chains that don't support Arachnid |
| `den-prod` | *Not yet available* | Production chains that don't support Arachnid |

---

## Safe 1.3.0 Deployment

The platform uses Safe (Gnosis Safe) multisig wallets for the **Guardian Safe** and **Admin Safe**. These Safes must be deployed before deploying the platform contracts.

### Why Safe Uses a Separate Profile

Safe 1.3.0 contracts were originally compiled with **Solidity 0.7.6**, and their official deployments use this compiler version. To ensure our Safe deployments produce **identical bytecode** (and therefore identical CREATE2 addresses) to the official Safe deployments, we compile Safe contracts with the same settings.

However, our platform contracts use **Solidity 0.8.33**. Since Foundry can only use one Solidity version per compilation, we maintain a **separate Foundry profile** for Safe deployment:

| Profile | Solidity Version | EVM Target | Purpose |
|---------|------------------|------------|---------|
| `default` | 0.8.33 | Paris | Platform contracts and libraries |
| `safe` | 0.7.6 | Istanbul | Safe 1.3.0 infrastructure and multisigs |

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
# Safe 1.3.0 must be deployed BEFORE platform contracts.
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
# Safe 1.3.0 must be deployed BEFORE platform contracts.
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

## Quick Reference

### Make Commands

| Command | Description |
|---------|-------------|
| `make fund-arachnid-deployer` | Fund the Arachnid factory deployer |
| `make deploy-arachnid-factory` | Deploy the Arachnid CREATE2 factory |
| `make fund-den-deployer` | Fund a Den factory deployer (requires `DEN_DEPLOYER_ADDRESS`) |
| `make deploy-den-factory` | Deploy the Den Singleton Factory |
| `make deploy-safe-infra` | Deploy Safe 1.3.0 infrastructure contracts |
| `make deploy-safe-infra-dry-run` | Simulate Safe infrastructure deployment (no broadcast) |
| `make deploy-safe-multisigs` | Deploy Guardian and Admin Safe multisigs |
| `make deploy-safe-multisigs-dry-run` | Simulate Safe multisig deployment (no broadcast) |
| `make deploy-independent-libs` | Deploy independent libraries (Policy, Admin) via CREATE2 |
| `make deploy-dependent-libs` | Deploy dependent libraries (Init, AccountSig) via CREATE2 |
| `make deploy-libraries` | Deploy all platform libraries (runs both stages) |
| `make deploy-contracts` | Deploy all contracts with library linking |
| `make deploy-platform` | Full deployment (Safe + libraries + contracts) |
| `make deploy-batched-transaction` | Deploy BatchedTransaction contract |
| `make compute-batched-transaction-address` | Preview expected BatchedTransaction address |
| `make deploy-guardian-safe-module` | Deploy SafeExecutorModule for the Guardian Safe |
| `make guardian-safe-add-module` | Approve adding the module to Guardian Safe |
| `make guardian-safe-remove-module` | Approve removing the module from Guardian Safe |
| `make check-guardian-module-status` | Check approval status for Guardian Safe module transaction |
| `make check-factory` | Check if a CREATE2 factory exists |
| `make check-all-factories` | Check all factories on a network |
| `make compute-addresses` | Compute all CREATE2 addresses for a specific factory |
| `make compute-all-addresses` | Compute all CREATE2 addresses for all three factories |

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
