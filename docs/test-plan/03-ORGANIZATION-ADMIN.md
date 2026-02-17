# 03 — Organization Admin Test Plan

## Scope

This plan covers admin functionality in:

- `src/organization/base/OrganizationAdminBase.sol`
- `src/organization/libraries/LibOrganizationAdmin.sol`

Out of scope for this plan:

- Interface files (no direct tests for interfaces)
- ERC-7201 storage slot tests (covered in `02-STORAGE-LIBRARIES.md`)

**Planned test files:**

- `test/organization/OrganizationAdminBase.t.sol`
- `test/organization/LibOrganizationAdmin.t.sol`
- `test/organization/harness/LibOrganizationAdminHarness.sol`
- `test/organization/fuzz/OrganizationAdmin.fuzz.t.sol`
- `test/organization/invariants/OrganizationAdmin.invariants.t.sol`

Legend: `[U]` unit, `[N]` negative, `[S]` security, `[E]` edge, `[EV]` event, `[F]` fuzz, `[I]` invariant.

---

## 1. File: `src/organization/base/OrganizationAdminBase.sol`

### 1.1 `modifyAdmins(address[] adminsToAdd, address[] adminsToRemove, uint256 newVotingThreshold, AdminAuthParams authParams)`

| # | Test Case | Type | Priority |
|---|---|---|---|
| B-1 | Non-guardian caller reverts via `onlyGuardian` | [N][S] | P0 |
| B-2 | Guardian + valid signatures + valid payload succeeds (add flow) | [U] | P0 |
| B-3 | Guardian + valid signatures + valid payload succeeds (remove flow) | [U] | P0 |
| B-4 | Guardian + valid signatures succeeds for add+remove in one call | [U] | P0 |
| B-5 | Signatures for a different operation type (`ModifyMembers`) cannot authorize `modifyAdmins` | [S] | P0 |
| B-6 | Rejection signatures (`isApproval=false`) cannot execute `modifyAdmins` | [S] | P0 |
| B-7 | Changing `adminsToAdd` after signing causes authorization failure | [S] | P0 |
| B-8 | Changing `adminsToRemove` after signing causes authorization failure | [S] | P0 |
| B-9 | Changing `newVotingThreshold` after signing causes authorization failure | [S] | P0 |
| B-10 | Reordering `adminsToAdd` after signing invalidates signatures (array order bound) | [S][E] | P0 |
| B-11 | Reordering `adminsToRemove` after signing invalidates signatures | [S][E] | P0 |
| B-12 | Expired auth params revert with `AdminOperationExpired` | [N] | P0 |
| B-13 | Replay (same nonce) reverts with `NonceAlreadyUsed` | [S] | P0 |
| B-14 | If downstream `LibOrganizationAdmin.modifyAdmins` reverts, state rolls back and nonce is not consumed | [S] | P0 |
| B-15 | Downstream revert due invalid threshold also rolls back nonce consumption | [S] | P0 |
| B-16 | Emits `AdminAdded`/`AdminRemoved`/`VotingThresholdUpdated` with correct args on success | [EV] | P1 |
| B-17 | No `VotingThresholdUpdated` event when threshold is unchanged | [EV][E] | P1 |
| B-18 | Mixed EOA + ERC-1271 admin signatures authorize successfully | [U][S] | P0 |

### 1.2 `rejectAdminOperation(OperationType operationType, bytes operationData, AdminAuthParams authParams)`

