# 07 — Account Transaction Test Plan

**Files Under Test:**
- `src/organization/base/OrganizationAccountTransactionBase.sol`
- `src/organization/libraries/LibOrganizationAccountTransaction.sol`
- `src/account/AccountImplementation.sol`

**Private Function Testability Plan (Global):**
All `private` functions in the files under test will be refactored to `internal` for testing and exposed via test harness contracts.

| File | Private functions to convert to `internal` for harness testing |
|---|---|
| `OrganizationAccountTransactionBase.sol` | None |
| `LibOrganizationAccountTransaction.sol` | `_validateAndUpdateRateLimitOrRevert`, `_validateAutoApproveRejectionOrRevert`, `_validateManualConfirmationOrRevert`, `_computeInitiatorHashFromParams`, `_computeReviewHashFromParams` |
| `AccountImplementation.sol` | `_execute`, `_onlyOrganization` |


---

## File 1: OrganizationAccountTransactionBase.sol

### 1.1 `executeAccountTransaction`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OATB-EAT-1 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| OATB-EAT-2 | Account not deployed by this organization — reverts `AccountNotDeployedByOrganization` | [N] | P0 |
| OATB-EAT-3 | Nonce computed deterministically from `(account, to, value, keccak256(data), policyId, salt)` | [U] | P0 |
| OATB-EAT-4 | Nonce consumed BEFORE validation and external call (CEI pattern) | [S] | P0 |
| OATB-EAT-5 | Previously used nonce — reverts (replay protection) | [S] | P0 |
| OATB-EAT-6 | Delegates to `validateTransactionApprovalOrRevert` for policy validation | [U] | P0 |
| OATB-EAT-7 | Emits `AccountTransactionExecuted` event with correct `(account, to, value, data, nonce, policyId)` | [EV] | P1 |
| OATB-EAT-8 | Emits `AccountTransactionExecuted` BEFORE calling `Account.executeTransaction` (CEI) | [S] | P0 |
| OATB-EAT-9 | Calls `IAccount.executeTransaction` with correct arguments | [U] | P0 |
| OATB-EAT-10 | Entire transaction reverts if `Account.executeTransaction` reverts (nonce consumption rolled back) | [S] | P0 |
| OATB-EAT-11 | Successful ETH transfer via Account — end-to-end | [I] | P0 |
| OATB-EAT-12 | Successful ERC-20 transfer via Account — end-to-end | [I] | P0 |
| OATB-EAT-13 | Successful contract interaction via Account — end-to-end | [I] | P0 |
| OATB-EAT-14 | Successful contract interaction via Account with `value > 0` (native token sent with calldata) — end-to-end | [I][E] | P0 |
| OATB-EAT-15 | End-to-end revert path: expired transaction via `executeAccountTransaction` reverts `TransactionExpired` | [I][N] | P0 |
| OATB-EAT-16 | End-to-end revert path: ManualApproval with insufficient review signatures via `executeAccountTransaction` reverts `InsufficientApprovals` | [I][N] | P0 |
| OATB-EAT-17 | **Desired Behavior:** pre-execution validation revert (bad proof/signature) does **not** permanently burn nonce; same params+salt can succeed after fixing inputs | [S] | P0 |
| OATB-EAT-18 | **Desired Behavior:** if `Account.executeTransaction` fails after rate-limit update step, all rate-limit state changes are rolled back with full tx revert | [S] | P0 |
| OATB-EAT-19 | **Desired Behavior:** identical `(account, to, value, data, policyId)` executes multiple times when using different salts and fresh signatures | [I][S] | P0 |

---

