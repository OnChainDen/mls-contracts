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
- `src/organization/OrganizationImplementation.sol`
- `src/organization/base/OrganizationAccountFactoryBase.sol`
- `src/organization/base/OrganizationMembersBase.sol`
- `src/organization/base/OrganizationGroupsBase.sol`
- `src/organization/base/OrganizationPolicyBase.sol`
- `src/organization/base/OrganizationGuardianBase.sol`
- `src/organization/base/OrganizationGuardianRecoveryBase.sol`
- `src/organization/base/OrganizationTxRecoveryBase.sol`
- `src/organization/libraries/LibOrganizationAccountTransaction.sol`
- `src/organization/libraries/LibOrganizationEIP712.sol`

**Harness Prerequisite (private functions -> internal in test branch):**
- Project-wide test assumption: currently `private` helper functions are made `internal` in the test branch and exposed through harness wrappers for direct unit tests.
- Private helpers in nonce/replay scope:
  - `LibOrganizationAdmin._areAdminSignaturesValid`
  - `LibOrganizationAdmin._getAdminOperationHash`
  - `LibOrganizationAccountTransaction._validateAutoApproveRejectionOrRevert`
  - `LibOrganizationAccountTransaction._validateManualConfirmationOrRevert`
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

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| NMSIG-CN-1 | Same `(operationType, operationData, salt, organization)` inputs produce same nonce (deterministic) | [U] | P0 |
| NMSIG-CN-2 | Different `operationType` with same data/salt produces different nonce | [U] | P0 |
| NMSIG-CN-3 | Different `operationData` with same type/salt produces different nonce | [U] | P0 |
| NMSIG-CN-4 | Different `salt` with same type/data produces different nonce | [U] | P0 |
| NMSIG-CN-5 | Same type/data/salt on different organization addresses produces different nonce (`address(this)` binding) | [S] | P0 |
| NMSIG-CN-6 | Empty `operationData` is supported and deterministic | [E] | P1 |
| NMSIG-CN-7 | Large `operationData` is supported and deterministic | [E] | P1 |

### 1.2 `validateAndConsumeNonceOrRevert` and `isNonceUsed`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| NMSIG-VCN-1 | Fresh nonce can be consumed once | [U] | P0 |
| NMSIG-VCN-2 | Reusing consumed nonce reverts `NonceAlreadyUsed` | [S] | P0 |
| NMSIG-VCN-3 | Revert payload includes the exact reused nonce value | [U] | P1 |
| NMSIG-VCN-4 | `isNonceUsed(n)` is `false` before consume and `true` after consume | [U] | P0 |
| NMSIG-VCN-5 | Consuming nonce `A` does not mark unrelated nonce `B` as used | [U] | P0 |
| NMSIG-VCN-6 | Once consumed, nonce remains used across subsequent successful operations (monotonic) | [S] | P0 |

---

## File 2: `OrganizationSignaturesBase.sol`

### 2.1 `computeNonce`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| NMSB-CN-1 | External `computeNonce` returns same value as direct library computation for same inputs | [U] | P1 |
| NMSB-CN-2 | Callable by non-guardian/non-admin callers (view access only) | [U] | P2 |

### 2.2 `isNonceUsed`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| NMSB-INU-1 | Reflects `false` for untouched nonce and `true` after nonce is consumed in another flow | [U] | P1 |
| NMSB-INU-2 | Callable by any caller (view access only) | [U] | P2 |

---

## File 3: `LibOrganizationAdmin.sol`

