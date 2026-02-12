# 08 — Account Transaction Test Plan

**Files Under Test:**
- `src/organization/base/OrganizationAccountTransactionBase.sol`
- `src/organization/libraries/LibOrganizationAccountTransaction.sol`
- `src/account/AccountImplementation.sol`
- `src/interfaces/organization/IOrganizationAccountTransaction.sol`
- `src/interfaces/IAccount.sol`

**Test File(s):** `test/OrganizationAccountTransactionBase.t.sol`, `test/LibOrganizationAccountTransaction.t.sol`, `test/AccountImplementation.t.sol`

---

## File 1: OrganizationAccountTransactionBase.sol

### 1.1 `executeAccountTransaction`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| 2 | Account not deployed by this organization — reverts `AccountNotDeployedByOrganization` | [N] | P0 |
| 3 | Nonce computed deterministically from `(account, to, value, keccak256(data), policyId, salt)` | [U] | P0 |
| 4 | Nonce consumed BEFORE validation and external call (CEI pattern) | [S] | P0 |
| 5 | Previously used nonce — reverts (replay protection) | [S] | P0 |
| 6 | Delegates to `validateTransactionApprovalOrRevert` for policy validation | [U] | P0 |
| 7 | Emits `AccountTransactionExecuted` event with correct `(account, to, value, data, nonce, policyId)` | [EV] | P1 |
| 8 | Emits `AccountTransactionExecuted` BEFORE calling `Account.executeTransaction` (CEI) | [S] | P0 |
| 9 | Calls `IAccount.executeTransaction` with correct arguments | [U] | P0 |
| 10 | Entire transaction reverts if `Account.executeTransaction` reverts (nonce consumption rolled back) | [S] | P0 |
| 11 | Successful ETH transfer via Account — end-to-end | [I] | P0 |
| 12 | Successful ERC-20 transfer via Account — end-to-end | [I] | P0 |
| 13 | Successful contract interaction via Account — end-to-end | [I] | P0 |

---

### 1.2 `rejectAccountTransaction`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 14 | Non-guardian caller — reverts (onlyGuardian modifier) | [N] | P0 |
| 15 | Account not deployed by this organization — reverts `AccountNotDeployedByOrganization` | [N] | P0 |
| 16 | Nonce is identical to `executeAccountTransaction` with same params (shared nonce space) | [S] | P0 |
| 17 | Nonce consumed before validation | [S] | P0 |
| 18 | Previously used nonce — reverts (replay protection) | [S] | P0 |
| 19 | Delegates to `validateTransactionRejectionOrRevert` for policy validation | [U] | P0 |
| 20 | Emits `AccountTransactionRejected` event with correct `(account, to, value, data, nonce, policyId)` | [EV] | P1 |
| 21 | Execute consumes nonce, then reject with same params — reverts (shared nonce space) | [S] | P0 |
| 22 | Reject consumes nonce, then execute with same params — reverts (shared nonce space) | [S] | P0 |

---

## File 2: LibOrganizationAccountTransaction.sol

> **Prerequisite:** The functions `_validateAndUpdateRateLimitOrRevert`, `_validateAutoApproveRejectionOrRevert`,
> `_validateManualConfirmationOrRevert`, `_computeInitiatorHashFromParams`, and `_computeReviewHashFromParams`
> are currently `private`. Convert them to `internal` and expose via a test harness for direct testing.