### 1.2 `rejectAccountTransaction`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OATB-RAT-1 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| OATB-RAT-2 | Account not deployed by this organization — reverts `AccountNotDeployedByOrganization` | [N] | P0 |
| OATB-RAT-3 | Nonce is identical to `executeAccountTransaction` with same params (shared nonce space) | [S] | P0 |
| OATB-RAT-4 | Nonce consumed before validation | [S] | P0 |
| OATB-RAT-5 | Previously used nonce — reverts (replay protection) | [S] | P0 |
| OATB-RAT-6 | Delegates to `validateTransactionRejectionOrRevert` for policy validation | [U] | P0 |
| OATB-RAT-7 | Emits `AccountTransactionRejected` event with correct `(account, to, value, data, nonce, policyId)` | [EV] | P1 |
| OATB-RAT-8 | Execute consumes nonce, then reject with same params — reverts (shared nonce space) | [S] | P0 |
| OATB-RAT-9 | Reject consumes nonce, then execute with same params — reverts (shared nonce space) | [S] | P0 |
| OATB-RAT-10 | **Desired Behavior:** validation revert does **not** permanently burn nonce; same params+salt can succeed after fixing inputs | [S] | P0 |

---

## File 2: LibOrganizationAccountTransaction.sol

> **Prerequisite:** The functions `_validateAndUpdateRateLimitOrRevert`, `_validateAutoApproveRejectionOrRevert`,
> `_validateManualConfirmationOrRevert`, `_computeInitiatorHashFromParams`, and `_computeReviewHashFromParams`
> are currently `private`. Convert them to `internal` and expose via a test harness for direct testing.

### 2.1 `validateTransactionApprovalOrRevert`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAT-VTAOR-1 | Expired transaction (`block.timestamp > expirationTimestamp`) — reverts `TransactionExpired` | [N] | P0 |
| LOAT-VTAOR-2 | Expiration at exactly `block.timestamp` — succeeds (strict `>` comparison) | [E] | P0 |
| LOAT-VTAOR-3 | Expiration at `block.timestamp - 1` — reverts `TransactionExpired` | [E] | P0 |
| LOAT-VTAOR-4 | Empty initiator signature (length 0) — reverts `InsufficientSignaturesLength` | [N] | P0 |
| LOAT-VTAOR-5 | Initiator hash computed with `isApproval=true` | [U] | P0 |
| LOAT-VTAOR-6 | Initiator signer recovered correctly from EOA signature | [U] | P0 |
| LOAT-VTAOR-7 | Initiator signer recovered correctly from ERC-1271 signature | [U] | P0 |
| LOAT-VTAOR-8 | Policy does not apply to transaction — reverts `PolicyDoesNotApply` | [N] | P0 |
| LOAT-VTAOR-9 | `TransactionType.Signatures` policy used for account transaction — reverts `PolicyDoesNotApply` | [N] | P0 |
| LOAT-VTAOR-10 | AutoApprove policy: succeeds without review signatures (no manual approval needed) | [U] | P0 |
| LOAT-VTAOR-11 | ManualApproval policy: delegates to `_validateManualConfirmationOrRevert` with `isApproval=true` | [U] | P0 |
| LOAT-VTAOR-12 | ManualApproval policy with empty review signatures — reverts `InsufficientApprovals` | [N] | P0 |
| LOAT-VTAOR-13 | Rate limit update called after approval validation for all policy types | [U] | P0 |
| LOAT-VTAOR-14 | Initiator not authorized by policy — reverts `PolicyDoesNotApply` (from `isTransactionAllowedByPolicy`) | [N] | P0 |
| LOAT-VTAOR-15 | **Desired Behavior:** unknown/invalid `PolicyType` value fails closed (reverts; never treated as implicit AutoApprove) | [S] | P0 |
| LOAT-VTAOR-16 | **Desired Behavior:** non-empty but invalid initiator signature (malformed/wrong signer/wrong hash) reverts | [N][S] | P0 |

---

