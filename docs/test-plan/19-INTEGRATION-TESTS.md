# 19 — Integration Tests Plan (File/Function Breakdown)

## Scope

- End-to-end behavior across Organization, Account, Whitelist, and Guardian Safe module flows.
- This plan intentionally excludes interface files and storage libraries.
- Test intent follows desired behavior documented in `README.md` and `docs/*.md`.
- Where desired behavior may differ from current implementation, cases are marked `[DESIRED]`.
- Private functions should be tested through harnesses in test-only builds by changing `private` to `internal`.

## Legend

- `[I]` Integration
- `[S]` Security / replay / isolation
- `[N]` Negative path
- `[E]` Edge case
- `[EV]` Event-focused
- `[DESIRED]` Desired behavior guardrail

---

## 1) `src/organization/OrganizationFactory.sol`

### 1.1 `deployOrganization(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Authorized deployer + whitelisted implementation + valid init params deploys, initializes, and returns expected address | [I] | P0 |
| 2 | Unauthorized caller reverts `UnauthorizedDeployer` | [N] | P0 |
| 3 | Non-whitelisted implementation reverts | [N] | P0 |
| 4 | Failed initialization (invalid init params) reverts atomically; no partial deployment persists | [S] | P0 |
| 5 | Retry after failed deploy with same `(salt, implementation, whitelist)` succeeds (salt not consumed on revert) | [I] | P1 |
| 6 | Deployment emits `OrganizationDeployed` only on successful full flow | [EV] | P1 |
| 7 | [DESIRED] `implementationAddress == address(0)` reverts | [DESIRED][N] | P0 |
| 8 | [DESIRED] `implementationAddress` without code reverts | [DESIRED][S] | P0 |
| 9 | [DESIRED] `whitelistAddress == address(0)` reverts | [DESIRED][S] | P0 |
| 10 | [DESIRED] `whitelistAddress` without code reverts | [DESIRED][S] | P0 |

### 1.2 `computeOrganizationAddress(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 11 | Deterministic for same inputs | [I] | P1 |
| 12 | Different salt/implementation/whitelist produce different addresses | [I] | P1 |
| 13 | Matches actual deployed address from `deployOrganization` | [I] | P0 |

### 1.3 `_getOrganizationProxyBytecode(...)` (private -> harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 14 | Bytecode hash is stable for same inputs and sensitive to implementation/whitelist changes | [S] | P1 |

---

## 2) `src/organization/base/OrganizationInitializationBase.sol` + `src/organization/libraries/LibOrganizationInitialization.sol`

### 2.1 `initialize(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 15 | Factory/deployer-only initialization succeeds once and sets core state (members/admins/groups/guardian/timelock) | [I] | P0 |
| 16 | Re-initialization reverts | [S] | P0 |
| 17 | Invalid initialization (no members, invalid admins/threshold/guardian/timelock) reverts with full rollback | [S] | P0 |
| 18 | Deferred recovery setup path works when recovery addresses are zero at init | [I] | P0 |
| 19 | Immediate recovery setup path works when recovery addresses are provided at init | [I] | P1 |
| 20 | Admins are always members after successful initialization | [S] | P0 |

---

## 3) `src/organization/base/OrganizationAdminBase.sol`

### 3.1 `modifyAdmins(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 21 | Guardian + valid admin signatures can add/remove admins and update threshold end-to-end | [I] | P0 |
| 22 | Non-guardian caller reverts | [N] | P0 |
| 23 | Signer ordering/duplicate signer violations revert | [S] | P0 |
| 24 | Admin removed after signing but before execution causes authorization failure at execution time | [S] | P0 |
| 25 | Threshold changes invalidate signatures that only satisfy old threshold | [S] | P0 |

### 3.2 `rejectAdminOperation(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 26 | Valid rejection burns nonce and blocks later approval of same operation params | [S] | P0 |
| 27 | Approval first blocks later rejection of same operation params | [S] | P0 |

---

## 4) `src/organization/base/OrganizationMembersBase.sol`

### 4.1 `modifyMembers(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 28 | Add/remove members via guardian + admin auth works end-to-end | [I] | P0 |
| 29 | Removing admin member reverts until admin role is removed first | [S] | P0 |
| 30 | Member removal affects later policy authorization (removed member cannot initiate/approve) | [I] | P0 |

---

## 5) `src/organization/base/OrganizationGroupsBase.sol` + `src/organization/libraries/LibOrganizationGroups.sol`

