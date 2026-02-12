# 08 — Account Transaction Test Plan

**Files Under Test:**
- `src/organization/libraries/LibOrganizationAccountTransaction.sol`
- `src/organization/base/OrganizationAccountTransactionBase.sol`
- `src/account/AccountImplementation.sol`
- `src/interfaces/organization/IOrganizationAccountTransaction.sol`
- `src/interfaces/IAccount.sol`

**Test File(s):** `test/LibOrganizationAccountTransaction.t.sol`, `test/AccountTransaction.t.sol`

---

## 1. Transaction Approval Flow

**Priority: P0 — Critical (core value path)**

### 1.1 Full Approval Validation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | AutoApprove policy: valid initiator signature — approved | [U] | P0 |
| 2 | ManualApproval policy: valid initiator + review signatures — approved | [U] | P0 |
| 3 | ManualApproval: insufficient review signatures — reverts `InsufficientApprovals` | [N] | P0 |
| 4 | Expired transaction — reverts `TransactionExpired` | [N] | P0 |
| 5 | Expiration at exactly `block.timestamp` — succeeds | [E] | P0 |
| 6 | Empty initiator signature — reverts `InsufficientSignaturesLength` | [N] | P0 |
| 7 | Policy does not apply to transaction — reverts `PolicyDoesNotApply` | [N] | P0 |
| 8 | Rate limit exceeded — reverts `RateLimitExceeded` | [N] | P0 |

### 1.2 Initiator Signature Verification

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 9 | Valid EOA initiator signature — signer recovered correctly | [U] | P0 |
| 10 | Valid ERC-1271 initiator signature — signer recovered correctly | [U] | P0 |
| 11 | Initiator is authorized by policy (Member type) — succeeds | [U] | P0 |
| 12 | Initiator is authorized by policy (Group type) — succeeds | [U] | P0 |
| 13 | Initiator not authorized by policy — reverts | [N] | P0 |

### 1.3 Review Signature Verification (ManualApproval)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 14 | Review hash includes initiator signature (binding) | [S] | P0 |
| 15 | Review signatures from different initiator request — fail (different hash) | [S] | P0 |
| 16 | Review signatures in ascending order — succeeds | [U] | P0 |
| 17 | Review signatures out of order — reverts `DuplicateOrOutOfOrderSigner` | [S] | P0 |
| 18 | Review signer not in required approval group — reverts | [S] | P0 |

### 1.4 Rate Limit Integration

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 19 | Transaction within rate limit — succeeds, usage updated | [U] | P0 |
| 20 | Transaction exceeds rate limit — reverts | [N] | P0 |
| 21 | Token transfer uses transfer amount as usage | [U] | P0 |
| 22 | Contract interaction uses 1 as usage | [U] | P0 |
| 23 | No rate limit configured — always succeeds | [U] | P1 |

---

## 2. Transaction Rejection Flow

**Priority: P0 — Critical**

### 2.1 ManualApproval Rejection

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 24 | ManualApproval: valid rejection signatures — rejection accepted | [U] | P0 |
| 25 | ManualApproval: insufficient rejection signatures — reverts | [N] | P0 |
| 26 | Rejection uses `isApproval=false` in hash — different from approval | [S] | P0 |
| 27 | Approval signatures cannot be used for rejection | [S] | P0 |

### 2.2 AutoApprove Rejection

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 28 | AutoApprove: rejection requires authorized initiator signature in reviewSignatures | [U] | P0 |
| 29 | AutoApprove: empty reviewSignatures — reverts `TransactionRejectionNotAllowed` | [N] | P0 |
| 30 | AutoApprove: rejection signer must be authorized initiator for policy | [S] | P0 |
| 31 | AutoApprove: non-initiator signer in reviewSignatures — reverts | [N] | P0 |

---

## 3. EIP-712 Hash Computation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 32 | Initiator hash includes: address(this), account, to, value, data, salt, expiration, policyId, isApproval, chainId | [U] | P0 |
| 33 | Review hash includes all initiator hash fields + initiatorSignature hash | [U] | P0 |
| 34 | Different `isApproval` values produce different hashes | [S] | P0 |
| 35 | Different chains produce different hashes (chain ID) | [S] | P0 |
| 36 | Different organizations produce different hashes (address(this)) | [S] | P0 |
| 37 | Different accounts produce different hashes | [U] | P0 |
| 38 | Different `to` addresses produce different hashes | [U] | P0 |
| 39 | Different `data` produces different hashes (data hashed) | [U] | P0 |