### 2.1 `validateTransactionApprovalOrRevert`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 23 | Expired transaction (`block.timestamp > expirationTimestamp`) — reverts `TransactionExpired` | [N] | P0 |
| 24 | Expiration at exactly `block.timestamp` — succeeds (strict `>` comparison) | [E] | P0 |
| 25 | Expiration at `block.timestamp - 1` — reverts `TransactionExpired` | [E] | P0 |
| 26 | Empty initiator signature (length 0) — reverts `InsufficientSignaturesLength` | [N] | P0 |
| 27 | Initiator hash computed with `isApproval=true` | [U] | P0 |
| 28 | Initiator signer recovered correctly from EOA signature | [U] | P0 |
| 29 | Initiator signer recovered correctly from ERC-1271 signature | [U] | P0 |
| 30 | Policy does not apply to transaction — reverts `PolicyDoesNotApply` | [N] | P0 |
| 31 | AutoApprove policy: succeeds without review signatures (no manual approval needed) | [U] | P0 |
| 32 | ManualApproval policy: delegates to `_validateManualConfirmationOrRevert` with `isApproval=true` | [U] | P0 |
| 33 | ManualApproval policy with empty review signatures — reverts `InsufficientApprovals` | [N] | P0 |
| 34 | Rate limit update called after approval validation for all policy types | [U] | P0 |
| 35 | Initiator not authorized by policy — reverts `PolicyDoesNotApply` (from `isTransactionAllowedByPolicy`) | [N] | P0 |

---

### 2.2 `validateTransactionRejectionOrRevert`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 36 | Expired transaction — reverts `TransactionExpired` | [N] | P0 |
| 37 | Expiration at exactly `block.timestamp` — succeeds (strict `>`) | [E] | P0 |
| 38 | Empty initiator signature — reverts `InsufficientSignaturesLength` | [N] | P0 |
| 39 | Initiator hash computed with `isApproval=true` (original approval signature used) | [S] | P0 |
| 40 | Policy does not apply — reverts `PolicyDoesNotApply` | [N] | P0 |
| 41 | AutoApprove policy — delegates to `_validateAutoApproveRejectionOrRevert` | [U] | P0 |
| 42 | ManualApproval policy — delegates to `_validateManualConfirmationOrRevert` with `isApproval=false` | [U] | P0 |
| 43 | Function is `view` — no state changes (rate limits NOT updated on rejection) | [U] | P1 |

---

### 2.3 `_validateAndUpdateRateLimitOrRevert`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 44 | `RateLimitType != TimeInterval` — returns without checking (no-op) | [U] | P0 |
| 45 | `TransactionType.TokenTransfers`: `usageAmount = extractTransferAmount(data, value)` | [U] | P0 |
| 46 | Non-TokenTransfers (`ContractInteractions`): `usageAmount = 1` | [U] | P0 |
| 47 | Non-TokenTransfers (`Signatures`): `usageAmount = 1` | [U] | P0 |
| 48 | Destination = `getActualDestination(to, data, value)` — may differ for ERC-20 transfers | [U] | P0 |
| 49 | `checkAndUpdateRateLimit` returns false — reverts `RateLimitExceeded(policyId)` | [N] | P0 |
| 50 | `checkAndUpdateRateLimit` returns true — succeeds, usage updated in storage | [U] | P0 |
| 51 | Native ETH transfer: `extractTransferAmount` uses `value` parameter (data is empty) | [U] | P0 |
| 52 | ERC-20 transfer: `extractTransferAmount` reads amount from calldata | [U] | P0 |

---

### 2.4 `_validateAutoApproveRejectionOrRevert`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 53 | Computes rejection hash with `isApproval=false` | [U] | P0 |
| 54 | Empty `reviewSignatures` (length 0) — reverts `TransactionRejectionNotAllowed` | [N] | P0 |
| 55 | Recovers rejection signer from `reviewSignatures` | [U] | P0 |
| 56 | Rejection signer not an authorized initiator for policy — reverts `TransactionRejectionNotAllowed` | [N] | P0 |
| 57 | Valid authorized initiator signs rejection — succeeds | [U] | P0 |
| 58 | Different authorized initiator (not the original) can also sign rejection | [U] | P0 |
| 59 | Approval signatures cannot be used for rejection (different hash: `isApproval=false` vs `true`) | [S] | P0 |

---

### 2.5 `_validateManualConfirmationOrRevert`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 60 | Calls `getRequiredApprovals` to determine threshold from policy | [U] | P0 |
| 61 | Review hash includes `initiatorSignature` (binding approvals to specific request) | [S] | P0 |
| 62 | `isApproval=true` for approval flow — review hash uses approval flag | [U] | P0 |
| 63 | `isApproval=false` for rejection flow — review hash uses rejection flag | [U] | P0 |
| 64 | `areApprovalsValid` returns false — reverts `InsufficientApprovals(required, 0)` | [N] | P0 |
| 65 | Sufficient valid approvals — succeeds | [U] | P0 |
| 66 | Different initiator signatures produce different review hashes (binding property) | [S] | P0 |

