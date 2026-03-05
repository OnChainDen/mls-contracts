# 12 - Transaction Recovery Test Plan

**Primary Files Under Test:**
- `src/organization/base/OrganizationTxRecoveryBase.sol`
- `src/organization/libraries/LibOrganizationTxRecovery.sol`

**Related Tx-Recovery Interaction Files (integration behavior only):**
- `src/organization/libraries/LibOrganizationInitialization.sol`
- `src/organization/libraries/LibOrganizationAccountSignature.sol`
- `src/account/AccountImplementation.sol`

**Out of Scope for This Plan:**
- `src/interfaces/organization/IOrganizationTxRecovery.sol` (interface-only coverage is tracked elsewhere)
- `src/organization/libraries/storage/LibOrganizationRecoveryStorage.sol` (storage library coverage is tracked elsewhere)

**Existing Tests:** `test/LibOrganizationTxRecovery.t.sol` (35 tests)

> Note on private function testing:
> This plan includes tests for all currently-`private` functions in scope (including related
> interaction files). For implementation, expose those as `internal` in dedicated harness-only
> test builds so they can be invoked directly.

---

## Legend

| Code | Meaning |
|------|---------|
| `[U]` | Unit |
| `[N]` | Negative / revert path |
| `[E]` | Edge case |
| `[S]` | Security-focused |
| `[I]` | Integration |
| `[EV]` | Event behavior |
| `[F]` | Fuzz / property |

---

## File 1: `OrganizationTxRecoveryBase.sol`

### 1.1 `initiateEnableTransactionAndERC1271Recovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| OTRB-IETR-1 | Non-tx-recovery caller reverts via `onlyTxRecoveryAddress` | `[N]` | P0 |
| OTRB-IETR-2 | Guardian caller also reverts (role isolation) | `[S]` | P0 |
| OTRB-IETR-3 | Authorized tx-recovery caller reaches library flow successfully | `[U]` | P1 |
| OTRB-IETR-4 | Library bubbles `TxRecoveryNotConfigured` when configuration is missing but `timelockDurationSeconds` is in valid range | `[N]` | P0 |
| OTRB-IETR-5 | Library revert bubbles when recovery already enabled (`TxRecoveryAlreadyEnabled`) | `[N]` | P1 |
| OTRB-IETR-6 | Library revert bubbles when enable already pending (`TxRecoveryEnableAlreadyPending`) | `[N]` | P1 |

---

### 1.2 `finalizeEnableTransactionAndERC1271Recovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| OTRB-FETR-1 | Non-tx-recovery caller reverts via `onlyTxRecoveryAddress` | `[N]` | P0 |
| OTRB-FETR-2 | No pending enable reverts (`NoTxRecoveryEnablePending`) | `[N]` | P1 |
| OTRB-FETR-3 | Before timelock expiry reverts (`TimelockNotExpired`) | `[N]` | P1 |
| OTRB-FETR-4 | At exact timelock timestamp succeeds | `[E]` | P1 |
| OTRB-FETR-5 | Success path enables recovery and clears pending timestamp | `[U]` | P1 |
| OTRB-FETR-6 | Second finalize attempt reverts after successful finalize | `[N]` | P1 |

---

### 1.3 `cancelEnableTransactionAndERC1271Recovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| OTRB-CETR-1 | Non-tx-recovery caller reverts via `onlyTxRecoveryAddress` | `[N]` | P0 |
| OTRB-CETR-2 | No pending enable reverts (`NoTxRecoveryEnablePending`) | `[N]` | P1 |
| OTRB-CETR-3 | Pending enable is cleared on success | `[U]` | P1 |
| OTRB-CETR-4 | Cancel works even if pending enable timelock has already expired (before finalize) | `[E]` | P1 |
| OTRB-CETR-5 | Cancel does not enable recovery | `[U]` | P1 |

---

### 1.4 `disableTransactionAndERC1271Recovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| OTRB-DTER-1 | Non-tx-recovery caller reverts via `onlyTxRecoveryAddress` | `[N]` | P0 |
| OTRB-DTER-2 | When enabled, disable immediately sets `isEnabled=false` | `[U]` | P0 |
| OTRB-DTER-3 | Disable clears any pending enable request | `[S]` | P0 |
| OTRB-DTER-4 | Disable is idempotent when already disabled (no revert) | `[E]` | P2 |
| OTRB-DTER-5 | After disable, recovery transaction execution path is blocked (`TxRecoveryNotEnabled`) | `[S]` | P0 |

---

### 1.5 `executeRecoveryAccountTransaction`

> Reviewer wording `executeRecoveryTransaction` maps to `executeRecoveryAccountTransaction` in current code.

