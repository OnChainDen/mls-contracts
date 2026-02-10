# Deployment Guide

This guide covers deploying the Multi-layer Security (MLS) Wallet platform contracts to a new chain.

## Table of Contents

1. [Deployment Quickstart Guide](#deployment-quickstart-guide)
   - [Prerequisites](#prerequisites)
   - [1. Install Dependencies](#1-install-dependencies)
   - [2. Install Git Submodules (Foundry Dependencies)](#2-install-git-submodules-foundry-dependencies)
   - [3. Verify Project Setup](#3-verify-project-setup)
   - [4. Set Up Foundry Managed Accounts](#4-set-up-foundry-managed-accounts)
   - [5. Run Local Deployment](#5-run-local-deployment)
2. [Deployment Order](#deployment-order)
   - [Step 1: Deploy CREATE2 Factory](#step-1-deploy-create2-factory)
   - [Step 2: Deploy Safe Infrastructure](#step-2-deploy-safe-infrastructure)
   - [Step 3: Deploy Safe Multisigs](#step-3-deploy-safe-multisigs)
   - [Step 4: Deploy Independent Libraries](#step-4-deploy-independent-libraries)
   - [Step 5: Deploy Dependent Libraries](#step-5-deploy-dependent-libraries)
   - [Step 6: Deploy Platform Contracts](#step-6-deploy-platform-contracts)
   - [Step 7: Deploy BatchedTransaction](#step-7-deploy-batchedtransaction)
   - [Step 8: Deploy Guardian Safe Executor Module](#step-8-deploy-guardian-safe-executor-module)
   - [Step 9: Add Module to Guardian Safe](#step-9-add-module-to-guardian-safe)
   - [Full Deployment Quick Reference](#full-deployment-quick-reference)
3. [Deployment Example (Arachnid Factory)](#deployment-example-arachnid-factory)
4. [Deploying with Ledger Hardware Wallets (production)](#deploying-with-ledger-hardware-wallets-production)
5. [Expected Contract Addresses](#expected-contract-addresses)
   - [deployment.toml Overview](#deploymenttoml-overview)
   - [How deployment.toml Is Used](#how-deploymenttoml-is-used)
   - [Computing Expected Addresses](#computing-expected-addresses)
   - [How Address Computation Works](#how-address-computation-works)
   - [Address Dependencies](#address-dependencies)
   - [Updating Addresses](#updating-addresses)
6. [CREATE2 Deterministic Deployment](#create2-deterministic-deployment)
7. [CREATE2 Factories](#create2-factories)
   - [Arachnid Deterministic Deployer (Preferred)](#arachnid-deterministic-deployer-preferred)
   - [Den Singleton Factory (Fallback)](#den-singleton-factory-fallback)
8. [External Libraries & Library Linking](#external-libraries--library-linking)
   - [Why Linking Matters](#why-linking-matters)
   - [Two-Stage Library Deployment](#two-stage-library-deployment)
9. [Make Reference](#make-reference)
   - [Configuration Variables](#configuration-variables)
   - [Core Commands](#core-commands)
   - [CREATE2 Factory Deployment](#create2-factory-deployment)
   - [Safe 1.4.1 Deployment](#safe-141-deployment)
   - [Guardian Safe Executor Module](#guardian-safe-executor-module)
   - [Platform Deployment](#platform-deployment)
   - [Utilities](#utilities)

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
Run the full setup suite to ensure a clean environment, install dependencies, and build the project:

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
>
> [!WARNING]
> If you do not have access to the EOAs that the `script/sh/test_deploy_scripts_locally.sh` script expects, you'll need to import accounts with the same names and update the expected addresses in `deployment.toml` to deploy locally.



---


## Deployment Order

This section outlines the complete deployment order for all contracts. Each step must be completed before the next. 

When testing deployment locally, the `script/sh/test_deploy_scripts_locally.sh` script performs all of these steps.

> **Note:** All deployment commands are idempotent—if a contract is already deployed at its deterministic address, the script skips it and continues.

### Step 1: Deploy CREATE2 Factory

All contracts are deployed via CREATE2 to ensure deterministic addresses across chains. Deploy the appropriate factory based on chain support. See [CREATE2 Deterministic Deployment](#create2-deterministic-deployment) to learn more.


**For most chains (Arachnid factory):**

```bash
# Fund the Arachnid deployer, then deploy the factory
make fund-arachnid-deployer ACCOUNT=my-deployer
make deploy-arachnid-factory ACCOUNT=my-deployer
```
To learn more about the Arachnid factory, see [Arachnid Deterministic Deployer (Preferred)](#arachnid-deterministic-deployer-preferred).

**For chains that reject Arachnid's pre-signed transaction (Den factory):**

```bash
# Fund the Den deployer, then deploy the factory
make fund-den-deployer DEN_DEPLOYER_ADDRESS=0x22002e8661A780d61EF4c86F4a9fFa843A6fea20 ACCOUNT=my-deployer
make deploy-den-factory ACCOUNT=den-nonprod-deployer
```

> The [Den factory](#den-singleton-factory-fallback) deployer must be at nonce 0. Use `cast nonce <address>` to verify before deploying.

To learn more about the Den Singleton Factory see [Den Singleton factory](#den-singleton-factory-fallback).

---

### Step 2: Deploy Safe Infrastructure

Deploys the Safe 1.4.1 singleton and supporting contracts (ProxyFactory, FallbackHandler, MultiSend, etc.).

```bash
make deploy-safe-infra ACCOUNT=my-deployer FACTORY=arachnid
```

> **Under the hood:** Uses `FOUNDRY_PROFILE=safe` which compiles with Solidity 0.7.6 (matching official Safe deployments) to ensure identical bytecode and deterministic addresses.

---

### Step 3: Deploy Safe Multisigs

Deploys the Guardian Safe and Admin Safe proxy wallets.

```bash
make deploy-safe-multisigs ACCOUNT=my-deployer FACTORY=arachnid
```

> **Under the hood:** Verifies Safe infrastructure is deployed before proceeding. 

---

### Step 4: Deploy Independent Libraries

Deploys `LibOrganizationPolicy`, `LibOrganizationAdmin`, `LibOrganizationMembers`, `LibOrganizationGroups`, `LibOrganizationTxRecovery`, and `LibOrganizationGuardianRecovery`—external libraries with no dependencies on other platform libraries.

```bash
make deploy-independent-libs ACCOUNT=my-deployer FACTORY=arachnid
```

---

### Step 5: Deploy Dependent Libraries

Deploys `LibOrganizationInitialization` and `LibOrganizationAccountSignature`—external libraries that depend on the independent libraries.

```bash
make deploy-dependent-libs ACCOUNT=my-deployer FACTORY=arachnid
```

> **Under the hood:** Passes `--libraries` flags to link the independent library addresses into the bytecode. This is required because the Solidity compiler embeds dependency addresses directly into dependent library bytecode, affecting their CREATE2 addresses.
>
> See [External Libraries & Library Linking](#external-libraries--library-linking) to learn more.

---

### Step 6: Deploy Platform Contracts

Deploys all platform contracts (`OrganizationImplementation`, `AccountImplementation`, `ImplementationWhitelist`, etc.).

```bash
make deploy-contracts ACCOUNT=my-deployer FACTORY=arachnid
```

> **Under the hood:** Passes `--libraries` flags for all four external libraries to ensure contracts are compiled with the correct linked addresses.
>
> See [External Libraries & Library Linking](#external-libraries--library-linking) to learn more.

---

### Step 7: Deploy BatchedTransaction

Deploys the `BatchedTransaction` contract, a security-focused batched transaction executor.

```bash
make deploy-batched-transaction ACCOUNT=my-deployer FACTORY=arachnid
```

> **Must be deployed before Step 8.** The SafeExecutorModule references BatchedTransaction as the only allowed DELEGATECALL target.

---

### Step 8: Deploy Guardian Safe Executor Module

Deploys the `SafeExecutorModule` for the Guardian Safe, allowing a designated EOA to execute transactions on behalf of the Safe.

```bash
make deploy-guardian-safe-module EXECUTOR=0xYourExecutorAddress ACCOUNT=my-deployer FACTORY=arachnid
```

The `EXECUTOR` address must match the expected Guardian Executor EOA in `deployment.toml`.

---

### Step 9: Add Module to Guardian Safe

Guardian Safe owners must approve adding the module. This is a multisig operation requiring threshold approvals.

```bash
# Each Guardian Safe owner runs this command
make guardian-safe-add-module EXECUTE=true ACCOUNT=guardian-safe-owner FACTORY=arachnid
```

When `EXECUTE=true` and the approval threshold is met, the transaction is automatically executed.

---

### Full Deployment Quick Reference

| Step | Command | Notes |
|------|---------|-------|
| 1 | `make deploy-arachnid-factory` | Or `deploy-den-factory` for unsupported chains |
| 2 | `make deploy-safe-infra` | Uses Solidity 0.7.6 profile |
| 3 | `make deploy-safe-multisigs` | Verifies infrastructure first |
| 4 | `make deploy-independent-libs` | Policy, Admin, Members, Groups, TxRecovery, GuardianRecovery libraries |
| 5 | `make deploy-dependent-libs` | Init, AccountSig libraries (with linking) |
| 6 | `make deploy-contracts` | Platform contracts (with linking) |
| 7 | `make deploy-batched-transaction` | Before SafeExecutorModule |
| 8 | `make deploy-guardian-safe-module` | Requires `EXECUTOR=` |
| 9 | `make guardian-safe-add-module` | Owner multisig operation |

**Convenience targets:**

| Target | Steps | What it deploys |
|--------|-------|-----------------|
| `make deploy-libraries` | 4, 5 | All eight external libraries (Policy, Admin, Members, Groups, TxRecovery, GuardianRecovery, Init, AccountSig) |
| `make deploy-platform` | 2, 3, 4, 5, 6 | Safe infrastructure, Safe multisigs, all libraries, and platform contracts |

> **Note:** Convenience targets do not include Steps 1, 7, 8, or 9. The CREATE2 factory (Step 1) only needs to be deployed once per chain. BatchedTransaction (Step 7), Guardian module (Step 8), and module approval (Step 9) are typically done separately after the core platform is deployed.

---

## Deployment Example (Arachnid Factory)

This example deploys the full platform to a local Anvil instance using the Arachnid factory.

```bash
#!/bin/bash
PORT="8545"
RPC_URL="http://127.0.0.1:$PORT"
ACCOUNT="my-deployer"  # Foundry keystore account name
EXECUTOR="0x66fb51bf8c7a973a278578a2e381fb5e89796de1"  # Guardian Executor EOA

# 1. Start Anvil (disable default CREATE2 factory to match production)
pkill anvil
anvil --disable-default-create2-deployer -p $PORT &
sleep 3

# 2. Fund deployer
SENDER=$(cast wallet address --account $ACCOUNT)
cast rpc anvil_setBalance $SENDER 0xffffffffffffffffffffffffffffffff --rpc-url $RPC_URL

# 3. Deploy Arachnid CREATE2 factory
make fund-arachnid-deployer ACCOUNT=$ACCOUNT
make deploy-arachnid-factory ACCOUNT=$ACCOUNT

# 4. Deploy platform (Safe infra + multisigs + libraries + contracts)
make deploy-platform ACCOUNT=$ACCOUNT

# 5. Deploy BatchedTransaction (required before SafeExecutorModule)
make deploy-batched-transaction ACCOUNT=$ACCOUNT

# 6. Deploy Guardian Safe Executor Module
make deploy-guardian-safe-module EXECUTOR=$EXECUTOR ACCOUNT=$ACCOUNT

# 7. Add module to Guardian Safe (each owner runs this; executes when threshold met)
make guardian-safe-add-module EXECUTE=true ACCOUNT=guardian-safe-owner

echo "Deployment complete."
```

> **Note:** For Den Singleton Factory deployments (chains that reject Arachnid's pre-signed transaction), use `FACTORY=den-nonprod` with all make targets and deploy the factory via `make deploy-den-factory`.


---

## Deploying with Ledger Hardware Wallets (production)

To deploy contracts using a Ledger: 
1. connect your Ledger and unlock it
2. Set `SIGNER=ledger` and `SENDER=0xYourLedgerAddress` for all `Makefile` deployment targets
3. Optionally set `HD_PATH=YourDerivationPath` for `Makefile` deployment targets to use a different derivation path (The default HD path is `m/44'/60'/0'/0/0`)

Example:

```bash
make deploy-libraries SIGNER=ledger SENDER=0xYourLedgerAddress HD_PATH="m/44'/60'/1'/0/0"
```

---


## Expected Contract Addresses

All contract addresses in this project are deterministic, meaning they can be computed before deployment. The `deployment.toml` file serves as the **single source of truth** for all expected addresses.

### deployment.toml Overview

The `deployment.toml` file at the project root contains:

| Section | Description |
|---------|-------------|
| `[factory.*]` | CREATE2 factory addresses and factory-dependent contract addresses (libraries, implementations, Safe infrastructure) |
| `[factory.*.env.*]` | Environment-dependent addresses (prod vs nonprod Safe multisigs, org factory, whitelist proxy, executor modules) |
| `[safe.*]` | Safe multisig configurations (owner addresses, thresholds, executor EOAs) |

The file is organized by CREATE2 factory because contract addresses differ based on which factory is used:

```toml
[factory.arachnid]           # Addresses when using Arachnid factory
[factory.arachnid.env.nonprod]  # Nonprod-specific addresses (1-of-1 Safes)
[factory.arachnid.env.prod]     # Prod-specific addresses (2-of-3 Safes)

[factory.den-nonprod]        # Addresses when using Den non-prod factory
[factory.den-nonprod.env.nonprod]
[factory.den-nonprod.env.prod]

[factory.den-prod]           # Addresses when using Den prod factory (not yet deployed)
...
```

### How deployment.toml Is Used

The `deployment.toml` file is consumed by multiple parts of the deployment system:

**1. Makefile**

The Makefile reads addresses from `deployment.toml` to:
- Generate `--libraries` flags for library linking
- Validate that the correct CREATE2 factory is being used
- Pass expected Safe addresses to deployment scripts

```bash
# Example: deploy-dependent-libs uses library addresses from deployment.toml
make deploy-dependent-libs FACTORY=arachnid ACCOUNT=my-deployer
# → Reads lib_org_policy and lib_org_admin addresses for --libraries flags
```

**2. Test Deployment Script (`script/sh/test_deploy_scripts_locally.sh`)**

The local test script reads from `deployment.toml` to:
- Get the Den factory deployer address for non-prod deployments
- Get Safe owner addresses for multisig deployment
- Get the Guardian Executor EOA address for module deployment

**3. Solidity Deployment Scripts**

The deployment scripts use `deployment.toml` to validate deployments. For example, when deploying the Guardian Safe Executor Module, the script:
- Reads the expected Guardian Safe address from `deployment.toml`
- Reads the expected Guardian Executor EOA from `deployment.toml`
- Reads the expected BatchedTransaction address from `deployment.toml`
- **Reverts if any address doesn't match** what's in the config file

This ensures all deployments are consistent with the expected deterministic addresses.

### Computing Expected Addresses

Use the `make compute-all-addresses` target to compute all expected CREATE2 addresses for all factories:

```bash
make compute-all-addresses
```

This command:
1. Computes addresses for the **Arachnid** factory
2. Computes addresses for the **Den non-prod** factory
3. Computes addresses for the **Den prod** factory

Output is in TOML format for easy comparison with `deployment.toml`.

To compute addresses for a specific factory:

```bash
make compute-addresses FACTORY=arachnid
make compute-addresses FACTORY=den-nonprod
make compute-addresses FACTORY=den-prod
```

### How Address Computation Works

The `compute_all_addresses.sh` script orchestrates address computation by:

1. **Reading factory deployer addresses from `deployment.toml`** — For the Den Singleton Factories (prod and non-prod), the factory address is derived from the deployer EOA at nonce 0. If you change the `factory_deployer` address in `deployment.toml`, all downstream addresses change.

2. **Computing addresses in dependency order:**
   - Safe infrastructure (singleton, proxy factory, handlers)
   - Safe multisigs (Guardian and Admin Safes for both prod and nonprod)
   - Independent libraries (Policy, Admin, Members, Groups)
   - Dependent libraries (Init, AccountSig) — computed with `--libraries` flags
   - Platform implementations (Organization, Account, Whitelist)
   - Platform contracts (OrganizationFactory, WhitelistProxy) — depends on Safe addresses
   - Guardian Safe Executor Modules — depends on Safe and BatchedTransaction addresses

3. **Outputting TOML format** — Compare the output with `deployment.toml` to verify correctness.

### Address Dependencies

Understanding which addresses depend on what is critical:

| Address | Dependencies |
|---------|--------------|
| Factory | Factory deployer EOA (for Den factories) |
| Libraries (Policy, Admin, Members, Groups, TxRecovery, GuardianRecovery) | Factory only |
| Libraries (Init, AccountSig) | Factory + independent library addresses |
| Safe infrastructure | Factory only |
| Safe multisigs | Factory + Safe proxy factory + Safe owner addresses |
| Platform implementations | Factory + all library addresses |
| OrganizationFactory | Factory + libraries + Guardian Safe address |
| WhitelistProxy | Factory + libraries + Admin Safe address |
| Guardian Executor Module | Factory + Guardian Safe + BatchedTransaction + Executor EOA |

> **Key insight:** If the Den factory deployer EOA changes, **all** contract addresses for that factory change. This is why we maintain separate deployer EOAs for production and non-production environments.

### Updating Addresses

When updating `deployment.toml`:

1. Run `make compute-all-addresses` to generate the expected addresses
2. Compare the output with your changes
3. Ensure all dependent addresses are updated (e.g., changing Safe owners affects SafeExecutorModule addresses)
4. Run the test deployment locally to verify: `script/sh/test_deploy_scripts_locally.sh arachnid`

---

## CREATE2 Deterministic Deployment

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

The six external libraries that require linking are:

| Library | Purpose | Dependencies |
|---------|---------|--------------|
| `LibOrganizationPolicy` | Policy validation and enforcement | None (independent) |
| `LibOrganizationAdmin` | Admin operations | None (independent) |
| `LibOrganizationTxRecovery` | Transaction and ERC1271 recovery | None (independent) |
| `LibOrganizationGuardianRecovery` | Guardian recovery operations | None (independent) |
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

**Stage 1 - Independent Libraries (Policy, Admin, Members, Groups, TxRecovery, GuardianRecovery):**
These libraries have no dependencies on other platform libraries. They can be deployed without any `--libraries` flags.

**Stage 2 - Dependent Libraries (Init and AccountSig):**
These libraries depend on the independent libraries being linked into their bytecode:
- `LibOrganizationInitialization` imports and uses `LibOrganizationAdmin`, `LibOrganizationMembers`, and `LibOrganizationGroups`
- `LibOrganizationAccountSignature` imports and uses `LibOrganizationPolicy`

They must be deployed with a `--libraries` flag that informs the compiler to link the external libraries they're dependent on.

When compiling dependent libraries, the Solidity compiler embeds the addresses of the libraries they depend on directly into their bytecode. This means the CREATE2 address of a dependent library is affected by the addresses of its dependencies.

**Why this matters for CREATE2:**

The CREATE2 address formula is:
```
address = keccak256(0xff ++ factory ++ salt ++ keccak256(initCode))[12:]
```

If `LibOrganizationInitialization` is compiled without `LibOrganizationAdmin`, `LibOrganizationMembers`, and `LibOrganizationGroups` being linked, the initCode will have placeholder bytes. When compiled with the correct `--libraries` flags, those addresses are embedded in the initCode, producing a different hash and therefore a different CREATE2 address.

The Makefile handles this automatically with the `deploy-libraries` target (which runs both stages), or you can run them separately:

```bash
# Deploy independent libraries (Policy, Admin, Members, Groups)
make deploy-independent-libs ACCOUNT=my-deployer

# Deploy dependent libraries (Init, AccountSig) - requires --libraries flags
make deploy-dependent-libs ACCOUNT=my-deployer
```

The library addresses depend on which CREATE2 factory is used. Our Makefile handles this automatically via Foundry profiles configured in `foundry.toml`.


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
| `make deploy-independent-libs` | Deploy independent libraries (Policy, Admin, Members, Groups) via CREATE2 |
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
