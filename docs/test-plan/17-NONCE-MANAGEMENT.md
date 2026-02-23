# 17 — Nonce Management & Replay Protection Test Plan

**Scope:** Nonce computation, nonce consumption, and replay protection behavior for admin operations and account transactions.

**Out of Scope (tested elsewhere):**
- Interface files
- Storage library files (including nonce storage layout libraries)

**Files Under Test:**
- `src/organization/libraries/LibOrganizationSignatures.sol`
- `src/organization/base/OrganizationSignaturesBase.sol`
- `src/organization/libraries/LibOrganizationAdmin.sol`
- `src/organization/base/OrganizationAdminBase.sol`
- `src/organization/base/OrganizationAccountTransactionBase.sol`
- `src/organization/base/OrganizationAccountFactoryBase.sol`
- `src/organization/base/OrganizationMembersBase.sol`
- `src/organization/base/OrganizationGroupsBase.sol`
- `src/organization/base/OrganizationPolicyBase.sol`
- `src/organization/base/OrganizationGuardianBase.sol`
- `src/organization/base/OrganizationGuardianRecoveryBase.sol`
- `src/organization/base/OrganizationTxRecoveryBase.sol`
- `src/organization/libraries/LibOrganizationAccountTransaction.sol`
- `src/organization/libraries/LibOrganizationEIP712.sol`

**Harness Prerequisite (private functions):**
- For direct unit tests of private helpers, temporarily change the target helpers to `internal` and expose them through a harness contract.
- Private helpers in scope:
  - `LibOrganizationAdmin._areAdminSignaturesValid`
  - `LibOrganizationAdmin._getAdminOperationHash`
  - `LibOrganizationAccountTransaction._computeInitiatorHashFromParams`
  - `LibOrganizationAccountTransaction._computeReviewHashFromParams`

---

## Legend

- `[U]` Unit
- `[S]` Security / replay-focused scenario
- `[N]` Negative path
- `[E]` Edge case
- `[F]` Fuzz
- `[I]` Invariant
- `[EV]` Event validation

---

## File 1: `LibOrganizationSignatures.sol`

### 1.1 `computeNonce`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Same `(operationType, operationData, salt, organization)` inputs produce same nonce (deterministic) | [U] | P0 |
| 2 | Different `operationType` with same data/salt produces different nonce | [U] | P0 |
| 3 | Different `operationData` with same type/salt produces different nonce | [U] | P0 |
| 4 | Different `salt` with same type/data produces different nonce | [U] | P0 |
| 5 | Same type/data/salt on different organization addresses produces different nonce (`address(this)` binding) | [S] | P0 |
| 6 | Empty `operationData` is supported and deterministic | [E] | P1 |
| 7 | Large `operationData` is supported and deterministic | [E] | P1 |

### 1.2 `validateAndConsumeNonceOrRevert` and `isNonceUsed`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 8 | Fresh nonce can be consumed once | [U] | P0 |
| 9 | Reusing consumed nonce reverts `NonceAlreadyUsed` | [S] | P0 |
| 10 | Revert payload includes the exact reused nonce value | [U] | P1 |
| 11 | `isNonceUsed(n)` is `false` before consume and `true` after consume | [U] | P0 |
| 12 | Consuming nonce `A` does not mark unrelated nonce `B` as used | [U] | P0 |
| 13 | Once consumed, nonce remains used across subsequent successful operations (monotonic) | [S] | P0 |

---

## File 2: `OrganizationSignaturesBase.sol`

### 2.1 `computeNonce`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 14 | External `computeNonce` returns same value as direct library computation for same inputs | [U] | P1 |
| 15 | Callable by non-guardian/non-admin callers (view access only) | [U] | P2 |

### 2.2 `isNonceUsed`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 16 | Reflects `false` for untouched nonce and `true` after nonce is consumed in another flow | [U] | P1 |
| 17 | Callable by any caller (view access only) | [U] | P2 |

---

## File 3: `LibOrganizationAdmin.sol`

