# 23 — Security Audit Gaps Test Plan

**Scope:** Security-focused tests identified as coverage gaps after auditing the Organization, Account, policy validation, signature validation, upgrade, and factory paths.

**Out of Scope for this plan (covered elsewhere):**
- Interface files (`src/interfaces/**/*.sol`)
- Storage libraries (`src/**/libraries/storage/**/*.sol`)

---

## Harness Prerequisite (Private Functions)

For direct unit tests of private helpers, temporarily change them to `internal` in the test branch and expose wrappers via harness contracts.

- `src/organization/libraries/LibOrganizationAccountTransaction.sol`
  - `_validateAndUpdateRateLimitOrRevert`
  - `_validateAutoApproveRejectionOrRevert`
  - `_validateManualConfirmationOrRevert`
  - `_computeInitiatorHashFromParams`
  - `_computeReviewHashFromParams`
- `src/organization/libraries/policy/LibPolicyParameterConstraints.sol`
  - `_processConstraints`
  - `_isParameterAllowedByConstraint`
  - `_isBoolParameterAllowedByConstraint`
  - `_isUintParameterAllowedByConstraint`
  - `_isIntParameterAllowedByConstraint`
  - `_isAddressParameterAllowedByConstraint`
  - `_isFixedBytesParameterAllowedByConstraint`
  - `_isBytesOrStringParameterAllowedByConstraint`
- `src/organization/libraries/LibOrganizationAccountSignature.sol`
  - `_validateRecoverySignature`
  - `_validatePolicyBasedSignature`
  - `_isValidGuardianSignature`
  - `_isERC1271SignatureAllowedByPolicy`
  - `_getInitiatorSignatureHash`
  - `_getReviewSignatureHash`
- `src/organization/libraries/LibOrganizationAdmin.sol`
  - `_areAdminSignaturesValid`
  - `_getAdminOperationHash`
- `src/account/AccountImplementation.sol`
  - `_execute`
  - `_onlyOrganization`
- `src/organization/OrganizationFactory.sol`
  - `_getOrganizationProxyBytecode`

---

## Legend

- `[U]` Unit
- `[S]` Security
- `[N]` Negative / revert path
- `[E]` Edge case
- `[I]` Integration
- `[F]` Fuzz
- `[INV]` Invariant
- `[EV]` Event

---

## File 1: `src/organization/libraries/LibOrganizationAccountTransaction.sol`

### 1.1 `validateTransactionApprovalOrRevert`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Expired transaction (`block.timestamp > expirationTimestamp`) reverts `TransactionExpired` | [N] | P0 |
| 2 | Empty `initiatorSignature` reverts `InsufficientSignaturesLength` | [N] | P0 |
| 3 | Malformed initiator signature bytes revert (fail-closed signer recovery) | [S] | P0 |
| 4 | Policy mismatch (proof/config/tx mismatch) reverts `PolicyDoesNotApply` | [N] | P0 |
| 5 | Manual-approval path binds reviewer approvals to `initiatorSignature` hash; tampering initiator sig invalidates collected reviews | [S] | P0 |
| 6 | Two different valid initiator signatures for same tx params produce different reviewer hashes (non-transferability) | [S] | P0 |
| 7 | Auto-approval policy succeeds without reviewer signatures but still enforces initiator authorization | [U] | P0 |
| 8 | Manual-approval policy with insufficient reviewer signatures reverts `InsufficientApprovals` | [N] | P0 |
| 9 | Rate-limit update runs only after policy/signature checks pass | [S] | P0 |

### 1.2 `validateTransactionRejectionOrRevert`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 10 | Rejection on expired transaction reverts `TransactionExpired` | [N] | P0 |
| 11 | Auto-approval rejection requires rejection hash (`isApproval=false`) signed by authorized initiator | [S] | P0 |
| 12 | Approval signature replayed as rejection signature fails (hash domain separation) | [S] | P0 |
| 13 | Manual rejection uses `isApproval=false` in review hash; approval review signatures are not reusable for rejection | [S] | P0 |
| 14 | Rejection validation is read-only (no rate-limit mutation on rejection path) | [U] | P1 |