### 5.1 `modifyGroups(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 31 | Create/update/delete group lifecycle works with admin auth | [I] | P0 |
| 32 | Deleted group cannot be recreated (group ID non-reuse) | [S] | P0 |
| 33 | Policies referencing deleted group stop authorizing approvals/initiations | [I] | P0 |
| 34 | Batch modifications are atomic (any failing modification reverts all) | [S] | P0 |
| 35 | Ghost membership data after delete does not authorize because group existence gate is enforced | [S] | P0 |
| 36 | [DESIRED] Adding non-member addresses to groups reverts | [DESIRED][S] | P0 |

### 5.2 Private helpers (private -> harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 37 | `_createGroup/_updateGroup/_deleteGroup/_addGroupMembers/_removeGroupMembers` enforce expected sequencing and revert conditions used by public integration flows | [S] | P1 |

---

## 6) `src/organization/base/OrganizationPolicyBase.sol` + policy libraries

### 6.1 `setPolicies(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 38 | Guardian + admin-auth updates policy root and enables new policy set immediately | [I] | P0 |
| 39 | Rejection flow (`rejectAdminOperation`) blocks later `setPolicies` execution for same signed operation | [S] | P0 |

### 6.2 `getPolicyUsage(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 40 | Valid policy proof returns live usage after transactions | [I] | P1 |
| 41 | Invalid policy proof reverts `PolicyVerificationFailed` | [N] | P1 |

### 6.3 Integrated policy constraint behavior

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 42 | Source-account filtering (`anySourceAccount` vs specific list) is enforced across multiple accounts | [I] | P0 |
| 43 | Destination custom-list validation uses actual recipient for ERC-20 transfers (not token contract address) | [S] | P0 |
| 44 | Token threshold boundary is strict `<` (amount == threshold rejected) | [E][S] | P0 |
| 45 | Function allowlist binds selector + constraints hash; same selector with different constraints behaves differently | [S] | P0 |
| 46 | Parameter constraints for dynamic bytes/string offsets reject malformed calldata without bypass | [S] | P0 |
| 47 | Rate-limit scopes (per initiator/source/destination vs across-all) track independently as configured | [I] | P0 |
| 48 | [DESIRED] Rate-limit arithmetic must fail safely (no overflow bypass / no wrapped usage) | [DESIRED][S] | P0 |
| 49 | [DESIRED] Zero approval threshold in group-manual policy is rejected | [DESIRED][S] | P0 |
| 50 | [DESIRED] `anyInitiator=true` still requires initiator to be an organization member | [DESIRED][S] | P0 |

### 6.4 Private helpers (private -> harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 51 | `LibOrganizationPolicy._computePolicyLeaf` and policy-private helpers preserve Merkle/constraint security assumptions used by end-to-end auth | [S] | P1 |

---

## 7) `src/organization/base/OrganizationAccountFactoryBase.sol`

### 7.1 `deployAccount(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 52 | Guardian + admin-auth deploys deterministic account; account is usable immediately | [I] | P0 |
| 53 | Replay of same admin auth nonce reverts | [S] | P0 |
| 54 | Account from org A cannot be treated as org B deployed account | [S] | P0 |

### 7.2 `setAccountImplementation(...)` / `implementation()`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 55 | Whitelisted account implementation upgrade updates behavior for all existing accounts under org | [I] | P0 |
| 56 | New accounts deployed after upgrade use new implementation | [I] | P1 |
| 57 | Non-whitelisted or wrong-contract-type implementation reverts | [N] | P0 |
| 58 | `implementation()` reverts before initial account implementation is configured | [N] | P1 |
| 59 | [DESIRED] Reject zero/no-code account implementation even if whitelist returns true | [DESIRED][S] | P0 |

---

## 8) `src/organization/base/OrganizationAccountTransactionBase.sol` + `src/organization/libraries/LibOrganizationAccountTransaction.sol` + `src/account/AccountImplementation.sol`

### 8.1 `executeAccountTransaction(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 60 | Full ETH transfer flow succeeds (policy proof + initiator/reviewer signatures + guardian caller) | [I] | P0 |
| 61 | Full ERC-20 transfer flow succeeds with destination/token/amount constraints | [I] | P0 |
| 62 | Full contract-interaction flow succeeds with function + parameter constraints | [I] | P0 |
| 63 | Nonce is shared and deterministic for `(account,to,value,data,policyId,salt)` | [S] | P0 |
| 64 | Nonce consumed before external call prevents same-tx reentrancy replay | [S] | P0 |
| 65 | If validation or account execution reverts, nonce consumption rolls back (same operation can be retried) | [S] | P0 |
| 66 | Manual-approval review signatures are bound to initiator signature (initiator sig swap invalidates approvals) | [S] | P0 |

