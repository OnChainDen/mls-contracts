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

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAT-AVTAOR-1 | Expired transaction (`block.timestamp > expirationTimestamp`) reverts `TransactionExpired` | [N] | P0 |
| LOAT-AVTAOR-2 | `expirationTimestamp == block.timestamp` is accepted (strict `>` expiration check) | [E] | P1 |
| LOAT-AVTAOR-3 | Empty `initiatorSignature` reverts `InsufficientSignaturesLength` | [N] | P0 |
| LOAT-AVTAOR-4 | Malformed initiator signature bytes revert (fail-closed signer recovery) | [S] | P0 |
| LOAT-AVTAOR-5 | Policy mismatch (proof/config/tx mismatch) reverts `PolicyDoesNotApply` | [N] | P0 |
| LOAT-AVTAOR-6 | Manual-approval path binds reviewer approvals to `initiatorSignature` hash; tampering initiator sig invalidates collected reviews | [S] | P0 |
| LOAT-AVTAOR-7 | Two different valid initiator signatures for same tx params produce different reviewer hashes (non-transferability) | [S] | P0 |
| LOAT-AVTAOR-8 | Auto-approval policy succeeds without reviewer signatures but still enforces initiator authorization | [U] | P0 |
| LOAT-AVTAOR-9 | Manual-approval policy with insufficient reviewer signatures reverts `InsufficientApprovals` | [N] | P0 |
| LOAT-AVTAOR-10 | Rate-limit update runs only after policy/signature checks pass | [S] | P0 |

### 1.2 `validateTransactionRejectionOrRevert`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAT-AVTROR-1 | Rejection on expired transaction reverts `TransactionExpired` | [N] | P0 |
| LOAT-AVTROR-2 | Auto-approval rejection requires rejection hash (`isApproval=false`) signed by authorized initiator | [S] | P0 |
| LOAT-AVTROR-3 | Approval signature replayed as rejection signature fails (hash domain separation) | [S] | P0 |
| LOAT-AVTROR-4 | Manual rejection uses `isApproval=false` in review hash; approval review signatures are not reusable for rejection | [S] | P0 |
| LOAT-AVTROR-5 | Rejection validation is read-only (no rate-limit mutation on rejection path) | [U] | P1 |

### 1.3 Private Helpers

| ID | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| LOAT-AHELP-1 | `_validateAndUpdateRateLimitOrRevert` | Token transfer usage uses extracted transfer amount, not fixed count | [U] | P0 |
| LOAT-AHELP-2 | `_validateAndUpdateRateLimitOrRevert` | Contract interaction usage counts as `1` regardless ETH value | [U] | P0 |
| LOAT-AHELP-3 | `_validateAndUpdateRateLimitOrRevert` | ERC-20 destination tracking uses transfer recipient from calldata (not token contract address) | [S] | P0 |
| LOAT-AHELP-4 | `_validateAndUpdateRateLimitOrRevert` | If `checkAndUpdateRateLimit` returns false, revert `RateLimitExceeded(policyId)` | [N] | P0 |
| LOAT-AHELP-5 | `_validateAutoApproveRejectionOrRevert` | Empty rejection signature bytes revert `TransactionRejectionNotAllowed` | [N] | P0 |
| LOAT-AHELP-6 | `_validateManualConfirmationOrRevert` | `reviewHash` includes `keccak256(initiatorSignature)` (binding property) | [S] | P0 |
| LOAT-AHELP-7 | `_computeInitiatorHashFromParams` | Hash changes across organization address / chain ID (cross-org and cross-chain replay defense) | [S] | P0 |
| LOAT-AHELP-8 | `_computeReviewHashFromParams` | Changing only `initiatorSignature` changes review hash | [S] | P0 |

---

## File 2: `src/organization/libraries/policy/LibPolicyRateLimits.sol`