### 1.3 Private Helpers

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 15 | `_validateAndUpdateRateLimitOrRevert` | Token transfer usage uses extracted transfer amount, not fixed count | [U] | P0 |
| 16 | `_validateAndUpdateRateLimitOrRevert` | Contract interaction usage counts as `1` regardless ETH value | [U] | P0 |
| 17 | `_validateAndUpdateRateLimitOrRevert` | ERC-20 destination tracking uses transfer recipient from calldata (not token contract address) | [S] | P0 |
| 18 | `_validateAndUpdateRateLimitOrRevert` | If `checkAndUpdateRateLimit` returns false, revert `RateLimitExceeded(policyId)` | [N] | P0 |
| 19 | `_validateAutoApproveRejectionOrRevert` | Empty rejection signature bytes revert `TransactionRejectionNotAllowed` | [N] | P0 |
| 20 | `_validateManualConfirmationOrRevert` | `reviewHash` includes `keccak256(initiatorSignature)` (binding property) | [S] | P0 |
| 21 | `_computeInitiatorHashFromParams` | Hash changes across organization address / chain ID (cross-org and cross-chain replay defense) | [S] | P0 |
| 22 | `_computeReviewHashFromParams` | Changing only `initiatorSignature` changes review hash | [S] | P0 |

---

## File 2: `src/organization/libraries/policy/LibPolicyRateLimits.sol`

### 2.1 `checkAndUpdateRateLimit`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 23 | `RateLimitType.None` returns true and does not update usage storage | [U] | P0 |
| 24 | `currentUsage + usageAmount == timeIntervalLimit` succeeds (inclusive limit boundary) | [E] | P0 |
| 25 | `currentUsage + usageAmount > timeIntervalLimit` returns false and leaves usage unchanged | [N] | P0 |
| 26 | `usageAmount = 0` does not increase stored usage | [E] | P1 |
| 27 | Crossing into a new time window reads/writes a fresh usage bucket (window reset behavior) | [U] | P0 |
| 28 | [DESIRED] `TimeInterval` config with `timeIntervalHours = 0` fails closed (reject usage) instead of bypassing rate limiting | [S] | P0 |
| 29 | [DESIRED] Arithmetic overflow in `currentUsage + usageAmount` is handled gracefully (no panic) | [S] | P0 |

### 2.2 `computeTimeWindow`, `computeUsageKey`, `getCurrentUsage`

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 30 | `computeTimeWindow` | Deterministic output for same timestamp/policy | [U] | P1 |
| 31 | `computeTimeWindow` | `timeIntervalHours = 0` returns `0` | [E] | P1 |
| 32 | `computeUsageKey` | `AcrossAll` scope normalizes to `address(0)` for that dimension | [U] | P0 |
| 33 | `computeUsageKey` | `PerEntity` scope isolates by concrete account/destination/initiator | [U] | P0 |
| 34 | `getCurrentUsage` | Returns `0` when rate limit is disabled / not time-interval | [U] | P1 |

---

## File 3: `src/organization/libraries/policy/LibPolicyParameterConstraints.sol`

### 3.1 `areParametersAllowedByConstraints` and `_processConstraints`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 35 | Empty `parameterConstraints` bytes returns true | [E] | P1 |
| 36 | Decoded empty constraints array returns true | [E] | P1 |
| 37 | `paramCalldataHeadSlotCount = 0` returns false | [N] | P0 |
| 38 | Declared head slots exceeding calldata length returns false | [N] | P0 |
| 39 | Multi-slot parameter (`paramCalldataHeadSlotCount > 1`) advances offset correctly | [U] | P0 |
| 40 | Constraint referencing out-of-bounds calldata position returns false | [N] | P0 |
| 41 | [DESIRED] Malformed ABI-encoded constraints payload should return false (not revert) | [S] | P0 |

