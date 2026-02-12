# 06 — Organization Policy Test Plan

**Files Under Test:**
- `src/organization/libraries/LibOrganizationPolicy.sol`
- `src/organization/base/OrganizationPolicyBase.sol`
- `src/organization/libraries/storage/LibOrganizationPolicyStorage.sol`
- `src/interfaces/organization/IOrganizationPolicy.sol`

**Test File(s):** `test/LibOrganizationPolicy.t.sol`, `test/OrganizationPolicyBase.t.sol`

---

## 1. Policy CRUD (`setPolicies`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Set policies root with valid Merkle root and IPFS CID — succeeds | [U] | P0 |
| 2 | Set policies root updates `policiesRoot` storage | [U] | P0 |
| 3 | Set policies emits `PoliciesUpdated(root, ipfsCid)` event | [EV] | P1 |
| 4 | Set policies root to bytes32(0) — succeeds (effectively clears all policies) | [E] | P0 |
| 5 | Set policies requires admin authorization | [U] | P0 |
| 6 | Set policies reverts when caller is not guardian | [N] | P0 |
| 7 | Set policies with insufficient admin signatures — reverts | [N] | P0 |

---

## 2. Policy Merkle Verification (`isPolicyInOrg`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 8 | Valid policy with valid proof — returns true | [U] | P0 |
| 9 | Valid policy with invalid proof — returns false | [U] | P0 |
| 10 | Policy not in tree — returns false | [U] | P0 |
| 11 | Empty proof with non-zero root — returns false | [N] | P0 |
| 12 | Single-leaf tree (policy is the root) — valid proof with empty array | [E] | P0 |
| 13 | Multiple policies in tree — each verifiable with correct proof | [U] | P0 |
| 14 | Policy leaf uses double hashing (second preimage resistance) | [S] | P0 |
| 15 | Tampering with any field of Policy struct invalidates proof | [S] | P0 |
| 16 | Tampering with policyId invalidates proof | [S] | P0 |

---

## 3. Transaction Policy Validation (`isTransactionAllowedByPolicy`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 16.1 | Policy not in org (invalid Merkle proof) — returns false before any other validation | [S] | P0 |
| 16.2 | Policy not in org (valid policy data but wrong policyId) — returns false | [S] | P0 |
| 16.3 | Policy not in org (policiesRoot is bytes32(0)) — returns false | [S] | P0 |
| 17 | Policy with `anySourceAccount=true` allows any account | [U] | P0 |
| 18 | Policy with specific source account — only that account allowed | [U] | P0 |
| 19 | Policy with wrong source account — rejected | [N] | P0 |
| 20 | Source account verified via Merkle proof when not `anySourceAccount` | [U] | P0 |
| 21 | Authorized initiator (Member type) — allowed | [U] | P0 |
| 22 | Unauthorized initiator — rejected | [N] | P0 |
| 23 | Policy with `TransactionType.Any` — allows all transaction types | [U] | P0 |
| 24 | Policy with `TransactionType.TokenTransfers` — only token transfers pass | [U] | P0 |
| 25 | Policy with `TransactionType.ContractInteractions` — only interactions pass | [U] | P0 |
| 26 | Policy with `TransactionType.Signatures` — only signatures pass | [U] | P0 |
| 27 | Destination validation delegated correctly | [U] | P0 |
| 28 | All sub-validations must pass (any failure = rejection) | [U] | P0 |

---

## 4. Policy Usage Tracking

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 29 | `getPolicyUsage` returns 0 for unused policy | [U] | P1 |
| 30 | `getPolicyUsage` requires policy to exist in Merkle tree | [U] | P1 |
| 31 | `getPolicyUsage` reverts with `PolicyVerificationFailed` if policy not in tree | [N] | P1 |
| 32 | Usage tracking reflects rate limit updates after transaction | [I] | P1 |

---

## 5. Policy Leaf Computation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 33 | Same policyId + Policy struct always produces same leaf (deterministic) | [U] | P1 |
| 34 | Different policyId with same Policy struct — different leaf | [U] | P1 |
| 35 | Same policyId with different Policy struct — different leaf | [U] | P1 |
| 36 | Double hashing prevents second preimage attack | [S] | P1 |

---

## 6. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 37 | Fuzz: Random policy configs produce valid Merkle trees and proofs | [F] | P0 |
| 38 | Fuzz: Random modifications to policy data invalidate proofs | [F] | P0 |
| 39 | Fuzz: Random policyIds produce unique leaves when paired with same config | [F] | P1 |
| 39.1 | Fuzz: Random Merkle roots with empty proofs — only single-leaf trees verify | [F] | P0 |
| 39.2 | Fuzz: Random policy structs — changing any single field always changes the leaf | [F] | P0 |
| 39.3 | Fuzz: Random source account addresses — `anySourceAccount=true` always accepts, specific account rejects wrong address | [F] | P0 |

---

## 6.5 Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 39.4 | **Merkle root consistency**: Policy Merkle root changes only via `setPolicies` (never implicitly) | P0 |
| 39.5 | **Double hashing**: Policy leaf is always double-hashed (second preimage resistance) | P1 |

---

## 7. Private Function Tests (Requires `private` → `internal` Conversion)

> **Prerequisite:** `_computePolicyLeaf` is currently `private` in `LibOrganizationPolicy`.
> Convert to `internal` and expose via a test harness. The existing section 5 tests (33-36)
> verify behavior through the public `isPolicyInOrg` interface; the tests below enable
> direct assertions on the leaf computation logic.

### 7.1 `_computePolicyLeaf`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 40 | Known policyId + Policy → known leaf hash (golden test, precomputed off-chain) | [U] | P0 |
| 41 | Encoding includes all Policy struct fields (changing any field changes the leaf) | [U] | P0 |
| 42 | Double hashing: `keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))))` matches expected | [U] | P1 |
| 43 | Leaf != `keccak256(abi.encode(policyId, policy))` (single hash — second preimage resistance) | [S] | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Policy CRUD | 7 | P0 |
| Merkle verification | 9 | P0 |
| Transaction validation | 15 | P0 |
| Usage tracking | 4 | P1 |
| Leaf computation | 4 | P1 |
| Fuzz tests | 6 | P0-P1 |
| Invariant tests | 2 | P0-P1 |
| Private function tests | 4 | P0-P1 |
| **Total** | **51** | |
