# 23 — Security Audit Gaps Test Plan

**Scope:** Security-focused tests identified as coverage gaps after auditing the Organization, Account, policy validation, signature validation, upgrade, and factory paths.

**Out of Scope for this plan (covered elsewhere):**
- Interface files (`src/interfaces/**/*.sol`)
- Storage libraries (`src/**/libraries/storage/**/*.sol`)

---

## Harness Prerequisite (Private Functions)

For this plan, all currently `private` helpers listed below are in scope for direct unit coverage.
In the test branch, temporarily change each listed helper to `internal` and expose wrappers via harness contracts so these helpers are tested explicitly (not only via indirect parent-path tests).

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
| 2 | `expirationTimestamp == block.timestamp` is accepted (strict `>` expiration check) | [E] | P1 |
| 3 | Empty `initiatorSignature` reverts `InsufficientSignaturesLength` | [N] | P0 |
| 4 | Malformed initiator signature bytes revert (fail-closed signer recovery) | [S] | P0 |
| 5 | Policy mismatch (proof/config/tx mismatch) reverts `PolicyDoesNotApply` | [N] | P0 |
| 6 | Manual-approval path binds reviewer approvals to `initiatorSignature` hash; tampering initiator sig invalidates collected reviews | [S] | P0 |
| 7 | Two different valid initiator signatures for same tx params produce different reviewer hashes (non-transferability) | [S] | P0 |
| 8 | Auto-approval policy succeeds without reviewer signatures but still enforces initiator authorization | [U] | P0 |
| 9 | Manual-approval policy with insufficient reviewer signatures reverts `InsufficientApprovals` | [N] | P0 |
| 10 | Rate-limit update runs only after policy/signature checks pass | [S] | P0 |

### 1.2 `validateTransactionRejectionOrRevert`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 11 | Rejection on expired transaction reverts `TransactionExpired` | [N] | P0 |
| 12 | Auto-approval rejection requires rejection hash (`isApproval=false`) signed by authorized initiator | [S] | P0 |
| 13 | Approval signature replayed as rejection signature fails (hash domain separation) | [S] | P0 |
| 14 | Manual rejection uses `isApproval=false` in review hash; approval review signatures are not reusable for rejection | [S] | P0 |
| 15 | Rejection validation is read-only (no rate-limit mutation on rejection path) | [U] | P1 |

### 1.3 Private Helpers

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 16 | `_validateAndUpdateRateLimitOrRevert` | Token transfer usage uses extracted transfer amount, not fixed count | [U] | P0 |
| 17 | `_validateAndUpdateRateLimitOrRevert` | Contract interaction usage counts as `1` regardless ETH value | [U] | P0 |
| 18 | `_validateAndUpdateRateLimitOrRevert` | ERC-20 destination tracking uses transfer recipient from calldata (not token contract address) | [S] | P0 |
| 19 | `_validateAndUpdateRateLimitOrRevert` | If `checkAndUpdateRateLimit` returns false, revert `RateLimitExceeded(policyId)` | [N] | P0 |
| 20 | `_validateAutoApproveRejectionOrRevert` | Empty rejection signature bytes revert `TransactionRejectionNotAllowed` | [N] | P0 |
| 21 | `_validateManualConfirmationOrRevert` | `reviewHash` includes `keccak256(initiatorSignature)` (binding property) | [S] | P0 |
| 22 | `_computeInitiatorHashFromParams` | Hash changes across organization address / chain ID (cross-org and cross-chain replay defense) | [S] | P0 |
| 23 | `_computeReviewHashFromParams` | Changing only `initiatorSignature` changes review hash | [S] | P0 |

---

## File 2: `src/organization/libraries/policy/LibPolicyRateLimits.sol`