| ID | Test Case | Type | Priority |
|---|---|---|---|
| OTRB-ERAT-1 | Non-tx-recovery caller reverts via `onlyTxRecoveryAddress` | `[N]` | P0 |
| OTRB-ERAT-2 | Recovery not configured reverts (`TxRecoveryNotConfigured`) | `[N]` | P0 |
| OTRB-ERAT-3 | Recovery configured but not enabled reverts (`TxRecoveryNotEnabled`) | `[N]` | P0 |
| OTRB-ERAT-4 | Enable timelock initiated and NOT yet expired (`block.timestamp < pendingEnableTimestamp`) reverts with exact custom error `TxRecoveryNotEnabled` | `[N][E]` | P0 |
| OTRB-ERAT-5 | Enable timelock initiated and already expired but not finalized (`block.timestamp >= pendingEnableTimestamp`) reverts with exact custom error `TxRecoveryNotEnabled` | `[N][E]` | P0 |
| OTRB-ERAT-6 | Account not deployed by organization reverts (`AccountNotDeployedByOrganization`) | `[N]` | P0 |
| OTRB-ERAT-7 | Successful call emits `RecoveryAccountTransactionExecuted(account,to,value,data)` | `[EV]` | P1 |
| OTRB-ERAT-8 | Forwards exact `account`, `to`, `value`, `data` to `IAccount.executeTransaction` | `[U]` | P0 |
| OTRB-ERAT-9 | Always calls account with `nonce=0` and `policyId=0` | `[S]` | P0 |
| OTRB-ERAT-10 | ETH transfer via recovery execution succeeds when account has balance | `[I]` | P0 |
| OTRB-ERAT-11 | Contract-call via recovery execution succeeds | `[I]` | P0 |
| OTRB-ERAT-12 | If account execution reverts, outer call reverts | `[N]` | P0 |
| OTRB-ERAT-13 | Validation order is preserved: recovery-enabled check happens before account-deployed check | `[U]` | P1 |
| OTRB-ERAT-14 | Recovery execution does not mutate tx recovery config fields | `[S]` | P1 |
| OTRB-ERAT-15 | Reentrancy hard-stop when `to` is the Organization contract itself: selector sweep over all state-changing (non-view) Organization functions via recovery path always reverts (no successful nested Organization entrypoint) | `[S][I]` | P0 |
| OTRB-ERAT-16 | Reentrancy hard-stop when `to` is the Account contract itself: selector sweep over all state-changing (non-view) Account functions via recovery path always reverts | `[S][I]` | P0 |
| OTRB-ERAT-20 | All recovery-execution revert paths above fully revert outer transaction and persist no `RecoveryAccountTransactionExecuted` logs or partial state mutations | `[S][EV]` | P0 |

---

### 1.6 `initiateInitializeTransactionAndERC1271Recovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| OTRB-IITR-1 | Non-guardian caller reverts via `onlyGuardian` | `[N]` | P0 |
| OTRB-IITR-2 | Insufficient admin authorization reverts | `[N]` | P0 |
| OTRB-IITR-3 | Signatures built with `isApproval=false` are rejected | `[S]` | P0 |
| OTRB-IITR-4 | Signatures for wrong `OperationType` are rejected | `[S]` | P0 |
| OTRB-IITR-5 | Valid auth requires `OperationType.InitiateInitializeTransactionRecovery` with `isApproval=true` | `[U]` | P1 |
| OTRB-IITR-6 | Auth `operationData` must be exact `abi.encode(recoveryAddress,timelockDurationSeconds)` | `[U]` | P1 |
| OTRB-IITR-7 | Signatures for mismatched `operationData` (`recoveryAddress`,`timelock`) are rejected | `[S]` | P0 |
| OTRB-IITR-8 | Replay with consumed nonce fails | `[S]` | P0 |
| OTRB-IITR-9 | Valid auth path delegates and creates pending init state | `[U]` | P1 |
| OTRB-IITR-10 | Library revert bubbles when already configured (`TransactionRecoveryAlreadyConfigured`) | `[N]` | P0 |
| OTRB-IITR-11 | Library revert bubbles when deferred init already pending (`TxRecoveryInitializationAlreadyPending`) | `[N]` | P1 |
| OTRB-IITR-12 | Invalid recovery address/timelock bubbles from library validation | `[N]` | P1 |

---

### 1.7 `finalizeInitializeTransactionAndERC1271Recovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| OTRB-FITR-1 | Non-guardian caller reverts via `onlyGuardian` | `[N]` | P0 |
| OTRB-FITR-2 | Insufficient admin authorization reverts | `[N]` | P0 |
| OTRB-FITR-3 | Signatures built with `isApproval=false` are rejected | `[S]` | P0 |
| OTRB-FITR-4 | Signatures for wrong `OperationType` are rejected | `[S]` | P0 |
| OTRB-FITR-5 | Valid auth requires `OperationType.FinalizeInitializeTransactionRecovery` with `isApproval=true` | `[U]` | P1 |
| OTRB-FITR-6 | Auth uses pending values from storage; stale signatures for old pending values fail | `[S]` | P0 |
| OTRB-FITR-7 | Valid auth but no pending init reverts (`NoTxRecoveryInitializationPending`) | `[N]` | P1 |
| OTRB-FITR-8 | Valid auth before admin-op timelock expiry reverts (`TimelockNotExpired`) | `[N]` | P1 |
| OTRB-FITR-9 | At exact admin-op timelock expiry, finalize succeeds | `[E]` | P1 |
| OTRB-FITR-10 | Success writes config and clears pending init fields | `[U]` | P1 |
| OTRB-FITR-11 | Recovery remains disabled after finalize (enable flow still required) | `[U]` | P1 |
| OTRB-FITR-12 | Second finalize attempt reverts after success | `[N]` | P1 |