### 3.1 `validateAdminAuthAndConsumeNonceOrRevert`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| NMADM-AUTH-1 | Valid admin auth consumes nonce and succeeds | [U] | P0 |
| NMADM-AUTH-2 | Replay with same `(operationType, operationData, salt)` reverts `NonceAlreadyUsed` | [S] | P0 |
| NMADM-AUTH-3 | Expired auth reverts `AdminOperationExpired` and nonce is not consumed | [S] | P0 |
| NMADM-AUTH-4 | Expiration at exactly `block.timestamp` is accepted and, with valid signatures, consumes nonce | [E] | P0 |
| NMADM-AUTH-5 | Insufficient valid signatures reverts `InsufficientAdminAuthorization` and nonce is not consumed | [S] | P0 |
| NMADM-AUTH-6 | Malformed signature bytes revert and nonce is not consumed | [S] | P0 |
| NMADM-AUTH-7 | Signatures that sign different operation data than the operationData passed in to the function revert and nonce is not consumed | [S] | P0 |
| NMADM-AUTH-8 | Signatures that sign different operation type than the operationType passed in to the function revert and nonce is not consumed | [S] | P0 |
| NMADM-AUTH-9 | Non-admin signer reverts `SignerIsNotAdmin` and nonce is not consumed | [S] | P0 |
| NMADM-AUTH-10 | Duplicate/out-of-order signer set reverts `DuplicateOrOutOfOrderAdminSigner` and nonce is not consumed | [S] | P0 |
| NMADM-AUTH-11 | Same operation data/salt, `isApproval=true` then `isApproval=false`: second call fails due shared nonce space | [S] | P0 |
| NMADM-AUTH-12 | Same operation data/salt with different `operationType` values can both succeed (nonce isolation by type) | [S] | P0 |
| NMADM-AUTH-13 | Same operation type/data with different salts can both succeed | [U] | P0 |
| NMADM-AUTH-14 | Exactly-threshold valid signatures succeed; below threshold fails without consuming nonce | [U] | P0 |
| NMADM-AUTH-15 | Mixed EOA + ERC-1271 admin signatures validate correctly and still enforce single nonce consumption | [S] | P0 |

### 3.2 `_getAdminOperationHash` (private -> internal via harness)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| NMADM-HASH-1 | Deterministic for identical inputs | [U] | P1 |
| NMADM-HASH-2 | Changing `isApproval` changes hash (approval/rejection signature separation) | [S] | P0 |
| NMADM-HASH-3 | Changing `operationType` changes hash | [S] | P0 |
| NMADM-HASH-4 | Changing `operationData` changes hash | [S] | P0 |
| NMADM-HASH-5 | Changing `salt` changes hash | [S] | P0 |
| NMADM-HASH-6 | Changing `expirationTimestamp` changes hash | [U] | P1 |
| NMADM-HASH-7 | Changing `chainId` changes hash (cross-chain replay protection) | [S] | P0 |
| NMADM-HASH-8 | Changing organization address changes hash (cross-org replay protection) | [S] | P0 |
| NMADM-HASH-9 | Golden vector: known inputs produce expected typed-data hash | [U] | P1 |

### 3.3 `_areAdminSignaturesValid` (private -> internal via harness)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| NMADM-SIG-1 | Empty signatures returns `false` | [N] | P0 |
| NMADM-SIG-2 | Duplicate signer reverts `DuplicateOrOutOfOrderAdminSigner` | [N] | P0 |
| NMADM-SIG-3 | Out-of-order signer list reverts `DuplicateOrOutOfOrderAdminSigner` | [N] | P0 |
| NMADM-SIG-4 | Insufficient admin signatures return `false` from `_areAdminSignaturesValid` | [N] | P0 |
| NMADM-SIG-5 | Non-admin signer reverts `SignerIsNotAdmin` | [N] | P0 |
| NMADM-SIG-6 | Returns `true` once threshold is reached | [U] | P1 |
| NMADM-SIG-7 | Mixed EOA->ERC1271->EOA packed signatures parsed correctly (offset accounting) | [S] | P0 |
| NMADM-SIG-8 | Malformed packed signature stream reverts | [N] | P0 |

---

## File 4: `OrganizationAdminBase.sol`

### 4.1 `modifyAdmins`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| NMADB-MA-1 | Successful execution consumes nonce (replay with same auth reverts) | [S] | P0 |
| NMADB-MA-2 | If downstream admin mutation reverts, nonce is rolled back (not burned) | [S] | P0 |

### 4.2 `rejectAdminOperation`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| NMADB-RAO-1 | Valid rejection consumes nonce and emits `AdminOperationRejected` with correct nonce | [EV] | P0 |
| NMADB-RAO-2 | Replaying same rejection call (same type/data/salt) reverts `NonceAlreadyUsed` | [S] | P0 |
| NMADB-RAO-3 | Rejecting with wrong `operationData` burns a different nonce and does not block the intended operation | [S] | P0 |
| NMADB-RAO-4 | Reject then approve same operation params/salt is blocked by shared nonce | [S] | P0 |
| NMADB-RAO-5 | Approve then reject same operation params/salt is blocked by shared nonce | [S] | P0 |
| NMADB-RAO-6 | **Desired behavior:** `rejectAdminOperation` accepts only admin operation types; `OperationType.AccountTransaction` reverts and does not burn nonce | [S] | P0 |
| NMADB-RAO-7 | **Desired behavior:** `rejectAdminOperation` rejects `OperationType.AccountTransactionRejection` and does not burn nonce | [S] | P0 |

