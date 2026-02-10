# Merkle Tree Architecture

MLS Wallet uses Merkle trees for **Policies** to efficiently store complex, nested policy structures on-chain. Members, Groups, and Admins are stored directly in **onchain mappings** for O(1) lookups.

---

## Table of Contents

1. [Storage Overview](#storage-overview)
2. [Members, Groups, and Admins (Mapping-Based)](#members-groups-and-admins-mapping-based)
3. [Policies Tree (Merkle-Based)](#policies-tree-merkle-based)
4. [Nested Merkle Tree Structure of Policies](#nested-merkle-tree-structure-of-policies)
5. [How Proofs Are Passed to Function Calls](#how-proofs-are-passed-to-function-calls)

---

## Storage Overview

| Data Type | Storage Method | Verification |
|-----------|---------------|--------------|
| Members | Mapping (`isMember[address]`) | O(1) lookup |
| Groups | Mapping (`isGroup[id]`, `isGroupMember[id][address]`) | O(1) lookup |
| Admins | Mapping (`isAdmin[address]`) with count and threshold | O(1) lookup |
| Policies | Merkle tree (`policiesRoot`) | O(log n) proof verification |

**Why Policies use Merkle trees:** Policies have complex nested structures (approvers, destinations, functions, parameter constraints) that would be extremely expensive to store directly on-chain. Merkle trees store only a 32-byte root on-chain while keeping the full data off-chain (on IPFS).

**Why Members/Groups/Admins use mappings:** These are simpler data structures where O(1) on-chain lookups provide better UX by eliminating the need for callers to compute and provide Merkle proofs. The gas cost for mapping-based storage is acceptable given the typical sizes of these sets.

---

## Members, Groups, and Admins (Mapping-Based)

### Members

Members are stored in a mapping with a counter:

```solidity
// LibOrganizationMembersStorage.sol
mapping(address => bool) isMember;
uint256 memberCount;
```

- Adding a duplicate member is a no-op
- Removing a non-existent member reverts
- Removing a member who is an admin reverts (admin status must be removed first)
- Organization must always have at least one member

### Groups

Groups use nested mappings with deletion tracking:

```solidity
// LibOrganizationGroupsStorage.sol
mapping(uint256 => bool) isGroup;
mapping(uint256 => mapping(address => bool)) isGroupMember;
mapping(uint256 => bool) wasGroupDeleted;
```

- Groups are implicitly created when first modified
- Group IDs are not reusable after deletion (`wasGroupDeleted` prevents ghost-member inheritance)
- Adding a duplicate group member is a no-op
- Removing a non-existent group member reverts

### Admins

Admins are stored in a mapping with count and voting threshold:

```solidity
// LibOrganizationAdminStorage.sol
mapping(address => bool) isAdmin;
uint256 adminCount;
uint256 votingThreshold;
```

- All admins must also be members (enforced during add)
- Adding a duplicate admin reverts
- Removing a non-existent admin reverts
- Must always have at least one admin
- Voting threshold cannot exceed admin count or be zero

---

## Policies Tree (Merkle-Based)

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

For policies that restrict which functions can be called, each allowed function leaf contains:
- **selector** — The 4-byte function selector
- **constraintsHash** — Hash of the parameter constraints array

The leaf is computed as `hash(hash(selector, constraintsHash))`, where `constraintsHash` is derived from an array of `ParameterConstraint` structs that define rules for each function parameter.

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

When executing transactions, callers must provide Merkle proofs only for **policy-related** verification. Member, group, and admin verification use direct mapping lookups.

### Transaction Validation Proofs

For account transactions, proofs are bundled in `ValidationProofs`:

```solidity
struct ValidationProofs {
    Policy policy;               // Full policy data to verify and use
    bytes32[] policyProof;       // Proof that policy exists in policiesRoot
    bytes32[] sourceAccountProof;    // Proof for source account (if not anySourceAccount)
    bytes32[] destinationProof;      // Proof for destination (if CustomList)
    bytes32[] functionProof;         // Proof for function (if not anyFunction)
    bytes constraints;               // ABI-encoded ParameterConstraint[] (includes OneOf proofs)
    uint256 initiatorGroupId;        // Group ID for initiator verification (mapping lookup)
    uint256 approverGroupId;         // Group ID for approver verification (mapping lookup)
}
```

### Validation Flow Example

When `executeAccountTransaction()` is called, the contract validates:

```solidity
// 1. Verify policy exists in organization (Merkle proof)
if (!isPolicyInOrg(policyId, proofs.policy, proofs.policyProof)) revert;

// 2. Verify source account is allowed by policy (Merkle proof)
if (!isSourceAccountAllowedByPolicy(proofs.policy, account, proofs.sourceAccountProof)) revert;

// 3. Verify initiator is authorized (mapping lookups for member/group)
if (!isInitiatorAuthorized(proofs.policy, initiator, proofs.initiatorGroupId)) revert;

// 4. Verify destination is allowed (Merkle proof)
if (!isDestinationAllowedByPolicy(proofs.policy, to, data, proofs.destinationProof)) revert;

// 5. Verify function and parameters (Merkle proof for function, constraints)
if (!isFunctionAllowedByPolicy(proofs.policy, data, proofs.functionProof, proofs.constraints)) revert;

// 6. Verify approvals (mapping lookups for member/group, signatures)
if (!areApprovalsValid(proofs.policy, signatures, hash, proofs.approverGroupId)) revert;
```

### Why Double Hashing?

All Merkle leaf computations use double hashing:

```solidity
leaf = keccak256(bytes.concat(keccak256(abi.encode(data))))
```

This prevents **second preimage attacks** where an attacker could craft intermediate tree nodes that look like valid leaves. Double hashing ensures leaves are always distinguishable from internal nodes.

---

## Key Files

| File | Purpose |
|------|---------|
| `src/libraries/MerkleUtils.sol` | Shared Merkle leaf computation utilities |
| `src/organization/libraries/LibOrganizationMembers.sol` | Members mapping operations |
| `src/organization/libraries/LibOrganizationGroups.sol` | Groups mapping operations |
| `src/organization/libraries/LibOrganizationAdmin.sol` | Admins mapping operations with signature verification |
| `src/organization/libraries/LibOrganizationPolicy.sol` | Policies Merkle tree operations |
| `src/organization/libraries/storage/Lib*Storage.sol` | EIP-7201 namespaced storage layouts |
| `src/types/PolicyTypes.sol` | Proof structs and policy types |
| `src/types/AdminTypes.sol` | Admin authorization types |
