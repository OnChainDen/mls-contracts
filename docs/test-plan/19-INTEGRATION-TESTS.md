# 19 — Integration Tests Plan (File/Function Breakdown)

## Scope

- End-to-end behavior across Organization, Account, Whitelist, and Guardian Safe module flows.
- This plan intentionally excludes interface files and storage libraries.
- Test intent follows desired behavior documented in `README.md` and `docs/*.md`.
- Where desired behavior may differ from current implementation, cases are marked `[DESIRED]`.
- All integration-critical private helpers should be tested through harnesses in test-only builds by changing `private` to `internal` (see section 16 plus private-helper subsections under each module).

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
| 7 | Reusing same `(salt, implementation, whitelist)` after successful deployment reverts (CREATE2 collision) and does not produce duplicate deploy side effects | [N][S] | P1 |
| 8 | [DESIRED] `implementationAddress == address(0)` reverts | [DESIRED][N] | P0 |
| 9 | [DESIRED] `implementationAddress` without code reverts | [DESIRED][S] | P0 |
| 10 | [DESIRED] `whitelistAddress == address(0)` reverts | [DESIRED][S] | P0 |
| 11 | [DESIRED] `whitelistAddress` without code reverts | [DESIRED][S] | P0 |

### 1.2 `computeOrganizationAddress(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 12 | Deterministic for same inputs | [I] | P1 |
| 13 | Different salt/implementation/whitelist produce different addresses | [I] | P1 |
| 14 | Matches actual deployed address from `deployOrganization` | [I] | P0 |

### 1.3 `_getOrganizationProxyBytecode(...)` (private -> harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 15 | Bytecode hash is stable for same inputs and sensitive to implementation/whitelist changes | [S] | P1 |

---

## 2) `src/organization/base/OrganizationInitializationBase.sol` + `src/organization/libraries/LibOrganizationInitialization.sol`

### 2.1 `initialize(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 16 | Factory/deployer-only initialization succeeds once and sets core state (members/admins/groups/guardian/timelock) | [I] | P0 |
| 17 | Non-deployer caller cannot initialize and reverts `UnauthorizedDeployer` | [N] | P0 |
| 18a | Re-initialization by the factory/deployer (same caller as original init) reverts on an already-initialized proxy (`initializer` modifier blocks second call) | [S] | P0 |
| 18b | Re-initialization by an arbitrary caller on an already-initialized proxy reverts (both `initializer` and `onlyDeployer` block the call) | [S] | P0 |
| 18c | After a failed initialization (e.g. invalid params that revert), the proxy remains uninitialised and a subsequent valid `initialize` call from the factory succeeds | [S] | P0 |
| 19 | Invalid initialization (no members, invalid admins/threshold/guardian/timelock) reverts with full rollback | [S] | P0 |
| 20 | Deferred recovery setup path works when recovery addresses are zero at init | [I] | P0 |
| 21 | Immediate recovery setup path works when recovery addresses are provided at init | [I] | P1 |
| 22 | Admins are always members after successful initialization | [S] | P0 |

### 2.2 `getDeployerAddress()` / `isInitialized()`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 23 | `getDeployerAddress` returns the factory address and `isInitialized` transitions `false -> true` only after successful initialization | [I] | P1 |

---

## 3) `src/organization/base/OrganizationAdminBase.sol`

### 3.1 `modifyAdmins(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 24 | Guardian + valid admin signatures can add/remove admins and update threshold end-to-end | [I] | P0 |
| 25 | Non-guardian caller reverts | [N] | P0 |
| 26 | Signer ordering/duplicate signer violations revert | [S] | P0 |
| 27 | Admin removed after signing but before execution causes authorization failure at execution time | [S] | P0 |
| 28 | Threshold changes invalidate signatures that only satisfy old threshold | [S] | P0 |
| 29 | Expired admin auth (`block.timestamp > expirationTimestamp`) reverts and does not consume an otherwise-unused nonce | [S] | P0 |

### 3.2 `rejectAdminOperation(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 30 | Valid rejection burns nonce and blocks later approval of same operation params | [S] | P0 |
| 31 | Approval first blocks later rejection of same operation params | [S] | P0 |
| 32 | Admin auth hash binds `isApproval`; approval signatures cannot authorize rejection and rejection signatures cannot authorize execution | [S] | P0 |

---

## 4) `src/organization/base/OrganizationMembersBase.sol`