---

## File 5: `OrganizationAccountTransactionBase.sol`

### 5.1 `executeAccountTransaction`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| NMATB-EAT-1 | Nonce depends on `(account, to, value, keccak256(data), policyId, salt)` | [U] | P0 |
| NMATB-EAT-2 | Changing `expirationTimestamp` only does not change nonce | [E] | P1 |
| NMATB-EAT-3 | Changing signatures/proofs only does not change nonce | [E] | P1 |
| NMATB-EAT-4 | First successful execution consumes nonce and emits it in event | [EV] | P0 |
| NMATB-EAT-5 | Replay with same nonce parameters reverts `NonceAlreadyUsed` | [S] | P0 |
| NMATB-EAT-6 | Nonce is consumed before external account call; reentrant same-nonce attempt in same tx fails | [S] | P0 |
| NMATB-EAT-7 | If policy/signature validation fails after consume call, transaction reverts and nonce remains unused | [S] | P0 |
| NMATB-EAT-8 | If downstream `Account.executeTransaction` reverts, nonce remains unused (rollback) | [S] | P0 |
| NMATB-EAT-9 | Expired transaction (`TransactionExpired`) reverts after consume-first ordering and nonce remains unused (rollback) | [S] | P0 |

### 5.2 `rejectAccountTransaction`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| NMATB-RAT-1 | Uses same nonce formula/domain as `executeAccountTransaction` for identical tx params | [S] | P0 |
| NMATB-RAT-2 | First successful rejection consumes nonce and emits it in event | [EV] | P0 |
| NMATB-RAT-3 | Replay reject with same nonce parameters reverts `NonceAlreadyUsed` | [S] | P0 |
| NMATB-RAT-4 | Reject then execute same tx params/salt is blocked | [S] | P0 |
| NMATB-RAT-5 | Execute then reject same tx params/salt is blocked | [S] | P0 |
| NMATB-RAT-6 | If rejection validation fails after consume call, transaction reverts and nonce remains unused | [S] | P0 |
| NMATB-RAT-7 | Both execute/reject paths intentionally use `OperationType.AccountTransaction` (shared nonce space) | [S] | P0 |
| NMATB-RAT-8 | Expired rejection (`TransactionExpired`) reverts after consume-first ordering and nonce remains unused (rollback) | [S] | P0 |

---

## File 6: Admin-Authorized Entry Points (by file/function)

### 6.1 `OrganizationAccountFactoryBase.sol`

| ID | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| NMAFB-AEP-1 | `deployAccount` | Replay with same signed params/salt reverts | [S] | P0 |
| NMAFB-AEP-2 | `deployAccount` | Different admin auth salt for same `create2Salt` yields independent nonce | [U] | P1 |
| NMAFB-AEP-3 | `deployAccount` | Same `create2Salt` with different admin auth salts cannot be executed twice on one org (second call reverts from CREATE2 collision); to keep both calls successful, run once per fresh organization instance with identical params | [S] | P1 |
| NMAFB-AEP-4 | `setAccountImplementation` | Replay with same signed params/salt reverts | [S] | P0 |
| NMAFB-AEP-5 | `setAccountImplementation` | Same `newImplementation` with different admin auth salts can both succeed (use a whitelisted implementation with runtime code so downstream validation passes both times) | [U] | P1 |
| NMAFB-AEP-6 | `setAccountImplementation` | If whitelist validation reverts, nonce is rolled back | [S] | P0 |
| NMAFB-AEP-7 | `deployAccount` | If CREATE2 deployment reverts (e.g., duplicate salt), nonce is rolled back | [S] | P0 |

### 6.2 `OrganizationMembersBase.sol`

| ID | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| NMMB-MM-1 | `modifyMembers` | Replay with same signed params/salt reverts | [S] | P0 |
| NMMB-MM-2 | `modifyMembers` | Same members set but different array order produces different nonce | [S] | P1 |
| NMMB-MM-3 | `modifyMembers` | Same `membersToAdd` and `membersToRemove` arrays (same order) can both succeed with different admin auth salts; if direct back-to-back would fail for chosen fixtures, restore pre-state with an intermediate inverse member update, then repeat the exact original call | [S] | P1 |
| NMMB-MM-4 | `modifyMembers` | If member mutation reverts (e.g., removing an admin member), nonce is rolled back | [S] | P0 |