### 3.2 Type-Specific Constraint Helpers

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 42 | `_isAddressParameterAllowedByConstraint` | `OneOf` with empty merkle proof returns false | [N] | P0 |
| 43 | `_isBytesOrStringParameterAllowedByConstraint` | Dynamic length exceeding calldata returns false | [N] | P0 |
| 44 | `_isBytesOrStringParameterAllowedByConstraint` | Exact hash match for bytes/string succeeds | [U] | P1 |
| 45 | `_isParameterAllowedByConstraint` | `Array`/`Struct` with non-`Any` constraint returns false | [N] | P0 |
| 46 | `_isParameterAllowedByConstraint` | Unsupported/unknown param type returns false | [N] | P1 |
| 47 | [DESIRED] Offset/length arithmetic overflow returns false (not panic) | [S] | P0 |
| 48 | [DESIRED] Malformed `comparisonData` for typed decodes returns false (not revert) | [S] | P0 |

---

## File 4: `src/organization/libraries/LibOrganizationAccountSignature.sol`

### 4.1 `isValidSignature`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 49 | Empty signature returns ERC-1271 invalid value | [N] | P0 |
| 50 | Unknown signature type byte returns ERC-1271 invalid value | [N] | P0 |
| 51 | Recovery signature type (`0x00`) with valid recovery signer and enabled recovery returns magic value | [U] | P0 |
| 52 | Recovery signature type (`0x00`) while recovery disabled/not configured returns invalid value | [S] | P0 |
| 53 | [DESIRED] Policy signature type (`0x01`) with malformed ABI payload returns invalid value (not revert) | [S] | P0 |

### 4.2 `_validatePolicyBasedSignature`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 54 | Expired signature request returns invalid value | [N] | P0 |
| 55 | Empty initiator signature returns invalid value | [N] | P0 |
| 56 | Invalid initiator signature recovery returns invalid value | [N] | P0 |
| 57 | Missing/malformed guardian signature returns invalid value | [N] | P0 |
| 58 | Policy proof mismatch / source-account proof mismatch returns invalid value | [N] | P0 |
| 59 | Policy `transactionType != Signatures` returns invalid value | [N] | P0 |
| 60 | Unauthorized initiator for policy returns invalid value | [N] | P0 |
| 61 | Auto-approval policy with valid initiator+guardian signatures returns magic value | [U] | P0 |
| 62 | Manual-approval policy requires threshold reviewer signatures; insufficient reviewer signatures returns invalid value | [N] | P0 |
| 63 | Manual-approval reviewer signatures are bound to initiator signature (cannot replay with different initiator signature) | [S] | P0 |
| 64 | [DESIRED] Any downstream approval-validation revert (duplicate/out-of-order/unauthorized reviewer) should map to invalid value, not revert | [S] | P0 |

### 4.3 `_isValidGuardianSignature`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 65 | Direct guardian signature is accepted | [U] | P0 |
| 66 | Enabled module signature is accepted | [I] | P0 |
| 67 | Signature from non-enabled module is rejected | [S] | P0 |
| 68 | Guardian contract reverting on `isModuleEnabled` call is handled as invalid (`false`) | [E] | P0 |
| 69 | Truncated `isModuleEnabled` return data (`< 32 bytes`) is handled as invalid (`false`) | [E] | P0 |
| 70 | [DESIRED] Non-canonical bool return data from `isModuleEnabled` is handled as invalid (`false`), not revert | [S] | P0 |

### 4.4 Recovery/Policy Path Isolation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 71 | Policy signatures (`0x01`) are never accepted through recovery path logic | [S] | P0 |
| 72 | Recovery signatures (`0x00`) are never accepted through policy path logic | [S] | P0 |

---

## File 5: `src/organization/base/OrganizationAccountSignatureBase.sol`

### 5.1 `isValidSignatureForAccount`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 73 | `msg.sender != account` reverts (caller spoofing blocked) | [S] | P0 |
| 74 | `msg.sender == account` but account not deployed by this org reverts `AccountNotDeployedByOrganization` | [S] | P0 |
| 75 | Valid deployed account call delegates to signature library and returns its result | [U] | P1 |