### 2.1 `checkAndUpdateRateLimit`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 24 | `RateLimitType.None` returns true and does not update usage storage | [U] | P0 |
| 25 | `currentUsage + usageAmount == timeIntervalLimit` succeeds (inclusive limit boundary) | [E] | P0 |
| 26 | `currentUsage + usageAmount > timeIntervalLimit` returns false and leaves usage unchanged | [N] | P0 |
| 27 | `usageAmount = 0` does not increase stored usage | [E] | P1 |
| 28 | Crossing into a new time window reads/writes a fresh usage bucket (window reset behavior) | [U] | P0 |
| 29 | [DESIRED] `TimeInterval` config with `timeIntervalHours = 0` fails closed (reject usage) instead of bypassing rate limiting | [S] | P0 |
| 30 | [DESIRED] Arithmetic overflow in `currentUsage + usageAmount` is handled gracefully (no panic) | [S] | P0 |

### 2.2 `computeTimeWindow`, `computeUsageKey`, `getCurrentUsage`

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 31 | `computeTimeWindow` | Deterministic output for same timestamp/policy | [U] | P1 |
| 32 | `computeTimeWindow` | `timeIntervalHours = 0` returns `0` | [E] | P1 |
| 33 | `computeUsageKey` | `AcrossAll` scope normalizes to `address(0)` for that dimension | [U] | P0 |
| 34 | `computeUsageKey` | `PerEntity` scope isolates by concrete account/destination/initiator | [U] | P0 |
| 35 | `getCurrentUsage` | Returns `0` when rate limit is disabled / not time-interval | [U] | P1 |

---

## File 3: `src/organization/libraries/policy/LibPolicyParameterConstraints.sol`

### 3.1 `areParametersAllowedByConstraints` and `_processConstraints`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 36 | Empty `parameterConstraints` bytes returns true | [E] | P1 |
| 37 | Decoded empty constraints array returns true | [E] | P1 |
| 38 | `paramCalldataHeadSlotCount = 0` returns false | [N] | P0 |
| 39 | Declared head slots exceeding calldata length returns false | [N] | P0 |
| 40 | Multi-slot parameter (`paramCalldataHeadSlotCount > 1`) advances offset correctly | [U] | P0 |
| 41 | Constraint referencing out-of-bounds calldata position returns false | [N] | P0 |
| 42 | [DESIRED] Malformed ABI-encoded constraints payload should return false (not revert) | [S] | P0 |

### 3.2 Type-Specific Constraint Helpers

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 43 | `_isAddressParameterAllowedByConstraint` | `OneOf` with empty merkle proof returns false | [N] | P0 |
| 44 | `_isBytesOrStringParameterAllowedByConstraint` | Dynamic length exceeding calldata returns false | [N] | P0 |
| 45 | `_isBytesOrStringParameterAllowedByConstraint` | Exact hash match for bytes/string succeeds | [U] | P1 |
| 46 | `_isParameterAllowedByConstraint` | `Array`/`Struct` with non-`Any` constraint returns false | [N] | P0 |
| 47 | `_isParameterAllowedByConstraint` | Unsupported/unknown param type returns false | [N] | P1 |
| 48 | [DESIRED] Offset/length arithmetic overflow returns false (not panic) | [S] | P0 |
| 49 | [DESIRED] Malformed `comparisonData` for typed decodes returns false (not revert) | [S] | P0 |
| 50 | `_isBoolParameterAllowedByConstraint` | `Exact` constraint accepts matching bool and rejects mismatching bool | [U] | P1 |
| 51 | `_isUintParameterAllowedByConstraint` | `Range` is inclusive at both boundaries (`min` and `max`) | [E] | P0 |
| 52 | `_isIntParameterAllowedByConstraint` | Signed negative values are validated correctly for `Exact`/`Range` constraints | [U] | P0 |
| 53 | `_isFixedBytesParameterAllowedByConstraint` | Exact fixed-bytes comparison succeeds only for byte-exact 32-byte match | [U] | P1 |

---

## File 4: `src/organization/libraries/LibOrganizationAccountSignature.sol`

