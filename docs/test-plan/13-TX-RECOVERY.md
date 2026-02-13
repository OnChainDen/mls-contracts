# 13 — Transaction Recovery Test Plan

**Files Under Test:**
- `src/organization/base/OrganizationTxRecoveryBase.sol`
- `src/organization/libraries/LibOrganizationTxRecovery.sol`
- `src/interfaces/organization/IOrganizationTxRecovery.sol`

**Existing Tests:** `test/LibOrganizationTxRecovery.t.sol` (35 tests)

**Test File(s):** Existing file + `test/OrganizationTxRecoveryBase.t.sol`

---

## File 1: OrganizationTxRecoveryBase.sol

### 1.1 `initiateEnableTransactionAndERC1271Recovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Non-recovery-address caller — reverts (onlyTxRecoveryAddress modifier) | [N] | P0 |
| 2 | Recovery address caller — delegates to `LibOrganizationTxRecovery.initiateEnableTxRecovery` | [U] | P1 |

---

### 1.2 `finalizeEnableTransactionAndERC1271Recovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 3 | Non-recovery-address caller — reverts (onlyTxRecoveryAddress modifier) | [N] | P0 |
| 4 | Recovery address caller — delegates to `LibOrganizationTxRecovery.finalizeEnableTxRecovery` | [U] | P1 |

---

### 1.3 `cancelEnableTransactionAndERC1271Recovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 5 | Non-recovery-address caller — reverts (onlyTxRecoveryAddress modifier) | [N] | P0 |
| 6 | Recovery address caller — delegates to `LibOrganizationTxRecovery.cancelEnableTxRecovery` | [U] | P1 |

---

### 1.4 `disableTransactionAndERC1271Recovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 7 | Non-recovery-address caller — reverts (onlyTxRecoveryAddress modifier) | [N] | P0 |
| 8 | Recovery address caller — delegates to `LibOrganizationTxRecovery.disableTxRecovery` | [U] | P1 |

---

### 1.5 `executeRecoveryAccountTransaction`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 9 | Non-recovery-address caller — reverts (onlyTxRecoveryAddress modifier) | [N] | P0 |
| 10 | Recovery not configured — reverts `TxRecoveryNotConfigured` | [N] | P0 |
| 11 | Recovery not enabled — reverts `TxRecoveryNotEnabled` | [N] | P0 |
| 12 | Account not deployed by this organization — reverts `AccountNotDeployedByOrganization` | [N] | P0 |
| 13 | Valid call — executes transaction on account with `nonce=0, policyId=0` | [U] | P0 |
| 14 | Emits `RecoveryAccountTransactionExecuted(account, to, value, data)` before external call (CEI) | [EV] | P1 |
| 15 | Recovery tx can transfer ETH from account | [I] | P0 |
| 16 | Recovery tx can call contracts from account | [I] | P0 |
| 17 | Calls `IAccount(account).executeTransaction` with correct parameters | [U] | P1 |
| 18 | Validation order: recovery allowed check before account deployed check | [U] | P1 |

---

### 1.6 `initiateInitializeTransactionAndERC1271Recovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 19 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| 20 | Insufficient admin signatures — reverts | [N] | P0 |
| 21 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| 22 | `OperationType` is `InitiateInitializeTransactionRecovery` in admin auth | [U] | P1 |
| 23 | `operationData` encodes `(recoveryAddress, timelockDurationSeconds)` | [U] | P1 |
| 24 | Delegates to `LibOrganizationTxRecovery.initiateInitializeTxRecovery` | [U] | P1 |

---

### 1.7 `finalizeInitializeTransactionAndERC1271Recovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 25 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| 26 | Insufficient admin signatures — reverts | [N] | P0 |
| 27 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| 28 | `OperationType` is `FinalizeInitializeTransactionRecovery` in admin auth | [U] | P1 |
| 29 | `operationData` encodes pending values `(pendingRecoveryAddress, pendingTimelockDurationSeconds)` from storage | [U] | P1 |
| 30 | Delegates to `LibOrganizationTxRecovery.finalizeInitializeTxRecovery` | [U] | P1 |