---

### 1.8 `cancelInitializeTransactionAndERC1271Recovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| OTRB-CITR-1 | Non-guardian caller reverts via `onlyGuardian` | `[N]` | P0 |
| OTRB-CITR-2 | Insufficient admin authorization reverts | `[N]` | P0 |
| OTRB-CITR-3 | Signatures built with `isApproval=false` are rejected | `[S]` | P0 |
| OTRB-CITR-4 | Signatures for wrong `OperationType` are rejected | `[S]` | P0 |
| OTRB-CITR-5 | Valid auth requires `OperationType.CancelInitializeTransactionRecovery` with `isApproval=true` | `[U]` | P1 |
| OTRB-CITR-6 | Auth uses pending values from storage; stale signatures for old pending values fail | `[S]` | P0 |
| OTRB-CITR-7 | Valid auth but no pending init reverts (`NoTxRecoveryInitializationPending`) | `[N]` | P1 |
| OTRB-CITR-8 | Success clears all pending init fields | `[U]` | P1 |
| OTRB-CITR-9 | Cancel allowed both before and after pending timestamp (no expiry requirement) | `[E]` | P1 |
| OTRB-CITR-10 | After cancel, recovery config remains unconfigured | `[U]` | P1 |
| OTRB-CITR-11 | Re-initiation is possible after cancel | `[U]` | P1 |

---

### 1.9 `getTxRecoveryState`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| OTRB-GTRS-1 | Returns full `TxRecoveryState` snapshot | `[U]` | P3 |
| OTRB-GTRS-2 | Callable by any address (no access control) | `[U]` | P3 |
| OTRB-GTRS-3 | Returns zeroed state before any tx recovery setup | `[U]` | P3 |
| OTRB-GTRS-4 | Reflects pending enable state during enable flow | `[U]` | P3 |
| OTRB-GTRS-5 | Reflects pending deferred-init state during deferred init flow | `[U]` | P3 |
| OTRB-GTRS-6 | Reflects enabled and disabled transitions correctly | `[U]` | P3 |

---

## File 2: `LibOrganizationTxRecovery.sol`

> Private helper functions included in this plan:
> `_clearPendingTxRecoveryInitTimelock`, `_validateTxRecoveryNotConfiguredOrRevert`,
> `_validateTxRecoveryParamsOrRevert`.
> For test implementation, expose them as `internal` through a harness.

### 2.1 `initializeTxRecovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-ITR-1 | Valid params set `recoveryAddress` | `[U]` | P1 |
| LOTR-ITR-2 | Valid params set `timelockDurationSeconds` | `[U]` | P1 |
| LOTR-ITR-3 | Initialization sets `isEnabled=false` | `[U]` | P1 |
| LOTR-ITR-4 | Clean initialization leaves pending fields zero | `[U]` | P1 |
| LOTR-ITR-5 | `recoveryAddress=address(0)` reverts (`InvalidTxRecoveryAddress`) | `[N]` | P1 |
| LOTR-ITR-6 | Timelock below min reverts (`InvalidTimelockDuration`) | `[N]` | P1 |
| LOTR-ITR-7 | Timelock above max reverts (`InvalidTimelockDuration`) | `[N]` | P1 |
| LOTR-ITR-8 | Timelock at min boundary succeeds | `[E]` | P1 |
| LOTR-ITR-9 | Timelock at max boundary succeeds | `[E]` | P1 |
| LOTR-ITR-10 | Any pre-existing config (`recoveryAddress!=0` or `timelock!=0`) reverts (`TransactionRecoveryAlreadyConfigured`) | `[N]` | P0 |

---

### 2.2 `initiateEnableTxRecovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-IETR-1 | Valid state sets `pendingEnableTimestamp = block.timestamp + timelockDurationSeconds` | `[U]` | P1 |
| LOTR-IETR-2 | Emits `TxRecoveryEnableInitiated(canFinalizeAtTimestamp)` with expected timestamp | `[EV]` | P1 |
| LOTR-IETR-3 | `recoveryAddress=0` with valid-range `timelockDurationSeconds` reverts (`TxRecoveryNotConfigured`) | `[N]` | P0 |
| LOTR-IETR-4 | Timelock validation is first: if `timelockDurationSeconds` is outside `[2 days, 30 days]`, `initiateEnableTxRecovery` reverts `InvalidTimelockDuration` regardless of configuration state | `[S]` | P0 |
| LOTR-IETR-5 | `isEnabled=true` reverts (`TxRecoveryAlreadyEnabled`) | `[N]` | P1 |
| LOTR-IETR-6 | Existing pending enable reverts (`TxRecoveryEnableAlreadyPending`) | `[N]` | P1 |
| LOTR-IETR-7 | `isEnabled` remains false after initiate | `[U]` | P1 |
| LOTR-IETR-8 | Check precedence: not-configured check runs before enabled/pending checks | `[U]` | P1 |