---

### 2.6 `_computeInitiatorHashFromParams`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 67 | Different organizations (`address(this)`) produce different hashes | [S] | P0 |
| 68 | Different accounts produce different hashes | [U] | P0 |
| 69 | Different `to` addresses produce different hashes | [U] | P0 |
| 70 | Different `value` amounts produce different hashes | [U] | P0 |
| 71 | Different `data` produces different hashes (`keccak256(data)` used) | [U] | P0 |
| 72 | Different `salt` values produce different hashes | [U] | P0 |
| 73 | Different `expirationTimestamp` values produce different hashes | [U] | P0 |
| 74 | Different `policyId` values produce different hashes | [U] | P0 |
| 75 | `isApproval=true` vs `isApproval=false` produce different hashes | [S] | P0 |
| 76 | Different `block.chainid` values produce different hashes | [S] | P0 |
| 77 | Uses `INITIATE_ACCOUNT_TRANSACTION_TYPEHASH` in struct hash | [U] | P1 |
| 78 | Deterministic: same inputs always produce same hash | [U] | P0 |
| 79 | Empty data → `keccak256("")` used in struct hash | [E] | P1 |
| 80 | Golden test: known inputs → known hash (precomputed off-chain) | [U] | P0 |

---

### 2.7 `_computeReviewHashFromParams`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 81 | Includes all fields from initiator hash (org, account, to, value, data, salt, expiration, policyId, isApproval, chainId) | [U] | P0 |
| 82 | Additionally includes `keccak256(initiatorSignature)` | [S] | P0 |
| 83 | Different initiator signatures → different review hashes | [S] | P0 |
| 84 | Uses `REVIEW_ACCOUNT_TRANSACTION_TYPEHASH` (distinct from initiator typehash) | [U] | P1 |
| 85 | `isApproval=true` vs `isApproval=false` → different hashes | [S] | P0 |
| 86 | Golden test: known inputs → known hash (precomputed off-chain) | [U] | P0 |

---

## File 3: AccountImplementation.sol

> **Prerequisite:** `_execute` and `_onlyOrganization` are currently `private`.
> Convert to `internal` and create a test contract inheriting from `AccountImplementation`
> to expose each via a public wrapper.

### 3.1 `receive()`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 87 | Accepts ETH from any address | [U] | P0 |
| 88 | Emits `MLSWalletAccountNativeTokenReceived(sender, value)` with correct parameters | [EV] | P1 |
| 89 | Zero-value ETH transfer — still emits event | [E] | P1 |

---

### 3.2 `executeTransaction`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 90 | Non-organization caller — reverts `OnlyOrganization` | [N] | P0 |
| 91 | Successful call (`_execute` returns true) — emits `TransactionExecuted` event | [U] | P0 |
| 92 | Failed call (`_execute` returns false) — reverts `TransactionExecutionFailed` | [N] | P0 |
| 93 | ETH value forwarded correctly to target | [U] | P0 |
| 94 | Calldata forwarded correctly to target contract | [U] | P0 |
| 95 | Emits `TransactionExecuted` with correct `(to, value, data, nonce, policyId)` | [EV] | P1 |

---

### 3.3 `getOrganizationAddress`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 96 | Returns the correct organization address from storage | [U] | P3 |
| 97 | Callable by anyone (no access restriction) | [U] | P3 |

---

### 3.4 `isValidSignature` (ERC-1271)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 98 | Delegates to `Organization.isValidSignatureForAccount(address(this), hash, signature)` | [U] | P0 |
| 99 | Returns ERC-1271 magic value when Organization approves | [U] | P0 |
| 100 | Returns non-magic value when Organization rejects | [N] | P0 |

---