### 4.1 `modifyMembers(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 33 | Add/remove members via guardian + admin auth works end-to-end | [I] | P0 |
| 34 | Removing admin member reverts until admin role is removed first | [S] | P0 |
| 35 | Member removal affects later policy authorization (removed member cannot initiate/approve) | [I] | P0 |

---

## 5) `src/organization/base/OrganizationGroupsBase.sol` + `src/organization/libraries/LibOrganizationGroups.sol`

### 5.1 `modifyGroups(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 36 | Create/update/delete group lifecycle works with admin auth | [I] | P0 |
| 37 | Deleted group cannot be recreated (group ID non-reuse) | [S] | P0 |
| 38 | Policies referencing deleted group stop authorizing approvals/initiations | [I] | P0 |
| 39 | Batch modifications are atomic (any failing modification reverts all) | [S] | P0 |
| 40 | Ghost membership data after delete does not authorize because group existence gate is enforced | [S] | P0 |
| 41 | Invalid operation shapes revert (Create with `membersToRemove`, Delete with non-empty member arrays) | [S] | P1 |
| 42 | [DESIRED] Adding non-member addresses to groups reverts | [DESIRED][S] | P0 |

### 5.2 Private helpers (private -> harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 43 | `_createGroup/_updateGroup/_deleteGroup/_addGroupMembers/_removeGroupMembers` enforce expected sequencing and revert conditions used by public integration flows | [S] | P1 |

---

## 6) `src/organization/base/OrganizationPolicyBase.sol` + policy libraries

### 6.1 `setPolicies(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 44 | Guardian + admin-auth updates policy root and enables new policy set immediately | [I] | P0 |
| 45 | Rejection flow (`rejectAdminOperation`) blocks later `setPolicies` execution for same signed operation | [S] | P0 |
| 46 | `setPolicies` authorization binds both `newPoliciesRoot` and `ipfsCid` hash (same root with different CID cannot reuse signatures) | [S] | P0 |

### 6.2 `getPolicyUsage(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 47 | Valid policy proof returns live usage after transactions | [I] | P1 |
| 48 | Invalid policy proof reverts `PolicyVerificationFailed` | [N] | P1 |

### 6.3 Integrated policy constraint behavior

Note: Destination, token, function, parameter-constraint, and rate-limit checks apply to `executeAccountTransaction` and `rejectAccountTransaction` only. They do not apply to the `isValidSignature` (ERC-1271) path, which only checks source account and initiator authorization. Source-account and initiator checks apply to all three entry points.

#### Source-account filtering

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 49a | `executeAccountTransaction`: policy with `anySourceAccount=false` — account in the source-account Merkle subtree succeeds; account not in the subtree reverts | [I] | P0 |
| 49b | `executeAccountTransaction`: policy with `anySourceAccount=true` — two different org accounts both execute successfully under the same policy | [I] | P0 |
| 49c | `isValidSignature`: policy with `anySourceAccount=false` — account in subtree returns valid; account not in subtree returns invalid | [I] | P0 |

#### Destination validation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 50a | `executeAccountTransaction` (ETH transfer): `DestinationType.CustomList` checks `to` address against the custom-destinations Merkle subtree; unlisted `to` reverts | [I] | P0 |
| 50b | `executeAccountTransaction` (ERC-20 `transfer`): `DestinationType.CustomList` checks the **recipient argument** extracted from calldata (not the token contract `to` address); unlisted recipient reverts | [S] | P0 |
| 50c | `executeAccountTransaction` (ERC-20 `transferFrom`): `DestinationType.CustomList` checks the **recipient argument** extracted from calldata; unlisted recipient reverts | [S] | P0 |
| 50d | `executeAccountTransaction`: `DestinationType.Any` allows any destination without proof | [I] | P1 |

#### Token type and amount threshold

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 51a | `executeAccountTransaction` (ETH transfer): policy allows native token — succeeds; policy does not allow native token — reverts | [I] | P0 |
| 51b | `executeAccountTransaction` (ERC-20 transfer): policy allows the specific token contract — succeeds; different token contract — reverts | [I] | P0 |
| 51c | `executeAccountTransaction`: `hasAmountThreshold=true` with `amountThreshold=N` — transfer of `N-1` succeeds, transfer of exactly `N` reverts (strict `<` boundary) | [E][S] | P0 |
| 51d | `executeAccountTransaction`: `hasAmountThreshold=false` — any amount succeeds | [I] | P1 |