### 2.1 `checkAndUpdateRateLimit`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LPRL-ACAURL-1 | `RateLimitType.None` returns true and does not update usage storage | [U] | P0 |
| LPRL-ACAURL-2 | `currentUsage + usageAmount == timeIntervalLimit` succeeds (inclusive limit boundary) | [E] | P0 |
| LPRL-ACAURL-3 | `currentUsage + usageAmount > timeIntervalLimit` returns false and leaves usage unchanged | [N] | P0 |
| LPRL-ACAURL-4 | `usageAmount = 0` does not increase stored usage | [E] | P1 |
| LPRL-ACAURL-5 | Crossing into a new time window reads/writes a fresh usage bucket (window reset behavior) | [U] | P0 |
| LPRL-ACAURL-6 | [DESIRED] `TimeInterval` config with `timeIntervalHours = 0` returns false and does not write usage instead of bypassing rate limiting | [S] | P0 |
| LPRL-ACAURL-7 | [DESIRED] Arithmetic overflow in `currentUsage + usageAmount` is handled gracefully (no panic) | [S] | P0 |

### 2.2 `computeTimeWindow`, `computeUsageKey`, `getCurrentUsage`

| ID | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| LPRL-AHELP-1 | `computeTimeWindow` | Deterministic output for same timestamp/policy | [U] | P1 |
| LPRL-AHELP-2 | `computeTimeWindow` | `timeIntervalHours = 0` returns `0` | [E] | P1 |
| LPRL-AHELP-3 | `computeUsageKey` | `AcrossAll` scope normalizes to `address(0)` for that dimension | [U] | P0 |
| LPRL-AHELP-4 | `computeUsageKey` | `PerEntity` scope isolates by concrete account/destination/initiator | [U] | P0 |
| LPRL-AHELP-5 | `getCurrentUsage` | Returns `0` when rate limit is disabled / not time-interval | [U] | P1 |

---

## File 3: `src/organization/libraries/policy/LibPolicyParameterConstraints.sol`

### 3.1 `areParametersAllowedByConstraints` and `_processConstraints`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LPPC-APROC-1 | Empty `parameterConstraints` bytes returns true | [E] | P1 |
| LPPC-APROC-2 | Decoded empty constraints array returns true | [E] | P1 |
| LPPC-APROC-3 | `paramCalldataHeadSlotCount = 0` returns false | [N] | P0 |
| LPPC-APROC-4 | Declared head slots exceeding calldata length returns false | [N] | P0 |
| LPPC-APROC-5 | Multi-slot parameter (`paramCalldataHeadSlotCount > 1`) advances offset correctly | [U] | P0 |
| LPPC-APROC-6 | Constraint referencing out-of-bounds calldata position returns false | [N] | P0 |
| LPPC-APROC-7 | Malformed ABI-encoded constraints payload reverts | [S] | P0 |

### 3.2 Type-Specific Constraint Helpers

| ID | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| LPPC-ATYPE-1 | `_isAddressParameterAllowedByConstraint` | `OneOf` with empty merkle proof returns false | [N] | P0 |
| LPPC-ATYPE-2 | `_isBytesOrStringParameterAllowedByConstraint` | Dynamic length exceeding calldata returns false | [N] | P0 |
| LPPC-ATYPE-3 | `_isBytesOrStringParameterAllowedByConstraint` | Exact hash match for bytes/string succeeds | [U] | P1 |
| LPPC-ATYPE-4 | `_isParameterAllowedByConstraint` | `Array`/`Struct` with non-`Any` constraint returns false | [N] | P0 |
| LPPC-ATYPE-5 | `_isParameterAllowedByConstraint` | Unsupported/unknown param type reverts | [N] | P1 |
| LPPC-ATYPE-6 | [DESIRED] Offset/length arithmetic overflow returns false (not panic) | [S] | P0 |
| LPPC-ATYPE-7 | [DESIRED] Malformed `comparisonData` for typed decodes returns false (not revert) | [S] | P0 |
| LPPC-ATYPE-8 | `_isBoolParameterAllowedByConstraint` | `Exact` constraint accepts matching bool and rejects mismatching bool | [U] | P1 |
| LPPC-ATYPE-9 | `_isUintParameterAllowedByConstraint` | `Range` is inclusive at both boundaries (`min` and `max`) | [E] | P0 |
| LPPC-ATYPE-10 | `_isIntParameterAllowedByConstraint` | Signed negative values are validated correctly for `Exact`/`Range` constraints | [U] | P0 |
| LPPC-ATYPE-11 | `_isFixedBytesParameterAllowedByConstraint` | Exact fixed-bytes comparison succeeds only for byte-exact 32-byte match | [U] | P1 |

