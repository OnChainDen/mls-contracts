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

| Test Case | Type | Priority |
|---|---|---|
| Non-tx-recovery caller reverts via `onlyTxRecoveryAddress` | `[N]` | P0 |
| Guardian caller also reverts (role isolation) | `[S]` | P0 |
| Authorized tx-recovery caller reaches library flow successfully | `[U]` | P1 |
| Library revert bubbles when tx recovery is not configured (`TxRecoveryNotConfigured`) | `[N]` | P0 |
| Library revert bubbles when recovery already enabled (`TxRecoveryAlreadyEnabled`) | `[N]` | P1 |
| Library revert bubbles when enable already pending (`TxRecoveryEnableAlreadyPending`) | `[N]` | P1 |

---

### 1.2 `finalizeEnableTransactionAndERC1271Recovery`

| Test Case | Type | Priority |
|---|---|---|
| Non-tx-recovery caller reverts via `onlyTxRecoveryAddress` | `[N]` | P0 |
| No pending enable reverts (`NoTxRecoveryEnablePending`) | `[N]` | P1 |
| Before timelock expiry reverts (`TimelockNotExpired`) | `[N]` | P1 |
| At exact timelock timestamp succeeds | `[E]` | P1 |
| Success path enables recovery and clears pending timestamp | `[U]` | P1 |
| Second finalize attempt reverts after successful finalize | `[N]` | P1 |

---

### 1.3 `cancelEnableTransactionAndERC1271Recovery`

| Test Case | Type | Priority |
|---|---|---|
| Non-tx-recovery caller reverts via `onlyTxRecoveryAddress` | `[N]` | P0 |
| No pending enable reverts (`NoTxRecoveryEnablePending`) | `[N]` | P1 |
| Pending enable is cleared on success | `[U]` | P1 |
| Cancel works even if pending enable timelock has already expired (before finalize) | `[E]` | P1 |
| Cancel does not enable recovery | `[U]` | P1 |

---

### 1.4 `disableTransactionAndERC1271Recovery`

| Test Case | Type | Priority |
|---|---|---|
| Non-tx-recovery caller reverts via `onlyTxRecoveryAddress` | `[N]` | P0 |
| When enabled, disable immediately sets `isEnabled=false` | `[U]` | P0 |
| Disable clears any pending enable request | `[S]` | P0 |
| Disable is idempotent when already disabled (no revert) | `[E]` | P2 |
| After disable, recovery transaction execution path is blocked (`TxRecoveryNotEnabled`) | `[S]` | P0 |

---

### 1.5 `executeRecoveryAccountTransaction`

| Test Case | Type | Priority |
|---|---|---|
| Non-tx-recovery caller reverts via `onlyTxRecoveryAddress` | `[N]` | P0 |
| Recovery not configured reverts (`TxRecoveryNotConfigured`) | `[N]` | P0 |
| Recovery configured but not enabled reverts (`TxRecoveryNotEnabled`) | `[N]` | P0 |
| Account not deployed by organization reverts (`AccountNotDeployedByOrganization`) | `[N]` | P0 |
| Successful call emits `RecoveryAccountTransactionExecuted(account,to,value,data)` | `[EV]` | P1 |
| Forwards exact `account`, `to`, `value`, `data` to `IAccount.executeTransaction` | `[U]` | P0 |
| Always calls account with `nonce=0` and `policyId=0` | `[S]` | P0 |
| ETH transfer via recovery execution succeeds when account has balance | `[I]` | P0 |
| Contract-call via recovery execution succeeds | `[I]` | P0 |
| If account execution reverts, outer call reverts and no event/log persists | `[N]` | P0 |
| Validation order is preserved: recovery-enabled check happens before account-deployed check | `[U]` | P1 |
| Recovery execution does not mutate tx recovery config fields | `[S]` | P1 |

---

### 1.6 `initiateInitializeTransactionAndERC1271Recovery`