### 3.1 `validateAdminAuthAndConsumeNonceOrRevert`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 18 | Valid admin auth consumes nonce and succeeds | [U] | P0 |
| 19 | Replay with same `(operationType, operationData, salt)` reverts `NonceAlreadyUsed` | [S] | P0 |
| 20 | Expired auth reverts `AdminOperationExpired` and nonce is not consumed | [S] | P0 |
| 21 | Insufficient valid signatures reverts `InsufficientAdminAuthorization` and nonce is not consumed | [S] | P0 |
| 22 | Malformed signature bytes revert and nonce is not consumed | [S] | P0 |
| 23 | Non-admin signer reverts `SignerIsNotAdmin` and nonce is not consumed | [S] | P0 |
| 24 | Duplicate/out-of-order signer set reverts `DuplicateOrOutOfOrderAdminSigner` and nonce is not consumed | [S] | P0 |
| 25 | Same operation data/salt, `isApproval=true` then `isApproval=false`: second call fails due shared nonce space | [S] | P0 |
| 26 | Same operation data/salt with different `operationType` values can both succeed (nonce isolation by type) | [S] | P0 |
| 27 | Same operation type/data with different salts can both succeed | [U] | P0 |
| 28 | Exactly-threshold valid signatures succeed; below threshold fails without consuming nonce | [U] | P0 |
| 29 | Mixed EOA + ERC-1271 admin signatures validate correctly and still enforce single nonce consumption | [S] | P0 |

### 3.2 `_getAdminOperationHash` (private -> internal via harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 30 | Deterministic for identical inputs | [U] | P1 |
| 31 | Changing `isApproval` changes hash (approval/rejection signature separation) | [S] | P0 |
| 32 | Changing `operationType` changes hash | [S] | P0 |
| 33 | Changing `operationData` changes hash | [S] | P0 |
| 34 | Changing `salt` changes hash | [S] | P0 |
| 35 | Changing `expirationTimestamp` changes hash | [U] | P1 |
| 36 | Changing `chainId` changes hash (cross-chain replay protection) | [S] | P0 |
| 37 | Changing organization address changes hash (cross-org replay protection) | [S] | P0 |
| 38 | Golden vector: known inputs produce expected typed-data hash | [U] | P1 |

### 3.3 `_areAdminSignaturesValid` (private -> internal via harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 39 | Empty signatures returns `false` | [N] | P0 |
| 40 | Duplicate signer reverts `DuplicateOrOutOfOrderAdminSigner` | [N] | P0 |
| 41 | Out-of-order signer list reverts `DuplicateOrOutOfOrderAdminSigner` | [N] | P0 |
| 42 | Non-admin signer reverts `SignerIsNotAdmin` | [N] | P0 |
| 43 | Returns `true` once threshold is reached | [U] | P1 |
| 44 | Mixed EOA->ERC1271->EOA packed signatures parsed correctly (offset accounting) | [S] | P0 |
| 45 | Malformed packed signature stream reverts | [N] | P0 |

---

## File 4: `OrganizationAdminBase.sol`

### 4.1 `modifyAdmins`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 46 | Successful execution consumes nonce (replay with same auth reverts) | [S] | P0 |
| 47 | If downstream admin mutation reverts, nonce is rolled back (not burned) | [S] | P0 |

### 4.2 `rejectAdminOperation`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 48 | Valid rejection consumes nonce and emits `AdminOperationRejected` with correct nonce | [EV] | P0 |
| 49 | Replaying same rejection call (same type/data/salt) reverts `NonceAlreadyUsed` | [S] | P0 |
| 50 | Rejecting with wrong `operationData` burns a different nonce and does not block the intended operation | [S] | P0 |
| 51 | Reject then approve same operation params/salt is blocked by shared nonce | [S] | P0 |
| 52 | Approve then reject same operation params/salt is blocked by shared nonce | [S] | P0 |

---

## File 5: `OrganizationAccountTransactionBase.sol`