---

## File 4: `src/organization/libraries/LibOrganizationAccountSignature.sol`

### 4.1 `isValidSignature`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAS-AIVS-1 | Empty signature returns ERC-1271 invalid value | [N] | P0 |
| LOAS-AIVS-2 | Unknown signature type byte returns ERC-1271 invalid value | [N] | P0 |
| LOAS-AIVS-3 | Recovery signature type (`0x00`) with valid recovery signer and enabled recovery returns magic value | [U] | P0 |
| LOAS-AIVS-4 | Recovery signature type (`0x00`) while recovery disabled/not configured returns invalid value | [S] | P0 |
| LOAS-AIVS-6 | Repeated calls with the same valid packed signature are deterministic and stateless (no nonce/rate-limit mutation side effects) | [S] | P0 |

### 4.2 `_validatePolicyBasedSignature`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAS-AVPBS-1 | Expired signature request returns invalid value | [N] | P0 |
| LOAS-AVPBS-2 | Empty initiator signature returns invalid value | [N] | P0 |
| LOAS-AVPBS-3 | Invalid initiator signature recovery returns invalid value | [N] | P0 |
| LOAS-AVPBS-4 | Missing/malformed guardian signature returns invalid value | [N] | P0 |
| LOAS-AVPBS-5 | Policy proof mismatch / source-account proof mismatch returns invalid value | [N] | P0 |
| LOAS-AVPBS-6 | Policy `transactionType != Signatures` returns invalid value | [N] | P0 |
| LOAS-AVPBS-7 | Unauthorized initiator for policy returns invalid value | [N] | P0 |
| LOAS-AVPBS-8 | Auto-approval policy with valid initiator+guardian signatures returns magic value | [U] | P0 |
| LOAS-AVPBS-9 | Manual-approval policy requires threshold reviewer signatures; insufficient reviewer signatures or malformed invalid review signatures should should fail | [N] | P0 |
| LOAS-AVPBS-10 | Manual-approval reviewer signatures are bound to initiator signature (cannot replay with different initiator signature) | [S] | P0 |
| LOAS-AVPBS-11 | [DESIRED] Any downstream approval-validation revert (duplicate/out-of-order/unauthorized reviewer) should map to invalid value, not revert | [S] | P0 |

### 4.3 `_isValidGuardianSignature`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAS-AIVGS-1 | Direct guardian signature is accepted | [U] | P0 |
| LOAS-AIVGS-2 | Enabled module signature is accepted | [I] | P0 |
| LOAS-AIVGS-3 | Signature from non-enabled module is rejected | [S] | P0 |
| LOAS-AIVGS-4 | Guardian contract reverting on `isModuleEnabled` call is handled as invalid (`false`) | [E] | P0 |
| LOAS-AIVGS-5 | Truncated `isModuleEnabled` return data (`< 32 bytes`) is handled as invalid (`false`) | [E] | P0 |
| LOAS-AIVGS-6 | Non-canonical bool return data from `isModuleEnabled` reverts during decode | [S] | P0 |

### 4.4 Recovery/Policy Path Isolation

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAS-AISO-1 | Policy signatures (`0x01`) are never accepted through recovery path logic | [S] | P0 |
| LOAS-AISO-2 | Recovery signatures (`0x00`) are never accepted through policy path logic | [S] | P0 |

