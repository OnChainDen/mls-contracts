# Multi-layer Security (MLS) Wallet Smart Contracts

Smart contracts for Multi-layer Security (MLS) Wallet - a policy-based non-custodial custody solution for organizations.

> [!IMPORTANT]
> The contents of this document and this repository are confidential. Do not share without expressed written permission from the Den team.

---

## Table of Contents

1. [Overview](#overview)
2. [Core Concepts](#core-concepts)
   - [Three Layers of Security](#three-layers-of-security)
   - [Key Abstractions](#key-abstractions)
   - [Types of Operations](#types-of-operations)
3. [Admin Operations](#admin-operations)
4. [Account Transactions](#account-transactions)
5. [Account Signatures (ERC-1271)](#account-signatures-erc-1271)
6. [Architecture](#architecture)
7. [Core Contracts](#core-contracts)
8. [Security Model](#security-model)
9. [Disaster Recovery](#disaster-recovery)
10. [Policies](#policies)
11. [Cross-chain Deployment](#cross-chain-deployment)
12. [File Structure](#file-structure)
13. [Deployment](#deployment)
14. [API](#api)

---

## Overview

MLS Wallet stores organization assets in smart contracts governed by **policies** - "if-then" rules that dictate what transactions can be executed and by whom. Unlike traditional multisig wallets, MLS Wallet provides:

- **Policy-based authorization**: Fine-grained control over transaction types, amounts, recipients, and approval requirements
- **Multiple redundant security layers**: Mobile wallet, offchain Guardian service, and onchain smart contracts independently validate every transaction
- **Merkle-based storage**: Policies, members, and groups stored as merkle trees (only roots on-chain) for gas efficiency

---

## Core Concepts

### Three Layers of Security

MLS Wallet uses three independent security layers. Each layer validates transactions independently - an attacker would need to compromise all three simultaneously to execute unauthorized transactions.

| Layer | Location | Purpose |
|-------|----------|---------|
| **Signing Client** | Mobile wallet / SDK | Policy validation before signing; prevents invalid transactions from being created |
| **Guardian Service** | Off-chain server | Independent policy validation; confirms all required approvals present |
| **Smart Contracts** | On-chain | Final enforcement; blocks malicious transactions at blockchain level |

![Three Security Layers](docs/images/MLSWalletSecurityLayersDiagram.svg)

### Key Abstractions

| Abstraction | Description |
|-------------|-------------|
| **Organization** | The on-chain representation of a business entity. Stores all state (members, groups, policies, admin config). Does NOT hold funds. |
| **Account** | Smart contract wallet that holds assets. Owned by an Organization. Executes transactions only when called by its Organization. |
| **Member** | A person or API identity belonging to an Organization. Identified by an address (EOA or smart contract). |
| **Group** | A collection of Members organized by function (e.g., "Finance Team"). Used for approval thresholds. |
| **Admin** | Privileged Member(s) or Group that can modify Organization configuration. Changes require threshold signatures. |
| **Policy** | "If-then" rule defining what transactions are allowed, by whom, and how often. Stored as merkle tree leaves. |

![Organizations and Accounts](docs/images/OrganizationsAndAccounts.svg)

### Types of Operations

MLS Wallet supports three distinct operation types, each with its own workflow:

| Operation Type | Purpose | Entry Point | Rejection Support |
|----------------|---------|-------------|-------------------|
| **Admin Operations** | Modify Organization state (members, groups, policies, admins) | `Organization.*` functions | Yes |
| **Account Transactions** | Execute transactions from Accounts (transfers, DeFi, etc.) | `Organization.executeAccountTransaction()` | Yes |
| **Account Signatures** | ERC-1271 signature validation for smart contract interactions | `Account.isValidSignature()` | No (stateless) |

---

## Admin Operations

Admin operations modify organizational state and require admin threshold signatures.

### Admin Operation Types

| Operation | Description | Files |
|-----------|-------------|-------|
| `ModifyAdmins` | Change admin configuration | `OrganizationAdminBase.sol`, `LibOrganizationAdmin.sol` |
| `ModifyMembers` | Update members merkle root | `OrganizationMembersBase.sol`, `LibOrganizationMembers.sol` |
| `ModifyGroups` | Update groups merkle root | `OrganizationGroupsBase.sol`, `LibOrganizationGroups.sol` |
| `ModifyPolicies` | Update policies merkle root | `OrganizationPolicyBase.sol`, `LibOrganizationPolicy.sol` |
| `UpdateGuardian` | Initiate/finalize Guardian change | `OrganizationGuardianBase.sol`, `LibOrganizationGuardian.sol` |
| `Upgrade` | Upgrade Organization implementation | `OrganizationImplementation.sol` |
| `DeployAccount` | Deploy a new Account | `OrganizationAccountFactoryBase.sol` |
| `UpgradeAccount` | Upgrade Account implementation (beacon) | `OrganizationAccountFactoryBase.sol` |

### Approving Admin Operations (Workflow)

![Approving Admin Operation](docs/images/ApprovingAdminOperation.svg)

1. **Admins sign an approval message** (need more than a threshold amount of signatures)
2. **Guardian collects the signatures**
3. **Guardian sends the signatures to the Organization contract**
4. **Organization contract performs validations and updates state** (checks that `msg.sender` is the Guardian, validates admin signatures)

### Rejecting Admin Operations (Workflow)

The rejection workflow is nearly identical to the approval workflow. The key differences are:
- Admins sign a **rejection** message (with `isApproval=false`) instead of an approval message
- Guardian calls `rejectAdminOperation()` instead of the operation-specific function

![Rejecting Admin Operation](docs/images/RejectingAdminOperation.svg)

1. **Admins sign a rejection message** (need more than a threshold amount of signatures)
2. **Guardian collects the signatures**
3. **Guardian sends the signatures to the Organization contract** (calls `rejectAdminOperation()`)
4. **Organization contract performs validations and consumes nonce** (checks that `msg.sender` is the Guardian, validates admin signatures, emits `AdminOperationRejected` event)

**Key Point:** Rejection requires the SAME authorization level as approval (threshold signatures). This prevents unauthorized actors from blocking legitimate operations.

### EIP-712 Typed Data

All admin operations use EIP-712 typed data signing:

```solidity
// Domain
EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)
// name: "MLSWalletOrganization", version: "1"

// Message
AdminOperation(uint8 operationType,bytes operationData,uint256 salt,bool isApproval,uint256 chainId,address organization)
```

---

## Account Transactions

Account transactions execute operations (transfers, DeFi interactions, etc.) from Accounts. Both approval and rejection flows are supported.

### Approval Workflow

1. **Initiate** — Initiator signs transaction data (EIP-712 typed data with `isApproval=true`)
   - Parameters: `account`, `to`, `value`, `data`, `salt`, `expirationTimestamp`, `policyId`
2. **Review** (if ManualApproval policy) — Reviewers sign the review hash (includes initiator signature to bind approvals)
3. **Guardian Validation** — Guardian service validates policy compliance off-chain
4. **Execute** — Guardian calls `Organization.executeAccountTransaction()` with all signatures and proofs
5. **On-chain Validation** (`OrganizationAccountTransactionBase.sol:22`)
   - Guardian check (`onlyGuardian` modifier)
   - Account ownership verification (`validateIsAccountDeployedByOrgOrRevert`)
   - Nonce computation and consumption (replay protection)
   - Expiration check (`block.timestamp <= expirationTimestamp`)
   - Initiator signature verification and recovery
   - Policy validation via merkle proofs (`isTransactionAllowedByPolicy`)
   - Manual approval validation if required (`areApprovalsValid`)
   - Time-based limit check and update
6. **Execution** — Organization calls `Account.executeTransaction(to, value, data, nonce, policyId)`
   - Account performs low-level CALL to destination

### Rejection Workflow

Rejection allows authorized parties to invalidate a pending transaction by consuming its nonce.

1. **Initiate** — Same initiator signature as approval (proves the transaction exists)
2. **Rejection Authorization**
   - *AutoApprove Policy*: Requires a separate rejection signature from an authorized initiator (signs with `isApproval=false`)
   - *ManualApproval Policy*: Requires threshold rejection signatures from approvers (reviewers sign with `isApproval=false`)
3. **Guardian Validation** — Guardian validates rejection authorization
4. **Execute** — Guardian calls `Organization.rejectAccountTransaction()` with signatures and proofs
5. **On-chain Validation** (`OrganizationAccountTransactionBase.sol:78`)
   - Same validations as approval (Guardian, account, nonce, expiration, policy)
   - Rejection authorization validation based on policy type
   - Nonce consumed (prevents future execution or re-rejection)
6. **Event** — `AccountTransactionRejected` emitted (no transaction executed on Account)

### Approval vs Rejection Comparison

| Aspect | Approval | Rejection |
|--------|----------|-----------|
| Transaction execution | Yes | No (event only) |
| AutoApprove policy | Initiator signature only | Initiator + rejection signature |
| ManualApproval policy | Threshold approvals | Threshold rejections (same count) |
| Time-based limits | Updated | Not affected |
| Nonce | Consumed | Consumed (same nonce) |

**Key Point:** Rejection requires the SAME authorization level as approval. This prevents unauthorized actors from blocking legitimate transactions.

### Policy Validation Details

When `isTransactionAllowedByPolicy()` is called, it validates:

1. **Policy exists** - Merkle proof against `policiesRoot`
2. **Source account allowed** - Either `anySourceAccount=true` or account in policy's source accounts tree
3. **Initiator authorized** - Member/group membership verified via merkle proofs
4. **Transaction type matches** - TokenTransfers, ContractInteractions, or Any
5. **Destination allowed** - Either any destination or merkle-verified custom list
6. **Token/amount constraints** - For token transfers
7. **Function/parameter constraints** - For contract interactions

**Important:** The `policyId` is **explicitly provided** by the caller. There is no "first match" ordering - the caller specifies exactly which policy should authorize the transaction.

Files: `OrganizationAccountTransactionBase.sol`, `LibOrganizationAccountTransaction.sol`

---

## Account Signatures (ERC-1271)

Accounts support ERC-1271 signature validation for smart contract interactions (e.g., Permit2, CoW Protocol, off-chain order books).

### Workflow

1. **External Call** — Third party calls `Account.isValidSignature(hash, signature)` (`AccountImplementation.sol:54`)
2. **Delegation** — Account delegates to `Organization.isValidSignatureForAccount(account, hash, signature)`
3. **Signature Type Detection** — First byte determines type:
   - `0x00` = Recovery signature (bypasses policy checks)
   - `0x01` = Policy-based signature (normal flow)

### Policy-Based Signature Validation (Type 0x01)

Signature format: `0x01 | ABI(policyId, expiration, initiatorSig, reviewSigs, guardianSig, proofs)`

Validation steps:
1. **Expiration check** - Signature must not be expired
2. **Initiator signature** - Verify initiator signed the hash
3. **Guardian signature** - Verify Guardian signed the review hash
4. **Policy check** - Policy must exist and apply to this signature:
   - `TransactionType.Signatures` required
   - Source account must be allowed
   - Initiator must be authorized
5. **Approval check (ManualApproval policies)** - Verify threshold approvals

### Recovery Signature Validation (Type 0x00)

- Only valid if recovery is BOTH supported AND enabled
- Bypasses all Guardian and policy checks
- Validates that recovery address signed the hash

**Important Limitation:** Time-based policy limits are NOT supported for ERC-1271 signatures because `isValidSignature` is a `view` function (cannot modify storage to track usage).

Files: `AccountImplementation.sol:54-62`, `LibOrganizationAccountSignature.sol`

---

## Architecture

### Proxy Patterns

**Organization**: ERC-1967 UUPS Proxy
- `OrganizationProxy.sol` → `OrganizationImplementation.sol`
- Upgrades require: Guardian call + Admin threshold signatures + Implementation whitelist validation
- Uses EIP-7201 namespaced storage to prevent slot collisions during upgrades

**Account**: Beacon Proxy (Organization as Beacon)
- `AccountProxy.sol` → `AccountImplementation.sol`
- Organization contract implements `IBeacon.implementation()`
- All Accounts under an Organization share the same implementation
- Account upgrades happen automatically when Organization updates the beacon implementation

```
┌─────────────────────────────────────────────────────────────────┐
│                     OrganizationFactory                          │
│  (CREATE2 deployment, deterministic addresses across chains)     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     OrganizationProxy                            │
│                    (ERC-1967 UUPS Proxy)                         │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              OrganizationImplementation                    │  │
│  │  • Implements IBeacon (returns Account implementation)     │  │
│  │  • Stores: membersRoot, groupsRoot, policiesRoot, admin    │  │
│  │  • Validates transactions, manages policies                │  │
│  │  • Guardian-protected external functions                   │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┴───────────────────┐
          ▼                                       ▼
┌──────────────────────┐              ┌──────────────────────┐
│    AccountProxy      │              │    AccountProxy      │
│   (BeaconProxy)      │              │   (BeaconProxy)      │
│  beacon = Org addr   │              │  beacon = Org addr   │
└──────────────────────┘              └──────────────────────┘
          │                                       │
          ▼                                       ▼
┌──────────────────────────────────────────────────────────────┐
│                   AccountImplementation                       │
│  (Shared implementation via Beacon pattern)                   │
│  • Holds assets (ETH, ERC-20 tokens)                          │
│  • Executes transactions only when called by Organization     │
│  • ERC-1271 signature validation delegated to Organization    │
└──────────────────────────────────────────────────────────────┘
```

### Storage Pattern (EIP-7201)

All state is stored using EIP-7201 namespaced storage to prevent slot collisions during upgrades:

```solidity
// Example: LibOrganizationMembersStorage.sol
library LibOrganizationMembersStorage {
    struct Layout {
        bytes32 membersRoot;
    }

    // Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.members")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant STORAGE_LOCATION = 0xb80799cfa22e7d42bb36b2b397b5d0bd56930d54ee4f345397b8ece603c6f300;

    function layout() internal pure returns (Layout storage _layout) {
        assembly {
            _layout.slot := STORAGE_LOCATION
        }
    }
}
```

---

## Core Contracts

### Organization (`src/organization/`)

The Organization contract is the central hub that:
- Stores all organizational state (members, groups, policies, admin configuration)
- Validates and executes transactions on behalf of Accounts
- Acts as a Beacon for Account proxies
- Enforces Guardian protection on all external functions

**Key files:**
| File | Purpose |
|------|---------|
| `OrganizationProxy.sol` | ERC-1967 UUPS proxy |
| `OrganizationImplementation.sol` | Main implementation, inherits all base contracts |
| `OrganizationFactory.sol` | CREATE2 deployment for deterministic addresses |
| `base/*.sol` | Modular base contracts (Admin, Members, Groups, Policy, etc.) |
| `libraries/*.sol` | Business logic libraries |
| `libraries/storage/*.sol` | EIP-7201 namespaced storage libraries |

### Account (`src/account/`)

The Account contract is a thin wrapper that:
- Holds organization assets (ETH, tokens)
- Executes transactions only when called by its Organization
- Delegates ERC-1271 signature validation to the Organization

**Key files:**
| File | Purpose |
|------|---------|
| `AccountProxy.sol` | BeaconProxy (Organization is the beacon) |
| `AccountImplementation.sol` | Simple execution logic |

### Implementation Whitelist (`src/implementation-whitelist/`)

A separate contract that maintains a whitelist of approved implementation addresses. Used to validate upgrades:
- Prevents malicious implementation swaps
- Controlled independently from individual Organizations

---

## Security Model

### Guardian Protection

**Every external function on Organization is protected by the Guardian check.**

```solidity
modifier onlyGuardian() {
    if (msg.sender != LibOrganizationGuardian.getGuardian()) {
        revert IOrganizationGuardian.OnlyGuardian();
    }
    _;
}
```

The Guardian is Den's offchain service that:
1. Independently validates transactions against policies
2. Acts as a redundant security layer
3. Prevents exploitation even if other vulnerabilities exist

**Guardian Update Flow (3-step timelocked process):**
1. `initiateGuardianUpdate(newGuardian)` - Admin-authorized, starts timelock
2. `finalizeGuardianUpdate()` - Admin-authorized, after timelock expires
3. `acceptGuardian()` - Called by the new Guardian itself

This prevents instant Guardian hijacking and allows time to detect malicious changes.

### Signature Validation

Supports both EOA and ERC-1271 (smart contract) signatures via a unified format:

**EOA Signatures (v = 27 or 28):**
```
| v (1 byte) | r (32 bytes) | s (32 bytes) |
Total: 65 bytes
```

**ERC-1271 Smart Contract Signatures (v = 0):**
```
| v=0 (1 byte) | signer address (20 bytes) | signature length (2 bytes) | signature data (N bytes) |
Total: 23 + N bytes
```

Implementation: `src/libraries/SignatureUtils.sol`

### Replay Protection

Uses **non-sequential nonces** computed from transaction parameters:

```solidity
nonce = computeNonce(operationType, operationData, salt)
      = keccak256(abi.encode(operationType, keccak256(operationData), salt))
```

- Same transaction data + same salt = same nonce (replayable → blocked)
- Same transaction data + different salt = different nonce (allowed)
- Nonces are consumed before external calls (CEI pattern)

Implementation: `src/organization/libraries/LibOrganizationSignatures.sol`

### Upgrade Authorization

Organization upgrades require all three protections:

1. **Guardian call** - Only Guardian can call `upgradeToAndCallWithAuthorization()`
2. **Admin signatures** - Threshold of admin signatures required
3. **Whitelist validation** - New implementation must be whitelisted

```solidity
function upgradeToAndCallWithAuthorization(
    address newImplementation,
    bytes calldata data,
    AdminAuthParams calldata authParams
) external onlyGuardian {
    // 1. Validate admin authorization
    LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert(...);

    // 2. Validate implementation against whitelist
    IImplementationWhitelist(whitelistAddress)
        .validateIsImplementationWhitelistedOrRevert(ContractType.Organization, newImplementation);

    // 3. Set authorization flag and perform upgrade
    LibOrganizationUpgradeStorage.layout().isUpgradeAuthorized = true;
    upgradeToAndCall(newImplementation, data);
    LibOrganizationUpgradeStorage.layout().isUpgradeAuthorized = false;
}
```

Direct calls to inherited `upgradeToAndCall()` revert with `UnauthorizedUpgrade()`.

---

## Disaster Recovery

MLS Wallet implements two independent recovery mechanisms to handle scenarios where the Guardian is compromised or unavailable.

### Recovery Architecture

| Mechanism | Purpose | Timelocked | Recovery Address |
|-----------|---------|------------|------------------|
| **Guardian Recovery** | Replace compromised/unavailable Guardian | Yes | `guardianRecoveryAddress` |
| **Transaction Recovery** | Execute transactions without Guardian | Yes (to enable) | `transactionAndERC1271RecoveryAddress` |

Both mechanisms use separate privileged addresses configured at Organization initialization.

---

### Guardian Recovery

Allows replacing the Guardian through a time-locked process.

**3-Step Flow:**

```
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: INITIATE                                                │
│ Caller: guardianRecoveryAddress                                 │
│ Function: initiateRecoveryGuardianUpdate(newGuardian)           │
│ Effect: Sets pendingGuardian, starts timelock                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Wait for timelock to expire
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: FINALIZE                                                │
│ Caller: guardianRecoveryAddress                                 │
│ Function: finalizeRecoveryGuardianUpdate()                      │
│ Effect: Marks update ready for acceptance                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: ACCEPT                                                  │
│ Caller: The new Guardian itself                                 │
│ Function: acceptGuardianRecovery()                              │
│ Effect: Updates Guardian address, clears pending state          │
└─────────────────────────────────────────────────────────────────┘
```

**Cancellation:** `cancelRecoveryGuardianUpdate()` - Can abort before finalization

Files: `OrganizationGuardianRecoveryBase.sol`, `LibOrganizationGuardianRecovery.sol`

---

### Transaction Recovery

Allows executing transactions and validating ERC-1271 signatures without the Guardian.

**Important:** Transaction recovery is OPTIONAL - configured at initialization via `isRecoverySupportedForTransactionsAndERC1271`.

**Enable Flow (2-Step with Timelock):**

```
1. initiateEnableTransactionAndERC1271Recovery()
   └── Caller: transactionAndERC1271RecoveryAddress
   └── Effect: Starts timelock

2. finalizeEnableTransactionAndERC1271Recovery()
   └── Caller: transactionAndERC1271RecoveryAddress
   └── Effect: Enables recovery after timelock expires
```

**Usage (when enabled):**

- `executeRecoveryAccountTransaction(account, to, value, data)` - Execute without Guardian/policy checks
- ERC-1271 signatures with type `0x00` prefix - Bypass Guardian/policy validation

**Disable:** `disableTransactionAndERC1271Recovery()` - Immediate (no timelock required)

Files: `OrganizationTxRecoveryBase.sol`, `LibOrganizationTxRecovery.sol`

---

### Recovery vs Normal Operations

| Aspect | Normal Flow | Recovery Flow |
|--------|-------------|---------------|
| Guardian required | Yes | No |
| Policy validation | Yes | No (bypassed) |
| Nonce/policyId | Computed | Set to 0 |
| Authorization | Guardian + policy | Recovery address only |
| Timelock | None | Required to enable |

---

### Recovery Scenarios

**Scenario A: Guardian Compromised**
1. Guardian Recovery Address initiates new Guardian
2. Wait for timelock
3. Finalize and have new Guardian accept
4. Normal operations resume with new Guardian

**Scenario B: Guardian Unavailable (Lost Keys)**
1. Initiate Guardian recovery (same as A)
2. While waiting, enable Transaction Recovery if urgent transactions needed
3. Execute critical transactions via recovery
4. Complete Guardian recovery
5. Disable Transaction Recovery

**Scenario C: Emergency Disable**
- Call `disableTransactionAndERC1271Recovery()` immediately (no timelock)
- Restores normal Guardian-mediated operations

---

## Policies

### Policy Structure

Policies are stored as merkle tree leaves. Full policy data is provided in calldata and verified:

```solidity
struct Policy {
    PolicyConfig config;   // Rules configuration
    PolicyRoots roots;     // Merkle roots for address/function lists
}

struct PolicyConfig {
    TransactionType transactionType;     // Any, TokenTransfers, ContractInteractions, Signatures
    bool anySourceAccount;               // If false, check sourceAccountsRoot
    bool anyFunction;                    // If false, check allowedFunctionsRoot
    DestinationType destinationType;     // Any or CustomList
    ApprovalConfig approval;             // PolicyType, approver, threshold
    InitiatorConfig initiator;           // Who can initiate
    TokenFilter token;                   // Token address and amount constraints
    TimeLimitConfig timeLimit;           // Rate limiting
}
```

See: `src/types/PolicyTypes.sol`

### Policy Types

| Type | Behavior |
|------|----------|
| `AutoApprove` | Transaction proceeds with just initiator signature |
| `RequireManualApproval` | Requires threshold approvals from designated approvers |

### Policy Matching

**The caller explicitly specifies which `policyId` to use.** The contract verifies:
1. The policy exists (merkle proof)
2. The policy applies to this transaction (filters match)
3. Required signatures are provided

There is no ordered list of policies - the policy ID is part of the transaction parameters.

### Time-Based Limits

Policies can enforce rate limits:

```solidity
enum PolicyLimitation {
    None,              // No limit
    SingleTransaction, // One-time use
    TimeInterval       // Resets after time period
}
```

For `TimeInterval`, usage is tracked per:
- Initiator (AcrossAll or PerEntity)
- Source account (AcrossAll or PerEntity)
- Destination (AcrossAll or PerEntity)

Implementation: `src/organization/libraries/policy/LibPolicyTimeBasedLimits.sol`

---

## Cross-chain Deployment

Organizations and Accounts are deployed at **deterministic addresses** using CREATE2:

```solidity
// OrganizationFactory.sol
function deployOrganization(
    bytes32 salt,
    address implementationAddress,
    address whitelistAddress,
    InitializationParams calldata initParams
) external returns (address organizationAddress) {
    // CREATE2 deployment
    organizationAddress = Create2.deploy(0, salt, bytecode);

    // Atomic initialization
    OrganizationImplementation(organizationAddress).initialize(initParams);
}
```

Same salt + same bytecode = same address on any EVM chain.

---

## File Structure

```
src/
├── account/
│   ├── AccountImplementation.sol          # Beacon target implementation
│   ├── AccountProxy.sol                   # BeaconProxy wrapper
│   └── libraries/storage/
│       └── LibAccountOrganizationAddressStorage.sol
│
├── organization/
│   ├── OrganizationImplementation.sol     # UUPS implementation (hub)
│   ├── OrganizationProxy.sol              # ERC-1967 proxy
│   ├── OrganizationFactory.sol            # CREATE2 deployment
│   │
│   ├── base/                              # Modular base contracts
│   │   ├── OrganizationAccountFactoryBase.sol
│   │   ├── OrganizationAccountSignatureBase.sol
│   │   ├── OrganizationAccountTransactionBase.sol
│   │   ├── OrganizationAdminBase.sol
│   │   ├── OrganizationGroupsBase.sol
│   │   ├── OrganizationGuardianBase.sol
│   │   ├── OrganizationGuardianRecoveryBase.sol
│   │   ├── OrganizationInitializationBase.sol
│   │   ├── OrganizationMembersBase.sol
│   │   ├── OrganizationPolicyBase.sol
│   │   ├── OrganizationSignaturesBase.sol
│   │   └── OrganizationTxRecoveryBase.sol
│   │
│   ├── common/
│   │   └── OrganizationModifiers.sol      # onlyGuardian, etc.
│   │
│   ├── libraries/                         # Business logic
│   │   ├── LibOrganizationAccountFactory.sol
│   │   ├── LibOrganizationAccountSignature.sol
│   │   ├── LibOrganizationAccountTransaction.sol
│   │   ├── LibOrganizationAdmin.sol
│   │   ├── LibOrganizationEIP712.sol
│   │   ├── LibOrganizationGroups.sol
│   │   ├── LibOrganizationGuardian.sol
│   │   ├── LibOrganizationGuardianRecovery.sol
│   │   ├── LibOrganizationInitialization.sol
│   │   ├── LibOrganizationMembers.sol
│   │   ├── LibOrganizationPolicy.sol
│   │   ├── LibOrganizationSignatures.sol
│   │   ├── LibOrganizationTxRecovery.sol
│   │   │
│   │   ├── policy/                        # Policy validation logic
│   │   │   ├── LibPolicyApproval.sol
│   │   │   ├── LibPolicyContractInteraction.sol
│   │   │   ├── LibPolicyDestination.sol
│   │   │   ├── LibPolicyInitiator.sol
│   │   │   ├── LibPolicyParameterConstraints.sol
│   │   │   ├── LibPolicyTimeBasedLimits.sol
│   │   │   └── LibPolicyTokenTransfer.sol
│   │   │
│   │   └── storage/                       # EIP-7201 storage
│   │       ├── LibOrganizationAccountFactoryStorage.sol
│   │       ├── LibOrganizationAdminStorage.sol
│   │       ├── LibOrganizationDeployerAddressStorage.sol
│   │       ├── LibOrganizationGroupsStorage.sol
│   │       ├── LibOrganizationGuardianStorage.sol
│   │       ├── LibOrganizationMembersStorage.sol
│   │       ├── LibOrganizationPolicyStorage.sol
│   │       ├── LibOrganizationRecoveryStorage.sol
│   │       ├── LibOrganizationSignaturesStorage.sol
│   │       └── LibOrganizationUpgradeStorage.sol
│
├── implementation-whitelist/
│   ├── ImplementationWhitelistImplementation.sol
│   ├── ImplementationWhitelistProxy.sol
│   └── libraries/storage/
│       └── LibImplementationWhitelistStorage.sol
│
├── interfaces/
│   ├── IAccount.sol
│   ├── IImplementationWhitelist.sol
│   ├── IOrganization.sol                  # Hub interface (aggregates all)
│   ├── IOrganizationFactory.sol
│   └── organization/                      # Per-module interfaces
│       ├── IOrganizationAccountFactory.sol
│       ├── IOrganizationAccountSignature.sol
│       ├── IOrganizationAccountTransaction.sol
│       ├── IOrganizationAdmin.sol
│       ├── IOrganizationGroups.sol
│       ├── IOrganizationGuardian.sol
│       ├── IOrganizationGuardianRecovery.sol
│       ├── IOrganizationInitialization.sol
│       ├── IOrganizationMembers.sol
│       ├── IOrganizationPolicy.sol
│       ├── IOrganizationSignatures.sol
│       └── IOrganizationTxRecovery.sol
│
├── libraries/                             # Shared utilities
│   ├── BytesUtils.sol
│   ├── ContractInteractionUtils.sol
│   ├── MerkleUtils.sol
│   ├── SignatureUtils.sol                 # EOA + ERC-1271 validation
│   └── TokenTransferUtils.sol
│
├── types/
│   ├── AdminTypes.sol
│   ├── CommonTypes.sol                    # ContractType, OperationType, InitializationParams
│   └── PolicyTypes.sol                    # Policy, PolicyConfig, ValidationProofs, etc.
│
└── safe-module/                           # Safe integration
    ├── BatchedTransaction.sol
    └── SafeExecutorModule.sol
```

---

## Deployment

For detailed deployment instructions, see **[DEPLOYMENT.md](./DEPLOYMENT.md)**.

### Quick Overview

All platform contracts are deployed **deterministically** using CREATE2:

1. **Deploy CREATE2 Factory** (if not already deployed on the chain)
2. **Deploy Platform Libraries** via CREATE2
3. **Deploy Contracts** with library linking

### Local Testing

```bash
./test_deploy_scripts_locally.sh
```

### Production Deployment

See [DEPLOYMENT.md](./DEPLOYMENT.md) for:
- Signer setup (Foundry keystore or Ledger)
- Step-by-step deployment commands
- Guardian/Admin Safe configuration
- Library linking requirements
- Troubleshooting guide

---

## API

### Overview

Using the MLS Wallet API, an application can take any action that an ordinary member can take:
- Build custom applications with custom user interfaces
- Programmatically execute transactions without human intervention
- Streamline workflows that require both manual human intervention and programmatic actions

### API Members

An application using the API is represented as a special type of Member called an "API Member". The API Member:
- Uses the API to interact with the Organization (instead of the Web Application)
- Manages its own private key (or uses the MLS Wallet SDK/CLI)

### Usage

1. **Create API Member** in the web app at `/members`
2. **Generate private key** using the CLI:
   ```bash
   npm install -i @onchainden/mls-wallet-cli
   mls-wallet-cli setup
   ```
3. **Get Admin approval** (if required by your Organization)
4. **Make requests** using the SDK:
   ```typescript
   import { MLSWalletClient } from "@onchainden/mls-wallet"

   const client = new MLSWalletClient({
       apiKey: process.env.MLS_WALLET_API_KEY,
       privateKey: process.env.MLS_WALLET_PRIVATE_KEY
   });

   const policies = await client.getPolicies();
   ```

---

## Known Limitations

### ERC-1271 Signatures and Time-Based Limits

Time-based policy limits are NOT supported for ERC-1271 signatures because `isValidSignature` must be a `view` function (cannot modify storage to track usage). See [Account Signatures (ERC-1271)](#account-signatures-erc-1271) for details.

### Gas Costs

Policy validation involves multiple merkle proof verifications. While this is significantly cheaper than storing full policy data on-chain, complex policies with many proofs will incur higher gas costs.

---

## Questions & Open Items

See internal documentation for current open questions regarding:
- Non-sequential nonce security analysis
- Gas optimization opportunities