### 5.1 `executeAccountTransaction`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 53 | Nonce depends on `(account, to, value, keccak256(data), policyId, salt)` | [U] | P0 |
| 54 | Changing `expirationTimestamp` only does not change nonce | [E] | P1 |
| 55 | Changing signatures/proofs only does not change nonce | [E] | P1 |
| 56 | First successful execution consumes nonce and emits it in event | [EV] | P0 |
| 57 | Replay with same nonce parameters reverts `NonceAlreadyUsed` | [S] | P0 |
| 58 | Nonce is consumed before external account call; reentrant same-nonce attempt in same tx fails | [S] | P0 |
| 59 | If policy/signature validation fails after consume call, transaction reverts and nonce remains unused | [S] | P0 |
| 60 | If downstream `Account.executeTransaction` reverts, nonce remains unused (rollback) | [S] | P0 |

### 5.2 `rejectAccountTransaction`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 61 | Uses same nonce formula/domain as `executeAccountTransaction` for identical tx params | [S] | P0 |
| 62 | First successful rejection consumes nonce and emits it in event | [EV] | P0 |
| 63 | Replay reject with same nonce parameters reverts `NonceAlreadyUsed` | [S] | P0 |
| 64 | Reject then execute same tx params/salt is blocked | [S] | P0 |
| 65 | Execute then reject same tx params/salt is blocked | [S] | P0 |
| 66 | If rejection validation fails after consume call, transaction reverts and nonce remains unused | [S] | P0 |
| 67 | Both execute/reject paths intentionally use `OperationType.AccountTransaction` (shared nonce space) | [S] | P0 |

---

## File 6: Admin-Authorized Entry Points (by file/function)

### 6.1 `OrganizationAccountFactoryBase.sol`

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 68 | `deployAccount` | Replay with same signed params/salt reverts | [S] | P0 |
| 69 | `deployAccount` | Different admin auth salt for same `create2Salt` yields independent nonce | [U] | P1 |
| 70 | `setAccountImplementation` | Replay with same signed params/salt reverts | [S] | P0 |
| 71 | `setAccountImplementation` | If whitelist validation reverts, nonce is rolled back | [S] | P0 |

### 6.2 `OrganizationMembersBase.sol`

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 72 | `modifyMembers` | Replay with same signed params/salt reverts | [S] | P0 |
| 73 | `modifyMembers` | Same members set but different array order produces different nonce | [S] | P1 |

### 6.3 `OrganizationGroupsBase.sol`

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 74 | `modifyGroups` | Replay with same signed params/salt reverts | [S] | P0 |
| 75 | `modifyGroups` | Same semantic modifications with different ordering produce different nonce | [S] | P1 |

### 6.4 `OrganizationPolicyBase.sol`

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 76 | `setPolicies` | Replay with same signed params/salt reverts | [S] | P0 |
| 77 | `setPolicies` | Same `newPoliciesRoot` but different `ipfsCid` yields different nonce (CID hash is bound) | [S] | P1 |
| 78 | `setPolicies` | Same root + same CID bytes yields same nonce | [U] | P1 |

### 6.5 `OrganizationGuardianBase.sol`

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 79 | `initiateGuardianUpdate` | Replay with same signed params/salt reverts | [S] | P0 |
| 80 | `finalizeGuardianUpdate` | Replay with same signed params/salt reverts | [S] | P0 |
| 81 | `cancelGuardianUpdate` | Replay with same signed params/salt reverts | [S] | P0 |
| 82 | `initiate/finalize/cancel` | Signatures for one stage cannot be replayed for another stage (distinct `OperationType`) | [S] | P0 |
| 83 | `finalize/cancel` | Signatures are bound to current pending guardian; stale signatures fail after pending value changes | [S] | P0 |