---

## 4. Account Execution

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 40 | `executeTransaction` on Account: successful ETH transfer | [I] | P0 |
| 41 | `executeTransaction` on Account: successful ERC-20 transfer | [I] | P0 |
| 42 | `executeTransaction` on Account: successful contract interaction | [I] | P0 |
| 43 | `executeTransaction` on Account: reverts when sub-call fails — reverts `TransactionExecutionFailed` | [N] | P0 |
| 44 | Only Organization can call `executeTransaction` on Account — reverts `OnlyOrganization` | [S] | P0 |
| 45 | Account emits `TransactionExecuted` event | [EV] | P1 |
| 46 | Nonce consumed BEFORE external call (CEI pattern) | [S] | P0 |
| 47 | Organization emits `AccountTransactionExecuted` event before external call | [EV] | P1 |

---

## 5. Account ETH Handling

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 48 | Account `receive()` accepts ETH | [U] | P0 |
| 49 | Account emits `MLSWalletAccountNativeTokenReceived` on receive | [EV] | P1 |
| 50 | Account can receive ETH from any address | [U] | P1 |

---

## 6. Nonce Integration

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 51 | Transaction nonce computed from operation data + salt | [U] | P0 |
| 52 | Same transaction executed twice — second reverts (nonce used) | [S] | P0 |
| 53 | Approval nonce consumed prevents rejection with same nonce | [S] | P0 |
| 54 | Rejection nonce consumed prevents approval with same nonce | [S] | P0 |

---

## 7. Access Control

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 55 | `executeAccountTransaction` reverts when caller is not guardian | [N] | P0 |
| 56 | `rejectAccountTransaction` reverts when caller is not guardian | [N] | P0 |
| 57 | Transaction against non-org account — reverts `AccountNotDeployedByOrganization` | [S] | P0 |

---

## 7.5 Reentrancy & CEI Pattern

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 57.1 | Nonce consumed before external call — deliberately failing account execution still marks nonce used | [S] | P0 |
| 57.2 | Account cannot re-enter executeAccountTransaction during execution (nonce already consumed) | [S] | P0 |
| 57.3 | Rate limit consumed before execution — failed execution still consumes rate limit budget | [S] | P0 |

---

## 8. Private Function Tests (Requires `private` → `internal` Conversion)

> **Prerequisite:** The functions below are currently `private` in `AccountImplementation`.
> For contract functions, create a test contract that inherits from `AccountImplementation`
> and exposes each private function via a public wrapper (requires converting `private` to `internal`).

### 8.1 `_execute` — Low-level assembly CALL

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 62 | Successful call returns `true` | [U] | P0 |
| 63 | Failed call (target reverts) returns `false` (no revert propagation) | [U] | P0 |
| 64 | Call to EOA with no code — returns `true` (CALL succeeds for EOAs) | [E] | P0 |
| 65 | ETH value forwarded correctly to target | [U] | P0 |
| 66 | Calldata forwarded correctly to target contract | [U] | P0 |
| 67 | Gas parameter respected — does not forward more gas than specified | [E] | P1 |
| 68 | Empty data with value > 0 — native transfer succeeds | [U] | P0 |
| 69 | Call to self-destructing contract — returns `true` | [E] | P1 |

### 8.2 `_onlyOrganization` — Access control check

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 70 | msg.sender == organization address — succeeds (no revert) | [U] | P0 |
| 71 | msg.sender != organization address — reverts `OnlyOrganization` | [N] | P0 |
| 72 | msg.sender == address(0) — reverts `OnlyOrganization` | [E] | P0 |

---

## 9. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 73 | Fuzz: Random valid transactions with AutoApprove policy — execute successfully | [F] | P0 |
| 74 | Fuzz: Random expiration timestamps — future pass, past fail | [F] | P0 |
| 75 | Fuzz: Random salt values produce unique nonces | [F] | P1 |
| 76 | Fuzz: Random transaction data produces correct EIP-712 hashes | [F] | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Approval flow | 23 | P0 |
| Rejection flow | 8 | P0 |
| EIP-712 hashes | 8 | P0 |
| Account execution | 8 | P0 |
| Account ETH handling | 3 | P0-P1 |
| Nonce integration | 4 | P0 |
| Access control | 3 | P0 |
| Reentrancy & CEI | 3 | P0 |
| Private function tests | 11 | P0-P1 |
| Fuzz tests | 4 | P0-P1 |
| **Total** | **75** | |