---

### 2.3 `finalizeEnableTxRecovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-FETR-1 | No pending enable reverts (`NoTxRecoveryEnablePending`) | `[N]` | P1 |
| LOTR-FETR-2 | Before pending timestamp reverts (`TimelockNotExpired`) | `[N]` | P1 |
| LOTR-FETR-3 | At exact pending timestamp succeeds | `[E]` | P1 |
| LOTR-FETR-4 | After expiry succeeds | `[U]` | P1 |
| LOTR-FETR-5 | Success sets `isEnabled=true` | `[U]` | P1 |
| LOTR-FETR-6 | Success clears `pendingEnableTimestamp` | `[U]` | P1 |
| LOTR-FETR-7 | Emits `TxRecoveryEnableFinalized()` | `[EV]` | P1 |
| LOTR-FETR-8 | Recovery config fields remain unchanged by finalize | `[U]` | P1 |

---

### 2.4 `cancelEnableTxRecovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-CETR-1 | No pending enable reverts (`NoTxRecoveryEnablePending`) | `[N]` | P1 |
| LOTR-CETR-2 | Pending enable is cleared on success | `[U]` | P1 |
| LOTR-CETR-3 | Emits `TxRecoveryEnableCancelled()` | `[EV]` | P1 |
| LOTR-CETR-4 | Cancel does not set `isEnabled=true` | `[U]` | P1 |
| LOTR-CETR-5 | Cancel allowed after pending timestamp has passed (before finalize) | `[E]` | P1 |
| LOTR-CETR-6 | Recovery config fields remain unchanged by cancel | `[U]` | P1 |

---

### 2.5 `disableTxRecovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-DTR-1 | Immediately sets `isEnabled=false` when currently enabled | `[U]` | P0 |
| LOTR-DTR-2 | Clears `pendingEnableTimestamp` in all states | `[S]` | P0 |
| LOTR-DTR-3 | Emits `TxRecoveryDisabled()` | `[EV]` | P1 |
| LOTR-DTR-4 | Idempotent when already disabled (no revert) | `[E]` | P2 |
| LOTR-DTR-5 | Disabling during pending enable before expiry cancels pending enable | `[S]` | P0 |
| LOTR-DTR-6 | Disabling during pending enable after expiry (before finalize) still cancels pending enable | `[S]` | P0 |
| LOTR-DTR-7 | Recovery config (`recoveryAddress`,`timelockDurationSeconds`) remains unchanged | `[U]` | P1 |
| LOTR-DTR-8 | After disable, `validateRecoveryAccountTransactionAllowedOrRevert` reverts (`TxRecoveryNotEnabled`) | `[S]` | P0 |
| LOTR-DTR-9 | `isValidRecoverySignature` result remains independent of `isEnabled` (enabled check happens elsewhere) | `[U]` | P1 |

---

### 2.6 `initiateInitializeTxRecovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-IITR-1 | Valid params set `pendingInit.pendingRecoveryAddress` | `[U]` | P1 |
| LOTR-IITR-2 | Valid params set `pendingInit.pendingTimelockDurationSeconds` | `[U]` | P1 |
| LOTR-IITR-3 | Valid params set `pendingInit.pendingTimestamp` based on admin-op timelock | `[U]` | P1 |
| LOTR-IITR-4 | Emits `TxRecoveryInitializationInitiated(recoveryAddress,timelock,canFinalizeAt)` | `[EV]` | P1 |
| LOTR-IITR-5 | Already configured reverts (`TransactionRecoveryAlreadyConfigured`) | `[N]` | P0 |
| LOTR-IITR-6 | Existing pending init reverts (`TxRecoveryInitializationAlreadyPending`) | `[N]` | P1 |
| LOTR-IITR-7 | Zero recovery address reverts (`InvalidTxRecoveryAddress`) | `[N]` | P1 |
| LOTR-IITR-8 | Timelock below min reverts (`InvalidTimelockDuration`) | `[N]` | P1 |
| LOTR-IITR-9 | Timelock above max reverts (`InvalidTimelockDuration`) | `[N]` | P1 |
| LOTR-IITR-10 | Timelock exactly at min boundary succeeds and stores pending init values | `[E]` | P1 |
| LOTR-IITR-11 | Timelock exactly at max boundary succeeds and stores pending init values | `[E]` | P1 |
| LOTR-IITR-12 | Active config and `isEnabled` are unchanged during initiate step | `[U]` | P1 |

---

### 2.7 `finalizeInitializeTxRecovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-FITR-1 | No pending init reverts (`NoTxRecoveryInitializationPending`) | `[N]` | P1 |
| LOTR-FITR-2 | Before admin-op timelock expiry reverts (`TimelockNotExpired`) | `[N]` | P1 |
| LOTR-FITR-3 | At exact expiry succeeds | `[E]` | P1 |
| LOTR-FITR-4 | Success writes config using pending values | `[U]` | P1 |
| LOTR-FITR-5 | Success clears all pending init fields | `[U]` | P1 |
| LOTR-FITR-6 | Success emits `TxRecoveryInitializationFinalized(pendingAddress,pendingTimelock)` | `[EV]` | P1 |
| LOTR-FITR-7 | Success leaves `isEnabled=false` (enable flow still required) | `[U]` | P1 |
| LOTR-FITR-8 | After success, enable flow can be initiated and finalized normally | `[I]` | P1 |
| LOTR-FITR-9 | Atomicity: if downstream `initializeTxRecovery` reverts (e.g., unexpected pre-configured state), pending init remains unchanged | `[S]` | P0 |
| LOTR-FITR-10 | Atomicity: when such revert occurs, no finalization event is emitted | `[EV]` | P1 |

---

### 2.8 `cancelInitializeTxRecovery`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-CITR-1 | No pending init reverts (`NoTxRecoveryInitializationPending`) | `[N]` | P1 |
| LOTR-CITR-2 | Clears `pendingInit.pendingRecoveryAddress` | `[U]` | P1 |
| LOTR-CITR-3 | Clears `pendingInit.pendingTimelockDurationSeconds` | `[U]` | P1 |
| LOTR-CITR-4 | Clears `pendingInit.pendingTimestamp` | `[U]` | P1 |
| LOTR-CITR-5 | Emits `TxRecoveryInitializationCancelled()` | `[EV]` | P1 |
| LOTR-CITR-6 | Active config remains unchanged by cancel | `[U]` | P1 |
| LOTR-CITR-7 | Re-initiation works after cancel | `[U]` | P1 |

---

### 2.9 `validateRecoveryAccountTransactionAllowedOrRevert`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-VRATOR-1 | Configured and enabled succeeds (no revert) | `[U]` | P0 |
| LOTR-VRATOR-2 | `recoveryAddress=0` reverts (`TxRecoveryNotConfigured`) | `[N]` | P0 |
| LOTR-VRATOR-3 | `timelockDurationSeconds=0` reverts (`TxRecoveryNotConfigured`) | `[N]` | P0 |
| LOTR-VRATOR-4 | Configured but disabled reverts (`TxRecoveryNotEnabled`) | `[N]` | P0 |
| LOTR-VRATOR-5 | Pending enable (not finalized yet) still reverts (`TxRecoveryNotEnabled`) | `[E]` | P0 |
| LOTR-VRATOR-6 | Check precedence: not-configured check runs before not-enabled check | `[U]` | P1 |

---

### 2.10 `isValidRecoverySignature`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-IVRS-1 | No configured recovery address returns false | `[N]` | P0 |
| LOTR-IVRS-2 | Valid EOA signature from configured recovery address returns true | `[U]` | P0 |
| LOTR-IVRS-3 | Valid EOA signature from wrong signer returns false | `[N]` | P0 |
| LOTR-IVRS-4 | Malformed signature bytes return false (no revert) | `[N]` | P0 |
| LOTR-IVRS-5 | EOA signature with non-65-byte length (including malformed payloads with `v=27`/`v=28`) returns false (no revert) | `[N]` | P0 |
| LOTR-IVRS-6 | EOA signature with malleable `s` (upper half-order) returns false (no revert) | `[N]` | P0 |
| LOTR-IVRS-7 | Unknown signature type byte returns false | `[N]` | P0 |
| LOTR-IVRS-8 | Valid ERC-1271 contract signature from configured recovery address returns true | `[U]` | P0 |
| LOTR-IVRS-9 | ERC-1271 contract signer returning invalid magic returns false | `[N]` | P0 |
| LOTR-IVRS-10 | ERC-1271 signer contract reverting on `isValidSignature` returns false | `[N]` | P0 |
| LOTR-IVRS-11 | ERC-1271 signature with truncated header (<23 bytes) returns false (no revert) | `[N]` | P0 |
| LOTR-IVRS-12 | ERC-1271 signature with declared inner length greater than available bytes returns false (no revert) | `[N]` | P0 |
| LOTR-IVRS-13 | ERC-1271 signer returning less than 32 bytes from `isValidSignature` returns false (no revert) | `[N]` | P0 |
| LOTR-IVRS-14 | Same signature over different hash returns false | `[N]` | P1 |
| LOTR-IVRS-15 | Result is independent of `isEnabled` state | `[U]` | P1 |

---