### 8.2 `rejectAccountTransaction(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 67 | Auto-approve rejection requires authorized initiator rejection signature (`isApproval=false` hash) | [I][S] | P0 |
| 68 | Manual-approval rejection requires reviewer threshold on rejection hash | [I][S] | P0 |
| 69 | Execute then reject (or reject then execute) with same params/salt is blocked via shared nonce | [S] | P0 |
| 70 | Rejection path does not mutate rate-limit usage | [S] | P1 |

### 8.3 `AccountImplementation.executeTransaction(...)` / `receive()` / `isValidSignature(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 71 | Only Organization can call `executeTransaction`; non-org caller reverts | [S] | P0 |
| 72 | Failed low-level call reverts `TransactionExecutionFailed` and bubbles failure to org flow | [I] | P0 |
| 73 | Account receives ETH and emits receive event | [I] | P1 |
| 74 | `Account.isValidSignature` delegates to Organization account-signature path and returns contract result | [I] | P0 |

### 8.4 Private helpers (private -> harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 75 | `_validateAndUpdateRateLimitOrRevert`, `_validateAutoApproveRejectionOrRevert`, `_validateManualConfirmationOrRevert`, `_computeInitiatorHashFromParams`, `_computeReviewHashFromParams`, `AccountImplementation._execute`, `AccountImplementation._onlyOrganization` preserve expected integration invariants | [S] | P1 |

---

## 9) `src/organization/base/OrganizationAccountSignatureBase.sol` + `src/organization/libraries/LibOrganizationAccountSignature.sol`

### 9.1 `isValidSignatureForAccount(...)` / policy & recovery signature paths

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 76 | Caller must be the account itself and account must belong to org | [S] | P0 |
| 77 | Type `0x01` policy signatures: AutoApprove and ManualApproval flows validate correctly end-to-end | [I] | P0 |
| 78 | Type `0x00` recovery signature is valid only when tx/ERC1271 recovery is configured and enabled | [I][S] | P0 |
| 79 | Unknown type prefix returns invalid value | [N] | P0 |
| 80 | Guardian signature accepted from guardian directly or enabled Safe module; disabled module is rejected | [S] | P0 |
| 81 | Signature policy requires `TransactionType.Signatures` exactly (`Any` does not authorize ERC-1271) | [S] | P0 |
| 82 | Cross-org replay prevented (domain binds organization address) | [S] | P0 |
| 83 | Cross-chain replay prevented (typed data binds `chainId`) | [S] | P0 |
| 84 | [DESIRED] Malformed policy payload returns invalid value instead of reverting | [DESIRED][S] | P0 |

### 9.2 Private helpers (private -> harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 85 | `_validateRecoverySignature`, `_validatePolicyBasedSignature`, `_isValidGuardianSignature`, `_isERC1271SignatureAllowedByPolicy`, `_getInitiatorSignatureHash`, `_getReviewSignatureHash` uphold integration security assumptions | [S] | P1 |

---

## 10) `src/organization/base/OrganizationGuardianBase.sol`

### 10.1 `initiateGuardianUpdate(...)`, `finalizeGuardianUpdate(...)`, `cancelGuardianUpdate(...)`, `acceptGuardian()`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 86 | Normal guardian update flow (initiate -> timelock -> finalize -> accept) succeeds with guardian+admin auth | [I] | P0 |
| 87 | Distinct signatures are required per stage (`Initiate`/`Finalize`/`Cancel` operation types not replayable across stages) | [S] | P0 |
| 88 | Cancel works both before and after finalize (before accept) | [I] | P1 |
| 89 | Only pending guardian can accept | [S] | P0 |

---

## 11) `src/organization/base/OrganizationGuardianRecoveryBase.sol` + `src/organization/base/OrganizationTxRecoveryBase.sol`

### 11.1 Deferred recovery initialization (`initiate/finalize/cancelInitialize*Recovery`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 90 | Guardian + admin-auth deferred initialization works for guardian recovery and tx recovery after admin timelock | [I] | P0 |
| 91 | Cancelled deferred initialization leaves mechanism unconfigured and re-initiable | [I] | P1 |
| 92 | Finalize/cancel operation signatures are bound to current pending values (stale signatures fail) | [S] | P0 |
| 93 | Recovery mechanisms can be initialized only once | [S] | P0 |