#### Function allowlist and parameter constraints

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 52a | `executeAccountTransaction` (contract interaction): `anyFunction=false` — allowed selector with matching constraints hash succeeds; same selector with different constraints hash reverts (leaf binds selector + constraints hash) | [S] | P0 |
| 52b | `executeAccountTransaction` (contract interaction): `anyFunction=true` — any selector with any calldata succeeds | [I] | P1 |
| 52c | `executeAccountTransaction` (contract interaction): calldata shorter than 4 bytes (no selector) reverts when `anyFunction=false` | [S] | P1 |
| 53a | `executeAccountTransaction` (contract interaction): `ConstraintType.Exact` on a static `uint256` parameter — matching value succeeds; different value reverts | [I] | P0 |
| 53b | `executeAccountTransaction` (contract interaction): `ConstraintType.Exact` on a dynamic `bytes` parameter — matching content succeeds; different content reverts | [I] | P0 |
| 53c | `executeAccountTransaction` (contract interaction): dynamic `bytes`/`string` parameter with offset pointing into the ABI head region (offset < 32) reverts | [S] | P0 |
| 53d | `executeAccountTransaction` (contract interaction): dynamic `bytes`/`string` parameter with truncated calldata (length word or content extends beyond `data.length`) reverts | [S] | P0 |

#### Rate limits

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 54a | `executeAccountTransaction`: `PerEntity` initiator scope — two different initiators each get independent usage budgets under the same policy | [I] | P0 |
| 54b | `executeAccountTransaction`: `PerEntity` source-account scope — two different accounts each get independent usage budgets under the same policy | [I] | P0 |
| 54c | `executeAccountTransaction`: `PerEntity` destination scope — two different destinations each get independent usage budgets under the same policy | [I] | P0 |
| 54d | `executeAccountTransaction`: `AcrossAll` on all three scopes — all transactions share a single usage budget regardless of initiator/source/destination | [I] | P0 |
| 55a | `executeAccountTransaction`: usage accumulated in one time window does not carry over after the window boundary passes (fresh budget in new window) | [I][E] | P1 |
| 55b | `executeAccountTransaction`: transaction at the exact time-window boundary uses the new window's fresh budget, not the old window's exhausted budget | [E] | P1 |
| 55c | `rejectAccountTransaction`: rejection does not consume rate-limit usage; a subsequent `executeAccountTransaction` sees the same usage as before the rejection | [S] | P0 |
| 56 | [DESIRED] `executeAccountTransaction`: rate-limit usage addition that would overflow `uint256` reverts instead of wrapping to a small value that passes the limit check | [DESIRED][S] | P0 |

#### Approval and initiator authorization

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 57 | [DESIRED] `executeAccountTransaction`: ManualApproval policy with group approver whose `approvalThreshold=0` is rejected (zero threshold must not allow zero-signature approval) | [DESIRED][S] | P0 |
| 58a | [DESIRED] `executeAccountTransaction`: `anyInitiator=true` policy — non-member initiator reverts (org membership is always required even when `anyInitiator` is set) | [DESIRED][S] | P0 |
| 58b | [DESIRED] `isValidSignature`: `anyInitiator=true` policy — non-member initiator returns invalid | [DESIRED][S] | P0 |

#### Policy/group mutation invalidates pre-collected signatures

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 58c | `executeAccountTransaction`: signatures collected under a valid policy become unexecutable after `setPolicies` updates the policy root to exclude that policy | [I][S] | P0 |
| 58d | `executeAccountTransaction`: ManualApproval signatures collected before a group member removal (dropping below threshold) cause execution to revert | [I][S] | P0 |

### 6.4 Private helpers (private -> harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 59 | `LibOrganizationPolicy._computePolicyLeaf` and policy-private helpers preserve Merkle/constraint security assumptions used by end-to-end auth | [S] | P1 |
| 60 | `LibPolicyContractInteraction._computeFunctionLeaf/_isFunctionAllowedByPolicy` preserve selector+constraints-hash binding and reject malformed selector paths | [S] | P1 |
| 61 | `LibPolicyApproval._isSignerAuthorizedForPolicy` enforces org membership and reviewer member/group authorization invariants | [S] | P1 |
| 62 | `LibPolicyTokenTransfer._isTokenAllowedByPolicy/_isTokenAmountAllowedByPolicy` enforce native/ERC-20 token and amount semantics used by integration flows | [S] | P1 |
| 63 | `LibPolicyParameterConstraints` private validators enforce the documented type/constraint compatibility matrix without bypass | [S] | P1 |

---

## 7) `src/organization/base/OrganizationAccountFactoryBase.sol`