### 4.1 `isValidSignature`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 54 | Empty signature returns ERC-1271 invalid value | [N] | P0 |
| 55 | Unknown signature type byte returns ERC-1271 invalid value | [N] | P0 |
| 56 | Recovery signature type (`0x00`) with valid recovery signer and enabled recovery returns magic value | [U] | P0 |
| 57 | Recovery signature type (`0x00`) while recovery disabled/not configured returns invalid value | [S] | P0 |
| 58 | [DESIRED] Policy signature type (`0x01`) with malformed ABI payload returns invalid value (not revert) | [S] | P0 |
| 59 | Repeated calls with the same valid packed signature are deterministic and stateless (no nonce/rate-limit mutation side effects) | [S] | P0 |

### 4.2 `_validatePolicyBasedSignature`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 60 | Expired signature request returns invalid value | [N] | P0 |
| 61 | Empty initiator signature returns invalid value | [N] | P0 |
| 62 | Invalid initiator signature recovery returns invalid value | [N] | P0 |
| 63 | Missing/malformed guardian signature returns invalid value | [N] | P0 |
| 64 | Policy proof mismatch / source-account proof mismatch returns invalid value | [N] | P0 |
| 65 | Policy `transactionType != Signatures` returns invalid value | [N] | P0 |
| 66 | Unauthorized initiator for policy returns invalid value | [N] | P0 |
| 67 | Auto-approval policy with valid initiator+guardian signatures returns magic value | [U] | P0 |
| 68 | Manual-approval policy requires threshold reviewer signatures; insufficient reviewer signatures or malformed invalid review signatures should should fail | [N] | P0 |
| 69 | Manual-approval reviewer signatures are bound to initiator signature (cannot replay with different initiator signature) | [S] | P0 |
| 70 | [DESIRED] Any downstream approval-validation revert (duplicate/out-of-order/unauthorized reviewer) should map to invalid value, not revert | [S] | P0 |

### 4.3 `_isValidGuardianSignature`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 71 | Direct guardian signature is accepted | [U] | P0 |
| 72 | Enabled module signature is accepted | [I] | P0 |
| 73 | Signature from non-enabled module is rejected | [S] | P0 |
| 74 | Guardian contract reverting on `isModuleEnabled` call is handled as invalid (`false`) | [E] | P0 |
| 75 | Truncated `isModuleEnabled` return data (`< 32 bytes`) is handled as invalid (`false`) | [E] | P0 |
| 76 | [DESIRED] Non-canonical bool return data from `isModuleEnabled` is handled as invalid (`false`), not revert | [S] | P0 |

### 4.4 Recovery/Policy Path Isolation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 77 | Policy signatures (`0x01`) are never accepted through recovery path logic | [S] | P0 |
| 78 | Recovery signatures (`0x00`) are never accepted through policy path logic | [S] | P0 |

### 4.5 Additional Private Helper Coverage

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 79 | `_validateRecoverySignature` | Malformed or unauthorized recovery signatures return ERC-1271 invalid value (never revert) | [S] | P0 |
| 80 | `_isERC1271SignatureAllowedByPolicy` | Returns true only when policy exists, `transactionType == Signatures`, source account is allowed, and initiator is authorized | [S] | P0 |
| 81 | `_isERC1271SignatureAllowedByPolicy` | Returns false when any one policy-allowance precondition fails | [N] | P0 |

---

## File 5: `src/organization/base/OrganizationAccountSignatureBase.sol`

### 5.1 `isValidSignatureForAccount`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 84 | `msg.sender != account` reverts (caller spoofing blocked) | [S] | P0 |
| 85 | `msg.sender == account` but account not deployed by this org reverts `AccountNotDeployedByOrganization` | [S] | P0 |
| 86 | Valid deployed account call delegates to signature library and returns its result | [U] | P1 |

---

## File 6: `src/organization/libraries/LibOrganizationAdmin.sol`

### 6.1 `validateAdminAuthAndConsumeNonceOrRevert`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 87 | Approval and rejection for same operation data/salt share nonce domain; second attempt fails with replay protection | [S] | P0 |
| 88 | Expired admin auth reverts before permanent nonce consumption | [S] | P0 |
| 89 | Admin removed after signatures are collected cannot execute with stale signatures | [S] | P0 |
| 90 | Voting threshold increase after signature collection invalidates previously sufficient signature sets | [S] | P0 |
| 91 | Mixed EOA + ERC-1271 packed admin signatures parse correctly across offsets | [S] | P0 |
| 92 | Malformed packed admin signature stream fails closed | [S] | P0 |