### 11.2 Guardian recovery flow (`initiate/finalize/cancelRecoveryGuardianUpdate`, `acceptGuardianRecovery`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 94 | Recovery address can rotate guardian without current guardian participation after timelock | [I] | P0 |
| 95 | Unauthorized callers to recovery-only functions revert | [N] | P0 |
| 96 | Recovery and normal guardian update flows can run in parallel without shared-state corruption | [S] | P0 |

### 11.3 Tx recovery flow (`initiate/finalize/cancelEnable...`, `disable...`, `executeRecoveryAccountTransaction`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 97 | Tx recovery enable requires timelock; disable is immediate and clears pending enable state | [I][S] | P0 |
| 98 | Recovery account transaction works only when configured+enabled and bypasses policy checks | [I] | P0 |
| 99 | Recovery account transaction executes with `nonce=0` and `policyId=0` on account side | [I] | P1 |
| 100 | Recovery disable immediately blocks further recovery transactions and recovery ERC-1271 signatures | [S] | P0 |

### 11.4 Private helpers (private -> harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 101 | Recovery private helpers (`_clearPending*`, `_validate*NotConfiguredOrRevert`, `_validate*ParamsOrRevert`) preserve timelock/configuration integrity in end-to-end flows | [S] | P1 |

---

## 12) `src/organization/OrganizationImplementation.sol`

### 12.1 `upgradeToAndCallWithAuthorization(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 102 | Guardian + admin-auth + whitelisted implementation performs successful org UUPS upgrade | [I] | P0 |
| 103 | Direct call to inherited `upgradeToAndCall` bypass path reverts `UnauthorizedUpgrade` | [S] | P0 |
| 104 | Failed migration call reverts atomically and does not leave upgraded implementation active | [S] | P0 |
| 105 | Existing org state (members/admins/groups/policies/recovery/nonces) persists after upgrade | [I] | P0 |
| 106 | Upgrade authorization flag is false before/after and never stuck true on failure | [S] | P0 |
| 107 | [DESIRED] Admin authorization must bind both `newImplementation` and migration `data` | [DESIRED][S] | P0 |
| 108 | [DESIRED] Migration payload cannot trigger unauthorized nested second upgrade | [DESIRED][S] | P0 |
| 109 | [DESIRED] Reject zero/no-code `newImplementation` even if whitelist contract misbehaves | [DESIRED][S] | P0 |

### 12.2 `_authorizeUpgrade(...)` (internal -> harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 110 | Authorization only succeeds inside validated upgrade window | [S] | P0 |
| 111 | [DESIRED] Authorization should be bound to specific approved implementation, not only boolean flag | [DESIRED][S] | P0 |

---

## 13) `src/implementation-whitelist/ImplementationWhitelistImplementation.sol`

### 13.1 `initialize(...)` / `whitelistImplementations(...)` / UUPS owner controls

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 112 | Whitelist proxy initialization seeds org/account allowlists and owner correctly | [I] | P1 |
| 113 | Only current owner can add/remove implementations; ownership transfer updates control immediately | [S] | P0 |
| 114 | Contract-type isolation: Account whitelist entries never authorize org deploy/upgrade and vice versa | [S] | P0 |
| 115 | Unwhitelisting blocks future deployments/upgrades but does not mutate already active implementation pointers | [I] | P1 |
| 116 | Whitelist UUPS upgrade preserves allowlist state and ownership | [I] | P1 |
| 117 | [DESIRED] Reject zero/no-code addresses when whitelisting | [DESIRED][S] | P0 |

### 13.2 Private helpers (private -> harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 118 | `_addToWhitelist` / `_removeFromWhitelist` preserve contract-type isolation and event/state semantics required by integration gates | [S] | P1 |

---

## 14) `src/safe-module/SafeExecutorModule.sol` + `src/safe-module/BatchedTransaction.sol`

### 14.1 `SafeExecutorModule.executeOnBehalf(...)` and `isValidSignature(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 119 | Only `AUTHORIZED_EXECUTOR` can execute on behalf of Safe | [S] | P0 |
| 120 | Calls targeting Safe itself are blocked | [S] | P0 |
| 121 | Non-batch targets use CALL; batch target uses DELEGATECALL; forwarded value is always zero | [S] | P0 |
| 122 | Safe execution failure reverts `ExecutionFailed` | [N] | P0 |
| 123 | Module ERC-1271 signature path accepts only signatures from authorized executor | [S] | P0 |
| 124 | Authorized executor can execute guardian-only Organization entrypoints via Safe module; unauthorized callers cannot | [I][S] | P0 |
| 125 | [DESIRED] Constructor hardening: reject invalid/non-contract Safe and BatchedTransaction wiring | [DESIRED][S] | P1 |