| Test Case | Type | Priority |
|---|---|---|
| Non-guardian caller reverts via `onlyGuardian` | `[N]` | P0 |
| Insufficient admin authorization reverts | `[N]` | P0 |
| Signatures built with `isApproval=false` are rejected | `[S]` | P0 |
| Signatures for wrong `OperationType` are rejected | `[S]` | P0 |
| Valid auth requires `OperationType.InitiateInitializeTransactionRecovery` with `isApproval=true` | `[U]` | P1 |
| Auth `operationData` must be exact `abi.encode(recoveryAddress,timelockDurationSeconds)` | `[U]` | P1 |
| Signatures for mismatched `operationData` (`recoveryAddress`,`timelock`) are rejected | `[S]` | P0 |
| Replay with consumed nonce fails | `[S]` | P0 |
| Valid auth path delegates and creates pending init state | `[U]` | P1 |
| Library revert bubbles when already configured (`TransactionRecoveryAlreadyConfigured`) | `[N]` | P0 |
| Library revert bubbles when deferred init already pending (`TxRecoveryInitializationAlreadyPending`) | `[N]` | P1 |
| Invalid recovery address/timelock bubbles from library validation | `[N]` | P1 |

---

### 1.7 `finalizeInitializeTransactionAndERC1271Recovery`

| Test Case | Type | Priority |
|---|---|---|
| Non-guardian caller reverts via `onlyGuardian` | `[N]` | P0 |
| Insufficient admin authorization reverts | `[N]` | P0 |
| Signatures built with `isApproval=false` are rejected | `[S]` | P0 |
| Signatures for wrong `OperationType` are rejected | `[S]` | P0 |
| Valid auth requires `OperationType.FinalizeInitializeTransactionRecovery` with `isApproval=true` | `[U]` | P1 |
| Auth uses pending values from storage; stale signatures for old pending values fail | `[S]` | P0 |
| Valid auth but no pending init reverts (`NoTxRecoveryInitializationPending`) | `[N]` | P1 |
| Valid auth before admin-op timelock expiry reverts (`TimelockNotExpired`) | `[N]` | P1 |
| At exact admin-op timelock expiry, finalize succeeds | `[E]` | P1 |
| Success writes config and clears pending init fields | `[U]` | P1 |
| Recovery remains disabled after finalize (enable flow still required) | `[U]` | P1 |
| Second finalize attempt reverts after success | `[N]` | P1 |

---

### 1.8 `cancelInitializeTransactionAndERC1271Recovery`

| Test Case | Type | Priority |
|---|---|---|
| Non-guardian caller reverts via `onlyGuardian` | `[N]` | P0 |
| Insufficient admin authorization reverts | `[N]` | P0 |
| Signatures built with `isApproval=false` are rejected | `[S]` | P0 |
| Signatures for wrong `OperationType` are rejected | `[S]` | P0 |
| Valid auth requires `OperationType.CancelInitializeTransactionRecovery` with `isApproval=true` | `[U]` | P1 |
| Auth uses pending values from storage; stale signatures for old pending values fail | `[S]` | P0 |
| Valid auth but no pending init reverts (`NoTxRecoveryInitializationPending`) | `[N]` | P1 |
| Success clears all pending init fields | `[U]` | P1 |
| Cancel allowed both before and after pending timestamp (no expiry requirement) | `[E]` | P1 |
| After cancel, recovery config remains unconfigured | `[U]` | P1 |
| Re-initiation is possible after cancel | `[U]` | P1 |

---

### 1.9 `getTxRecoveryState`

| Test Case | Type | Priority |
|---|---|---|
| Returns full `TxRecoveryState` snapshot | `[U]` | P3 |
| Callable by any address (no access control) | `[U]` | P3 |
| Returns zeroed state before any tx recovery setup | `[U]` | P3 |
| Reflects pending enable state during enable flow | `[U]` | P3 |
| Reflects pending deferred-init state during deferred init flow | `[U]` | P3 |
| Reflects enabled and disabled transitions correctly | `[U]` | P3 |

---

## File 2: `LibOrganizationTxRecovery.sol`

> Private helper functions included in this plan:
> `_clearPendingTxRecoveryInitTimelock`, `_validateTxRecoveryNotConfiguredOrRevert`,
> `_validateTxRecoveryParamsOrRevert`.
> For test implementation, expose them as `internal` through a harness.

### 2.1 `initializeTxRecovery`

| Test Case | Type | Priority |
|---|---|---|
| Valid params set `recoveryAddress` | `[U]` | P1 |
| Valid params set `timelockDurationSeconds` | `[U]` | P1 |
| Initialization sets `isEnabled=false` | `[U]` | P1 |
| Clean initialization leaves pending fields zero | `[U]` | P1 |
| `recoveryAddress=address(0)` reverts (`InvalidTxRecoveryAddress`) | `[N]` | P1 |
| Timelock below min reverts (`InvalidTimelockDuration`) | `[N]` | P1 |
| Timelock above max reverts (`InvalidTimelockDuration`) | `[N]` | P1 |
| Timelock at min boundary succeeds | `[E]` | P1 |
| Timelock at max boundary succeeds | `[E]` | P1 |
| Any pre-existing config (`recoveryAddress!=0` or `timelock!=0`) reverts (`TransactionRecoveryAlreadyConfigured`) | `[N]` | P0 |