### 3.5 `_execute`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 101 | Successful call returns `true` | [U] | P0 |
| 102 | Failed call (target reverts) returns `false` (no revert propagation) | [U] | P0 |
| 103 | Call to EOA with no code — returns `true` (CALL succeeds for EOAs) | [E] | P0 |
| 104 | ETH value forwarded correctly to target | [U] | P0 |
| 105 | Calldata forwarded correctly to target contract | [U] | P0 |
| 106 | Gas parameter respected — does not forward more gas than specified | [E] | P1 |
| 107 | Empty data with value > 0 — native ETH transfer succeeds | [U] | P0 |
| 108 | Return data from target is not captured (assembly output size = 0) | [E] | P1 |

---

### 3.6 `_onlyOrganization`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 109 | `msg.sender == organization` address — no revert | [U] | P0 |
| 110 | `msg.sender != organization` address — reverts `OnlyOrganization` | [N] | P0 |
| 111 | `msg.sender == address(0)` — reverts `OnlyOrganization` | [E] | P0 |

---

## 4. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 112 | Fuzz: Random valid transactions with AutoApprove policy — execute successfully | [F] | P0 |
| 113 | Fuzz: Random expiration timestamps — future pass, past fail | [F] | P0 |
| 114 | Fuzz: Random salt values produce unique nonces | [F] | P1 |
| 115 | Fuzz: Random transaction data → deterministic EIP-712 hashes | [F] | P0 |
| 116 | Fuzz: Random initiator signatures → different review hashes (binding property) | [F][S] | P0 |
| 117 | Fuzz: Random ETH values and ERC-20 amounts — rate limit usage computed correctly | [F] | P0 |
| 118 | Fuzz: Random ManualApproval threshold counts — insufficient signers always rejected | [F] | P0 |
| 119 | Fuzz: Random `TxParams` fields — changing any single field always changes initiator hash | [F] | P0 |
| 120 | Fuzz: Random `TxParams` + initiator signature — changing any field changes review hash | [F] | P0 |
| 121 | Fuzz: Random accounts — non-org accounts always rejected with `AccountNotDeployedByOrganization` | [F] | P0 |
| 122 | Fuzz: Random policy types — rejection routed to correct handler (AutoApprove vs ManualApproval) | [F] | P1 |

---

## 5. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 123 | **Nonce consumption**: Once a transaction nonce is consumed, it can never be reused for approval or rejection | P0 |
| 124 | **Rate limit atomicity**: Rate limit usage either increases by exact amount or tx reverts — no partial updates | P0 |
| 125 | **CEI ordering**: Nonce consumed before external call — during reentrancy nonce is already used | P0 |
| 126 | **Shared nonce space**: `executeAccountTransaction` and `rejectAccountTransaction` produce the same nonce for the same `(account, to, value, data, policyId, salt)` | P0 |
| 127 | **Approval/rejection hash separation**: `isApproval=true` and `isApproval=false` always produce different initiator hashes for the same transaction | P0 |
| 128 | **Organization binding**: Initiator hash always includes `address(this)` — signatures from one organization cannot be replayed on another | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| `executeAccountTransaction` | 13 | P0 |
| `rejectAccountTransaction` | 9 | P0 |
| `validateTransactionApprovalOrRevert` | 13 | P0 |
| `validateTransactionRejectionOrRevert` | 8 | P0 |
| `_validateAndUpdateRateLimitOrRevert` | 9 | P0 |
| `_validateAutoApproveRejectionOrRevert` | 7 | P0 |
| `_validateManualConfirmationOrRevert` | 7 | P0 |
| `_computeInitiatorHashFromParams` | 14 | P0-P1 |
| `_computeReviewHashFromParams` | 6 | P0-P1 |
| `receive()` | 3 | P0-P1 |
| `executeTransaction` | 6 | P0-P1 |
| `getOrganizationAddress` | 2 | P3 |
| `isValidSignature` | 3 | P0 |
| `_execute` | 8 | P0-P1 |
| `_onlyOrganization` | 3 | P0 |
| Fuzz tests | 11 | P0-P1 |
| Invariant tests | 6 | P0 |
| **Total** | **128** | |