| # | Test Case | Type | Priority |
|---|---|---|---|
| B-19 | Non-guardian caller reverts via `onlyGuardian` | [N][S] | P0 |
| B-20 | Valid rejection authorization succeeds and burns nonce | [U] | P0 |
| B-21 | Emits `AdminOperationRejected` with exact `(operationType, operationData, nonce)` | [EV] | P1 |
| B-22 | Approval signatures (`isApproval=true`) cannot be reused for rejection | [S] | P0 |
| B-23 | Any mutation of signed `(operationType, operationData)` causes failure | [S] | P0 |
| B-24 | Expired auth params revert with `AdminOperationExpired` | [N] | P0 |
| B-25 | Replay rejection with same nonce reverts `NonceAlreadyUsed` | [N][S] | P0 |
| B-26 | Reject first, then attempt actual execution of same operation payload: execution fails by used nonce | [S] | P0 |
| B-27 | Execute first, then reject same payload: rejection fails by used nonce | [S] | P0 |
| B-28 | Failed rejection authorization does not consume nonce | [S] | P0 |
| B-29 | Rejection works for arbitrary operation types (e.g., `Upgrade`, `ModifyPolicies`) when properly signed | [U][E] | P1 |
| B-30 | Empty `operationData` can be rejected when signatures are for empty payload | [E] | P2 |

### 1.3 View wrappers

#### `isAdmin(address)`

| # | Test Case | Type | Priority |
|---|---|---|---|
| B-31 | Returns `true` for admin | [U] | P3 |
| B-32 | Returns `false` for non-admin | [U] | P3 |

#### `adminCount()`

| # | Test Case | Type | Priority |
|---|---|---|---|
| B-33 | Mirrors storage count after add/remove sequences | [U] | P3 |

#### `votingThreshold()`

| # | Test Case | Type | Priority |
|---|---|---|---|
| B-34 | Mirrors storage threshold after updates | [U] | P3 |

---

## 2. File: `src/organization/libraries/LibOrganizationAdmin.sol`

### 2.1 `validateAdminAuthAndConsumeNonceOrRevert(OperationType operationType, bytes operationData, bool isApproval, AdminAuthParams authParams)`

| # | Test Case | Type | Priority |
|---|---|---|---|
| L-1 | Future expiration succeeds | [U] | P0 |
| L-2 | `expirationTimestamp == block.timestamp` succeeds | [E] | P0 |
| L-3 | Past expiration reverts `AdminOperationExpired` | [N] | P0 |
| L-4 | Empty signatures revert `InsufficientAdminAuthorization` | [N] | P0 |
| L-5 | Threshold=1 and one valid admin signature succeeds | [U] | P0 |
| L-6 | Exactly threshold valid signatures succeeds | [U] | P0 |
| L-7 | Fewer valid signatures than threshold reverts `InsufficientAdminAuthorization` | [N] | P0 |
| L-8 | Duplicate signer reverts `DuplicateOrOutOfOrderAdminSigner` | [S] | P0 |
| L-9 | Out-of-order signers reverts `DuplicateOrOutOfOrderAdminSigner` | [S] | P0 |
| L-10 | Valid signer that is not admin reverts `SignerIsNotAdmin` | [S] | P0 |
| L-11 | Malformed packed signatures revert `SignatureRecoveryFailed` | [N][S] | P0 |
| L-12 | ERC-1271 signer returning wrong magic reverts `SignatureRecoveryFailed` | [N][S] | P0 |
| L-13 | ERC-1271 signer reverting reverts `SignatureRecoveryFailed` | [N] | P0 |
| L-14 | Mixed EOA + ERC-1271 signatures in ascending signer order succeeds | [U][S] | P0 |
| L-15 | First use of nonce succeeds; second use reverts `NonceAlreadyUsed` | [S] | P0 |
| L-16 | Same operation with different salt produces different nonces | [U] | P0 |
| L-17 | Same data+salt but different operationType produces different nonces | [U][S] | P0 |
| L-18 | Same data+salt on different organization addresses produces different nonces | [S] | P0 |
| L-19 | Approval signatures cannot authorize rejection (`isApproval` domain separation) | [S] | P0 |
| L-20 | Rejection signatures cannot authorize approval | [S] | P0 |
| L-21 | Extra trailing signatures/bytes after threshold is met are ignored (early exit behavior) | [E] | P1 |
| L-22 | If auth fails/reverts after nonce write attempt, nonce state rolls back (nonce remains unused) | [S] | P0 |
| L-23 | Admin removed after signing but before execution causes failure (`SignerIsNotAdmin`) | [S] | P0 |
| L-24 | Threshold raised after signing causes old signature set to fail (`InsufficientAdminAuthorization`) | [S] | P0 |
| L-25 | `vm.chainId` change invalidates old signatures (chain-bound signing) | [S][E] | P1 |