---

### 2.2 `initiateEnableTxRecovery`

| Test Case | Type | Priority |
|---|---|---|
| Valid state sets `pendingEnableTimestamp = block.timestamp + timelockDurationSeconds` | `[U]` | P1 |
| Emits `TxRecoveryEnableInitiated(canFinalizeAtTimestamp)` with expected timestamp | `[EV]` | P1 |
| `recoveryAddress=0` reverts (`TxRecoveryNotConfigured`) | `[N]` | P0 |
| `timelockDurationSeconds=0` reverts (`TxRecoveryNotConfigured`) | `[N]` | P0 |
| `isEnabled=true` reverts (`TxRecoveryAlreadyEnabled`) | `[N]` | P1 |
| Existing pending enable reverts (`TxRecoveryEnableAlreadyPending`) | `[N]` | P1 |
| `isEnabled` remains false after initiate | `[U]` | P1 |
| Check precedence: not-configured check runs before enabled/pending checks | `[U]` | P1 |

---

### 2.3 `finalizeEnableTxRecovery`

| Test Case | Type | Priority |
|---|---|---|
| No pending enable reverts (`NoTxRecoveryEnablePending`) | `[N]` | P1 |
| Before pending timestamp reverts (`TimelockNotExpired`) | `[N]` | P1 |
| At exact pending timestamp succeeds | `[E]` | P1 |
| After expiry succeeds | `[U]` | P1 |
| Success sets `isEnabled=true` | `[U]` | P1 |
| Success clears `pendingEnableTimestamp` | `[U]` | P1 |
| Emits `TxRecoveryEnableFinalized()` | `[EV]` | P1 |
| Recovery config fields remain unchanged by finalize | `[U]` | P1 |

---

### 2.4 `cancelEnableTxRecovery`

| Test Case | Type | Priority |
|---|---|---|
| No pending enable reverts (`NoTxRecoveryEnablePending`) | `[N]` | P1 |
| Pending enable is cleared on success | `[U]` | P1 |
| Emits `TxRecoveryEnableCancelled()` | `[EV]` | P1 |
| Cancel does not set `isEnabled=true` | `[U]` | P1 |
| Cancel allowed after pending timestamp has passed (before finalize) | `[E]` | P1 |
| Recovery config fields remain unchanged by cancel | `[U]` | P1 |

---

### 2.5 `disableTxRecovery`

| Test Case | Type | Priority |
|---|---|---|
| Immediately sets `isEnabled=false` when currently enabled | `[U]` | P0 |
| Clears `pendingEnableTimestamp` in all states | `[S]` | P0 |
| Emits `TxRecoveryDisabled()` | `[EV]` | P1 |
| Idempotent when already disabled (no revert) | `[E]` | P2 |
| Disabling during pending enable before expiry cancels pending enable | `[S]` | P0 |
| Disabling during pending enable after expiry (before finalize) still cancels pending enable | `[S]` | P0 |
| Recovery config (`recoveryAddress`,`timelockDurationSeconds`) remains unchanged | `[U]` | P1 |
| After disable, `validateRecoveryAccountTransactionAllowedOrRevert` reverts (`TxRecoveryNotEnabled`) | `[S]` | P0 |
| `isValidRecoverySignature` result remains independent of `isEnabled` (enabled check happens elsewhere) | `[U]` | P1 |

---

### 2.6 `initiateInitializeTxRecovery`

| Test Case | Type | Priority |
|---|---|---|
| Valid params set `pendingInit.pendingRecoveryAddress` | `[U]` | P1 |
| Valid params set `pendingInit.pendingTimelockDurationSeconds` | `[U]` | P1 |
| Valid params set `pendingInit.pendingTimestamp` based on admin-op timelock | `[U]` | P1 |
| Emits `TxRecoveryInitializationInitiated(recoveryAddress,timelock,canFinalizeAt)` | `[EV]` | P1 |
| Already configured reverts (`TransactionRecoveryAlreadyConfigured`) | `[N]` | P0 |
| Existing pending init reverts (`TxRecoveryInitializationAlreadyPending`) | `[N]` | P1 |
| Zero recovery address reverts (`InvalidTxRecoveryAddress`) | `[N]` | P1 |
| Timelock below min reverts (`InvalidTimelockDuration`) | `[N]` | P1 |
| Timelock above max reverts (`InvalidTimelockDuration`) | `[N]` | P1 |
| Timelock exactly at min boundary succeeds and stores pending init values | `[E]` | P1 |
| Timelock exactly at max boundary succeeds and stores pending init values | `[E]` | P1 |
| Active config and `isEnabled` are unchanged during initiate step | `[U]` | P1 |

