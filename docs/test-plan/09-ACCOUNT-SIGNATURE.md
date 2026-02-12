# 09 — Account Signature (ERC-1271) Test Plan

**Files Under Test:**
- `src/organization/libraries/LibOrganizationAccountSignature.sol`
- `src/organization/base/OrganizationAccountSignatureBase.sol`
- `src/interfaces/organization/IOrganizationAccountSignature.sol`

**Test File(s):** `test/LibOrganizationAccountSignature.t.sol`, `test/AccountSignature.t.sol`

---

## 1. Signature Type Routing

**Priority: P0 — Critical**

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Type prefix `0x01` (Policy) routes to policy-based validation | [U] | P0 |
| 2 | Type prefix `0x00` (Recovery) routes to recovery validation | [U] | P0 |
| 3 | Unknown type prefix (e.g., `0x02`) returns `ERC1271_INVALID_VALUE` | [N] | P0 |
| 4 | Empty signature returns `ERC1271_INVALID_VALUE` | [N] | P0 |

---

## 2. Policy-Based Signature Validation (Type 0x01)

### 2.1 Happy Path

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 5 | AutoApprove policy: valid initiator + guardian signature — returns magic value | [U] | P0 |
| 6 | ManualApproval policy: valid initiator + review + guardian signatures — returns magic value | [U] | P0 |

### 2.2 Guardian Signature Validation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 7 | Guardian is EOA: valid signature — accepted | [U] | P0 |
| 8 | Guardian is EOA: invalid signature — rejected | [N] | P0 |
| 9 | Guardian is Safe: module enabled, module signs — accepted | [U] | P0 |
| 10 | Guardian is Safe: module not enabled — rejected | [N] | P0 |
| 11 | Guardian is non-Safe contract: isModuleEnabled staticcall fails gracefully — rejected | [E] | P0 |
| 12 | Guardian is Safe: ERC-1271 signature from Safe itself — accepted | [U] | P0 |

### 2.3 Initiator Validation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 13 | Initiator authorized by policy (Member type) — valid | [U] | P0 |
| 14 | Initiator authorized by policy (Group type) — valid | [U] | P0 |
| 15 | Initiator not authorized — invalid | [N] | P0 |
| 16 | Policy must be configured for Signatures transaction type | [U] | P0 |
| 17 | Policy configured for TokenTransfers (not Signatures) — invalid | [N] | P0 |

### 2.4 Review Signatures (ManualApproval)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 18 | Sufficient review signatures — valid | [U] | P0 |
| 19 | Insufficient review signatures — invalid | [N] | P0 |
| 20 | Review hash includes initiator signature (binding) | [S] | P0 |

### 2.5 Expiration

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 21 | Valid expiration (future) — succeeds | [U] | P0 |
| 22 | Expired timestamp — invalid | [N] | P0 |
| 23 | Expiration exactly at `block.timestamp` — succeeds | [E] | P0 |

### 2.6 Policy Verification

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 24 | Policy must exist in Merkle tree | [U] | P0 |
| 25 | Policy not in tree — invalid | [N] | P0 |
| 26 | Policy must apply to source account | [U] | P0 |
| 27 | Policy with `anySourceAccount=true` — allows any account | [U] | P0 |

---

## 3. Recovery Signature Validation (Type 0x00)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 28 | Recovery enabled: valid recovery address signature — returns magic value | [U] | P0 |
| 29 | Recovery not enabled — returns invalid value | [N] | P0 |
| 30 | Recovery not configured — returns invalid value | [N] | P0 |
| 31 | Wrong recovery address signs — invalid | [N] | P0 |
| 32 | Recovery signature supports both EOA and ERC-1271 | [U] | P0 |

---

## 4. Access Control (Base Contract)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 33 | `isValidSignatureForAccount` only callable by the account itself (msg.sender check) | [S] | P0 |
| 34 | Non-account caller — reverts `AccountNotDeployedByOrganization` | [N] | P0 |
| 35 | Account not deployed by this org — reverts | [N] | P0 |

---

## 5. EIP-712 Hash Computation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 36 | Initiator hash includes: address(this), account, hash, policyId, expiration, chainId | [U] | P0 |
| 37 | Review hash includes all initiator fields + initiatorSignature hash | [U] | P0 |
| 38 | Different chains produce different hashes | [S] | P0 |
| 39 | Different organizations produce different hashes | [S] | P0 |

---

## 5.5 Guardian Module Edge Cases

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 39.1 | Guardian contract reverts on isModuleEnabled() staticcall — signature returns invalid (not revert) | [E] | P0 |
| 39.2 | Guardian contract returns truncated data (<32 bytes) from isModuleEnabled() — returns invalid | [E] | P0 |
| 39.3 | Signature with only type prefix byte (0x01) and no additional data — returns invalid (not panic) | [E] | P0 |
| 39.4 | Empty sourceAccountProof with policy requiring specific source accounts — validation fails | [S] | P0 |

---

## 6. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 40 | Fuzz: Random hashes with valid policy signature — returns magic value | [F] | P0 |
| 41 | Fuzz: Random type prefixes (not 0x00/0x01) — returns invalid value | [F] | P0 |
| 42 | Fuzz: Random expiration timestamps — future pass, past fail | [F] | P0 |
| 43 | Fuzz: Random policy IDs with valid Merkle proofs — signature validation succeeds | [F] | P0 |
| 44 | Fuzz: Random guardian EOA private keys — guardian signature always accepted | [F] | P0 |
| 45 | Fuzz: Random review signer counts below threshold — always rejected | [F] | P0 |
| 46 | Fuzz: Random recovery address signatures — valid signer returns magic, wrong signer returns invalid | [F] | P0 |

---

## 7. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 47 | **Type prefix exclusivity**: Only `0x00` and `0x01` type prefixes ever produce `ERC1271_MAGIC_VALUE` | P0 |
| 48 | **Approval/rejection separation**: Approval signatures never validate as rejection signatures | P0 |
| 49 | **Cross-org replay**: Signatures for org A are never valid for org B | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Type routing | 4 | P0 |
| Policy-based validation | 23 | P0 |
| Recovery validation | 5 | P0 |
| Access control | 3 | P0 |
| EIP-712 hashes | 4 | P0 |
| Guardian module edge cases | 4 | P0 |
| Fuzz tests | 7 | P0 |
| Invariant tests | 3 | P0 |
| **Total** | **53** | |