### 4.5 Additional Private Helper Coverage

| ID | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| LOAS-AHELP-1 | `_validateRecoverySignature` | Malformed or unauthorized recovery signatures return ERC-1271 invalid value (never revert) | [S] | P0 |
| LOAS-AHELP-2 | `_isERC1271SignatureAllowedByPolicy` | Returns true only when policy exists, `transactionType == Signatures`, source account is allowed, and initiator is authorized | [S] | P0 |
| LOAS-AHELP-3 | `_isERC1271SignatureAllowedByPolicy` | Returns false when any one policy-allowance precondition fails | [N] | P0 |

---

## File 5: `src/organization/base/OrganizationAccountSignatureBase.sol`

### 5.1 `isValidSignatureForAccount`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OASB-AISFA-1 | `msg.sender != account` reverts (caller spoofing blocked) | [S] | P0 |
| OASB-AISFA-2 | `msg.sender == account` but account not deployed by this org reverts `AccountNotDeployedByOrganization` | [S] | P0 |
| OASB-AISFA-3 | Valid deployed account call delegates to signature library and returns its result | [U] | P1 |

---

## File 6: `src/organization/libraries/LibOrganizationAdmin.sol`

### 6.1 `validateAdminAuthAndConsumeNonceOrRevert`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOA-AAUTH-1 | Approval and rejection for same operation data/salt share nonce domain; second attempt fails with replay protection | [S] | P0 |
| LOA-AAUTH-2 | Expired admin auth reverts before permanent nonce consumption | [S] | P0 |
| LOA-AAUTH-3 | Admin removed after signatures are collected cannot execute with stale signatures | [S] | P0 |
| LOA-AAUTH-4 | Voting threshold increase after signature collection invalidates previously sufficient signature sets | [S] | P0 |
| LOA-AAUTH-5 | Mixed EOA + ERC-1271 packed admin signatures parse correctly across offsets | [S] | P0 |
| LOA-AAUTH-6 | Malformed packed admin signature stream fails closed | [S] | P0 |

### 6.2 `_areAdminSignaturesValid` and `modifyAdmins`

| ID | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| LOA-AADMIN-1 | `_areAdminSignaturesValid` | Duplicate or out-of-order signers revert | [N] | P0 |
| LOA-AADMIN-2 | `_areAdminSignaturesValid` | Non-admin signer reverts | [N] | P0 |
| LOA-AADMIN-3 | `_areAdminSignaturesValid` | Exact-threshold valid signatures succeed | [U] | P1 |
| LOA-AADMIN-4 | `modifyAdmins` | Removing the last admin always reverts `InvalidAdminConfig` | [S] | P0 |
| LOA-AADMIN-5 | `modifyAdmins` | Adding a non-member as admin reverts | [N] | P0 |
| LOA-AADMIN-6 | `_getAdminOperationHash` | Hash differs when only `isApproval` flips (approval/rejection domain separation) | [S] | P0 |
| LOA-AADMIN-7 | `_getAdminOperationHash` | Hash changes across organization address / chain ID (cross-org and cross-chain replay defense) | [S] | P0 |

---

## File 7: `src/organization/base/OrganizationAccountTransactionBase.sol`

### 7.1 `executeAccountTransaction` and `rejectAccountTransaction`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OATB-AXACT-1 | Cross-organization account call reverts `AccountNotDeployedByOrganization` | [S] | P0 |
| OATB-AXACT-2 | Nonce is consumed before external account call (reentrancy replay defense ordering) | [S] | P0 |
| OATB-AXACT-3 | Reentrant attempt with same nonce in same transaction fails replay check | [S] | P0 |
| OATB-AXACT-4 | Failed downstream account execution reverts whole tx: nonce/rate-limit/event side effects are rolled back | [S] | P0 |
| OATB-AXACT-5 | Execute and reject paths intentionally share nonce domain for identical tx params/salt | [S] | P0 |
| OATB-AXACT-6 | Execute then reject with same params reverts replay; reject then execute also reverts replay | [S] | P0 |
| OATB-AXACT-7 | Approval/rejection validation failure (before any external account call) also rolls back prior nonce consumption | [S] | P0 |
| OATB-AXACT-8 | Validation revert on execute path cannot leave partial rate-limit updates in storage | [S] | P0 |