---

## File 6: `src/organization/libraries/LibOrganizationAdmin.sol`

### 6.1 `validateAdminAuthAndConsumeNonceOrRevert`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 76 | Approval and rejection for same operation data/salt share nonce domain; second attempt fails with replay protection | [S] | P0 |
| 77 | Expired admin auth reverts before permanent nonce consumption | [S] | P0 |
| 78 | Admin removed after signatures are collected cannot execute with stale signatures | [S] | P0 |
| 79 | Voting threshold increase after signature collection invalidates previously sufficient signature sets | [S] | P0 |
| 80 | Mixed EOA + ERC-1271 packed admin signatures parse correctly across offsets | [S] | P0 |
| 81 | Malformed packed admin signature stream fails closed | [S] | P0 |

### 6.2 `_areAdminSignaturesValid` and `modifyAdmins`

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 82 | `_areAdminSignaturesValid` | Duplicate or out-of-order signers revert | [N] | P0 |
| 83 | `_areAdminSignaturesValid` | Non-admin signer reverts | [N] | P0 |
| 84 | `_areAdminSignaturesValid` | Exact-threshold valid signatures succeed | [U] | P1 |
| 85 | `modifyAdmins` | Removing the last admin always reverts `InvalidAdminConfig` | [S] | P0 |
| 86 | `modifyAdmins` | Adding a non-member as admin reverts | [N] | P0 |
| 87 | `modifyAdmins` | [DESIRED] Ambiguous add/remove inputs for same address in one call fail closed | [S] | P1 |

---

## File 7: `src/organization/base/OrganizationAccountTransactionBase.sol`

### 7.1 `executeAccountTransaction` and `rejectAccountTransaction`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 88 | Cross-organization account call reverts `AccountNotDeployedByOrganization` | [S] | P0 |
| 89 | Nonce is consumed before external account call (reentrancy replay defense ordering) | [S] | P0 |
| 90 | Reentrant attempt with same nonce in same transaction fails replay check | [S] | P0 |
| 91 | Failed downstream account execution reverts whole tx: nonce/rate-limit/event side effects are rolled back | [S] | P0 |
| 92 | Execute and reject paths intentionally share nonce domain for identical tx params/salt | [S] | P0 |
| 93 | Execute then reject with same params reverts replay; reject then execute also reverts replay | [S] | P0 |

---

## File 8: `src/account/AccountImplementation.sol`

### 8.1 `executeTransaction`, `receive`, `isValidSignature`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 94 | Non-organization caller to `executeTransaction` reverts `OnlyOrganization` | [N] | P0 |
| 95 | Low-level call returning `false` causes `TransactionExecutionFailed` revert | [N] | P0 |
| 96 | Reverting callee also surfaces as `TransactionExecutionFailed` (revert data not bubbled) | [E] | P0 |
| 97 | Insufficient-gas call path fails with `TransactionExecutionFailed` | [S] | P0 |
| 98 | `receive()` cannot be used to bypass `onlyOrganization` and re-enter privileged execution | [S] | P0 |
| 99 | `isValidSignature` always forwards `address(this)` as account to Organization signature validation | [U] | P0 |
| 100 | [DESIRED] Executing a call that attempts account self-destruction does not destroy the account | [S] | P1 |

---

## File 9: `src/organization/OrganizationImplementation.sol`

### 9.1 `upgradeToAndCallWithAuthorization` and `_authorizeUpgrade`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 101 | Direct call to inherited `upgradeToAndCall` (without wrapper flow) reverts `UnauthorizedUpgrade` | [S] | P0 |
| 102 | Failed upgrade/migration path does not leave authorization flag stuck true | [S] | P0 |
| 103 | Whitelist validation failure occurs before auth flag is set | [S] | P0 |
| 104 | `_authorizeUpgrade` is flag-gated and does not re-validate `newImplementation` parameter | [U] | P1 |
| 105 | [DESIRED] Admin authorization must bind migration `data` payload (not only `newImplementation`) | [S] | P0 |
| 106 | [DESIRED] Migration `data` cannot trigger nested second upgrade to bypass whitelist/admin checks | [S] | P0 |