### 2.2 `validateTransactionRejectionOrRevert`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAT-VTROR-1 | Expired transaction — reverts `TransactionExpired` | [N] | P0 |
| LOAT-VTROR-2 | Expiration at exactly `block.timestamp` — succeeds (strict `>`) | [E] | P0 |
| LOAT-VTROR-3 | Expiration at `block.timestamp - 1` — reverts `TransactionExpired` | [E] | P0 |
| LOAT-VTROR-4 | Empty initiator signature — reverts `InsufficientSignaturesLength` | [N] | P0 |
| LOAT-VTROR-5 | Initiator hash computed with `isApproval=true` (original approval signature used) | [S] | P0 |
| LOAT-VTROR-6 | Initiator signer recovered correctly from EOA signature (rejection flow) | [U] | P0 |
| LOAT-VTROR-7 | Initiator signer recovered correctly from ERC-1271 signature (rejection flow) | [U] | P0 |
| LOAT-VTROR-8 | Policy does not apply — reverts `PolicyDoesNotApply` | [N] | P0 |
| LOAT-VTROR-9 | AutoApprove policy — delegates to `_validateAutoApproveRejectionOrRevert` | [U] | P0 |
| LOAT-VTROR-10 | ManualApproval policy — delegates to `_validateManualConfirmationOrRevert` with `isApproval=false` | [U] | P0 |
| LOAT-VTROR-11 | Function is `view` — no state changes (rate limits NOT updated on rejection) | [U] | P1 |
| LOAT-VTROR-12 | **Desired Behavior:** unknown/invalid `PolicyType` value fails closed (reverts; cannot silently skip checks) | [S] | P0 |
| LOAT-VTROR-13 | **Desired Behavior:** non-empty but invalid initiator signature (malformed/wrong signer/wrong hash) reverts | [N][S] | P0 |

---

### 2.3 `_validateAndUpdateRateLimitOrRevert`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAT-VAURLOR-1 | `RateLimitType != TimeInterval` — returns without checking (no-op) | [U] | P0 |
| LOAT-VAURLOR-2 | `TransactionType.TokenTransfers`: `usageAmount = extractTransferAmount(data, value)` | [U] | P0 |
| LOAT-VAURLOR-3 | Non-TokenTransfers (`ContractInteractions`): `usageAmount = 1` | [U] | P0 |
| LOAT-VAURLOR-4 | Destination for rate-limit key is derived via `getActualDestination(to, data, value)` | [U] | P0 |
| LOAT-VAURLOR-5 | `getActualDestination` (native transfer): returns `to` when `data` is empty | [U] | P0 |
| LOAT-VAURLOR-6 | `getActualDestination` (ERC-20 transfer): returns recipient parsed from calldata (not token contract `to`) | [U] | P0 |
| LOAT-VAURLOR-7 | `getActualDestination` (contract interaction): returns `to` for non-token-transfer calldata | [U] | P0 |
| LOAT-VAURLOR-8 | `checkAndUpdateRateLimit` returns false — reverts `RateLimitExceeded(policyId)` | [N] | P0 |
| LOAT-VAURLOR-9 | `checkAndUpdateRateLimit` returns true — succeeds, usage updated in storage | [U] | P0 |
| LOAT-VAURLOR-10 | After hitting `timeIntervalLimit` in current window, advancing to the next window allows usage again for the same `(policyId, account, destination, initiator)` | [U][E] | P0 |
| LOAT-VAURLOR-11 | Native ETH transfer: `extractTransferAmount` uses `value` parameter (data is empty) | [U] | P0 |
| LOAT-VAURLOR-12 | ERC-20 transfer: `extractTransferAmount` reads amount from calldata | [U] | P0 |
| LOAT-VAURLOR-13 | **Desired Behavior:** `TransactionType.Any` with rate limiting enabled uses count-based accounting (`usageAmount = 1`) even when tx shape is token transfer | [U][S] | P0 |

---

### 2.4 `_validateAutoApproveRejectionOrRevert`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAT-VAAROR-1 | Computes rejection hash with `isApproval=false` | [U] | P0 |
| LOAT-VAAROR-2 | Empty `reviewSignatures` (length 0) — reverts `TransactionRejectionNotAllowed` | [N] | P0 |
| LOAT-VAAROR-3 | Recovers rejection signer from `reviewSignatures` | [U] | P0 |
| LOAT-VAAROR-4 | Rejection signer not an authorized initiator for policy — reverts `TransactionRejectionNotAllowed` | [N] | P0 |
| LOAT-VAAROR-5 | Valid authorized initiator signs rejection — succeeds | [U] | P0 |
| LOAT-VAAROR-6 | Different authorized initiator (not the original) can also sign rejection | [U] | P0 |
| LOAT-VAAROR-7 | Approval signatures cannot be used for rejection (different hash: `isApproval=false` vs `true`) | [S] | P0 |