### 6.6 `OrganizationGuardianRecoveryBase.sol`

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 84 | `initiateInitializeGuardianRecovery` | Replay with same signed params/salt reverts | [S] | P0 |
| 85 | `finalizeInitializeGuardianRecovery` | Replay with same signed params/salt reverts | [S] | P0 |
| 86 | `cancelInitializeGuardianRecovery` | Replay with same signed params/salt reverts | [S] | P0 |
| 87 | `initiate/finalize/cancel` | Signatures for one stage cannot be replayed for another stage (distinct `OperationType`) | [S] | P0 |
| 88 | `finalize/cancel` | Signatures are bound to current pending `(recoveryAddress, timelock)` values | [S] | P0 |

### 6.7 `OrganizationTxRecoveryBase.sol`

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 89 | `initiateInitializeTransactionAndERC1271Recovery` | Replay with same signed params/salt reverts | [S] | P0 |
| 90 | `finalizeInitializeTransactionAndERC1271Recovery` | Replay with same signed params/salt reverts | [S] | P0 |
| 91 | `cancelInitializeTransactionAndERC1271Recovery` | Replay with same signed params/salt reverts | [S] | P0 |
| 92 | `initiate/finalize/cancel` | Signatures for one stage cannot be replayed for another stage (distinct `OperationType`) | [S] | P0 |
| 93 | `finalize/cancel` | Signatures are bound to current pending `(recoveryAddress, timelock)` values | [S] | P0 |

---

## File 7: Replay Hash Helpers

### 7.1 `LibOrganizationAccountTransaction.sol`

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 94 | `_computeInitiatorHashFromParams` | `isApproval=true` and `isApproval=false` produce different hashes | [S] | P0 |
| 95 | `_computeInitiatorHashFromParams` | Different `chainId` produces different hash (cross-chain replay protection) | [S] | P0 |
| 96 | `_computeInitiatorHashFromParams` | Different organization address produces different hash (cross-org replay protection) | [S] | P0 |
| 97 | `_computeReviewHashFromParams` | Different `initiatorSignature` produces different reviewer hash (`keccak256(initiatorSignature)` binding) | [S] | P0 |
| 98 | `_computeReviewHashFromParams` | `isApproval` flip changes reviewer hash | [S] | P0 |
| 99 | `_computeInitiatorHashFromParams` + `_computeReviewHashFromParams` | Golden vectors match expected typed-data hashes | [U] | P1 |

### 7.2 `LibOrganizationEIP712.sol`

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 100 | `getDomainSeparator` | Deterministic for same chain + same organization | [U] | P1 |
| 101 | `getDomainSeparator` | Different chain IDs produce different domain separators | [S] | P0 |
| 102 | `getDomainSeparator` | Different organization addresses produce different domain separators | [S] | P0 |
| 103 | `computeTypedDataHash` | Matches EIP-712 reference output for known `(domain, structHash)` vector | [U] | P1 |

---

## Fuzz Tests

| # | Test Case | Runs | Priority |
|---|-----------|------|----------|
| 104 | Random `(operationType, operationData, salt)` tuples produce collision-resistant nonces in practice | 1000 | P1 |
| 105 | Random salts for fixed operation always produce independent nonces | 1000 | P1 |
| 106 | Across mixed nonce-consuming entry points, replaying any successfully used nonce always reverts | 1000 | P0 |
| 107 | Random invalid/expired admin auth attempts never leave nonce marked as used | 1000 | P0 |
| 108 | Random mixed EOA/ERC-1271 admin signature streams parse offsets correctly and enforce ordering/admin checks | 1000 | P0 |

---

## Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 109 | **Nonce monotonicity:** once `isNonceUsed(nonce) == true`, it never returns `false` | P0 |
| 110 | **No double-spend:** a nonce consumed by approve/execute cannot be consumed by reject (and vice versa) | P0 |
| 111 | **Cross-org isolation:** same operation inputs across different organizations never share nonce/hash validity | P0 |
| 112 | **Rollback safety:** failed paths that revert do not burn nonces | P0 |

---

## Summary

| Category | Tests | Priority Focus |
|----------|-------|----------------|
| File/function unit + security cases | 103 | P0/P1 |
| Fuzz tests | 5 | P0/P1 |
| Invariants | 4 | P0 |
| **Total** | **112** | |