---

## File 8: `src/account/AccountImplementation.sol`

### 8.1 `executeTransaction`, `receive`, `isValidSignature`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| AI-AENT-1 | Non-organization caller to `executeTransaction` reverts `OnlyOrganization` | [N] | P0 |
| AI-AENT-2 | Organization caller + successful downstream call emits `TransactionExecuted` with exact forwarded `to/value/data/nonce/policyId` | [U][EV] | P0 |
| AI-AENT-3 | Low-level call returning `false` causes `TransactionExecutionFailed` revert | [N] | P0 |
| AI-AENT-4 | Reverting callee also surfaces as `TransactionExecutionFailed` (revert data not bubbled) | [E] | P0 |
| AI-AENT-6 | `receive()` emits `MLSWalletAccountNativeTokenReceived(sender, value)` with exact caller/value | [U][EV] | P1 |
| AI-AENT-7 | `receive()` cannot be used to bypass `onlyOrganization` and re-enter privileged execution | [S] | P0 |
| AI-AENT-8 | `isValidSignature` always forwards `address(this)` as account to Organization signature validation | [U] | P0 |
| AI-AENT-9 | `isValidSignature` returns exactly the value produced by Organization validation (magic/invalid passthrough) | [U] | P1 |

### 8.2 Private Helpers

| ID | Function | Test Case | Type | Priority |
|---|----------|-----------|------|----------|
| AI-AHELP-1 | `_execute` | Successful low-level call returns `true` and forwards exact calldata/value/gas budget | [U] | P1 |
| AI-AHELP-2 | `_execute` | Reverting/failing callee returns `false` and does not bubble revert data | [E] | P0 |
| AI-AHELP-3 | `_onlyOrganization` | Reverts `OnlyOrganization` when caller is not stored Organization address | [N] | P0 |
| AI-AHELP-4 | `_onlyOrganization` | Succeeds when caller equals stored Organization address | [U] | P1 |

---

## File 9: `src/organization/OrganizationImplementation.sol`

### 9.1 `upgradeToAndCallWithAuthorization` and `_authorizeUpgrade`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OI-AUPG-1 | Direct call to inherited `upgradeToAndCall` (without wrapper flow) reverts `UnauthorizedUpgrade` | [S] | P0 |
| OI-AUPG-2 | Failed upgrade/migration path does not leave authorization flag stuck true | [S] | P0 |
| OI-AUPG-3 | Whitelist validation failure occurs before auth flag is set | [S] | P0 |
| OI-AUPG-5 | [DESIRED] Admin authorization must bind migration `data` payload (not only `newImplementation`) | [S] | P0 |
| OI-AUPG-6 | [DESIRED] Migration `data` cannot trigger nested second upgrade to bypass whitelist/admin checks | [S] | P0 |

---

## File 10: `src/organization/OrganizationFactory.sol`

### 10.1 `constructor`, `deployOrganization`, `computeOrganizationAddress`, `_getOrganizationProxyBytecode`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OF-ADEP-1 | Constructor rejects zero `DEPLOYER_ADDRESS` | [N] | P0 |
| OF-ADEP-2 | `deployOrganization` is callable only by `DEPLOYER_ADDRESS` | [S] | P0 |
| OF-ADEP-3 | Same salt + same init bytecode cannot be deployed twice | [N] | P1 |
| OF-ADEP-4 | Initialization failure reverts atomically (no uninitialized organization left deployed) | [S] | P0 |
| OF-ADEP-5 | `computeOrganizationAddress` changes when `whitelistAddress` changes | [U] | P1 |
| OF-ADEP-6 | `DEPLOYER_ADDRESS` remains immutable after deployment | [S] | P1 |
| OF-ADEP-7 | [DESIRED] Deployment fails closed if `whitelistAddress` has no code (EOA/zero) | [S] | P0 |
| OF-ADEP-8 | [DESIRED] Deployment fails closed if `implementationAddress` has no code, even if whitelist contract is permissive | [S] | P0 |
| OF-ADEP-9 | `_getOrganizationProxyBytecode` is deterministic and argument-sensitive (harness) | [U] | P1 |