### 2.2 `modifyAdmins(address[] adminsToAdd, address[] adminsToRemove, uint256 newVotingThreshold)`

| # | Test Case | Type | Priority |
|---|---|---|---|
| L-26 | Add one valid member as admin succeeds and increments count | [U] | P0 |
| L-27 | Add multiple valid members as admins succeeds | [U] | P0 |
| L-28 | Add `address(0)` reverts `InvalidMemberAddress` | [N] | P0 |
| L-29 | Add non-member reverts `AdminNotMember` | [N] | P0 |
| L-30 | Add existing admin reverts `AdminAlreadyExists` | [N] | P0 |
| L-31 | Duplicate address inside `adminsToAdd` reverts on second occurrence (`AdminAlreadyExists`) | [E] | P0 |
| L-32 | Remove existing admin succeeds and decrements count | [U] | P0 |
| L-33 | Remove multiple existing admins succeeds | [U] | P0 |
| L-34 | Remove non-admin reverts `AdminDoesNotExist` | [N] | P0 |
| L-35 | Remove `address(0)` reverts `AdminDoesNotExist` | [E] | P1 |
| L-36 | Duplicate address inside `adminsToRemove` reverts on second occurrence (`AdminDoesNotExist`) | [E] | P0 |
| L-37 | Removing the last admin reverts `InvalidAdminConfig` | [S] | P0 |
| L-38 | `newVotingThreshold = 0` reverts `InvalidAdminVotingThreshold` | [N] | P0 |
| L-39 | `newVotingThreshold > finalAdminCount` reverts `InvalidAdminVotingThreshold` | [N] | P0 |
| L-40 | `newVotingThreshold = 1` succeeds when final count >= 1 | [U] | P0 |
| L-41 | `newVotingThreshold = finalAdminCount` succeeds | [U] | P0 |
| L-42 | Removing admins while keeping old threshold that becomes too high reverts | [S] | P0 |
| L-43 | Empty add/remove arrays with unchanged valid threshold is a successful no-op | [E] | P2 |
| L-44 | Empty add/remove arrays with changed valid threshold succeeds and updates threshold | [U] | P1 |
| L-45 | Same address in add+remove (initially non-admin member) succeeds; net admin status unchanged | [E] | P1 |
| L-46 | Same address in add+remove (initially admin) reverts because add loop runs first (`AdminAlreadyExists`) | [E] | P1 |
| L-47 | Revert during additions rolls back earlier successful additions (atomicity) | [S] | P0 |
| L-48 | Revert during removals rolls back prior additions/removals from same tx (atomicity) | [S] | P0 |
| L-49 | Emits one `AdminAdded` per successful add with correct indexed address | [EV] | P1 |
| L-50 | Emits one `AdminRemoved` per successful remove with correct indexed address | [EV] | P1 |
| L-51 | Emits `VotingThresholdUpdated(old,new)` only when threshold changes | [EV] | P1 |
| L-52 | Post-state consistency: `adminCount` equals effective admin mapping cardinality for touched set | [U][I] | P1 |

### 2.3 `isAdmin(address adminAddress)`

| # | Test Case | Type | Priority |
|---|---|---|---|
| L-53 | Returns `true` for known admin | [U] | P3 |
| L-54 | Returns `false` for known non-admin | [U] | P3 |
| L-55 | Returns `false` for `address(0)` | [U][E] | P3 |

### 2.4 `getAdminCount()`

| # | Test Case | Type | Priority |
|---|---|---|---|
| L-56 | Returns initial count, then updated count after successful mutations | [U] | P3 |

### 2.5 `getVotingThreshold()`

| # | Test Case | Type | Priority |
|---|---|---|---|
| L-57 | Returns initial threshold, then updated threshold after successful changes | [U] | P3 |