### 7.1 `deployAccount(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 64 | Guardian + admin-auth deploys deterministic account; account is usable immediately | [I] | P0 |
| 65 | Replay of same admin auth nonce reverts | [S] | P0 |
| 66 | Account from org A cannot be treated as org B deployed account | [S] | P0 |
| 67 | Reusing same account CREATE2 salt after successful deployment reverts and does not duplicate deployment side effects | [N][S] | P1 |

### 7.2 `setAccountImplementation(...)` / `implementation()`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 68 | Whitelisted account implementation upgrade updates behavior for all existing accounts under org | [I] | P0 |
| 69 | New accounts deployed after upgrade use new implementation | [I] | P1 |
| 70 | Non-whitelisted or wrong-contract-type implementation reverts | [N] | P0 |
| 71 | `implementation()` reverts before initial account implementation is configured | [N] | P1 |
| 72 | [DESIRED] Reject zero/no-code account implementation even if whitelist returns true | [DESIRED][S] | P0 |

### 7.3 `computeAccountAddress(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 73 | Deterministic for same salt and organization | [I] | P1 |
| 74 | Matches actual deployed address from `deployAccount` | [I] | P0 |

---

## 8) `src/organization/base/OrganizationAccountTransactionBase.sol` + `src/organization/libraries/LibOrganizationAccountTransaction.sol` + `src/account/AccountImplementation.sol`

### 8.1 `executeAccountTransaction(...)`
Critical: test these cases fully end-to-end using a guardian that is a v1.4.1 Safe that uses our SafeExecutorModule as the entry point for executing the test transactions as the guardian.

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 75 | Full ETH transfer flow succeeds (policy proof + initiator/reviewer signatures + guardian caller) | [I] | P0 |
| 76 | Full ERC-20 transfer flow succeeds with destination/token/amount constraints | [I] | P0 |
| 77 | Full contract-interaction flow succeeds with function + parameter constraints | [I] | P0 |
| 78 | Nonce is shared and deterministic for `(account,to,value,data,policyId,salt)` | [S] | P0 |
| 79 | Nonce consumed before external call prevents same-tx reentrancy replay | [S] | P0 |
| 80 | If validation or account execution reverts, nonce consumption rolls back (same operation can be retried) | [S] | P0 |
| 81 | Manual-approval review signatures are bound to initiator signature (initiator sig swap invalidates approvals) | [S] | P0 |
| 82 | Execute path reverts for accounts not deployed by the organization | [S][N] | P0 |
| 83 | Execute path rejects expired signatures and preserves retryability for valid fresh signatures | [S] | P0 |
| 84 | If account execution reverts after rate-limit update, rate-limit usage rolls back with the transaction | [S] | P0 |

### 8.2 `rejectAccountTransaction(...)`

Critical: test these cases fully end-to-end using a guardian that is a v1.4.1 Safe that uses our SafeExecutorModule as the entry point for executing the test transactions as the guardian.

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 85 | Auto-approve rejection requires authorized initiator rejection signature (`isApproval=false` hash) | [I][S] | P0 |
| 86 | Manual-approval rejection requires reviewer threshold on rejection hash | [I][S] | P0 |
| 87 | Execute then reject (or reject then execute) with same params/salt is blocked via shared nonce | [S] | P0 |
| 88 | Rejection path does not mutate rate-limit usage | [S] | P1 |
| 89 | If rejection validation fails, nonce consumption rolls back (same operation params/salt can still be validly retried) | [S] | P0 |