---

## File 11: `src/organization/common/OrganizationModifiers.sol`

All modifiers delegate to library `enforce*` functions that perform a single `msg.sender != storedAddress` check and revert with a typed error.
None of the enforce functions contain special-case handling for `address(0)`, so zero-address fail-closed behavior must be tested explicitly.

**Testing approach:** All tests in this section must exercise the **modifier itself** (by calling a function that uses the modifier) rather than calling the underlying `enforce*` library function directly. This ensures the modifier wiring, the `_;` continuation, and the full call-site integration are covered — not just the library logic in isolation.

### 11.1 `onlyGuardian` — `LibOrganizationGuardian.enforceOnlyGuardian()`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OMOD-AGUARD-1 | Authorized guardian caller passes through the modifier | [U] | P0 |
| OMOD-AGUARD-2 | Non-guardian caller reverts `UnauthorizedGuardian(caller, guardian)` | [N] | P0 |
| OMOD-AGUARD-3 | After guardian transfer (propose + accept), previous guardian is rejected | [S] | P0 |
| OMOD-AGUARD-4 | Pending guardian (proposed but not yet accepted) is rejected by `onlyGuardian` | [S] | P0 |
| OMOD-AGUARD-5 | Revert error encodes actual `msg.sender` as first parameter and stored `guardian` as second parameter | [U] | P1 |

### 11.2 `onlyDeployer` — `LibOrganizationInitialization.enforceOnlyDeployer()`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OMOD-ADEP-1 | Authorized deployer caller passes through the modifier | [U] | P0 |
| OMOD-ADEP-2 | Non-deployer caller reverts `UnauthorizedDeployer()` | [N] | P0 |
| OMOD-ADEP-3 | `UnauthorizedDeployer()` error carries no parameters (does not leak stored deployer address) | [U] | P1 |

### 11.3 `onlyTxRecoveryAddress` — `LibOrganizationTxRecovery.enforceOnlyTxRecoveryAddress()`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OMOD-ATXREC-1 | Authorized tx-recovery address passes through the modifier | [U] | P0 |
| OMOD-ATXREC-2 | Non-recovery caller reverts `UnauthorizedTxRecoveryAddress(caller, expected)` | [N] | P0 |
| OMOD-ATXREC-3 | Revert error encodes actual `msg.sender` and stored `txRecovery.recoveryAddress` | [U] | P1 |

### 11.4 `onlyGuardianRecoveryAddress` — `LibOrganizationGuardianRecovery.enforceOnlyGuardianRecoveryAddress()`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OMOD-AGREC-1 | Authorized guardian-recovery address passes through the modifier | [U] | P0 |
| OMOD-AGREC-2 | Non-recovery caller reverts `UnauthorizedGuardianRecoveryAddress(caller, expected)` | [N] | P0 |
| OMOD-AGREC-3 | Revert error encodes actual `msg.sender` and stored `guardianRecovery.recoveryAddress` | [U] | P1 |

### 11.5 `onlyPendingGuardian` — `LibOrganizationGuardian.enforceOnlyPendingGuardian()`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OMOD-APENDG-1 | Designated pending guardian passes when a guardian update is pending | [U] | P0 |
| OMOD-APENDG-2 | Non-pending caller reverts `UnauthorizedGuardianAcceptance(caller, pendingGuardian)` | [N] | P0 |
| OMOD-APENDG-3 | When no guardian update is pending (`pendingGuardian == address(0)`), all callers are rejected | [S] | P0 |
| OMOD-APENDG-4 | After pending guardian accepts and pending state is cleared, previous pending address is rejected | [S] | P0 |
| OMOD-APENDG-5 | Current guardian is rejected by `onlyPendingGuardian` (guardian ≠ pending guardian) | [S] | P0 |