---

### 2.5 `_validateManualConfirmationOrRevert`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAT-VMCOR-1 | Calls `getRequiredApprovals` to determine threshold from policy | [U] | P0 |
| LOAT-VMCOR-2 | Review hash includes `initiatorSignature` (binding approvals to specific request) | [S] | P0 |
| LOAT-VMCOR-3 | `isApproval=true` for approval flow — review hash uses approval flag | [U] | P0 |
| LOAT-VMCOR-4 | `isApproval=false` for rejection flow — review hash uses rejection flag | [U] | P0 |
| LOAT-VMCOR-5 | `areApprovalsValid` returns false — reverts `InsufficientApprovals(required, 0)` | [N] | P0 |
| LOAT-VMCOR-6 | Non-empty but below-threshold valid review signatures (e.g., required `2`, provided `1`) — reverts `InsufficientApprovals(required, 0)` | [N] | P0 |
| LOAT-VMCOR-7 | Sufficient valid approvals — succeeds | [U] | P0 |
| LOAT-VMCOR-8 | Different initiator signatures produce different review hashes (binding property) | [S] | P0 |
| LOAT-VMCOR-9 | Duplicate or out-of-order reviewer signers fail closed — reverts `InsufficientApprovals(required, 0)` | [N] | P0 |
| LOAT-VMCOR-10 | Unauthorized reviewer signer fails closed — reverts `InsufficientApprovals(required, 0)` | [N] | P0 |
| LOAT-VMCOR-11 | With `ApproverType.Group`, non-existent approver group fails closed — reverts `InsufficientApprovals(required, 0)` | [N] | P0 |

---

### 2.6 `_computeInitiatorHashFromParams`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAT-CIHFP-1 | Different organizations (`address(this)`) produce different hashes | [S] | P0 |
| LOAT-CIHFP-2 | Different accounts produce different hashes | [U] | P0 |
| LOAT-CIHFP-3 | Different `to` addresses produce different hashes | [U] | P0 |
| LOAT-CIHFP-4 | Different `value` amounts produce different hashes | [U] | P0 |
| LOAT-CIHFP-5 | Different `data` produces different hashes (`keccak256(data)` used) | [U] | P0 |
| LOAT-CIHFP-6 | Different `salt` values produce different hashes | [U] | P0 |
| LOAT-CIHFP-7 | Different `expirationTimestamp` values produce different hashes | [U] | P0 |
| LOAT-CIHFP-8 | Different `policyId` values produce different hashes | [U] | P0 |
| LOAT-CIHFP-9 | `isApproval=true` vs `isApproval=false` produce different hashes | [S] | P0 |
| LOAT-CIHFP-10 | Different `block.chainid` values produce different hashes | [S] | P0 |
| LOAT-CIHFP-11 | Uses `INITIATE_ACCOUNT_TRANSACTION_TYPEHASH` in struct hash | [U] | P1 |
| LOAT-CIHFP-12 | Deterministic: same inputs always produce same hash | [U][F] | P0 |
| LOAT-CIHFP-13 | Empty data → `keccak256("")` used in struct hash | [E] | P1 |
| LOAT-CIHFP-14 | Golden test: known inputs → known hash (precomputed off-chain) | [U] | P0 |

---