### 8.3 `AccountImplementation.executeTransaction(...)` / `receive()` / `isValidSignature(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 90 | Only Organization can call `executeTransaction`; non-org caller reverts | [S] | P0 |
| 91 | Failed low-level call reverts `TransactionExecutionFailed` and bubbles failure to org flow | [I] | P0 |
| 92 | Account execution path is CALL-only (no delegatecall semantics available to mutate account storage) | [S] | P1 |
| 93 | Account receives ETH and emits receive event | [I] | P1 |
| 94 | `Account.isValidSignature` delegates to Organization account-signature path and returns contract result | [I] | P0 |
| 171 | `executeTransaction` called directly on the implementation contract (not via proxy) reverts `OnlyOrganization` (organization address is unset in implementation's own storage) | [S] | P0 |
| 172 | `isValidSignature` called directly on the implementation contract returns ERC-1271 invalid value (organization address is unset in implementation's own storage, so `staticcall` to `address(0)` fails) | [S] | P0 |

### 8.4 Private helpers (private -> harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 95 | `_validateAndUpdateRateLimitOrRevert`, `_validateAutoApproveRejectionOrRevert`, `_validateManualConfirmationOrRevert`, `_computeInitiatorHashFromParams`, `_computeReviewHashFromParams`, `AccountImplementation._execute`, `AccountImplementation._onlyOrganization` preserve expected integration invariants | [S] | P1 |

---

## 9) `src/organization/base/OrganizationAccountSignatureBase.sol` + `src/organization/libraries/LibOrganizationAccountSignature.sol`

### 9.1 `isValidSignatureForAccount(...)` / policy & recovery signature paths

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 96 | Caller must be the account itself and account must belong to org | [S] | P0 |
| 97 | Type `0x01` policy signatures: AutoApprove and ManualApproval flows validate correctly end-to-end | [I] | P0 |
| 98 | Type `0x00` recovery signature is valid only when tx/ERC1271 recovery is configured and enabled | [I][S] | P0 |
| 99 | Unknown type prefix returns invalid value | [N] | P0 |
| 100 | Guardian signature accepted from guardian directly or enabled Safe module; disabled module is rejected | [S] | P0 |
| 101 | Signature policy requires `TransactionType.Signatures` exactly (`Any` does not authorize ERC-1271) | [S] | P0 |
| 102 | Policy-signature expiration boundary is enforced (`== expiration` valid, `> expiration` invalid) | [S][E] | P0 |
| 103 | Repeated calls with the same valid policy signature remain stateless (no nonce burn / no state mutation) | [I][S] | P1 |
| 104 | Cross-org replay prevented (domain binds organization address) | [S] | P0 |
| 105 | Cross-chain replay prevented (typed data binds `chainId`) | [S] | P0 |
| 106 | [DESIRED] Malformed policy payload returns invalid value instead of reverting | [DESIRED][S] | P0 |

### 9.2 Private helpers (tested through `isValidSignature` on Account / `isValidSignatureForAccount` on Organization)

Critical: Test these through high-level external functions on our Base contracts, like `isValidSignature` on the account contract (which delegates to `isValidSignatureForAccount` on the org contract).

#### 9.2.1 `_validateRecoverySignature`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 107a | Recovery signature (`0x00` type) returns invalid when tx/ERC1271 recovery is not configured (zero address / zero timelock) | [S] | P0 |
| 107b | Recovery signature returns invalid when recovery is configured but not enabled (enable flow not finalized) | [S] | P0 |
| 107c | Recovery signature returns valid when recovery is configured, enabled, and signed by the stored recovery EOA address | [I] | P0 |
| 107d | Recovery signature returns valid when recovery address is an ERC-1271 contract and its `isValidSignature` returns magic value | [I] | P1 |
| 107e | Recovery signature returns invalid when signed by an address other than the stored recovery address | [S] | P0 |
| 107f | Recovery signature returns invalid for malformed/truncated signature bytes (no revert) | [S] | P1 |

#### 9.2.2 `_validatePolicyBasedSignature`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 107g | Policy signature (`0x01` type) returns invalid when `block.timestamp > expirationTimestamp` | [S] | P0 |
| 107h | Policy signature returns valid when `block.timestamp == expirationTimestamp` (boundary) | [E] | P0 |
| 107i | Policy signature returns invalid when initiator signature is empty (zero-length bytes) | [S] | P0 |
| 107j | Policy signature returns invalid when initiator signature is malformed (recovery fails) | [S] | P0 |
| 107k | AutoApprove policy signature succeeds without any review signatures (guardian + initiator + policy proof sufficient) | [I] | P0 |
| 107l | ManualApproval policy signature requires reviewer threshold met on the review hash; insufficient reviewers returns invalid | [I] | P0 |
| 107m | ManualApproval policy signature succeeds when reviewer threshold is met | [I] | P0 |
| 107n | Unknown policy type (neither AutoApprove nor ManualApproval) returns invalid | [S] | P1 |
| 107n1 | AutoApprove succeeds with EOA initiator + Safe-module guardian (mixed signer types across roles) | [I] | P0 |
| 107n2 | AutoApprove succeeds with ERC-1271 contract initiator + EOA guardian (mixed signer types across roles) | [I] | P1 |
| 107n3 | ManualApproval succeeds with EOA initiator + Safe-module guardian + mix of EOA and ERC-1271 contract reviewers | [I] | P0 |
| 107n4 | ManualApproval succeeds when all reviewers are ERC-1271 contract signers (no EOA reviewers) | [I] | P1 |

#### 9.2.3 `_isValidGuardianSignature`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 107o | Guardian EOA signature on the review hash is accepted | [I] | P0 |
| 107p | Signature from an enabled Safe module (e.g. `SafeExecutorModule`) on the guardian Safe is accepted | [I] | P0 |
| 107q | Signature from a disabled Safe module on the guardian Safe is rejected | [S] | P0 |
| 107r | Signature from an arbitrary address that is neither guardian nor enabled module is rejected | [S] | P0 |
| 107s | Guardian is an ERC-1271 contract (non-Safe); valid contract signature is accepted | [I] | P1 |
| 107t | Malformed guardian signature returns false (no revert) | [S] | P1 |

#### 9.2.4 `_isERC1271SignatureAllowedByPolicy`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 107u | Returns false when policy Merkle proof is invalid (policy not in org's policy tree) | [S] | P0 |
| 107v | Returns false when policy `transactionType` is not `TransactionType.Signatures` (e.g. `TokenTransfers` or `ContractInteractions`) | [S] | P0 |
| 107w | Returns false when account is not an allowed source account for the policy (`anySourceAccount=false`, account not in subtree) | [S] | P0 |
| 107x | Returns true when `anySourceAccount=true` regardless of which org account calls | [I] | P1 |
| 107y | Returns false when recovered initiator is not authorized by the policy (not in initiator members/groups) | [S] | P0 |
| 107z | Returns true when all four checks pass (valid proof, correct type, authorized source, authorized initiator) | [I] | P0 |

#### 9.2.5 `_getInitiatorSignatureHash` / `_getReviewSignatureHash` (cross-domain binding)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 107aa | Initiator hash binds `address(this)` — same params signed against a different org address produce a different hash (cross-org replay prevented) | [S] | P0 |
| 107ab | Initiator hash binds `block.chainid` — signature produced on a fork/different chain is invalid | [S] | P0 |
| 107ac | Review hash includes `keccak256(initiatorSignature)` — swapping the initiator signature invalidates all existing guardian/reviewer approvals | [S] | P0 |
| 107ad | Review hash differs from initiator hash for the same parameters (distinct type hashes) | [S] | P1 |
| 107ae | Changing any single parameter (`account`, `hash`, `policyId`, `expirationTimestamp`) produces a different initiator hash and review hash | [S] | P0 |

### 9.3 `src/libraries/SignatureUtils.sol` private helpers (private -> harness)
Critical: Test these through high-level external functions on our Base contracts, like `executeAccountTransaction` on the org contract and `isValidSignature` on the account contract.
| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 108 | `_isValidERC1271SignatureNow`, `_tryRecoverContractSigner`, `_tryRecoverEOASigner`, and parser helpers reject malformed/truncated/high-`s` signatures and accept valid EOA/ERC-1271 encodings.  This should involve writing many tests. | [S] | P0 |


---

## 10) `src/organization/base/OrganizationGuardianBase.sol`

### 10.1 `initiateGuardianUpdate(...)`, `finalizeGuardianUpdate(...)`, `cancelGuardianUpdate(...)`, `acceptGuardian()`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 109 | Normal guardian update flow (initiate -> timelock -> finalize -> accept) succeeds with guardian+admin auth | [I] | P0 |
| 110 | Distinct signatures are required per stage (`Initiate`/`Finalize`/`Cancel` operation types not replayable across stages) | [S] | P0 |
| 111 | Finalize reverts before timelock expiry and succeeds at/after expiry boundary | [S][E] | P0 |
| 112 | Cancel works both before and after finalize (before accept) | [I] | P1 |
| 113 | Cannot initiate a second normal guardian update while one is pending | [S] | P0 |
| 114 | Only pending guardian can accept | [S] | P0 |

---

## 11) `src/organization/base/OrganizationGuardianRecoveryBase.sol` + `src/organization/base/OrganizationTxRecoveryBase.sol`

### 11.1 Deferred recovery initialization (`initiate/finalize/cancelInitialize*Recovery`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 115 | Guardian + admin-auth deferred initialization works for guardian recovery and tx recovery after admin timelock | [I] | P0 |
| 116 | Cancelled deferred initialization leaves mechanism unconfigured and re-initiable | [I] | P1 |
| 117 | Deferred init finalize reverts before timelock expiry and succeeds at/after expiry boundary | [S][E] | P0 |
| 118 | Finalize/cancel operation signatures are bound to current pending values (stale signatures fail) | [S] | P0 |
| 119 | Recovery mechanisms can be initialized only once | [S] | P0 |

### 11.2 Guardian recovery flow (`initiate/finalize/cancelRecoveryGuardianUpdate`, `acceptGuardianRecovery`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 120 | Recovery address can rotate guardian without current guardian participation after timelock | [I] | P0 |
| 121 | Unauthorized callers to recovery-only functions revert | [N] | P0 |
| 122 | Recovery guardian finalize reverts before recovery timelock expiry and succeeds at/after expiry boundary | [S][E] | P0 |
| 123 | Recovery and normal guardian update flows can run in parallel without shared-state corruption | [S] | P0 |

### 11.3 Tx recovery flow (`initiate/finalize/cancelEnable...`, `disable...`, `executeRecoveryAccountTransaction`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 124 | Tx recovery enable requires timelock; disable is immediate and clears pending enable state | [I][S] | P0 |
| 125 | Enable flow reverts when tx/ERC1271 recovery is not configured | [N][S] | P0 |
| 126 | Recovery account transaction works only when configured+enabled and bypasses policy checks | [I] | P0 |
| 127 | Recovery account transaction rejects accounts not deployed by this organization | [S] | P0 |
| 128 | Recovery account transaction executes with `nonce=0` and `policyId=0` on account side | [I] | P1 |
| 129 | Recovery account-transaction target failure bubbles as revert and leaves no side effects | [S] | P0 |
| 130 | Recovery disable immediately blocks further recovery transactions and recovery ERC-1271 signatures | [S] | P0 |

### 11.4 Private helpers (private -> harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 131 | Recovery private helpers (`_clearPending*`, `_validate*NotConfiguredOrRevert`, `_validate*ParamsOrRevert`) preserve timelock/configuration integrity in end-to-end flows | [S] | P1 |

---

## 12) `src/organization/OrganizationImplementation.sol`

### 12.1 `upgradeToAndCallWithAuthorization(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 132 | Guardian + admin-auth + whitelisted implementation performs successful org UUPS upgrade | [I] | P0 |
| 133 | Direct call to inherited `upgradeToAndCall` bypass path reverts `UnauthorizedUpgrade` | [S] | P0 |
| 134 | Failed migration call reverts atomically and does not leave upgraded implementation active | [S] | P0 |
| 135 | Existing org state (members/admins/groups/policies/recovery/nonces) persists after upgrade | [I] | P0 |
| 136 | Upgrade authorization flag is false before/after and never stuck true on failure | [S] | P0 |
| 137 | Rejected upgrade operation (`rejectAdminOperation` + `OperationType.Upgrade`) blocks later upgrade execution for same signed params | [S] | P0 |
| 138 | [DESIRED] Admin authorization must bind both `newImplementation` and migration `data` | [DESIRED][S] | P0 |
| 139 | [DESIRED] Migration payload cannot trigger unauthorized nested second upgrade | [DESIRED][S] | P0 |
| 140 | [DESIRED] Reject zero/no-code `newImplementation` even if whitelist contract misbehaves | [DESIRED][S] | P0 |

### 12.2 `_authorizeUpgrade(...)` (internal -> harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 141 | Authorization only succeeds inside validated upgrade window | [S] | P0 |
| 142 | [DESIRED] Authorization should be bound to specific approved implementation, not only boolean flag | [DESIRED][S] | P0 |

### 12.3 Implementation contract direct-call protection (uninitialized implementation attack vector)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 173 | `initialize()` called directly on the implementation contract (not via proxy) reverts (deployer address is unset in implementation's own storage, so `onlyDeployer` fails) | [S] | P0 |
| 174 | Inherited `upgradeToAndCall()` called directly on the implementation contract reverts `UnauthorizedUpgrade` (`authorizedUpgradeImplementation` is unset in implementation's own storage) | [S] | P0 |
| 175 | `upgradeToAndCallWithAuthorization()` called directly on the implementation contract reverts (guardian is unset in implementation's own storage, so `onlyGuardian` fails) | [S] | P0 |
| 178 | [DESIRED] Constructor calls `_disableInitializers()` so `initialize()` on the implementation contract reverts `InvalidInitialization` (explicit defense-in-depth, not relying on `onlyDeployer` as an accidental guard) | [DESIRED][S] | P0 |

---

## 13) `src/implementation-whitelist/ImplementationWhitelistImplementation.sol`

### 13.1 `initialize(...)` / `whitelistImplementations(...)` / UUPS owner controls

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 143 | Whitelist proxy initialization seeds org/account allowlists and owner correctly | [I] | P1 |
| 144 | `initialize` is one-time only (second initialization attempt reverts) | [S] | P0 |
| 145 | Only current owner can add/remove implementations; ownership transfer updates control immediately | [S] | P0 |
| 146 | Contract-type isolation: Account whitelist entries never authorize org deploy/upgrade and vice versa | [S] | P0 |
| 147 | Unwhitelisting blocks future deployments/upgrades but does not mutate already active implementation pointers | [I] | P1 |
| 148 | Whitelist UUPS upgrade preserves allowlist state and ownership | [I] | P1 |
| 149 | [DESIRED] Reject zero/no-code addresses when whitelisting | [DESIRED][S] | P0 |

### 13.2 Implementation contract direct-call protection (uninitialized implementation attack vector)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 176 | `initialize()` called directly on the implementation contract reverts `InvalidInitialization` (`_disableInitializers()` in constructor permanently marks implementation's own storage as fully initialized) | [S] | P0 |
| 177 | Inherited `upgradeToAndCall()` called directly on the implementation contract reverts `OwnableUnauthorizedAccount` (owner is unset in implementation's own storage, so `onlyOwner` in `_authorizeUpgrade` fails) | [S] | P0 |

### 13.3 Private helpers (private -> harness)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 150 | `_addToWhitelist` / `_removeFromWhitelist` preserve contract-type isolation and event/state semantics required by integration gates | [S] | P1 |

---

## 14) `src/safe-module/SafeExecutorModule.sol` + `src/safe-module/BatchedTransaction.sol`

### 14.1 `SafeExecutorModule.executeOnBehalf(...)` and `isValidSignature(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 151 | Only `AUTHORIZED_EXECUTOR` can execute on behalf of Safe | [S] | P0 |
| 152 | Calls targeting Safe itself are blocked | [S] | P0 |
| 153 | Non-batch targets use CALL; batch target uses DELEGATECALL; forwarded value is always zero | [S] | P0 |
| 154 | Safe execution failure reverts `ExecutionFailed` | [N] | P0 |
| 155 | Module ERC-1271 signature path accepts only signatures from authorized executor | [S] | P0 |
| 156 | Malformed/invalid module-signature encodings return ERC-1271 invalid value (not revert) | [S] | P1 |
| 157 | Authorized executor can execute guardian-only Organization entrypoints via Safe module; unauthorized callers cannot | [I][S] | P0 |
| 158 | [DESIRED] Constructor hardening: reject invalid/non-contract Safe and BatchedTransaction wiring | [DESIRED][S] | P1 |

### 14.2 `BatchedTransaction.execute(...)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 159 | Valid packed batch executes subcalls in order atomically | [I] | P0 |
| 160 | Any failing subcall reverts full batch and rolls back earlier subcall effects | [S] | P0 |
| 161 | Subcall to `address(this)` (Safe in delegatecall context) always reverts `CannotCallSafe` | [S] | P0 |
| 162 | No ETH value transfer possible through batch (value hardcoded zero) | [S] | P0 |
| 163 | [DESIRED] Malformed packed encoding (short trailing bytes / oversized lengths / trailing garbage) reverts instead of silently succeeding | [DESIRED][S] | P0 |

---

## 15) Cross-Module End-to-End Scenarios

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 164 | Full lifecycle: deploy org -> initialize -> deploy account -> set policies -> execute tx -> reject tx variant -> verify nonce and policy usage outcomes | [I] | P0 |
| 165 | Multiple accounts in one org execute independently under shared policy set; scoped rate limits behave as configured | [I] | P0 |
| 166 | Multiple orgs on same chain cannot replay each other’s admin/tx/signature authorizations | [S] | P0 |
| 167 | Access-control matrix: unauthorized callers are rejected across all modifier-protected entrypoints (`onlyGuardian`, `onlyDeployer`, `onlyPendingGuardian`, `onlyRecoveryPendingGuardian`, `onlyGuardianRecoveryAddress`, `onlyTxRecoveryAddress`) | [S] | P0 |
| 168 | `computeNonce` / `isNonceUsed` public views match actual execution/rejection outcomes and rollback semantics across operation types | [I][S] | P1 |
| 169 | Guardian update, recovery flows, and tx execution remain coherent through organization upgrade and account implementation upgrade | [I][S] | P0 |
| 170 | Guardian Safe module rotation (disable old module/enable new) immediately changes valid guardian module signatures with no org state change | [I][S] | P0 |

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