### 6.2 `_areAdminSignaturesValid` and `modifyAdmins`

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 93 | `_areAdminSignaturesValid` | Duplicate or out-of-order signers revert | [N] | P0 |
| 94 | `_areAdminSignaturesValid` | Non-admin signer reverts | [N] | P0 |
| 95 | `_areAdminSignaturesValid` | Exact-threshold valid signatures succeed | [U] | P1 |
| 96 | `modifyAdmins` | Removing the last admin always reverts `InvalidAdminConfig` | [S] | P0 |
| 97 | `modifyAdmins` | Adding a non-member as admin reverts | [N] | P0 |
| 99 | `_getAdminOperationHash` | Hash differs when only `isApproval` flips (approval/rejection domain separation) | [S] | P0 |
| 100 | `_getAdminOperationHash` | Hash changes across organization address / chain ID (cross-org and cross-chain replay defense) | [S] | P0 |

---

## File 7: `src/organization/base/OrganizationAccountTransactionBase.sol`

### 7.1 `executeAccountTransaction` and `rejectAccountTransaction`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 101 | Cross-organization account call reverts `AccountNotDeployedByOrganization` | [S] | P0 |
| 102 | Nonce is consumed before external account call (reentrancy replay defense ordering) | [S] | P0 |
| 103 | Reentrant attempt with same nonce in same transaction fails replay check | [S] | P0 |
| 104 | Failed downstream account execution reverts whole tx: nonce/rate-limit/event side effects are rolled back | [S] | P0 |
| 105 | Execute and reject paths intentionally share nonce domain for identical tx params/salt | [S] | P0 |
| 106 | Execute then reject with same params reverts replay; reject then execute also reverts replay | [S] | P0 |
| 107 | Approval/rejection validation failure (before any external account call) also rolls back prior nonce consumption | [S] | P0 |
| 108 | Validation revert on execute path cannot leave partial rate-limit updates in storage | [S] | P0 |

---

## File 8: `src/account/AccountImplementation.sol`

### 8.1 `executeTransaction`, `receive`, `isValidSignature`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 109 | Non-organization caller to `executeTransaction` reverts `OnlyOrganization` | [N] | P0 |
| 110 | Organization caller + successful downstream call emits `TransactionExecuted` with exact forwarded `to/value/data/nonce/policyId` | [U][EV] | P0 |
| 111 | Low-level call returning `false` causes `TransactionExecutionFailed` revert | [N] | P0 |
| 112 | Reverting callee also surfaces as `TransactionExecutionFailed` (revert data not bubbled) | [E] | P0 |
| 113 | Insufficient-gas call path fails with `TransactionExecutionFailed` | [S] | P0 |
| 114 | `receive()` emits `MLSWalletAccountNativeTokenReceived(sender, value)` with exact caller/value | [U][EV] | P1 |
| 115 | `receive()` cannot be used to bypass `onlyOrganization` and re-enter privileged execution | [S] | P0 |
| 116 | `isValidSignature` always forwards `address(this)` as account to Organization signature validation | [U] | P0 |
| 117 | `isValidSignature` returns exactly the value produced by Organization validation (magic/invalid passthrough) | [U] | P1 |
| 118 | [DESIRED] Executing a call that attempts account self-destruction does not destroy the account | [S] | P1 |

### 8.2 Private Helpers

| # | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| 119 | `_execute` | Successful low-level call returns `true` and forwards exact calldata/value/gas budget | [U] | P1 |
| 120 | `_execute` | Reverting/failing callee returns `false` and does not bubble revert data | [E] | P0 |
| 121 | `_onlyOrganization` | Reverts `OnlyOrganization` when caller is not stored Organization address | [N] | P0 |
| 122 | `_onlyOrganization` | Succeeds when caller equals stored Organization address | [U] | P1 |