### 2.6 `_areAdminSignaturesValid(bytes signatures, bytes32 operationHash)` (private; test via harness)

| # | Test Case | Type | Priority |
|---|---|---|---|
| L-58 | Empty signatures returns `false` | [N] | P0 |
| L-59 | Exactly threshold valid signatures returns `true` | [U] | P0 |
| L-60 | More than threshold signatures returns `true` via early exit | [U][E] | P0 |
| L-61 | Fewer than threshold valid signatures returns `false` | [N] | P0 |
| L-62 | Duplicate signer reverts `DuplicateOrOutOfOrderAdminSigner` | [S] | P0 |
| L-63 | Out-of-order signer reverts `DuplicateOrOutOfOrderAdminSigner` | [S] | P0 |
| L-64 | Non-admin signer reverts `SignerIsNotAdmin` | [S] | P0 |
| L-65 | Mixed EOA + ERC-1271 signers succeeds when globally sorted by signer address | [U][S] | P0 |
| L-66 | Malformed signature encoding reverts `SignatureRecoveryFailed` | [N] | P0 |
| L-67 | Threshold met before trailing malformed bytes still returns `true` (documents short-circuit behavior) | [E] | P1 |

### 2.7 `_getAdminOperationHash(...)` (private; test via harness)

| # | Test Case | Type | Priority |
|---|---|---|---|
| L-68 | Deterministic: same inputs produce same hash | [U] | P1 |
| L-69 | Different `operationType` produces different hash | [U] | P1 |
| L-70 | Different `operationData` bytes produces different hash | [U] | P1 |
| L-71 | Different `salt` produces different hash | [U] | P1 |
| L-72 | Different `expirationTimestamp` produces different hash | [U] | P1 |
| L-73 | `isApproval=true/false` produces different hash | [S] | P0 |
| L-74 | Different `chainId` produces different hash | [S] | P0 |
| L-75 | Different contract address (`address(this)`) produces different hash | [S] | P0 |
| L-76 | Hash equals manual EIP-712 typed-data computation using expected domain + struct encoding | [U] | P1 |
| L-77 | Same byte content in different memory instances yields same hash (content, not pointer, dependent) | [E] | P2 |

---

## 3. Cross-File Fuzz and Invariant Coverage

### 3.1 Fuzz tests

| # | Test Case | Type | Priority |
|---|---|---|---|
| F-1 | Fuzz valid admin sets and thresholds: successful authorizations always require >= threshold valid admin signatures | [F] | P0 |
| F-2 | Fuzz invalid threshold updates (`0` or `> finalAdminCount`) always revert | [F] | P0 |
| F-3 | Fuzz salts for same operation payload produce unique nonces with overwhelming probability | [F] | P1 |
| F-4 | Fuzz non-admin signer inclusion: any included non-admin signer causes strict revert (`SignerIsNotAdmin`) | [F][S] | P0 |
| F-5 | Fuzz payload mutation after signing always invalidates authorization | [F][S] | P0 |
| F-6 | Fuzz mixed add/remove arrays: successful calls never leave zero admins and never violate threshold bounds | [F] | P0 |

### 3.2 Invariants

| # | Invariant | Priority |
|---|---|---|
| I-1 | `adminCount >= 1` after initialization | P0 |
| I-2 | `1 <= votingThreshold <= adminCount` always holds | P0 |
| I-3 | For any tracked address: `isAdmin(addr) => isMember(addr)` | P0 |
| I-4 | Used nonce monotonicity: once `usedNonces[nonce]` becomes true, it never becomes false | P0 |
| I-5 | Model consistency: modeled admin set cardinality matches on-chain `adminCount` | P1 |

---

## Summary

| Category | Tests | Priority Focus |
|---|---|---|
| `OrganizationAdminBase.sol` | 34 | P0 |
| `LibOrganizationAdmin.sol` | 77 | P0 |
| Fuzz + invariants | 11 | P0 |
| **Total** | **122** | **Security + correctness first** |