### 6.3 `OrganizationGroupsBase.sol`

| ID | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| NMGB-MG-1 | `modifyGroups` | Replay with same signed params/salt reverts | [S] | P0 |
| NMGB-MG-2 | `modifyGroups` | Same semantic modifications with different ordering produce different nonce | [S] | P1 |
| NMGB-MG-3 | `modifyGroups` | Same `modifications` array (same order) can both succeed with different admin auth salts; when using non-repeatable create/delete shapes, insert an intermediate state-reset sequence (for example, delete/recreate or recreate/delete as appropriate) so the second call sees the same valid pre-state | [S] | P1 |
| NMGB-MG-4 | `modifyGroups` | If group mutation reverts (invalid create/update/delete/member changes), nonce is rolled back | [S] | P0 |

### 6.4 `OrganizationPolicyBase.sol`

| ID | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| NMPB-SP-1 | `setPolicies` | Replay with same signed params/salt reverts | [S] | P0 |
| NMPB-SP-2 | `setPolicies` | Same `newPoliciesRoot` but different `ipfsCid` yields different nonce (CID hash is bound) | [S] | P1 |
| NMPB-SP-3 | `setPolicies` | Same root + same CID bytes yields same nonce | [U] | P1 |
| NMPB-SP-4 | `setPolicies` | Same `(newPoliciesRoot, ipfsCid)` can both succeed with different admin auth salts (idempotent downstream write) | [U] | P1 |

### 6.5 `OrganizationGuardianBase.sol`

| ID | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| NMGUB-GUF-1 | `initiateGuardianUpdate` | Replay with same signed params/salt reverts | [S] | P0 |
| NMGUB-GUF-2 | `initiateGuardianUpdate` | Same `newGuardian` can both succeed with different admin auth salts by doing `initiate(newGuardian)` -> `cancelGuardianUpdate(...)` -> `initiate(newGuardian)` again | [S] | P1 |
| NMGUB-GUF-3 | `finalizeGuardianUpdate` | Replay with same signed params/salt reverts | [S] | P0 |
| NMGUB-GUF-4 | `finalizeGuardianUpdate` | Same pending guardian can be finalized twice with different admin auth salts: initiate once, wait timelock once, call `finalizeGuardianUpdate` twice before accept/cancel | [S] | P1 |
| NMGUB-GUF-5 | `cancelGuardianUpdate` | Replay with same signed params/salt reverts | [S] | P0 |
| NMGUB-GUF-6 | `cancelGuardianUpdate` | Same pending guardian can be canceled twice with different admin auth salts by re-initiating the same guardian between cancels | [S] | P1 |
| NMGUB-GUF-7 | `initiate/finalize/cancel` | Signatures for one stage cannot be replayed for another stage (distinct `OperationType`) | [S] | P0 |
| NMGUB-GUF-8 | `finalize/cancel` | Signatures are bound to current pending guardian; stale signatures fail after pending value changes | [S] | P0 |
| NMGUB-GUF-9 | `initiateGuardianUpdate` | If downstream guardian validation fails (`newGuardian=0` or update already pending), nonce is rolled back | [S] | P0 |
| NMGUB-GUF-10 | `finalize/cancel` | If downstream pending/timelock checks fail, nonce is rolled back | [S] | P0 |

### 6.6 `OrganizationGuardianRecoveryBase.sol`