---

## File 9: `src/organization/OrganizationImplementation.sol`

### 9.1 `upgradeToAndCallWithAuthorization` and `_authorizeUpgrade`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 123 | Direct call to inherited `upgradeToAndCall` (without wrapper flow) reverts `UnauthorizedUpgrade` | [S] | P0 |
| 124 | Failed upgrade/migration path does not leave authorization flag stuck true | [S] | P0 |
| 125 | Whitelist validation failure occurs before auth flag is set | [S] | P0 |
| 126 | `_authorizeUpgrade` is flag-gated and does not re-validate `newImplementation` parameter | [U] | P1 |
| 127 | [DESIRED] Admin authorization must bind migration `data` payload (not only `newImplementation`) | [S] | P0 |
| 128 | [DESIRED] Migration `data` cannot trigger nested second upgrade to bypass whitelist/admin checks | [S] | P0 |

---

## File 10: `src/organization/OrganizationFactory.sol`

### 10.1 `constructor`, `deployOrganization`, `computeOrganizationAddress`, `_getOrganizationProxyBytecode`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 129 | Constructor rejects zero `DEPLOYER_ADDRESS` | [N] | P0 |
| 130 | `deployOrganization` is callable only by `DEPLOYER_ADDRESS` | [S] | P0 |
| 131 | Same salt + same init bytecode cannot be deployed twice | [N] | P1 |
| 132 | Initialization failure reverts atomically (no uninitialized organization left deployed) | [S] | P0 |
| 133 | `computeOrganizationAddress` changes when `whitelistAddress` changes | [U] | P1 |
| 134 | `DEPLOYER_ADDRESS` remains immutable after deployment | [S] | P1 |
| 135 | [DESIRED] Deployment fails closed if `whitelistAddress` has no code (EOA/zero) | [S] | P0 |
| 136 | [DESIRED] Deployment fails closed if `implementationAddress` has no code, even if whitelist contract is permissive | [S] | P0 |
| 137 | `_getOrganizationProxyBytecode` is deterministic and argument-sensitive (harness) | [U] | P1 |

---

## File 11: `src/organization/common/OrganizationModifiers.sol`

All modifiers delegate to library `enforce*` functions that perform a single `msg.sender != storedAddress` check and revert with a typed error.
None of the enforce functions contain special-case handling for `address(0)`, so zero-address fail-closed behavior must be tested explicitly.

**Testing approach:** All tests in this section must exercise the **modifier itself** (by calling a function that uses the modifier) rather than calling the underlying `enforce*` library function directly. This ensures the modifier wiring, the `_;` continuation, and the full call-site integration are covered — not just the library logic in isolation.

### 11.1 `onlyGuardian` — `LibOrganizationGuardian.enforceOnlyGuardian()`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 138 | Authorized guardian caller passes through the modifier | [U] | P0 |
| 139 | Non-guardian caller reverts `UnauthorizedGuardian(caller, guardian)` | [N] | P0 |
| 140 | After guardian transfer (propose + accept), previous guardian is rejected | [S] | P0 |
| 141 | Pending guardian (proposed but not yet accepted) is rejected by `onlyGuardian` | [S] | P0 |
| 142 | Revert error encodes actual `msg.sender` as first parameter and stored `guardian` as second parameter | [U] | P1 |

### 11.2 `onlyDeployer` — `LibOrganizationInitialization.enforceOnlyDeployer()`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 143 | Authorized deployer caller passes through the modifier | [U] | P0 |
| 144 | Non-deployer caller reverts `UnauthorizedDeployer()` | [N] | P0 |
| 145 | `UnauthorizedDeployer()` error carries no parameters (does not leak stored deployer address) | [U] | P1 |

### 11.3 `onlyTxRecoveryAddress` — `LibOrganizationTxRecovery.enforceOnlyTxRecoveryAddress()`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 146 | Authorized tx-recovery address passes through the modifier | [U] | P0 |
| 147 | Non-recovery caller reverts `UnauthorizedTxRecoveryAddress(caller, expected)` | [N] | P0 |
| 149 | Revert error encodes actual `msg.sender` and stored `txRecovery.recoveryAddress` | [U] | P1 |