### 11.6 `onlyRecoveryPendingGuardian` — `LibOrganizationGuardianRecovery.enforceOnlyRecoveryPendingGuardian()`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OMOD-ARPENDG-1 | Designated recovery pending guardian passes when a recovery guardian update is pending | [U] | P0 |
| OMOD-ARPENDG-2 | Non-pending caller reverts `UnauthorizedRecoveryGuardianAcceptance(caller, pendingGuardian)` | [N] | P0 |
| OMOD-ARPENDG-3 | When no recovery update is pending (`pendingGuardian == address(0)`), all callers are rejected | [S] | P0 |
| OMOD-ARPENDG-4 | After recovery pending guardian accepts and state is cleared, previous pending address is rejected | [S] | P0 |
| OMOD-ARPENDG-5 | Guardian-recovery address itself is rejected by `onlyRecoveryPendingGuardian` (recoveryAddress ≠ pendingGuardian) | [S] | P0 |

### 11.7 Cross-Role Isolation Matrix

Each role holder must be rejected by every modifier it does not hold.

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OMOD-AROLE-1 | `onlyGuardian` rejects tx-recovery, guardian-recovery, deployer, pending guardian, and recovery pending guardian addresses | [S] | P0 |
| OMOD-AROLE-2 | `onlyDeployer` rejects guardian, tx-recovery, guardian-recovery, pending guardian, and recovery pending guardian addresses | [S] | P0 |
| OMOD-AROLE-3 | `onlyTxRecoveryAddress` rejects guardian, guardian-recovery, deployer, pending guardian, and recovery pending guardian addresses | [S] | P0 |
| OMOD-AROLE-4 | `onlyGuardianRecoveryAddress` rejects guardian, tx-recovery, deployer, pending guardian, and recovery pending guardian addresses | [S] | P0 |
| OMOD-AROLE-5 | `onlyPendingGuardian` rejects current guardian, guardian-recovery, tx-recovery, deployer, and recovery pending guardian addresses | [S] | P0 |
| OMOD-AROLE-6 | `onlyRecoveryPendingGuardian` rejects current guardian, current guardian-recovery tx-recovery, deployer, and normal pending guardian addresses | [S] | P0 |
| OMOD-AROLE-7 | Same address intentionally assigned to two distinct roles (e.g., guardian and tx-recovery) passes both corresponding modifiers but no others | [E] | P1 |

### 11.8 Zero-Address / Uninitialized Fail-Closed

No enforce function special-cases `address(0)`. These tests verify that when a role is uninitialized or unconfigured, the modifier still rejects every caller rather than silently passing.
Each test sets the stored role address to `address(0)` and calls the guarded function from one or more non-zero addresses, confirming they all revert. (`msg.sender == address(0)` is not a realistic scenario and is not tested.)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OMOD-AZERO-1 | `onlyGuardian` reverts for non-zero callers when `guardian` storage slot is `address(0)` (pre-initialization state) | [S] | P0 |
| OMOD-AZERO-2 | `onlyDeployer` reverts for non-zero callers when `deployerAddress` storage slot is `address(0)` | [S] | P0 |
| OMOD-AZERO-3 | `onlyTxRecoveryAddress` reverts for non-zero callers when `txRecovery.recoveryAddress` is `address(0)` (unconfigured); error includes `expected = address(0)` | [S] | P0 |
| OMOD-AZERO-4 | `onlyGuardianRecoveryAddress` reverts for non-zero callers when `guardianRecovery.recoveryAddress` is `address(0)` (unconfigured); error includes `expected = address(0)` | [S] | P0 |
| OMOD-AZERO-5 | `onlyPendingGuardian` reverts for non-zero callers when `pendingGuardian` is `address(0)` (no pending guardian update); error includes `pendingGuardian = address(0)` | [S] | P0 |
| OMOD-AZERO-6 | `onlyRecoveryPendingGuardian` reverts for non-zero callers when `guardianRecovery.pendingGuardian` is `address(0)` (no pending recovery update); error includes `pendingGuardian = address(0)` | [S] | P0 |