---

### 2.7 `finalizeInitializeTxRecovery`

| Test Case | Type | Priority |
|---|---|---|
| No pending init reverts (`NoTxRecoveryInitializationPending`) | `[N]` | P1 |
| Before admin-op timelock expiry reverts (`TimelockNotExpired`) | `[N]` | P1 |
| At exact expiry succeeds | `[E]` | P1 |
| Success writes config using pending values | `[U]` | P1 |
| Success clears all pending init fields | `[U]` | P1 |
| Success emits `TxRecoveryInitializationFinalized(pendingAddress,pendingTimelock)` | `[EV]` | P1 |
| Success leaves `isEnabled=false` (enable flow still required) | `[U]` | P1 |
| After success, enable flow can be initiated and finalized normally | `[I]` | P1 |
| Atomicity: if downstream `initializeTxRecovery` reverts (e.g., unexpected pre-configured state), pending init remains unchanged | `[S]` | P0 |
| Atomicity: when such revert occurs, no finalization event is emitted | `[EV]` | P1 |

---

### 2.8 `cancelInitializeTxRecovery`

| Test Case | Type | Priority |
|---|---|---|
| No pending init reverts (`NoTxRecoveryInitializationPending`) | `[N]` | P1 |
| Clears `pendingInit.pendingRecoveryAddress` | `[U]` | P1 |
| Clears `pendingInit.pendingTimelockDurationSeconds` | `[U]` | P1 |
| Clears `pendingInit.pendingTimestamp` | `[U]` | P1 |
| Emits `TxRecoveryInitializationCancelled()` | `[EV]` | P1 |
| Active config remains unchanged by cancel | `[U]` | P1 |
| Re-initiation works after cancel | `[U]` | P1 |

---

### 2.9 `validateRecoveryAccountTransactionAllowedOrRevert`

| Test Case | Type | Priority |
|---|---|---|
| Configured and enabled succeeds (no revert) | `[U]` | P0 |
| `recoveryAddress=0` reverts (`TxRecoveryNotConfigured`) | `[N]` | P0 |
| `timelockDurationSeconds=0` reverts (`TxRecoveryNotConfigured`) | `[N]` | P0 |
| Configured but disabled reverts (`TxRecoveryNotEnabled`) | `[N]` | P0 |
| Pending enable (not finalized yet) still reverts (`TxRecoveryNotEnabled`) | `[E]` | P0 |
| Check precedence: not-configured check runs before not-enabled check | `[U]` | P1 |

---

### 2.10 `isValidRecoverySignature`

| Test Case | Type | Priority |
|---|---|---|
| No configured recovery address returns false | `[N]` | P0 |
| Valid EOA signature from configured recovery address returns true | `[U]` | P0 |
| Valid EOA signature from wrong signer returns false | `[N]` | P0 |
| Malformed signature bytes return false (no revert) | `[N]` | P0 |
| Unknown signature type byte returns false | `[N]` | P0 |
| Valid ERC-1271 contract signature from configured recovery address returns true | `[U]` | P0 |
| ERC-1271 contract signer returning invalid magic returns false | `[N]` | P0 |
| ERC-1271 signer contract reverting on `isValidSignature` returns false | `[N]` | P0 |
| Same signature over different hash returns false | `[N]` | P1 |
| Result is independent of `isEnabled` state | `[U]` | P1 |

---

### 2.11 `enforceOnlyTxRecoveryAddress`

| Test Case | Type | Priority |
|---|---|---|
| `msg.sender == recoveryAddress` succeeds | `[U]` | P0 |
| `msg.sender != recoveryAddress` reverts (`UnauthorizedTxRecoveryAddress`) | `[N]` | P0 |
| Error payload contains exact caller and expected addresses | `[U]` | P1 |
| With `recoveryAddress=0`, all callers revert and expected value is zero | `[E]` | P0 |

---

### 2.12 `isRecoveryEnabledForTxAndERC1271`

