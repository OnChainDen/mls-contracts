# 13 — Transaction Recovery Test Plan (Gap Analysis)

**Files Under Test:**
- `src/organization/libraries/LibOrganizationTxRecovery.sol`
- `src/organization/base/OrganizationTxRecoveryBase.sol`
- `src/interfaces/organization/IOrganizationTxRecovery.sol`

**Existing Tests:** `test/LibOrganizationTxRecovery.t.sol` (35 tests)

**Test File(s):** Existing file + `test/OrganizationTxRecoveryBase.t.sol`

---

## Existing Coverage Summary

The existing 35 tests cover:
- Initialization (happy path + error cases)
- Enable flow (initiate/finalize/cancel)
- Disable functionality
- Validation of recovery transaction allowed state
- Deferred initialization (initiate/finalize/cancel)

## Gaps to Fill

### 1. Base Contract Integration Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | `initiateEnableTransactionAndERC1271Recovery` only callable by `onlyTxRecoveryAddress` | [N] | P1 |
| 2 | `finalizeEnableTransactionAndERC1271Recovery` only callable by `onlyTxRecoveryAddress` | [N] | P1 |
| 3 | `cancelEnableTransactionAndERC1271Recovery` only callable by `onlyTxRecoveryAddress` | [N] | P1 |
| 4 | `disableTransactionAndERC1271Recovery` only callable by `onlyTxRecoveryAddress` | [N] | P1 |
| 5 | `executeRecoveryAccountTransaction` only callable by `onlyTxRecoveryAddress` | [N] | P1 |
| 6 | `initiateInitializeTransactionAndERC1271Recovery` only callable by `onlyGuardian` | [N] | P1 |
| 7 | `finalizeInitializeTransactionAndERC1271Recovery` only callable by `onlyGuardian` | [N] | P1 |
| 8 | `cancelInitializeTransactionAndERC1271Recovery` only callable by `onlyGuardian` | [N] | P1 |

### 2. Recovery Transaction Execution

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 9 | `executeRecoveryAccountTransaction` succeeds when recovery enabled | [I] | P0 |
| 10 | Recovery tx uses nonce=0, policyId=0 (bypasses policy) | [S] | P0 |
| 11 | Recovery tx validates account is deployed by org | [U] | P0 |
| 12 | Recovery tx reverts when recovery not configured | [N] | P0 |
| 13 | Recovery tx reverts when recovery not enabled | [N] | P0 |
| 14 | Recovery tx emits `RecoveryAccountTransactionExecuted` event | [EV] | P1 |
| 15 | Recovery tx can transfer ETH from account | [I] | P0 |
| 16 | Recovery tx can call contracts from account | [I] | P0 |

### 3. Recovery Signature Validation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 17 | `isValidRecoverySignature` with valid recovery address EOA signature — true | [U] | P0 |
| 18 | `isValidRecoverySignature` with wrong signer — false | [N] | P0 |
| 19 | `isValidRecoverySignature` with recovery address as ERC-1271 contract — true | [U] | P0 |
| 20 | `isValidRecoverySignature` with malformed signature — false | [N] | P0 |

### 4. Admin Authorization for Deferred Init

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 21 | Deferred init requires admin auth signatures | [U] | P1 |
| 22 | Deferred init with insufficient admin signatures — reverts | [N] | P1 |

### 5. Disable Safety

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 23 | Disable immediately works without timelock | [U] | P0 |
| 24 | Disable clears any pending enable request | [U] | P0 |
| 25 | After disable, recovery transactions revert | [S] | P0 |
| 26 | After disable, recovery signatures return invalid | [S] | P0 |
| 27 | Re-enable after disable requires full enable flow again | [I] | P0 |

### 6. Edge Cases

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 28 | Enable flow: multiple enable/disable cycles | [I] | P1 |
| 29 | Recovery tx against non-org account — reverts | [N] | P0 |

### 7. Private Function Tests (Requires `private` → `internal` Conversion)

> **Prerequisite:** The functions below are currently `private` in `LibOrganizationTxRecovery`.
> Convert them to `internal` and expose via a test harness.

#### 7.1 `_clearPendingTxRecoveryInitTimelock`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 30 | After clear: `pendingRecoveryAddress == address(0)` | [U] | P1 |
| 31 | After clear: `pendingTimelockDurationSeconds == 0` | [U] | P1 |
| 32 | After clear: `pendingTimestamp == 0` | [U] | P1 |
| 33 | Clearing already-zeroed state — no-op, no revert | [E] | P2 |

#### 7.2 `_validateTxRecoveryNotConfiguredOrRevert`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 34 | Both fields zero — succeeds (not configured) | [U] | P1 |
| 35 | `recoveryAddress` non-zero — reverts `TransactionRecoveryAlreadyConfigured` | [N] | P1 |
| 36 | `timelockDurationSeconds` non-zero — reverts `TransactionRecoveryAlreadyConfigured` | [N] | P1 |
| 37 | Both non-zero — reverts `TransactionRecoveryAlreadyConfigured` | [N] | P1 |

#### 7.3 `_validateTxRecoveryParamsOrRevert`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 38 | Valid address + valid timelock duration — succeeds | [U] | P1 |
| 39 | `recoveryAddress == address(0)` — reverts `InvalidTxRecoveryAddress` | [N] | P1 |
| 40 | Timelock duration below minimum (< 2 days) — reverts `InvalidTimelockDuration` | [N] | P1 |
| 41 | Timelock duration above maximum (> 30 days) — reverts `InvalidTimelockDuration` | [N] | P1 |
| 42 | Timelock at exact minimum boundary (2 days) — succeeds | [E] | P1 |
| 43 | Timelock at exact maximum boundary (30 days) — succeeds | [E] | P1 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Access control (base) | 8 | P1 |
| Recovery tx execution | 8 | P0 |
| Recovery signature | 4 | P0 |
| Admin auth | 2 | P1 |
| Disable safety | 5 | P0 |
| Edge cases | 2 | P0-P1 |
| Private function tests | 14 | P1-P2 |
| **Total** | **43** | |