---

### 1.8 `cancelInitializeTransactionAndERC1271Recovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 31 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| 32 | Insufficient admin signatures — reverts | [N] | P0 |
| 33 | Admin auth nonce consumed — replay with same nonce reverts | [S] | P0 |
| 34 | `OperationType` is `CancelInitializeTransactionRecovery` in admin auth | [U] | P1 |
| 35 | `operationData` encodes pending values `(pendingRecoveryAddress, pendingTimelockDurationSeconds)` from storage | [U] | P1 |
| 36 | Delegates to `LibOrganizationTxRecovery.cancelInitializeTxRecovery` | [U] | P1 |

---

### 1.9 `getTxRecoveryState` (view)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 37 | Returns full `TxRecoveryState` struct from storage | [U] | P3 |
| 38 | Callable by anyone (no access restriction) | [U] | P3 |
| 39 | Returns zeroed struct when no recovery is configured | [U] | P3 |
| 40 | Returns correct config after `initializeTxRecovery` | [U] | P3 |
| 41 | Returns `isEnabled=true` after enable flow completes | [U] | P3 |
| 42 | Returns correct pending enable state during enable flow | [U] | P3 |
| 43 | Returns correct pending init state during deferred init flow | [U] | P3 |

---

## File 2: LibOrganizationTxRecovery.sol

> Note: All public functions in this library are called via DELEGATECALL (library deployed as
> separate contract for bytecode size savings). The 3 private functions
> (`_clearPendingTxRecoveryInitTimelock`, `_validateTxRecoveryNotConfiguredOrRevert`,
> `_validateTxRecoveryParamsOrRevert`) need to be converted to `internal` and exposed via
> a test harness for direct testing.

### 2.1 `initializeTxRecovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 44 | Valid address + valid timelock duration — sets `recoveryAddress` in storage | [U] | P1 |
| 45 | Valid address + valid timelock duration — sets `timelockDurationSeconds` in storage | [U] | P1 |
| 46 | Sets `isEnabled = false` on initialization | [U] | P1 |
| 47 | `address(0)` — reverts `InvalidTxRecoveryAddress` | [N] | P1 |
| 48 | Timelock below minimum (< 2 days) — reverts `InvalidTimelockDuration` | [N] | P1 |
| 49 | Timelock above maximum (> 30 days) — reverts `InvalidTimelockDuration` | [N] | P1 |
| 50 | Already configured (`recoveryAddress` non-zero) — reverts `TransactionRecoveryAlreadyConfigured` | [N] | P0 |
| 51 | Already configured (`timelockDurationSeconds` non-zero) — reverts `TransactionRecoveryAlreadyConfigured` | [N] | P0 |
| 52 | Values readable via `getTxRecoveryState()` after initialization | [U] | P1 |

---

### 2.2 `initiateEnableTxRecovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 53 | Valid state — sets `pendingEnableTimestamp` to `block.timestamp + timelockDurationSeconds` | [U] | P1 |
| 54 | Recovery not configured (`recoveryAddress == address(0)`) — reverts `TxRecoveryNotConfigured` | [N] | P0 |
| 55 | Recovery not configured (`timelockDurationSeconds == 0`) — reverts `TxRecoveryNotConfigured` | [N] | P0 |
| 56 | Already enabled — reverts `TxRecoveryAlreadyEnabled` | [N] | P1 |
| 57 | Already pending (`pendingEnableTimestamp != 0`) — reverts `TxRecoveryEnableAlreadyPending` | [N] | P1 |
| 58 | Emits `TxRecoveryEnableInitiated(canFinalizeAtTimestamp)` | [EV] | P1 |
| 59 | Validation order: not-configured check → already-enabled check → already-pending check | [U] | P1 |