### 11.4 `onlyGuardianRecoveryAddress` — `LibOrganizationGuardianRecovery.enforceOnlyGuardianRecoveryAddress()`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 150 | Authorized guardian-recovery address passes through the modifier | [U] | P0 |
| 151 | Non-recovery caller reverts `UnauthorizedGuardianRecoveryAddress(caller, expected)` | [N] | P0 |
| 153 | Revert error encodes actual `msg.sender` and stored `guardianRecovery.recoveryAddress` | [U] | P1 |

### 11.5 `onlyPendingGuardian` — `LibOrganizationGuardian.enforceOnlyPendingGuardian()`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 154 | Designated pending guardian passes when a guardian update is pending | [U] | P0 |
| 155 | Non-pending caller reverts `UnauthorizedGuardianAcceptance(caller, pendingGuardian)` | [N] | P0 |
| 156 | When no guardian update is pending (`pendingGuardian == address(0)`), all callers are rejected | [S] | P0 |
| 157 | After pending guardian accepts and pending state is cleared, previous pending address is rejected | [S] | P0 |
| 158 | Current guardian is rejected by `onlyPendingGuardian` (guardian ≠ pending guardian) | [S] | P0 |

### 11.6 `onlyRecoveryPendingGuardian` — `LibOrganizationGuardianRecovery.enforceOnlyRecoveryPendingGuardian()`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 159 | Designated recovery pending guardian passes when a recovery guardian update is pending | [U] | P0 |
| 160 | Non-pending caller reverts `UnauthorizedRecoveryGuardianAcceptance(caller, pendingGuardian)` | [N] | P0 |
| 161 | When no recovery update is pending (`pendingGuardian == address(0)`), all callers are rejected | [S] | P0 |
| 162 | After recovery pending guardian accepts and state is cleared, previous pending address is rejected | [S] | P0 |
| 163 | Guardian-recovery address itself is rejected by `onlyRecoveryPendingGuardian` (recoveryAddress ≠ pendingGuardian) | [S] | P0 |

### 11.7 Cross-Role Isolation Matrix

Each role holder must be rejected by every modifier it does not hold.

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 164 | `onlyGuardian` rejects tx-recovery, guardian-recovery, deployer, pending guardian, and recovery pending guardian addresses | [S] | P0 |
| 165 | `onlyDeployer` rejects guardian, tx-recovery, guardian-recovery, pending guardian, and recovery pending guardian addresses | [S] | P0 |
| 166 | `onlyTxRecoveryAddress` rejects guardian, guardian-recovery, deployer, pending guardian, and recovery pending guardian addresses | [S] | P0 |
| 167 | `onlyGuardianRecoveryAddress` rejects guardian, tx-recovery, deployer, pending guardian, and recovery pending guardian addresses | [S] | P0 |
| 168 | `onlyPendingGuardian` rejects guardian-recovery, tx-recovery, deployer, and recovery pending guardian addresses | [S] | P0 |
| 169 | `onlyRecoveryPendingGuardian` rejects guardian, tx-recovery, deployer, and normal pending guardian addresses | [S] | P0 |
| 170 | Same address intentionally assigned to two distinct roles (e.g., guardian and tx-recovery) passes both corresponding modifiers but no others | [E] | P1 |

### 11.8 Zero-Address / Uninitialized Fail-Closed

No enforce function special-cases `address(0)`. These tests verify that when a role is uninitialized or unconfigured, the modifier still rejects every caller rather than silently passing.
Each test sets the stored role address to `address(0)` and calls the guarded function from one or more non-zero addresses, confirming they all revert. (`msg.sender == address(0)` is not a realistic scenario and is not tested.)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 171 | `onlyGuardian` reverts for non-zero callers when `guardian` storage slot is `address(0)` (pre-initialization state) | [S] | P0 |
| 172 | `onlyDeployer` reverts for non-zero callers when `deployerAddress` storage slot is `address(0)` | [S] | P0 |
| 173 | `onlyTxRecoveryAddress` reverts for non-zero callers when `txRecovery.recoveryAddress` is `address(0)` (unconfigured); error includes `expected = address(0)` | [S] | P0 |
| 174 | `onlyGuardianRecoveryAddress` reverts for non-zero callers when `guardianRecovery.recoveryAddress` is `address(0)` (unconfigured); error includes `expected = address(0)` | [S] | P0 |