### 14.2 `BatchedTransaction.execute(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 126 | Valid packed batch executes subcalls in order atomically | [I] | P0 |
| 127 | Any failing subcall reverts full batch and rolls back earlier subcall effects | [S] | P0 |
| 128 | Subcall to `address(this)` (Safe in delegatecall context) always reverts `CannotCallSafe` | [S] | P0 |
| 129 | No ETH value transfer possible through batch (value hardcoded zero) | [S] | P0 |
| 130 | [DESIRED] Malformed packed encoding (short trailing bytes / oversized lengths / trailing garbage) reverts instead of silently succeeding | [DESIRED][S] | P0 |

---

## 15) Cross-Module End-to-End Scenarios

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 131 | Full lifecycle: deploy org -> initialize -> deploy account -> set policies -> execute tx -> reject tx variant -> verify nonce and policy usage outcomes | [I] | P0 |
| 132 | Multiple accounts in one org execute independently under shared policy set; scoped rate limits behave as configured | [I] | P0 |
| 133 | Multiple orgs on same chain cannot replay each other’s admin/tx/signature authorizations | [S] | P0 |
| 134 | Guardian update, recovery flows, and tx execution remain coherent through organization upgrade and account implementation upgrade | [I][S] | P0 |
| 135 | Guardian Safe module rotation (disable old module/enable new) immediately changes valid guardian module signatures with no org state change | [I][S] | P0 |

---

## 16) Private Function Harness Coverage (Integration-Critical)

In test-only builds, change the following from `private` to `internal` and expose via harness wrappers so integration assumptions can be validated directly:

- `src/organization/libraries/LibOrganizationAdmin.sol`
  - `_areAdminSignaturesValid`, `_getAdminOperationHash`
- `src/organization/libraries/LibOrganizationAccountTransaction.sol`
  - `_validateAndUpdateRateLimitOrRevert`, `_validateAutoApproveRejectionOrRevert`, `_validateManualConfirmationOrRevert`, `_computeInitiatorHashFromParams`, `_computeReviewHashFromParams`
- `src/account/AccountImplementation.sol`
  - `_execute`, `_onlyOrganization`
- `src/organization/libraries/LibOrganizationAccountSignature.sol`
  - `_validateRecoverySignature`, `_validatePolicyBasedSignature`, `_isValidGuardianSignature`, `_isERC1271SignatureAllowedByPolicy`, `_getInitiatorSignatureHash`, `_getReviewSignatureHash`
- `src/organization/libraries/LibOrganizationGroups.sol`
  - `_createGroup`, `_updateGroup`, `_deleteGroup`, `_addGroupMembers`, `_removeGroupMembers`
- `src/organization/libraries/LibOrganizationPolicy.sol`
  - `_computePolicyLeaf`
- `src/organization/libraries/LibOrganizationGuardianRecovery.sol`
  - `_clearPendingGuardianRecoveryInitTimelock`, `_validateGuardianRecoveryNotConfiguredOrRevert`, `_validateGuardianRecoveryParamsOrRevert`
- `src/organization/libraries/LibOrganizationTxRecovery.sol`
  - `_clearPendingTxRecoveryInitTimelock`, `_validateTxRecoveryNotConfiguredOrRevert`, `_validateTxRecoveryParamsOrRevert`
- `src/organization/OrganizationFactory.sol`
  - `_getOrganizationProxyBytecode`
- `src/implementation-whitelist/ImplementationWhitelistImplementation.sol`
  - `_addToWhitelist`, `_removeFromWhitelist`
- `src/organization/libraries/policy/LibPolicyContractInteraction.sol`
  - `_isFunctionAllowedByPolicy`, `_computeFunctionLeaf`
- `src/organization/libraries/policy/LibPolicyApproval.sol`
  - `_isSignerAuthorizedForPolicy`
- `src/organization/libraries/policy/LibPolicyTokenTransfer.sol`
  - `_isTokenAllowedByPolicy`, `_isTokenAmountAllowedByPolicy`
- `src/organization/libraries/policy/LibPolicyParameterConstraints.sol`
  - private constraint validators used in function-call policy enforcement
- `src/libraries/SignatureUtils.sol`
  - `_isValidERC1271SignatureNow`, `_tryRecoverContractSigner`, `_tryRecoverEOASigner`, `_getVByte`, `_getContractSigner`, `_getContractSignatureLength`, `_extractContractInnerSignature`