---

### 2.3 `finalizeEnableTxRecovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 60 | After timelock expires — sets `isEnabled = true` | [U] | P1 |
| 61 | After timelock expires — clears `pendingEnableTimestamp` to 0 | [U] | P1 |
| 62 | No pending request (`pendingEnableTimestamp == 0`) — reverts `NoTxRecoveryEnablePending` | [N] | P1 |
| 63 | Before timelock expires — reverts `TimelockNotExpired` | [N] | P1 |
| 64 | At exactly timelock expiry timestamp — succeeds | [E] | P1 |
| 65 | Emits `TxRecoveryEnableFinalized()` | [EV] | P1 |

---

### 2.4 `cancelEnableTxRecovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 66 | Clears `pendingEnableTimestamp` to 0 | [U] | P1 |
| 67 | No pending request (`pendingEnableTimestamp == 0`) — reverts `NoTxRecoveryEnablePending` | [N] | P1 |
| 68 | Emits `TxRecoveryEnableCancelled()` | [EV] | P1 |
| 69 | `isEnabled` remains false after cancel | [U] | P1 |
| 70 | Recovery config (`recoveryAddress`, `timelockDurationSeconds`) unchanged after cancel | [U] | P1 |

---

### 2.5 `disableTxRecovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 71 | Sets `isEnabled = false` immediately (no timelock) | [U] | P0 |
| 72 | Clears `pendingEnableTimestamp` to 0 (cancels any pending enable) | [U] | P0 |
| 73 | Emits `TxRecoveryDisabled()` | [EV] | P1 |
| 74 | Disable when already disabled — no-op, no revert | [E] | P2 |
| 75 | Disable cancels pending enable even if timelock has expired | [S] | P0 |
| 76 | After disable, recovery transactions revert `TxRecoveryNotEnabled` | [S] | P0 |
| 77 | After disable, `isValidRecoverySignature` still works (view function, independent of isEnabled) | [U] | P1 |
| 78 | Recovery config (`recoveryAddress`, `timelockDurationSeconds`) unchanged after disable | [U] | P1 |

---

### 2.6 `initiateInitializeTxRecovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 79 | Valid params — sets `pendingInit.pendingRecoveryAddress` in storage | [U] | P1 |
| 80 | Valid params — sets `pendingInit.pendingTimelockDurationSeconds` in storage | [U] | P1 |
| 81 | `pendingInit.pendingTimestamp` computed via `LibOrganizationAdminOperationTimelock.computeCanFinalizeAtTimestamp()` | [U] | P1 |
| 82 | Already configured (`recoveryAddress` non-zero) — reverts `TransactionRecoveryAlreadyConfigured` | [N] | P0 |
| 83 | Already pending (`pendingInit.pendingTimestamp != 0`) — reverts `TxRecoveryInitializationAlreadyPending` | [N] | P1 |
| 84 | `address(0)` recovery address — reverts `InvalidTxRecoveryAddress` | [N] | P1 |
| 85 | Timelock below minimum — reverts `InvalidTimelockDuration` | [N] | P1 |
| 86 | Timelock above maximum — reverts `InvalidTimelockDuration` | [N] | P1 |
| 87 | Emits `TxRecoveryInitializationInitiated(recoveryAddress, timelockDurationSeconds, canFinalizeAtTimestamp)` | [EV] | P1 |
| 88 | Validation order: not-configured check before already-pending check | [U] | P1 |

---

### 2.7 `finalizeInitializeTxRecovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 89 | After timelock expires — sets `recoveryAddress` and `timelockDurationSeconds` in config | [U] | P1 |
| 90 | No pending initialization (`pendingTimestamp == 0`) — reverts `NoTxRecoveryInitializationPending` | [N] | P1 |
| 91 | Before timelock expires — reverts `TimelockNotExpired` | [N] | P1 |
| 92 | At exactly timelock expiry timestamp — succeeds | [E] | P1 |
| 93 | Clears all `pendingInit` fields after finalization (delegates to `_clearPendingTxRecoveryInitTimelock`) | [U] | P1 |
| 94 | Delegates to `initializeTxRecovery` for validation and config writes | [U] | P1 |
| 95 | Emits `TxRecoveryInitializationFinalized(pendingAddress, pendingTimelock)` | [EV] | P1 |
| 96 | `isEnabled` remains false after finalization (must still go through enable flow) | [U] | P1 |
| 97 | After finalization, enable flow (initiate/finalize/cancel) can be used | [I] | P1 |

---

### 2.8 `cancelInitializeTxRecovery`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 98 | No pending initialization (`pendingTimestamp == 0`) — reverts `NoTxRecoveryInitializationPending` | [N] | P1 |
| 99 | Clears `pendingInit.pendingRecoveryAddress` to `address(0)` | [U] | P1 |
| 100 | Clears `pendingInit.pendingTimelockDurationSeconds` to 0 | [U] | P1 |
| 101 | Clears `pendingInit.pendingTimestamp` to 0 | [U] | P1 |
| 102 | Emits `TxRecoveryInitializationCancelled()` | [EV] | P1 |
| 103 | Recovery config (`recoveryAddress`, `timelockDurationSeconds`) remain zero after cancel | [U] | P1 |
| 104 | Can initiate again after cancel | [U] | P1 |

---

### 2.9 `validateRecoveryAccountTransactionAllowedOrRevert`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 105 | Recovery configured and enabled — succeeds (no revert) | [U] | P0 |
| 106 | Recovery not configured (`recoveryAddress == address(0)`) — reverts `TxRecoveryNotConfigured` | [N] | P0 |
| 107 | Recovery not configured (`timelockDurationSeconds == 0`) — reverts `TxRecoveryNotConfigured` | [N] | P0 |
| 108 | Recovery configured but not enabled — reverts `TxRecoveryNotEnabled` | [N] | P0 |
| 109 | Validation order: not-configured check before not-enabled check | [U] | P1 |

---

### 2.10 `isValidRecoverySignature`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 110 | Valid EOA signature from recovery address — returns true | [U] | P0 |
| 111 | Wrong signer (not recovery address) — returns false | [N] | P0 |
| 112 | Malformed signature (`tryRecoverSigner` fails) — returns false | [N] | P0 |
| 113 | Recovery not configured (`recoveryAddress == address(0)`) — returns false | [N] | P0 |
| 114 | Valid ERC-1271 contract signature from recovery address — returns true | [U] | P0 |
| 115 | Function is `view` — no state changes | [U] | P1 |
| 116 | Never reverts — always returns true or false | [E] | P0 |

---

### 2.11 `enforceOnlyTxRecoveryAddress`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 117 | `msg.sender == recoveryAddress` — no revert | [U] | P0 |
| 118 | `msg.sender != recoveryAddress` — reverts `UnauthorizedTxRecoveryAddress(msg.sender, expected)` | [N] | P0 |
| 119 | Error includes both caller address and expected recovery address | [U] | P1 |
| 120 | Recovery not configured (`recoveryAddress == address(0)`) — any address reverts | [E] | P0 |

---

### 2.12 `isRecoveryEnabledForTxAndERC1271`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 121 | Returns false when not configured | [U] | P3 |
| 122 | Returns false after initialization (before enable) | [U] | P3 |
| 123 | Returns true after enable flow completes | [U] | P3 |
| 124 | Returns false after disable | [U] | P3 |

---

### 2.13 `_clearPendingTxRecoveryInitTimelock` (private -> internal)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 125 | After clear: `pendingInit.pendingRecoveryAddress == address(0)` | [U] | P1 |
| 126 | After clear: `pendingInit.pendingTimelockDurationSeconds == 0` | [U] | P1 |
| 127 | After clear: `pendingInit.pendingTimestamp == 0` | [U] | P1 |
| 128 | Clearing already-zeroed state — no-op, no revert | [E] | P2 |

