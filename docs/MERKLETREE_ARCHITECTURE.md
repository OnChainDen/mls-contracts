# Merkle Tree Architecture

MLS Wallet uses Merkle trees extensively to store Members, Groups, Admins, and Policies. This document explains why, how the trees are structured, and how proofs are passed to function calls.

---

## Table of Contents

1. [Why Merkle Trees?](#why-merkle-trees)
2. [What's Stored as Merkle Trees](#whats-stored-as-merkle-trees)
   - [Members Tree](#1-members-tree)
   - [Groups Tree (Nested)](#2-groups-tree-nested)
   - [Admins Tree](#3-admins-tree)
   - [Policies Tree (Multi-Level Nested)](#4-policies-tree-multi-level-nested)
3. [Nested Merkle Tree Structure of Policies](#nested-merkle-tree-structure-of-policies)
4. [How Proofs Are Passed to Function Calls](#how-proofs-are-passed-to-function-calls)

---

## Why Merkle Trees?

Merkle trees enable **massive gas savings** by storing only a 32-byte root on-chain while keeping the full data off-chain (on IPFS). Without Merkle trees, storing data directly would be prohibitively expensive:

| Data Type | Example Size | Direct Storage Cost | Merkle Tree Cost |
|-----------|--------------|---------------------|------------------|
| Members | 1,000 addresses | ~20M gas (1,000 SSTORE) | ~20K gas (1 SSTORE) |
| Groups | 50 groups with 100 members each | ~100M gas | ~20K gas (1 SSTORE) |
| Policies | 100 policies with nested data | ~200M+ gas | ~20K gas (1 SSTORE) |

**Key benefits:**

1. **Fixed storage cost** — Modifying any amount of data costs the same: one `SSTORE` operation to update the root
2. **Scales with organization size** — An organization with 10,000 members pays the same storage cost as one with 10 members
3. **Complex policies become feasible** — Policies contain nested structures (approvers, destinations, functions, parameter constraints) that would be extremely expensive to store directly

**Trade-off:** Callers must provide Merkle proofs in calldata to verify membership. This adds calldata cost but is significantly cheaper than storage. Verification requires `O(log n)` hash operations, making it efficient even for large trees.

---

## What's Stored as Merkle Trees

Four distinct Merkle trees are stored on the Organization contract, each containing different types of data:

### 1. Members Tree

Stores all organization member addresses.

```
membersRoot (bytes32)
    └── leaf: hash(hash(memberAddress))
    └── leaf: hash(hash(memberAddress))
    └── ...
```

| Stored On-Chain | Stored Off-Chain (IPFS) |
|-----------------|-------------------------|
| `membersRoot` (32 bytes) | Array of member addresses |

**Leaf computation:**
```solidity
// MerkleUtils.sol
keccak256(bytes.concat(keccak256(abi.encode(memberAddress))))
```

---

### 2. Groups Tree (Nested)

Groups use a **nested Merkle tree** structure. The organization stores one root, but each group contains its own sub-tree of members.

```
groupsRoot (bytes32)
    └── leaf: hash(hash(groupId, groupMembersRoot))
        └── groupMembersRoot contains:
            └── leaf: hash(hash(memberAddress))
            └── leaf: hash(hash(memberAddress))
            └── ...
    └── leaf: hash(hash(groupId, groupMembersRoot))
        └── groupMembersRoot contains:
            └── ...
```

| Stored On-Chain | Stored Off-Chain (IPFS) |
|-----------------|-------------------------|
| `groupsRoot` (32 bytes) | Array of groups, each with `groupId` and array of member addresses |

**Two-level verification:**
1. Verify the group exists: proof against `groupsRoot` using `hash(hash(groupId, groupMembersRoot))`
2. Verify the member is in the group: proof against `groupMembersRoot` using `hash(hash(memberAddress))`

```solidity
// LibOrganizationGroups.sol
function isMemberInGroupAndGroupInOrg(
    address memberAddress,
    GroupData memory groupData,
    bytes32[] memory groupInOrgGroupsTreeProof,
    bytes32[] memory memberInGroupProof
) internal view returns (bool) {
    // First verify the group exists
    if (!isGroupInOrg(groupData, groupInOrgGroupsTreeProof)) {
        return false;
    }
    // Then verify the member is in the group
    return isMemberInGroup(memberAddress, groupData.groupMembersRoot, memberInGroupProof);
}
```

---

### 3. Admins Tree

Stores admin member addresses. Admins must also be in the Members tree (enforced to prevent bricking).

```
adminsRoot (bytes32)
    └── leaf: hash(hash(adminAddress))
    └── leaf: hash(hash(adminAddress))
    └── ...
```

| Stored On-Chain | Stored Off-Chain (IPFS) |
|-----------------|-------------------------|
| `AdminConfig.adminsRoot` (32 bytes) | Array of admin addresses |
| `AdminConfig.adminCount` | — |
| `AdminConfig.votingThreshold` | — |

**Dual membership requirement:** When validating admin operations, each admin must prove membership in *both* the `adminsRoot` and `membersRoot` trees. This prevents a misconfiguration where admins are removed from the members tree, which would brick the organization.

---

### 4. Policies Tree (Multi-Level Nested)

Policies have the most complex structure, with **up to 4 levels of nesting**:

```
policiesRoot (bytes32)
    └── leaf: hash(hash(policyId, Policy))
        └── Policy contains PolicyRoots:
            ├── sourceAccountsRoot
            │   └── leaf: hash(hash(accountAddress))
            ├── customDestinationsRoot
            │   └── leaf: hash(hash(destinationAddress))
            └── allowedFunctionsRoot
                └── leaf: hash(hash(selector, constraintsHash))
                    └── constraintsHash may contain:
                        └── OneOf constraint with allowedAddressesRoot
                            └── leaf: hash(hash(address))
```

| Stored On-Chain | Stored Off-Chain (IPFS) |
|-----------------|-------------------------|
| `policiesRoot` (32 bytes) | Array of policies with full config and nested address/function lists |

---

## Nested Merkle Tree Structure of Policies

Policies are the most data-rich structures in MLS Wallet. A single policy can reference hundreds of source accounts, destinations, and functions with complex parameter constraints. Merkle trees make this feasible.

### Policy Structure Overview

Each policy consists of:

1. **PolicyConfig** — Configuration flags and nested structs (approval requirements, initiator config, token filters, rate limits)
2. **PolicyRoots** — Three Merkle roots for lists that can grow arbitrarily large

```solidity
struct Policy {
    PolicyConfig config;
    PolicyRoots roots;
}

struct PolicyRoots {
    bytes32 sourceAccountsRoot;      // Which accounts this policy applies to
    bytes32 customDestinationsRoot;  // Allowed destination addresses
    bytes32 allowedFunctionsRoot;    // Allowed function selectors + constraints
}
```

### Level 1: Organization Policies Tree

The organization stores a single `policiesRoot`. Each leaf is a complete policy:

```
Leaf = hash(hash(policyId, Policy))
     = hash(hash(policyId, PolicyConfig, PolicyRoots))
```

### Level 2: Policy Sub-Trees

Each policy contains up to three sub-trees via `PolicyRoots`:

| Sub-Tree | Purpose | Leaf Format |
|----------|---------|-------------|
| `sourceAccountsRoot` | Which Accounts this policy governs | `hash(hash(accountAddress))` |
| `customDestinationsRoot` | Allowed destination addresses | `hash(hash(destinationAddress))` |
| `allowedFunctionsRoot` | Allowed function selectors | `hash(hash(selector, constraintsHash))` |

**When are sub-trees used?**

- `sourceAccountsRoot`: Only used when `config.anySourceAccount == false`
- `customDestinationsRoot`: Only used when `config.destinationType == CustomList`
- `allowedFunctionsRoot`: Only used when `config.anyFunction == false`

### Level 3: Function Constraint Hashes

For policies that restrict which functions can be called, each allowed function is stored as:

```solidity
struct FunctionLeaf {
    bytes4 selector;          // The 4-byte function selector
    bytes32 constraintsHash;  // Hash of parameter constraints array
}
```

The `constraintsHash` is computed from an array of `ParameterConstraint` structs that define rules for each function parameter.

### Level 4: OneOf Address Lists

For `Address` parameters with `OneOf` constraints (e.g., "recipient must be one of these 50 whitelisted addresses"), the constraint stores another Merkle root:

```solidity
struct ParameterConstraint {
    ParamType paramType;        // ParamType.Address
    ConstraintType constraintType;  // ConstraintType.OneOf
    bytes comparisonData;       // abi.encode(allowedAddressesRoot)
    bytes32[] paramValueInListProof;  // Proof for the actual address
}
```

### Visual Hierarchy

```
Organization
└── policiesRoot
    └── Policy Leaf (policyId + Policy)
        ├── PolicyConfig
        │   ├── transactionType, anySourceAccount, anyFunction, destinationType
        │   ├── ApprovalConfig (policyType, approverType, threshold)
        │   ├── InitiatorConfig (anyInitiator, initiatorType, member/group)
        │   ├── TokenFilter (anyToken, tokenAddress, amountThreshold)
        │   └── RateLimitConfig (limitType, interval, scopes)
        └── PolicyRoots
            ├── sourceAccountsRoot
            │   └── Address leaves (if !anySourceAccount)
            ├── customDestinationsRoot
            │   └── Address leaves (if destinationType == CustomList)
            └── allowedFunctionsRoot
                └── Function leaves (if !anyFunction)
                    └── constraintsHash
                        └── OneOf address roots (for Address OneOf constraints)
```

---

## How Proofs Are Passed to Function Calls

When executing transactions or performing admin operations, callers must provide:

1. **The full data** that the Merkle root commits to (e.g., the complete `Policy` struct)
2. **Merkle proofs** that verify the data is part of the committed tree

These are bundled into proof structs that are passed as function parameters.

### Transaction Validation Proofs

For account transactions, all proofs are bundled in `ValidationProofs`:

```solidity
struct ValidationProofs {
    Policy policy;               // Full policy data to verify and use
    bytes32[] policyProof;       // Proof that policy exists in policiesRoot
    bytes32[] sourceAccountProof;    // Proof for source account (if not anySourceAccount)
    bytes32[] destinationProof;      // Proof for destination (if CustomList)
    bytes32[] functionProof;         // Proof for function (if not anyFunction)
    bytes constraints;               // ABI-encoded ParameterConstraint[] (includes OneOf proofs)
    InitiatorProofs initiatorProofs; // Proofs for initiator verification
    ApproverProofs approverProofs;   // Proofs for approver verification
}
```

### Initiator Proofs

Verifying an initiator requires proving they're a member (and optionally in a specific group):

```solidity
struct InitiatorProofs {
    bytes32[] initiatorInOrgMembersTreeProof;  // Proof: initiator is in membersRoot
    GroupData group;                            // Group data (if initiator must be in a group)
    bytes32[] groupInOrgGroupsTreeProof;       // Proof: group exists in groupsRoot
    bytes32[] memberInGroupProof;              // Proof: initiator is in group's members tree
}
```

### Approver Proofs

For manual approval policies, each approver must prove membership:

```solidity
struct ApproverProofs {
    bytes32[][] approverInOrgMembersTreeProofs;  // Per-signer: proof in membersRoot
    GroupData group;                              // Approver group data (if Group type)
    bytes32[] groupInOrgGroupsTreeProof;         // Proof: group exists in groupsRoot
    bytes32[][] memberInGroupProofs;             // Per-signer: proof in group's tree
}
```

Note the double array (`bytes32[][]`): each signer needs their own proof, and each proof is an array of hashes.

### Admin Operation Proofs

Admin operations use separate proof structures:

```solidity
// For operations that need to verify ALL admins (e.g., setMembers, setAdmins)
struct AllAdminsInOrgProofs {
    address[] adminAddresses;                    // All admin addresses (ascending order)
    bytes32[][] adminInOrgAdminTreeProofs;      // Proof each admin is in adminsRoot
    bytes32[][] adminInOrgMembersTreeProofs;    // Proof each admin is in membersRoot
}

// For operations that only verify SIGNING admins
struct SigningAdminsInOrgProofs {
    bytes32[][] adminInOrgAdminTreeProofs;      // Per-signer: proof in adminsRoot
    bytes32[][] adminInOrgMembersTreeProofs;    // Per-signer: proof in membersRoot
}
```

### Validation Flow Example

When `executeAccountTransaction()` is called, the contract validates:

```solidity
// 1. Verify policy exists in organization
if (!isPolicyInOrg(policyId, proofs.policy, proofs.policyProof)) revert;

// 2. Verify source account is allowed by policy
if (!isSourceAccountAllowedByPolicy(proofs.policy, account, proofs.sourceAccountProof)) revert;

// 3. Verify initiator is authorized
if (!isInitiatorAuthorized(proofs.policy, initiator, proofs.initiatorProofs)) revert;

// 4. Verify destination is allowed
if (!isDestinationAllowedByPolicy(proofs.policy, to, data, proofs.destinationProof)) revert;

// 5. Verify function and parameters (for contract interactions)
if (!isFunctionAllowedByPolicy(proofs.policy, data, proofs.functionProof, proofs.constraints)) revert;

// 6. Verify approvals (for manual approval policies)
if (!areApprovalsValid(proofs.policy, signatures, hash, proofs.approverProofs)) revert;
```

Each verification step involves computing a leaf from the provided data and verifying it against the appropriate Merkle root using the provided proof.

### Why Double Hashing?

All leaf computations use double hashing:

```solidity
leaf = keccak256(bytes.concat(keccak256(abi.encode(data))))
```

This prevents **second preimage attacks** where an attacker could craft intermediate tree nodes that look like valid leaves. Double hashing ensures leaves are always distinguishable from internal nodes.

---

## Key Files

| File | Purpose |
|------|---------|
| `src/libraries/MerkleUtils.sol` | Shared leaf computation utilities |
| `src/organization/libraries/LibOrganizationMembers.sol` | Members tree operations |
| `src/organization/libraries/LibOrganizationGroups.sol` | Groups tree operations (nested) |
| `src/organization/libraries/LibOrganizationAdmin.sol` | Admins tree operations |
| `src/organization/libraries/LibOrganizationPolicy.sol` | Policies tree operations |
| `src/organization/libraries/storage/Lib*Storage.sol` | EIP-7201 storage for Merkle roots |
| `src/types/PolicyTypes.sol` | Proof structs and policy types |
| `src/types/AdminTypes.sol` | Admin proof structs |