### 2.7 `_computeReviewHashFromParams`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOAT-CRHFP-1 | Organization binding: different organizations (`address(this)`) produce different review hashes | [S] | P0 |
| LOAT-CRHFP-2 | Different accounts produce different review hashes | [U] | P0 |
| LOAT-CRHFP-3 | Different `to` addresses produce different review hashes | [U] | P0 |
| LOAT-CRHFP-4 | Different `value` amounts produce different review hashes | [U] | P0 |
| LOAT-CRHFP-5 | Different `data` produces different review hashes (`keccak256(data)` used) | [U] | P0 |
| LOAT-CRHFP-6 | Different `salt` values produce different review hashes | [U] | P0 |
| LOAT-CRHFP-7 | Different `expirationTimestamp` values produce different review hashes | [U] | P0 |
| LOAT-CRHFP-8 | Different `policyId` values produce different review hashes | [U] | P0 |
| LOAT-CRHFP-9 | Different `block.chainid` values produce different review hashes | [S] | P0 |
| LOAT-CRHFP-10 | Additionally includes `keccak256(initiatorSignature)` | [S] | P0 |
| LOAT-CRHFP-11 | Different initiator signatures → different review hashes | [S] | P0 |
| LOAT-CRHFP-12 | Uses `REVIEW_ACCOUNT_TRANSACTION_TYPEHASH` (distinct from initiator typehash) | [U] | P1 |
| LOAT-CRHFP-13 | `isApproval=true` vs `isApproval=false` → different hashes | [F][S] | P0 |
| LOAT-CRHFP-14 | Golden test: known inputs → known hash (precomputed off-chain) | [U] | P0 |

---

## File 3: AccountImplementation.sol

> **Prerequisite:** `_execute` and `_onlyOrganization` are currently `private`.
> Convert to `internal` and create a test contract inheriting from `AccountImplementation`
> to expose each via a public wrapper.

### 3.1 `receive()`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| AI-RCV-1 | Accepts ETH from anyone | [U][F] | P0 |
| AI-RCV-2 | Emits `MLSWalletAccountNativeTokenReceived(sender, value)` with correct parameters | [EV] | P1 |
| AI-RCV-3 | Zero-value ETH transfer — still emits event | [E] | P1 |

---