---

### 2.14 `_validateTxRecoveryNotConfiguredOrRevert` (private -> internal)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 129 | Both `recoveryAddress` and `timelockDurationSeconds` zero — succeeds (not configured) | [U] | P1 |
| 130 | `recoveryAddress` non-zero, `timelockDurationSeconds` zero — reverts `TransactionRecoveryAlreadyConfigured` | [N] | P1 |
| 131 | `recoveryAddress` zero, `timelockDurationSeconds` non-zero — reverts `TransactionRecoveryAlreadyConfigured` | [N] | P1 |
| 132 | Both non-zero — reverts `TransactionRecoveryAlreadyConfigured` | [N] | P1 |

---

### 2.15 `_validateTxRecoveryParamsOrRevert` (private -> internal)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 133 | Valid address + valid timelock duration — succeeds | [U] | P1 |
| 134 | `recoveryAddress == address(0)` — reverts `InvalidTxRecoveryAddress` | [N] | P1 |
| 135 | Timelock below minimum (< 2 days) — reverts `InvalidTimelockDuration` | [N] | P1 |
| 136 | Timelock above maximum (> 30 days) — reverts `InvalidTimelockDuration` | [N] | P1 |
| 137 | Timelock at exact minimum boundary (2 days) — succeeds | [E] | P1 |
| 138 | Timelock at exact maximum boundary (30 days) — succeeds | [E] | P1 |
| 139 | Timelock at 0 seconds — reverts `InvalidTimelockDuration` | [E] | P1 |

---

## 3. Full Lifecycle Integration Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 140 | Complete enable flow: initiate → time passes → finalize — recovery enabled | [I] | P0 |
| 141 | Cancel enable flow: initiate → cancel → initiate again — works | [I] | P1 |
| 142 | Enable → disable → re-enable: full enable flow → disable → must do full enable flow again | [I] | P0 |
| 143 | Disable during pending enable: initiate → disable — clears pending and disables | [I] | P1 |
| 144 | Deferred init lifecycle: initiateInit → time passes → finalizeInit → recovery config set | [I] | P1 |
| 145 | Deferred init cancel + retry: initiateInit → cancelInit → initiateInit again — works | [I] | P1 |
| 146 | Full lifecycle after deferred init: initiateInit → finalizeInit → initiateEnable → finalize → enabled | [I] | P1 |
| 147 | Recovery tx execution: full setup → enable → executeRecoveryAccountTransaction succeeds | [I] | P0 |
| 148 | Multiple enable/disable cycles: enable → disable → enable → disable — all state transitions correct | [I] | P1 |
| 149 | Recovery signature valid when configured (even if not enabled) — `isValidRecoverySignature` is independent of `isEnabled` | [I] | P1 |

---

## 4. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 150 | Fuzz: Random non-zero recovery addresses with valid timelock durations always configure successfully | [F] | P1 |
| 151 | Fuzz: Random timelock durations in [2 days, 30 days] always accepted by `_validateTxRecoveryParamsOrRevert` | [F] | P1 |
| 152 | Fuzz: Random timelock durations outside [2 days, 30 days] always revert `InvalidTimelockDuration` | [F] | P1 |
| 153 | Fuzz: Random timestamps before enable timelock expiry — finalize always reverts `TimelockNotExpired` | [F] | P1 |
| 154 | Fuzz: Random timestamps at/after enable timelock expiry — finalize always succeeds | [F] | P1 |
| 155 | Fuzz: Random valid recovery address EOA signatures always authenticate via `isValidRecoverySignature` | [F] | P0 |
| 156 | Fuzz: Random non-recovery-address signers always rejected by `isValidRecoverySignature` | [F] | P0 |
| 157 | Fuzz: Random non-recovery addresses always revert on `enforceOnlyTxRecoveryAddress` | [F] | P0 |
| 158 | Fuzz: Random enable timelock durations — `pendingEnableTimestamp` always equals `block.timestamp + duration` | [F] | P1 |