### 2.11 `enforceOnlyTxRecoveryAddress`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-EOTRA-1 | `msg.sender == recoveryAddress` succeeds | `[U]` | P0 |
| LOTR-EOTRA-2 | `msg.sender != recoveryAddress` reverts (`UnauthorizedTxRecoveryAddress`) | `[N]` | P0 |
| LOTR-EOTRA-3 | Error payload contains exact caller and expected addresses | `[U]` | P1 |
| LOTR-EOTRA-4 | With `recoveryAddress=0`, all callers revert and expected value is zero | `[E]` | P0 |

---

### 2.12 `isRecoveryEnabledForTxAndERC1271`

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-IRET-1 | Unconfigured state returns false | `[U]` | P3 |
| LOTR-IRET-2 | Configured but not enabled returns false | `[U]` | P3 |
| LOTR-IRET-3 | Pending enable (not finalized) returns false | `[U]` | P3 |
| LOTR-IRET-4 | Enabled state returns true | `[U]` | P3 |
| LOTR-IRET-5 | Disabled state returns false after previously being enabled | `[U]` | P3 |

---

### 2.13 `_clearPendingTxRecoveryInitTimelock` (private -> internal harness)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-CPTRI-1 | Sets `pendingRecoveryAddress` to zero | `[U]` | P1 |
| LOTR-CPTRI-2 | Sets `pendingTimelockDurationSeconds` to zero | `[U]` | P1 |
| LOTR-CPTRI-3 | Sets `pendingTimestamp` to zero | `[U]` | P1 |
| LOTR-CPTRI-4 | Idempotent when fields are already zero | `[E]` | P2 |

---

### 2.14 `_validateTxRecoveryNotConfiguredOrRevert` (private -> internal harness)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-VTNCR-1 | Both config fields zero succeeds | `[U]` | P1 |
| LOTR-VTNCR-2 | `recoveryAddress!=0` and `timelock=0` reverts (`TransactionRecoveryAlreadyConfigured`) | `[N]` | P1 |
| LOTR-VTNCR-3 | `recoveryAddress=0` and `timelock!=0` reverts (`TransactionRecoveryAlreadyConfigured`) | `[N]` | P1 |
| LOTR-VTNCR-4 | Both non-zero reverts (`TransactionRecoveryAlreadyConfigured`) | `[N]` | P1 |

---

### 2.15 `_validateTxRecoveryParamsOrRevert` (private -> internal harness)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOTR-VTPR-1 | Non-zero address + valid-range timelock succeeds | `[U]` | P1 |
| LOTR-VTPR-2 | Zero address reverts (`InvalidTxRecoveryAddress`) | `[N]` | P1 |
| LOTR-VTPR-3 | Timelock below min reverts (`InvalidTimelockDuration`) | `[N]` | P1 |
| LOTR-VTPR-4 | Timelock above max reverts (`InvalidTimelockDuration`) | `[N]` | P1 |
| LOTR-VTPR-5 | Timelock exactly min succeeds | `[E]` | P1 |
| LOTR-VTPR-6 | Timelock exactly max succeeds | `[E]` | P1 |

---

## File 3: Related Tx-Recovery Interaction Points

### 3.1 `LibOrganizationInitialization.initialize` (tx-recovery branch only)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOI-INIT-1 | Non-zero `transactionAndERC1271RecoveryAddress` + valid timelock configures tx recovery during org initialization | `[I]` | P1 |
| LOI-INIT-2 | Non-zero recovery address + tx-recovery timelock at min boundary configures successfully at initialization | `[E]` | P1 |
| LOI-INIT-3 | Non-zero recovery address + tx-recovery timelock at max boundary configures successfully at initialization | `[E]` | P1 |
| LOI-INIT-4 | `transactionAndERC1271RecoveryAddress=0` leaves tx recovery unconfigured (deferred setup) | `[I]` | P1 |
| LOI-INIT-5 | Deferred setup path does not auto-enable tx recovery | `[I]` | P1 |
| LOI-INIT-6 | Non-zero recovery address with invalid tx recovery timelock reverts organization initialization | `[N]` | P0 |
| LOI-INIT-7 | Invalid `adminOperationTimelockDurationSeconds` (including `0` / below min / above max) reverts organization initialization with `InvalidTimelockDuration` | `[N]` | P0 |
| LOI-INIT-8 | Cannot create an org with invalid admin-op timelock and then instantly finalize deferred tx-recovery initialization in the same block/window | `[I][S]` | P0 |
| LOI-INIT-9 | Zero recovery address does not require tx recovery timelock validation at init time | `[E]` | P1 |

---