### 11.9 State Transition Atomicity

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OMOD-AATOM-1 | Guardian transfer (propose + accept): after acceptance, only the new guardian passes `onlyGuardian`; old guardian cannot pass at any point after acceptance in the same transaction | [S] | P0 |
| OMOD-AATOM-2 | Pending guardian full lifecycle: propose → pending address passes `onlyPendingGuardian` → accept → pending slot cleared → pending address no longer passes | [I] | P0 |
| OMOD-AATOM-3 | Recovery pending guardian full lifecycle: initiate → pending address passes `onlyRecoveryPendingGuardian` → accept → pending slot cleared → pending address no longer passes | [I] | P0 |

### 11.10 Access-Control Fuzz Tests

| ID | Test Case | Runs | Type | Priority |
|---|-----------|------|------|----------|
| OMOD-AFUZ-1 | [AUDIT-FUZZ] Random `msg.sender` against each of the 6 modifiers always reverts unless caller exactly equals stored role address | 10000 | [F] | P0 |
| OMOD-AFUZ-2 | [AUDIT-FUZZ] Random role address written to storage followed by random callers: only exact address match passes, all others revert with correct typed error | 10000 | [F] | P0 |

## 12. Additional Invariants

| ID | Invariant | Priority |
|---|-----------|----------|
| SAG-INV-1 | **Cross-org signature isolation:** signatures valid for one Organization are never valid for another | P0 |
| SAG-INV-2 | **Recovery isolation:** tx-recovery operations do not mutate guardian-recovery state, and vice versa | P0 |
| SAG-INV-3 | **Nonce monotonicity:** once a nonce is consumed, it is never reusable | P0 |
| SAG-INV-4 | **Rate-limit atomicity:** reverted outer transaction cannot leave partial usage updates | P0 |
| SAG-INV-5 | **Account beacon binding:** an Account’s Organization/beacon address is immutable post-deployment | P0 |
| SAG-INV-6 | **ERC-1271 statelessness:** account signature validation never consumes nonces or mutates policy usage state | P0 |

---

## 13. Additional Fuzz Tests

| ID | Test Case | Runs | Priority |
|---|-----------|------|----------|
| SAG-FUZ-1 | [AUDIT-FUZZ] Random parameter constraints (offset/head/length permutations) never panic and terminate safely | 10000 | P0 |
| SAG-FUZ-2 | [AUDIT-FUZZ] Random malformed policy-signature payloads (`0x01`) return invalid (no revert) | 10000 | P0 |
| SAG-FUZ-4 | [AUDIT-FUZZ] Random mixed admin signature streams preserve strict ordering and threshold rules | 5000 | P0 |
| SAG-FUZ-5 | [AUDIT-FUZZ] Random rate-limit scope configs produce expected key sharing/isolation | 10000 | P0 |
| SAG-FUZ-6 | [AUDIT-FUZZ] Random execute/reject ordering preserves shared nonce replay protection | 5000 | P0 |
| SAG-FUZ-7 | [AUDIT-FUZZ] [DESIRED] Random upgrade migration calldata cannot bypass wrapper whitelist/admin checks via nested upgrade | 2000 | P0 |

---

## Summary

| Category | Tests | Priority |
|----------|-------|----------|
| File/function scoped security gap cases | 175 | P0-P1 |
| Invariants | 6 | P0 |
| Fuzz tests | 8 | P0 |
| **Total** | **189** | |