| ID | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| NMGRB-IGR-1 | `initiateInitializeGuardianRecovery` | Replay with same signed params/salt reverts | [S] | P0 |
| NMGRB-IGR-2 | `initiateInitializeGuardianRecovery` | Same `(recoveryAddress, timelockDurationSeconds)` can both succeed with different admin auth salts by using `initiate` -> `cancel` -> `initiate` (same params) | [S] | P1 |
| NMGRB-IGR-3 | `finalizeInitializeGuardianRecovery` | Replay with same signed params/salt reverts | [S] | P0 |
| NMGRB-IGR-4 | `finalizeInitializeGuardianRecovery` | Same pending init params can each finalize with different salts only on fresh org instances (single org cannot finalize init twice because first finalize permanently configures guardian recovery); run `initiate` + timelock wait + `finalize` once per fresh org | [S] | P1 |
| NMGRB-IGR-5 | `cancelInitializeGuardianRecovery` | Replay with same signed params/salt reverts | [S] | P0 |
| NMGRB-IGR-6 | `cancelInitializeGuardianRecovery` | Same pending init params can be canceled twice with different admin auth salts by re-initiating identical params between cancels | [S] | P1 |
| NMGRB-IGR-7 | `initiate/finalize/cancel` | Signatures for one stage cannot be replayed for another stage (distinct `OperationType`) | [S] | P0 |
| NMGRB-IGR-8 | `finalize/cancel` | Signatures are bound to current pending `(recoveryAddress, timelock)` values | [S] | P0 |
| NMGRB-IGR-9 | `initiateInitializeGuardianRecovery` | If downstream init checks fail (invalid params/already configured/already pending), nonce is rolled back | [S] | P0 |
| NMGRB-IGR-10 | `finalize/cancel` | If downstream pending/timelock checks fail, nonce is rolled back | [S] | P0 |

### 6.7 `OrganizationTxRecoveryBase.sol`

| ID | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| NMTRB-ITR-1 | `initiateInitializeTransactionAndERC1271Recovery` | Replay with same signed params/salt reverts | [S] | P0 |
| NMTRB-ITR-2 | `initiateInitializeTransactionAndERC1271Recovery` | Same `(recoveryAddress, timelockDurationSeconds)` can both succeed with different admin auth salts by using `initiate` -> `cancel` -> `initiate` (same params) | [S] | P1 |
| NMTRB-ITR-3 | `finalizeInitializeTransactionAndERC1271Recovery` | Replay with same signed params/salt reverts | [S] | P0 |
| NMTRB-ITR-4 | `finalizeInitializeTransactionAndERC1271Recovery` | Same pending init params can each finalize with different salts only on fresh org instances (single org cannot finalize init twice because first finalize permanently configures tx recovery); run `initiate` + timelock wait + `finalize` once per fresh org | [S] | P1 |
| NMTRB-ITR-5 | `cancelInitializeTransactionAndERC1271Recovery` | Replay with same signed params/salt reverts | [S] | P0 |
| NMTRB-ITR-6 | `cancelInitializeTransactionAndERC1271Recovery` | Same pending init params can be canceled twice with different admin auth salts by re-initiating identical params between cancels | [S] | P1 |
| NMTRB-ITR-7 | `initiate/finalize/cancel` | Signatures for one stage cannot be replayed for another stage (distinct `OperationType`) | [S] | P0 |
| NMTRB-ITR-8 | `finalize/cancel` | Signatures are bound to current pending `(recoveryAddress, timelock)` values | [S] | P0 |
| NMTRB-ITR-9 | `initiateInitializeTransactionAndERC1271Recovery` | If downstream init checks fail (invalid params/already configured/already pending), nonce is rolled back | [S] | P0 |
| NMTRB-ITR-10 | `finalize/cancel` | If downstream pending/timelock checks fail, nonce is rolled back | [S] | P0 |

### 6.8 `OrganizationImplementation.sol`

| ID | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| NMOI-UTACWA-1 | `upgradeToAndCallWithAuthorization` | Replay with same signed params/salt reverts | [S] | P0 |
| NMOI-UTACWA-2 | `upgradeToAndCallWithAuthorization` | Same `(newImplementation, data)` can both succeed with different admin auth salts when `data` is idempotent/no-op migration calldata; avoid one-time initializer calldata that would revert on the second call | [S] | P1 |
| NMOI-UTACWA-3 | `upgradeToAndCallWithAuthorization` | **Desired behavior:** admin authorization/nonce domain binds both `newImplementation` and migration `data` (guardian cannot swap calldata) | [S] | P0 |
| NMOI-UTACWA-4 | `upgradeToAndCallWithAuthorization` | If whitelist validation, UUPS upgrade checks, or migration call reverts, nonce is rolled back | [S] | P0 |

---

## File 7: Replay Hash & Binding Helpers

### 7.1 `LibOrganizationAccountTransaction.sol`