### 3.2 `LibOrganizationAccountSignature._validateRecoverySignature` (private -> internal harness)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| LOAS-VRS-1 | Recovery signature path (`0x00`) returns invalid value (not revert) when tx recovery is unconfigured | `[N]` | P0 |
| LOAS-VRS-2 | Recovery signature path (`0x00`) returns magic value when tx recovery is enabled and signer is valid | `[I]` | P0 |
| LOAS-VRS-3 | Same valid signer returns invalid value when tx recovery is configured but disabled | `[I]` | P0 |
| LOAS-VRS-4 | After `disableTransactionAndERC1271Recovery`, previously-valid recovery signatures are rejected | `[S]` | P0 |
| LOAS-VRS-5 | Re-enabling tx recovery re-allows valid recovery signatures | `[I]` | P1 |
| LOAS-VRS-6 | Recovery signature path requires raw recovery signature only (no guardian signature, no policy proofs) | `[S]` | P0 |
| LOAS-VRS-7 | Recovery signature path returns invalid value (not revert) for malformed raw EOA signature length payloads | `[N]` | P0 |
| LOAS-VRS-8 | Recovery signature path returns invalid value (not revert) for malformed raw EOA signatures with high-`s` malleability | `[N]` | P0 |
| LOAS-VRS-9 | Recovery signature path returns invalid value (not revert) for malformed raw ERC-1271 signatures with truncated header | `[N]` | P0 |
| LOAS-VRS-10 | Recovery signature path returns invalid value (not revert) for malformed raw ERC-1271 signatures whose declared inner length exceeds available bytes | `[N]` | P0 |
| LOAS-VRS-11 | Recovery signature path returns invalid value (not revert) when ERC-1271 `isValidSignature` returns less than 32 bytes | `[N]` | P0 |

---

### 3.3 `AccountImplementation.executeTransaction` (recovery passthrough behavior)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| AI-ET-1 | Failed inner account call bubbles back through recovery execution path as revert | `[I]` | P0 |
| AI-ET-2 | Successful recovery execution produces account-level `TransactionExecuted` with `nonce=0` and `policyId=0` | `[I]` | P0 |
| AI-ET-3 | Direct external call to `Account.executeTransaction` from non-organization caller still reverts (`OnlyOrganization`) | `[S]` | P0 |

---

### 3.4 `AccountImplementation` private helpers (`_onlyOrganization`, `_execute`) (private -> internal harness)

| ID | Test Case | Type | Priority |
|---|---|---|---|
| AI-PH-1 | `_onlyOrganization` reverts `OnlyOrganization` for non-organization caller | `[N]` | P0 |
| AI-PH-2 | `_onlyOrganization` succeeds for the configured organization caller | `[U]` | P1 |
| AI-PH-3 | `_execute` returns `true` for successful low-level call and forwards exact `to` / `value` / `data` | `[U]` | P1 |
| AI-PH-4 | `_execute` returns `false` (without reverting by itself) when the inner call fails | `[U]` | P1 |

---

## 4. Full Lifecycle Integration Scenarios

| ID | Test Case | Type | Priority |
|---|---|---|---|
| TXR-INT-1 | Deferred setup lifecycle: deploy with zero tx recovery address -> initiate deferred init -> finalize -> initiate enable -> finalize enable -> execute recovery tx | `[I]` | P0 |
| TXR-INT-2 | Init-time setup lifecycle: deploy with tx recovery config -> enable -> execute recovery tx -> disable -> re-enable -> execute again | `[I]` | P0 |
| TXR-INT-3 | Emergency disable lifecycle: pending enable exists -> disable immediately -> finalize enable fails -> recovery remains disabled | `[I]` | P0 |
| TXR-INT-4 | Signature lifecycle: enable recovery -> `0x00` account signature accepted -> disable -> `0x00` rejected -> re-enable -> accepted again | `[I]` | P0 |
| TXR-INT-5 | Tx recovery and guardian recovery can operate independently without cross-state corruption | `[I]` | P0 |
| TXR-INT-6 | Guardian cannot call tx-recovery-only entrypoints and tx recovery address cannot call guardian-only entrypoints | `[S]` | P0 |
| TXR-INT-7 | Stale admin signatures for deferred finalize/cancel fail if pending values changed | `[S]` | P0 |
| TXR-INT-8 | Recovery flow bypasses guardian/policy execution path but still enforces organization-account ownership | `[S]` | P0 |
| TXR-INT-9 | Recovery execution cannot be used to perform guardian-only Organization operations via account call chaining | `[S]` | P0 |
| TXR-INT-10 | Recovery -> account -> organization call chain targeting `modifyAdmins` reverts and leaves admin set + voting threshold unchanged | `[S]` | P0 |
| TXR-INT-11 | Recovery -> account -> organization call chain targeting `modifyMembers` reverts and leaves membership/admin status unchanged | `[S]` | P0 |
| TXR-INT-12 | Recovery -> account -> organization call chain targeting `setPoliciesMerkleLeaf` reverts and leaves policy merkle root/state unchanged | `[S]` | P0 |
| TXR-INT-13 | Recovery -> account -> organization call chain targeting tx-recovery management entrypoints (`disable` / `initiateEnable` / `finalizeEnable`) reverts and leaves tx-recovery state unchanged | `[S]` | P0 |
| TXR-INT-14 | Full Organization selector-matrix integration (`to=organization`) from recovery execution reverts for every state-changing (non-view) selector and leaves all Organization/Account/Recovery state unchanged | `[I][S]` | P0 |
| TXR-INT-15 | Full Account selector-matrix integration (`to=account`) from recovery execution reverts for every state-changing (non-view) selector and leaves all Organization/Account/Recovery state unchanged | `[I][S]` | P0 |