### 11.9 State Transition Atomicity

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 175 | Guardian transfer (propose + accept): after acceptance, only the new guardian passes `onlyGuardian`; old guardian cannot pass at any point after acceptance in the same transaction | [S] | P0 |
| 176 | Pending guardian full lifecycle: propose → pending address passes `onlyPendingGuardian` → accept → pending slot cleared → pending address no longer passes | [I] | P0 |
| 177 | Recovery pending guardian full lifecycle: initiate → pending address passes `onlyRecoveryPendingGuardian` → accept → pending slot cleared → pending address no longer passes | [I] | P0 |

### 11.10 Access-Control Fuzz Tests

| # | Test Case | Runs | Type | Priority |
|---|-----------|------|------|----------|
| 178 | [AUDIT-FUZZ] Random `msg.sender` against each of the 6 modifiers always reverts unless caller exactly equals stored role address | 10000 | [F] | P0 |
| 179 | [AUDIT-FUZZ] Random role address written to storage followed by random callers: only exact address match passes, all others revert with correct typed error | 10000 | [F] | P0 |

### 11.11 Access-Control Invariant Tests

| # | Invariant | Type | Priority |
|---|-----------|------|----------|
| 180 | **Single-holder exclusivity:** at most one address can pass each access-control modifier at any given storage state (zero addresses pass when role is unset) | [INV] | P0 |
| 181 | **Cross-role exclusion:** after any sequence of role mutations, no address can pass a modifier for a role it does not currently hold | [INV] | P0 |

---

## 12. Additional Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 182 | **Cross-org signature isolation:** signatures valid for one Organization are never valid for another | P0 |
| 183 | **Recovery isolation:** tx-recovery operations do not mutate guardian-recovery state, and vice versa | P0 |
| 184 | **Nonce monotonicity:** once a nonce is consumed, it is never reusable | P0 |
| 185 | **Rate-limit atomicity:** reverted outer transaction cannot leave partial usage updates | P0 |
| 186 | **Account beacon binding:** an Account’s Organization/beacon address is immutable post-deployment | P0 |
| 187 | **ERC-1271 statelessness:** account signature validation never consumes nonces or mutates policy usage state | P0 |

---

## 13. Additional Fuzz Tests

| # | Test Case | Runs | Priority |
|---|-----------|------|----------|
| 188 | [AUDIT-FUZZ] Random parameter constraints (offset/head/length permutations) never panic and terminate safely | 10000 | P0 |
| 189 | [AUDIT-FUZZ] Random malformed policy-signature payloads (`0x01`) return invalid (no revert) | 10000 | P0 |
| 190 | [AUDIT-FUZZ] Random guardian module behaviors (EOA/contract/revert/truncated return data) never cause signature-validation revert | 5000 | P0 |
| 191 | [AUDIT-FUZZ] Random mixed admin signature streams preserve strict ordering and threshold rules | 5000 | P0 |
| 192 | [AUDIT-FUZZ] Random rate-limit scope configs produce expected key sharing/isolation | 10000 | P0 |
| 193 | [AUDIT-FUZZ] Random execute/reject ordering preserves shared nonce replay protection | 5000 | P0 |
| 194 | [AUDIT-FUZZ] [DESIRED] Random upgrade migration calldata cannot bypass wrapper whitelist/admin checks via nested upgrade | 2000 | P0 |

---

## Summary

| Category | Tests | Priority |
|----------|-------|----------|
| File/function scoped security gap cases | 177 | P0-P1 |
| Invariants | 8 | P0 |
| Fuzz tests | 9 | P0 |
| **Total** | **194** | |