---

## 5. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 159 | **Disable immediacy**: `disableTxRecovery` always works immediately without timelock | P0 |
| 160 | **Enable requires timelock**: Tx recovery can only be enabled after timelock expires via initiate → finalize | P0 |
| 161 | **Guardian recovery isolation**: Tx recovery state changes never affect guardian recovery state | P0 |
| 162 | **Config immutability**: `recoveryAddress` and `timelockDurationSeconds` never change after initialization (only set once) | P0 |
| 163 | **Disable clears pending**: After `disableTxRecovery`, `pendingEnableTimestamp` is always 0 | P0 |
| 164 | **Deferred init state consistency**: If `pendingInit.pendingTimestamp == 0`, then `pendingInit.pendingRecoveryAddress == address(0)` AND `pendingInit.pendingTimelockDurationSeconds == 0` | P0 |
| 165 | **isEnabled monotonic per cycle**: `isEnabled` only transitions `false → true` via finalize and `true → false` via disable — never skips steps | P0 |
| 166 | **Recovery tx requires enabled**: `validateRecoveryAccountTransactionAllowedOrRevert` always reverts when `isEnabled == false` | P0 |
| 167 | **Signature view purity**: `isValidRecoverySignature` never modifies storage (is `view`) | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| `initiateEnableTransactionAndERC1271Recovery` (Base) | 2 | P0-P1 |
| `finalizeEnableTransactionAndERC1271Recovery` (Base) | 2 | P0-P1 |
| `cancelEnableTransactionAndERC1271Recovery` (Base) | 2 | P0-P1 |
| `disableTransactionAndERC1271Recovery` (Base) | 2 | P0-P1 |
| `executeRecoveryAccountTransaction` (Base) | 10 | P0-P1 |
| `initiateInitializeTransactionAndERC1271Recovery` (Base) | 6 | P0-P1 |
| `finalizeInitializeTransactionAndERC1271Recovery` (Base) | 6 | P0-P1 |
| `cancelInitializeTransactionAndERC1271Recovery` (Base) | 6 | P0-P1 |
| `getTxRecoveryState` (Base) | 7 | P3 |
| `initializeTxRecovery` (Lib) | 9 | P0-P1 |
| `initiateEnableTxRecovery` (Lib) | 7 | P0-P1 |
| `finalizeEnableTxRecovery` (Lib) | 6 | P1 |
| `cancelEnableTxRecovery` (Lib) | 5 | P1 |
| `disableTxRecovery` (Lib) | 8 | P0-P2 |
| `initiateInitializeTxRecovery` (Lib) | 10 | P0-P1 |
| `finalizeInitializeTxRecovery` (Lib) | 9 | P1 |
| `cancelInitializeTxRecovery` (Lib) | 7 | P1 |
| `validateRecoveryAccountTransactionAllowedOrRevert` (Lib) | 5 | P0-P1 |
| `isValidRecoverySignature` (Lib) | 7 | P0-P1 |
| `enforceOnlyTxRecoveryAddress` (Lib) | 4 | P0-P1 |
| `isRecoveryEnabledForTxAndERC1271` (Lib) | 4 | P3 |
| `_clearPendingTxRecoveryInitTimelock` | 4 | P1-P2 |
| `_validateTxRecoveryNotConfiguredOrRevert` | 4 | P1 |
| `_validateTxRecoveryParamsOrRevert` | 7 | P1 |
| Full lifecycle integration | 10 | P0-P1 |
| Fuzz tests | 9 | P0-P1 |
| Invariant tests | 9 | P0 |
| **Total** | **167** | |