---

## 5. Fuzz / Property Tests

| ID | Test Case | Type | Priority |
|---|---|---|---|
| TXR-FZ-1 | Fuzz valid non-zero recovery addresses + valid timelocks: initialization always succeeds | `[F]` | P1 |
| TXR-FZ-2 | Fuzz out-of-range timelocks: initialization and deferred-init initiation always revert | `[F]` | P1 |
| TXR-FZ-3 | Fuzz timestamps before enable-finalize timestamp: finalize always reverts | `[F]` | P1 |
| TXR-FZ-4 | Fuzz timestamps at/after enable-finalize timestamp: finalize succeeds when pending exists | `[F]` | P1 |
| TXR-FZ-5 | Fuzz arbitrary signature bytes/hashes for `isValidRecoverySignature`: function never reverts | `[F]` | P0 |
| TXR-FZ-6 | Fuzz random non-recovery callers across all only-tx-recovery entrypoints: always revert with unauthorized error | `[F]` | P0 |
| TXR-FZ-7 | Fuzz random `to/value/data` for successful recovery execution on test accounts: forwarded calldata/value are exact | `[F]` | P1 |
| TXR-FZ-8 | Fuzz Organization selector sweep with random calldata/value via recovery (`to=organization`) always reverts for every state-changing (non-view) selector | `[F][S]` | P0 |
| TXR-FZ-9 | Fuzz Account selector sweep with random calldata/value via recovery (`to=account`) always reverts for every state-changing (non-view) selector | `[F][S]` | P0 |
| TXR-FZ-11 | Fuzz repeated enable/disable cycles: config remains immutable and transitions remain legal | `[F]` | P1 |
| TXR-FZ-12 | Fuzz mixed enable/finalize/disable sequences: any `isEnabled=true` state always has non-zero config and zero pending-enable timestamp | `[F]` | P1 |

---

## 6. Invariants

| ID | Invariant | Priority |
|---|---|---|
| TXR-INV-1 | Only tx recovery address can call tx-recovery-protected state-changing entrypoints | P0 |
| TXR-INV-2 | Tx recovery config (`recoveryAddress`, `timelockDurationSeconds`) is write-once after first successful initialization | P0 |
| TXR-INV-3 | `isEnabled` transitions to `true` only through finalize-enable path | P0 |
| TXR-INV-4 | `isEnabled` transitions to `false` only through disable path (or stays false from initialization) | P0 |
| TXR-INV-5 | If `isEnabled == true`, then `recoveryAddress != address(0)`, `timelockDurationSeconds != 0`, and `pendingEnableTimestamp == 0` | P0 |
| TXR-INV-6 | If `pendingEnableTimestamp != 0`, then `isEnabled` must be false | P0 |
| TXR-INV-7 | If `pendingEnableTimestamp != 0`, then tx recovery config fields (`recoveryAddress`,`timelockDurationSeconds`) are both non-zero | P0 |
| TXR-INV-8 | After any successful disable, `pendingEnableTimestamp == 0` | P0 |
| TXR-INV-9 | If `pendingInit.pendingTimestamp == 0`, then pending init address and timelock are also zero | P0 |
| TXR-INV-10 | If tx recovery config is set, deferred-init pending fields remain cleared (no configured+pending-init overlap) | P0 |
| TXR-INV-11 | Recovery transaction execution never mutates tx recovery config/pending fields | P0 |
| TXR-INV-12 | Any tx-recovery-driven account call chain attempting `modifyAdmins` cannot mutate admin set or voting threshold | P0 |
| TXR-INV-13 | Any tx-recovery-driven account call chain attempting `modifyMembers` cannot mutate member/admin membership mappings | P0 |
| TXR-INV-14 | Any tx-recovery-driven account call chain attempting `setPoliciesMerkleLeaf` cannot mutate policy merkle root or policy config state | P0 |
| TXR-INV-15 | Any tx-recovery-driven account call chain attempting tx-recovery management entrypoints cannot mutate tx-recovery config/enable/pending state | P0 |
| TXR-INV-16 | While `executeRecoveryAccountTransaction` is in-flight, no reentrant path can successfully enter any state-changing (non-view) Organization function | P0 |
| TXR-INV-17 | While `executeRecoveryAccountTransaction` is in-flight, no reentrant path can successfully enter any state-changing (non-view) Account function | P0 |
| TXR-INV-18 | For any reentrancy attempt via `to=organization` or `to=account`, end-of-tx Organization/Account/TxRecovery state equals pre-call snapshot | P0 |
| TXR-INV-19 | `validateRecoveryAccountTransactionAllowedOrRevert` must revert whenever `isEnabled == false` | P0 |
| TXR-INV-20 | Tx recovery state transitions never modify guardian recovery state | P0 |
| TXR-INV-21 | Any successful recovery execution uses `nonce=0` and `policyId=0` | P0 |