| ID | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| NMATL-RHB-1 | `_computeInitiatorHashFromParams` | Fuzz differential matrix: from one baseline input tuple, mutate exactly one bound field at a time and assert hash changes for each field: `organization (address(this))`, `account`, `to`, `value`, `data`, `salt`, `expirationTimestamp`, `policyId`, `isApproval`, `chainId` | [F] | P0 |
| NMATL-RHB-2 | `_computeInitiatorHashFromParams` | Invariant: for any two initiator input tuples, if any bound field differs then hash must differ; when varying `data`, require `keccak256(dataA) != keccak256(dataB)` | [I] | P0 |
| NMATL-RHB-3 | `_computeReviewHashFromParams` | Fuzz differential matrix: from one baseline input tuple, mutate exactly one bound field at a time and assert hash changes for each field: `organization (address(this))`, `account`, `to`, `value`, `data`, `salt`, `expirationTimestamp`, `policyId`, `isApproval`, `chainId`, `initiatorSignature` | [F] | P0 |
| NMATL-RHB-4 | `_computeReviewHashFromParams` | Invariant: for any two review input tuples, if any bound field differs then hash must differ; when varying `data`/`initiatorSignature`, require differing `keccak256` values | [I] | P0 |
| NMATL-RHB-5 | `_computeInitiatorHashFromParams` + `_computeReviewHashFromParams` | Baseline control: with identical inputs across repeated calls, hashes are deterministic and equal (guards against false positives in differential checks) | [U] | P1 |
| NMATL-RHB-6 | `_computeInitiatorHashFromParams` + `_computeReviewHashFromParams` | Golden vectors match expected typed-data hashes | [U] | P1 |
| NMATL-RHB-7 | `_validateAutoApproveRejectionOrRevert` | Approval signature cannot be replayed as rejection authorization (`isApproval` domain separation) | [S] | P0 |
| NMATL-RHB-8 | `_validateManualConfirmationOrRevert` | Reviewer signatures are bound to `(isApproval, initiatorSignature)`; replay across approval/rejection or different initiator signature fails | [S] | P0 |

### 7.2 `LibOrganizationEIP712.sol`

| ID | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| NMEIP-E712-1 | `getDomainSeparator` | Deterministic for same chain + same organization | [U] | P1 |
| NMEIP-E712-2 | `getDomainSeparator` | Different chain IDs produce different domain separators | [S] | P0 |
| NMEIP-E712-3 | `getDomainSeparator` | Different organization addresses produce different domain separators | [S] | P0 |
| NMEIP-E712-4 | `computeTypedDataHash` | Matches EIP-712 reference output for known `(domain, structHash)` vector | [U] | P1 |

---

## Fuzz Tests

| ID | Test Case | Runs | Priority |
|---|-----------|------|----------|
| NMFZ-1 | Random `(operationType, operationData, salt)` tuples produce collision-resistant nonces in practice | 1000 | P1 |
| NMFZ-2 | Random salts for fixed operation always produce independent nonces | 1000 | P1 |
| NMFZ-3 | Across mixed nonce-consuming entry points, replaying any successfully used nonce always reverts | 1000 | P0 |
| NMFZ-4 | Random invalid/expired admin auth attempts never leave nonce marked as used | 1000 | P0 |
| NMFZ-5 | Random mixed EOA/ERC-1271 admin signature streams parse offsets correctly and enforce ordering/admin checks | 1000 | P0 |
| NMFZ-6 | Random unauthorized-caller attempts against nonce-consuming entry points never burn nonce | 1000 | P0 |

---

## Invariant Tests

| ID | Invariant | Priority |
|---|-----------|----------|
| NMINV-1 | **Nonce monotonicity:** once `isNonceUsed(nonce) == true`, it never returns `false` | P0 |
| NMINV-2 | **No double-spend:** a nonce consumed by approve/execute cannot be consumed by reject (and vice versa) | P0 |
| NMINV-3 | **Cross-org isolation:** same operation inputs across different organizations never share nonce/hash validity | P0 |
| NMINV-4 | **Rollback safety:** failed paths that revert do not burn nonces | P0 |
| NMINV-5 | **Admin reject domain isolation (desired):** `rejectAdminOperation` cannot consume nonces in account-transaction operation domains | P0 |

---

## Summary

| Category | Tests | Priority Focus |
|----------|-------|----------------|
| File/function unit + security cases | 137 | P0/P1 |
| Fuzz tests | 6 | P0/P1 |
| Invariants | 5 | P0 |
| **Total** | **148** | |
