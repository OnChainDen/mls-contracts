# Deployment Guide

This guide covers deploying the Multi-layer Security (MLS) Wallet platform contracts to a new chain.

## Table of Contents

1. [Core Concepts](#core-concepts)
   - [CREATE2 Deterministic Deployment](#create2-deterministic-deployment)
   - [Library Linking](#library-linking)
2. [Prerequisites](#prerequisites)
   - [Required Tools](#required-tools)
   - [Signer Setup](#signer-setup)
3. [Configuration](#configuration)
   - [Networks](#networks)
   - [Signers](#signers)
   - [Factories](#factories)
4. [Deployment Examples](#deployment-examples)
   - [Example 1: Deploy via Arachnid Factory](#example-1-deploy-via-arachnid-factory)
   - [Example 2: Deploy via Den Singleton Factory](#example-2-deploy-via-den-singleton-factory)
5. [Verifying Deployments](#verifying-deployments)
6. [Troubleshooting](#troubleshooting)

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

The [Arachnid Deterministic Deployment Proxy](https://github.com/Arachnid/deterministic-deployment-proxy) is available on most EVM chains and is our preferred factory.

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

| Library | Purpose |
|---------|---------|
| `LibOrganizationPolicy` | Policy validation and enforcement |
| `LibOrganizationAdmin` | Admin operations |
| `LibOrganizationInitialization` | Organization setup |
| `LibOrganizationAccountSignature` | Account signature verification |

#### Why Linking Matters

Without explicit library linking:
- Foundry auto-deploys libraries using regular `CREATE` (nonce-dependent)
- Library addresses differ across chains
- Contracts that reference libraries have different bytecode on each chain

With explicit library linking:
- Libraries are deployed via CREATE2 with deterministic addresses
- The compiler links to these known addresses
- Contract bytecode is identical across all chains

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
# Step 4: Deploy platform libraries and contracts
# -----------------------------------------------------------------------------
# FACTORY=arachnid is the default, so we don't need to specify it
# Libraries are deployed first, then contracts are deployed with library linking

make deploy-platform ACCOUNT=$ACCOUNT

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
# Step 4: Deploy platform libraries and contracts
# -----------------------------------------------------------------------------
# IMPORTANT: Use FACTORY=den-nonprod to:
# - Target the correct factory address
# - Use the correct library addresses (library addresses differ per factory)

make deploy-platform ACCOUNT=$FUNDER_ACCOUNT FACTORY=den-nonprod

# -----------------------------------------------------------------------------
# Deployment complete!
# -----------------------------------------------------------------------------
echo "Deployment complete. Contracts deployed via Den Singleton Factory (non-prod)."
```

---

## Verifying Deployments

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

---

## Quick Reference

### Make Commands

| Command | Description |
|---------|-------------|
| `make fund-arachnid-deployer` | Fund the Arachnid factory deployer |
| `make deploy-arachnid-factory` | Deploy the Arachnid CREATE2 factory |
| `make fund-den-deployer` | Fund a Den factory deployer (requires `DEN_DEPLOYER_ADDRESS`) |
| `make deploy-den-factory` | Deploy the Den Singleton Factory |
| `make deploy-libraries` | Deploy the 4 platform libraries via CREATE2 |
| `make deploy-contracts` | Deploy all contracts with library linking |
| `make deploy-platform` | Full deployment (libraries + contracts) |
| `make check-factory` | Check if a CREATE2 factory exists |
| `make check-all-factories` | Check all factories on a network |
| `make compute-lib-addresses` | Compute expected library addresses for a factory |

### Key Addresses

| Resource | Address |
|----------|---------|
| Arachnid Factory | `0x4e59b44847b379578588920cA78FbF26c0B4956C` |
| Arachnid Deployer (for funding) | `0x3fAB184622Dc19b6109349B94811493BF2a45362` |
| Den Non-Prod Factory | `0xC6123B1C95825f98939C76c8cBCEFDBB1C0D94db` |
| Den Non-Prod Deployer | `0x22002e8661A780d61EF4c86F4a9fFa843A6fea20` |
| Den Prod Factory | *Not yet available* |
| Den Prod Deployer | *Not yet available* |

### Library Addresses by Factory

**Arachnid Factory (`FACTORY=arachnid`):**

| Library | Address |
|---------|---------|
| LibOrganizationPolicy | `0x0c39cb4F67AA70D53ceE37d4c88f11ffDb07E314` |
| LibOrganizationAdmin | `0x744CaFa607273AF5664073d05BE066C6bDbf8201` |
| LibOrganizationInitialization | `0x95A9CDA2a67E48b154d8EFa3B147f31eC6e8147E` |
| LibOrganizationAccountSignature | `0x6A6709A2c898E719A6Ee7635a3963122059655eB` |

**Den Non-Prod Factory (`FACTORY=den-nonprod`):**

| Library | Address |
|---------|---------|
| LibOrganizationPolicy | `0x85c8b8410F0feeFd157496245c37d89F33985cC0` |
| LibOrganizationAdmin | `0xCAE149fD735Cc65290e737BF06855Bba119b6082` |
| LibOrganizationInitialization | `0x384803ADc053682c7f42270De5DF50d37c243913` |
| LibOrganizationAccountSignature | `0xFcBDb3e95De055ac3BAedADA90894E5624Af1162` |

**Den Prod Factory (`FACTORY=den-prod`):**

*Library addresses not yet available. Update this section after deploying libraries via the production Den Singleton Factory.*