| Test Case | Type | Priority |
|---|---|---|
| Unconfigured state returns false | `[U]` | P3 |
| Configured but not enabled returns false | `[U]` | P3 |
| Pending enable (not finalized) returns false | `[U]` | P3 |
| Enabled state returns true | `[U]` | P3 |
| Disabled state returns false after previously being enabled | `[U]` | P3 |

---

### 2.13 `_clearPendingTxRecoveryInitTimelock` (private -> internal harness)

| Test Case | Type | Priority |
|---|---|---|
| Sets `pendingRecoveryAddress` to zero | `[U]` | P1 |
| Sets `pendingTimelockDurationSeconds` to zero | `[U]` | P1 |
| Sets `pendingTimestamp` to zero | `[U]` | P1 |
| Idempotent when fields are already zero | `[E]` | P2 |

---

### 2.14 `_validateTxRecoveryNotConfiguredOrRevert` (private -> internal harness)

| Test Case | Type | Priority |
|---|---|---|
| Both config fields zero succeeds | `[U]` | P1 |
| `recoveryAddress!=0` and `timelock=0` reverts (`TransactionRecoveryAlreadyConfigured`) | `[N]` | P1 |
| `recoveryAddress=0` and `timelock!=0` reverts (`TransactionRecoveryAlreadyConfigured`) | `[N]` | P1 |
| Both non-zero reverts (`TransactionRecoveryAlreadyConfigured`) | `[N]` | P1 |

---

### 2.15 `_validateTxRecoveryParamsOrRevert` (private -> internal harness)

| Test Case | Type | Priority |
|---|---|---|
| Non-zero address + valid-range timelock succeeds | `[U]` | P1 |
| Zero address reverts (`InvalidTxRecoveryAddress`) | `[N]` | P1 |
| Timelock below min reverts (`InvalidTimelockDuration`) | `[N]` | P1 |
| Timelock above max reverts (`InvalidTimelockDuration`) | `[N]` | P1 |
| Timelock exactly min succeeds | `[E]` | P1 |
| Timelock exactly max succeeds | `[E]` | P1 |

---

## File 3: Related Tx-Recovery Interaction Points

### 3.1 `LibOrganizationInitialization.initialize` (tx-recovery branch only)

| Test Case | Type | Priority |
|---|---|---|
| Non-zero `transactionAndERC1271RecoveryAddress` + valid timelock configures tx recovery during org initialization | `[I]` | P1 |
| Non-zero recovery address + tx-recovery timelock at min boundary configures successfully at initialization | `[E]` | P1 |
| Non-zero recovery address + tx-recovery timelock at max boundary configures successfully at initialization | `[E]` | P1 |
| `transactionAndERC1271RecoveryAddress=0` leaves tx recovery unconfigured (deferred setup) | `[I]` | P1 |
| Deferred setup path does not auto-enable tx recovery | `[I]` | P1 |
| Non-zero recovery address with invalid tx recovery timelock reverts organization initialization | `[N]` | P0 |
| Zero recovery address does not require tx recovery timelock validation at init time | `[E]` | P1 |

---

### 3.2 `LibOrganizationAccountSignature._validateRecoverySignature` (private -> internal harness)

| Test Case | Type | Priority |
|---|---|---|
| Recovery signature path (`0x00`) returns invalid value (not revert) when tx recovery is unconfigured | `[N]` | P0 |
| Recovery signature path (`0x00`) returns magic value when tx recovery is enabled and signer is valid | `[I]` | P0 |
| Same valid signer returns invalid value when tx recovery is configured but disabled | `[I]` | P0 |
| After `disableTransactionAndERC1271Recovery`, previously-valid recovery signatures are rejected | `[S]` | P0 |
| Re-enabling tx recovery re-allows valid recovery signatures | `[I]` | P1 |
| Recovery signature path requires raw recovery signature only (no guardian signature, no policy proofs) | `[S]` | P0 |
| Recovery signature path returns invalid value (not revert) for malformed raw recovery signature bytes | `[N]` | P0 |

---

### 3.3 `AccountImplementation.executeTransaction` (recovery passthrough behavior)

| Test Case | Type | Priority |
|---|---|---|
| Failed inner account call bubbles back through recovery execution path as revert | `[I]` | P0 |
| Successful recovery execution produces account-level `TransactionExecuted` with `nonce=0` and `policyId=0` | `[I]` | P0 |
| Direct external call to `Account.executeTransaction` from non-organization caller still reverts (`OnlyOrganization`) | `[S]` | P0 |

---

### 3.4 `AccountImplementation` private helpers (`_onlyOrganization`, `_execute`) (private -> internal harness)