### 3.2 `executeTransaction`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| AI-ET-1 | Non-organization caller — reverts `OnlyOrganization` | [N] | P0 |
| AI-ET-2 | Different organization caller (not this account's bound organization/beacon organization) — reverts `OnlyOrganization` | [N][S] | P0 |
| AI-ET-3 | Successful call (`_execute` returns true) — emits `TransactionExecuted` event | [U] | P0 |
| AI-ET-4 | Failed call (`_execute` returns false) — reverts `TransactionExecutionFailed` | [N] | P0 |
| AI-ET-5 | ETH value forwarded correctly to target | [U] | P0 |
| AI-ET-6 | Calldata forwarded correctly to target contract | [U] | P0 |
| AI-ET-7 | Emits `TransactionExecuted` with correct `(to, value, data, nonce, policyId)` | [EV] | P1 |

---

### 3.3 `getOrganizationAddress`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| AI-GOA-1 | Returns the correct organization address from storage | [U] | P3 |
| AI-GOA-2 | Callable by anyone (no access restriction) | [U] | P3 |

---

### 3.4 `isValidSignature` (ERC-1271)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| AI-IVS-1 | Delegates to `Organization.isValidSignatureForAccount(address(this), hash, signature)` | [U] | P0 |
| AI-IVS-2 | Returns ERC-1271 magic value when Organization approves | [U] | P0 |
| AI-IVS-3 | Returns non-magic value when Organization rejects | [N] | P0 |
| AI-IVS-4 | Fuzz: `isValidSignature` is callable by anyone (no access restriction on caller) | [F] | P0 |

---

### 3.5 `_execute`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| AI-EXE-1 | Successful call returns `true` | [U] | P0 |
| AI-EXE-2 | Failed call (target reverts) returns `false` (no revert propagation) | [U] | P0 |
| AI-EXE-3 | Call to EOA with no code — returns `true` (CALL succeeds for EOAs) | [E] | P0 |
| AI-EXE-4 | ETH value forwarded correctly to target | [U] | P0 |
| AI-EXE-5 | Calldata forwarded correctly to target contract | [U] | P0 |
| AI-EXE-6 | Gas parameter respected — does not forward more gas than specified | [E] | P1 |
| AI-EXE-7 | Empty data with value > 0 — native ETH transfer succeeds | [U] | P0 |
| AI-EXE-8 | Return data from target is not captured (assembly output size = 0) | [E] | P1 |
| AI-EXE-9 | **Desired Behavior:** execution is CALL-only (no delegatecall semantics); target cannot mutate Account storage context as delegatecall would | [S] | P0 |

---

### 3.6 `_onlyOrganization`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| AI-OO-1 | `msg.sender == organization` address — no revert | [U] | P0 |
| AI-OO-2 | `msg.sender != organization` address — reverts `OnlyOrganization` | [N] | P0 |
| AI-OO-3 | Different organization caller (not this account's bound organization/beacon organization) — reverts `OnlyOrganization` | [N][S] | P0 |
| AI-OO-4 | `msg.sender == address(0)` — reverts `OnlyOrganization` | [E] | P0 |

---

## 4. Fuzz Tests

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| AT-FZ-1 | Fuzz: Random valid transactions with AutoApprove policy — execute successfully | [F] | P0 |
| AT-FZ-2 | Fuzz: Random expiration timestamps — future pass, past fail | [F] | P0 |
| AT-FZ-3 | Fuzz: Random salt values produce unique nonces | [F] | P1 |
| AT-FZ-4 | Fuzz: Random transaction data → deterministic EIP-712 hashes | [F] | P0 |
| AT-FZ-5 | Fuzz: Random initiator signatures → different review hashes (binding property) | [F][S] | P0 |
| AT-FZ-6 | Fuzz: Random native ETH, ERC-20, and contract-interaction tx shapes — rate limit destination and usage computed correctly | [F] | P0 |
| AT-FZ-7 | Fuzz: Random ManualApproval threshold counts — insufficient signers always rejected | [F] | P0 |
| AT-FZ-8 | Fuzz: Random `TxParams` fields — changing any single field always changes initiator hash | [F] | P0 |
| AT-FZ-9 | Fuzz: Random `TxParams` + initiator signature — changing any field changes review hash | [F] | P0 |
| AT-FZ-10 | Fuzz: Random accounts — non-org accounts always rejected with `AccountNotDeployedByOrganization` | [F] | P0 |
| AT-FZ-11 | Fuzz: Random policy types — rejection routed to correct handler (AutoApprove vs ManualApproval) | [F] | P1 |

---

## 5. Invariant Tests

| ID | Invariant | Priority |
|---|-----------|----------|
| AT-INV-1 | **Nonce consumption**: Once a transaction nonce is consumed, it can never be reused for approval or rejection | P0 |
| AT-INV-2 | **Rate limit atomicity**: Rate limit usage either increases by exact amount or tx reverts — no partial updates | P0 |
| AT-INV-3 | **CEI ordering**: Nonce consumed before external call — during reentrancy nonce is already used | P0 |
| AT-INV-4 | **Shared nonce space**: `executeAccountTransaction` and `rejectAccountTransaction` produce the same nonce for the same `(account, to, value, data, policyId, salt)` | P0 |
| AT-INV-5 | **Approval/rejection hash separation**: `isApproval=true` and `isApproval=false` always produce different initiator hashes for the same transaction | P0 |
| AT-INV-6 | **Organization binding**: Initiator hash always includes `address(this)` — signatures from one organization cannot be replayed on another | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| `executeAccountTransaction` | 19 | P0 |
| `rejectAccountTransaction` | 10 | P0 |
| `validateTransactionApprovalOrRevert` | 16 | P0 |
| `validateTransactionRejectionOrRevert` | 13 | P0 |
| `_validateAndUpdateRateLimitOrRevert` | 13 | P0 |
| `_validateAutoApproveRejectionOrRevert` | 7 | P0 |
| `_validateManualConfirmationOrRevert` | 11 | P0 |
| `_computeInitiatorHashFromParams` | 14 | P0-P1 |
| `_computeReviewHashFromParams` | 14 | P0-P1 |
| `receive()` | 3 | P0-P1 |
| `executeTransaction` | 7 | P0-P1 |
| `getOrganizationAddress` | 2 | P3 |
| `isValidSignature` | 4 | P0 |
| `_execute` | 9 | P0-P1 |
| `_onlyOrganization` | 4 | P0 |
| Fuzz tests | 11 | P0-P1 |
| Invariant tests | 6 | P0 |
| **Total** | **149** | |