---

## File 10: `src/organization/OrganizationFactory.sol`

### 10.1 `constructor`, `deployOrganization`, `computeOrganizationAddress`, `_getOrganizationProxyBytecode`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 107 | Constructor rejects zero `DEPLOYER_ADDRESS` | [N] | P0 |
| 108 | `deployOrganization` is callable only by `DEPLOYER_ADDRESS` | [S] | P0 |
| 109 | Same salt + same init bytecode cannot be deployed twice | [N] | P1 |
| 110 | Initialization failure reverts atomically (no uninitialized organization left deployed) | [S] | P0 |
| 111 | `computeOrganizationAddress` changes when `whitelistAddress` changes | [U] | P1 |
| 112 | `DEPLOYER_ADDRESS` remains immutable after deployment | [S] | P1 |
| 113 | [DESIRED] Deployment fails closed if `whitelistAddress` has no code (EOA/zero) | [S] | P0 |
| 114 | [DESIRED] Deployment fails closed if `implementationAddress` has no code, even if whitelist contract is permissive | [S] | P0 |
| 115 | `_getOrganizationProxyBytecode` is deterministic and argument-sensitive (harness) | [U] | P1 |

---

## File 11: `src/organization/common/OrganizationModifiers.sol`

### 11.1 Access-Control Modifiers

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 116 | `onlyGuardian` rejects tx-recovery and guardian-recovery roles (no cross-role escalation) | [S] | P0 |
| 117 | `onlyTxRecoveryAddress` rejects guardian caller | [S] | P0 |
| 118 | `onlyGuardianRecoveryAddress` rejects tx-recovery caller | [S] | P0 |
| 119 | `onlyPendingGuardian` and `onlyRecoveryPendingGuardian` reject calls when pending address is unset | [S] | P0 |
| 120 | All role modifiers fail closed when configured role address is zero | [S] | P0 |

---

## 12. Additional Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 121 | **Cross-org signature isolation:** signatures valid for one Organization are never valid for another | P0 |
| 122 | **Recovery isolation:** tx-recovery operations do not mutate guardian-recovery state, and vice versa | P0 |
| 123 | **Nonce monotonicity:** once a nonce is consumed, it is never reusable | P0 |
| 124 | **Rate-limit atomicity:** reverted outer transaction cannot leave partial usage updates | P0 |
| 125 | **Account beacon binding:** an Account’s Organization/beacon address is immutable post-deployment | P0 |

---

## 13. Additional Fuzz Tests

| # | Test Case | Runs | Priority |
|---|-----------|------|----------|
| 126 | [AUDIT-FUZZ] Random parameter constraints (offset/head/length permutations) never panic and terminate safely | 10000 | P0 |
| 127 | [AUDIT-FUZZ] Random malformed policy-signature payloads (`0x01`) return invalid (no revert) | 10000 | P0 |
| 128 | [AUDIT-FUZZ] Random guardian module behaviors (EOA/contract/revert/truncated return data) never cause signature-validation revert | 5000 | P0 |
| 129 | [AUDIT-FUZZ] Random mixed admin signature streams preserve strict ordering and threshold rules | 5000 | P0 |
| 130 | [AUDIT-FUZZ] Random rate-limit scope configs produce expected key sharing/isolation | 10000 | P0 |
| 131 | [AUDIT-FUZZ] Random execute/reject ordering preserves shared nonce replay protection | 5000 | P0 |
| 132 | [AUDIT-FUZZ] [DESIRED] Random upgrade migration calldata cannot bypass wrapper whitelist/admin checks via nested upgrade | 2000 | P0 |

---

## Summary

| Category | Tests | Priority |
|----------|-------|----------|
| File/function scoped security gap cases | 120 | P0-P1 |
| Invariants | 5 | P0 |
| Fuzz tests | 7 | P0 |
| **Total** | **132** | |