| Test Case | Type | Priority |
|---|---|---|
| `_onlyOrganization` reverts `OnlyOrganization` for non-organization caller | `[N]` | P0 |
| `_onlyOrganization` succeeds for the configured organization caller | `[U]` | P1 |
| `_execute` returns `true` for successful low-level call and forwards exact `to` / `value` / `data` | `[U]` | P1 |
| `_execute` returns `false` (without reverting by itself) when the inner call fails | `[U]` | P1 |

---

## 4. Full Lifecycle Integration Scenarios

| Test Case | Type | Priority |
|---|---|---|
| Deferred setup lifecycle: deploy with zero tx recovery address -> initiate deferred init -> finalize -> initiate enable -> finalize enable -> execute recovery tx | `[I]` | P0 |
| Init-time setup lifecycle: deploy with tx recovery config -> enable -> execute recovery tx -> disable -> re-enable -> execute again | `[I]` | P0 |
| Emergency disable lifecycle: pending enable exists -> disable immediately -> finalize enable fails -> recovery remains disabled | `[I]` | P0 |
| Signature lifecycle: enable recovery -> `0x00` account signature accepted -> disable -> `0x00` rejected -> re-enable -> accepted again | `[I]` | P0 |
| Tx recovery and guardian recovery can operate independently without cross-state corruption | `[I]` | P0 |
| Guardian cannot call tx-recovery-only entrypoints and tx recovery address cannot call guardian-only entrypoints | `[S]` | P0 |
| Stale admin signatures for deferred finalize/cancel fail if pending values changed | `[S]` | P0 |
| Recovery flow bypasses guardian/policy execution path but still enforces organization-account ownership | `[S]` | P0 |
| Recovery execution cannot be used to perform guardian-only Organization operations via account call chaining | `[S]` | P0 |

---

## 5. Fuzz / Property Tests

| Test Case | Type | Priority |
|---|---|---|
| Fuzz valid non-zero recovery addresses + valid timelocks: initialization always succeeds | `[F]` | P1 |
| Fuzz out-of-range timelocks: initialization and deferred-init initiation always revert | `[F]` | P1 |
| Fuzz timestamps before enable-finalize timestamp: finalize always reverts | `[F]` | P1 |
| Fuzz timestamps at/after enable-finalize timestamp: finalize succeeds when pending exists | `[F]` | P1 |
| Fuzz arbitrary signature bytes/hashes for `isValidRecoverySignature`: function never reverts | `[F]` | P0 |
| Fuzz random non-recovery callers across all only-tx-recovery entrypoints: always revert with unauthorized error | `[F]` | P0 |
| Fuzz random `to/value/data` for successful recovery execution on test accounts: forwarded calldata/value are exact | `[F]` | P1 |
| Fuzz repeated enable/disable cycles: config remains immutable and transitions remain legal | `[F]` | P1 |
| Fuzz mixed enable/finalize/disable sequences: any `isEnabled=true` state always has non-zero config and zero pending-enable timestamp | `[F]` | P1 |

---

## 6. Invariants

| Invariant | Priority |
|---|---|
| Only tx recovery address can call tx-recovery-protected state-changing entrypoints | P0 |
| Tx recovery config (`recoveryAddress`, `timelockDurationSeconds`) is write-once after first successful initialization | P0 |
| `isEnabled` transitions to `true` only through finalize-enable path | P0 |
| `isEnabled` transitions to `false` only through disable path (or stays false from initialization) | P0 |
| If `isEnabled == true`, then `recoveryAddress != address(0)`, `timelockDurationSeconds != 0`, and `pendingEnableTimestamp == 0` | P0 |
| If `pendingEnableTimestamp != 0`, then `isEnabled` must be false | P0 |
| If `pendingEnableTimestamp != 0`, then tx recovery config fields (`recoveryAddress`,`timelockDurationSeconds`) are both non-zero | P0 |
| After any successful disable, `pendingEnableTimestamp == 0` | P0 |
| If `pendingInit.pendingTimestamp == 0`, then pending init address and timelock are also zero | P0 |
| If tx recovery config is set, deferred-init pending fields remain cleared (no configured+pending-init overlap) | P0 |
| Recovery transaction execution never mutates tx recovery config/pending fields | P0 |
| `validateRecoveryAccountTransactionAllowedOrRevert` must revert whenever `isEnabled == false` | P0 |
| Tx recovery state transitions never modify guardian recovery state | P0 |
| Any successful recovery execution uses `nonce=0` and `policyId=0` | P0 |
