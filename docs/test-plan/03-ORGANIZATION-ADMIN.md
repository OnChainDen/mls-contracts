# 03 — Organization Admin Test Plan

**Files Under Test:**
- `src/organization/libraries/LibOrganizationAdmin.sol`
- `src/organization/base/OrganizationAdminBase.sol`
- `src/organization/libraries/storage/LibOrganizationAdminStorage.sol`
- `src/interfaces/organization/IOrganizationAdmin.sol`

**Test File(s):** `test/LibOrganizationAdmin.t.sol`, `test/OrganizationAdminBase.t.sol`

---

## 1. Admin Authorization (`validateAdminAuthAndConsumeNonceOrRevert`)

**Priority: P0 — Critical (every admin operation depends on this)**

### 1.1 Expiration Checks

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Valid expiration (future timestamp) — succeeds | [U] | P0 |
| 2 | Expired operation (past timestamp) — reverts with `AdminOperationExpired` | [N] | P0 |
| 3 | Expiration at exactly `block.timestamp` — succeeds (<=) | [E] | P0 |
| 4 | Expiration at `block.timestamp - 1` — reverts | [E] | P0 |
| 5 | Expiration at `type(uint256).max` — succeeds | [E] | P0 |

### 1.2 Nonce Management

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 6 | First use of nonce — succeeds and marks as used | [U] | P0 |
| 7 | Replay same nonce — reverts with `NonceAlreadyUsed` | [S] | P0 |
| 8 | Same operation data with different salt — different nonce, both succeed | [U] | P0 |
| 9 | Different operation types with same data and salt — different nonces | [U] | P0 |
| 10 | Nonce includes `address(this)` — cross-contract replay prevented | [S] | P0 |

### 1.3 Signature Validation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 11 | Single admin with threshold=1, valid signature — succeeds | [U] | P0 |
| 12 | Multiple admins, threshold=2, two valid signatures — succeeds | [U] | P0 |
| 13 | Threshold=2 but only 1 valid signature — reverts `InsufficientAdminAuthorization` | [N] | P0 |
| 14 | Signers not in ascending order — reverts `DuplicateOrOutOfOrderAdminSigner` | [S] | P0 |
| 15 | Duplicate signer (same signature twice) — reverts `DuplicateOrOutOfOrderAdminSigner` | [S] | P0 |
| 16 | Valid signer who is NOT an admin — reverts `SignerIsNotAdmin` | [S] | P0 |
| 17 | More signatures than threshold — succeeds (extra ignored after threshold met) | [E] | P0 |
| 18 | Zero signatures with threshold > 0 — reverts | [N] | P0 |
| 19 | Signatures for approval cannot be reused for rejection (isApproval flag) | [S] | P0 |
| 20 | Signatures for rejection cannot be reused for approval (isApproval flag) | [S] | P0 |
| 21 | Mixed EOA + ERC-1271 admin signatures — succeeds | [U] | P0 |
| 22 | ERC-1271 admin signature with contract that reverts — reverts | [N] | P0 |

### 1.4 Operation Hash Verification

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 23 | Hash includes chain ID — different chains produce different hashes | [S] | P0 |
| 24 | Hash includes contract address — different orgs produce different hashes | [S] | P0 |
| 25 | Hash includes isApproval flag — approval vs rejection produce different hashes | [U] | P0 |
| 26 | Hash includes operation type and data — different operations produce different hashes | [U] | P0 |

---

## 2. Admin Modification (`modifyAdmins`)

**Priority: P0 — Critical**

### 2.1 Adding Admins

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 27 | Add a single member as admin — succeeds, increments count | [U] | P0 |
| 28 | Add multiple members as admins — all added, count correct | [U] | P0 |
| 29 | Add address(0) as admin — reverts | [N] | P0 |
| 30 | Add non-member as admin — reverts with `AdminNotMember` | [N] | P0 |
| 31 | Add existing admin — reverts with `AdminAlreadyExists` | [N] | P0 |
| 32 | Admin added emits `AdminAdded` event | [EV] | P1 |

### 2.2 Removing Admins

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 33 | Remove existing admin — succeeds, decrements count | [U] | P0 |
| 34 | Remove multiple admins — all removed, count correct | [U] | P0 |
| 35 | Remove non-existent admin — reverts with `AdminDoesNotExist` | [N] | P0 |
| 36 | Remove last admin (count would be 0) — reverts with `InvalidAdminConfig` | [S] | P0 |
| 37 | Admin removed emits `AdminRemoved` event | [EV] | P1 |

### 2.3 Voting Threshold

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 38 | Set threshold = 1 — succeeds | [U] | P0 |
| 39 | Set threshold = adminCount — succeeds | [U] | P0 |
| 40 | Set threshold = 0 — reverts with `InvalidAdminVotingThreshold` | [N] | P0 |
| 41 | Set threshold > adminCount — reverts with `InvalidAdminVotingThreshold` | [N] | P0 |
| 42 | Threshold = adminCount after removing admins — succeeds | [E] | P0 |
| 43 | Remove admin where threshold would exceed new count — reverts | [S] | P0 |
| 44 | Threshold change emits `VotingThresholdUpdated(old, new)` event | [EV] | P1 |

### 2.4 Combined Add/Remove Operations

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 45 | Add and remove in same call — final state correct | [U] | P0 |
| 46 | Add then remove same address in same call (add first) — net effect depends on ordering | [E] | P0 |
| 47 | Remove then add same address (not possible — arrays processed add first) | [E] | P0 |
| 48 | Both arrays empty — no-op succeeds | [E] | P2 |

---

## 3. Admin Query Functions

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 49 | `isAdmin` returns true for admin | [U] | P3 |
| 50 | `isAdmin` returns false for non-admin | [U] | P3 |
| 51 | `isAdmin` returns false for address(0) | [U] | P3 |
| 52 | `adminCount` returns correct count after add/remove | [U] | P3 |
| 53 | `votingThreshold` returns correct value after update | [U] | P3 |

---

## 4. Admin Operation Rejection (`rejectAdminOperation`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 54 | Reject an admin operation with valid admin signatures — consumes nonce | [U] | P0 |
| 55 | Rejection uses isApproval=false — different hash from approval | [U] | P0 |
| 56 | Rejection emits `AdminOperationRejected` event | [EV] | P1 |
| 57 | Rejecting with already-used nonce reverts | [N] | P0 |
| 58 | Rejection prevents subsequent approval with same nonce | [S] | P0 |
| 59 | Approval prevents subsequent rejection with same nonce | [S] | P0 |

---

## 5. Access Control (Base Contract Level)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 60 | `modifyAdmins` reverts when caller is not guardian | [N] | P0 |
| 61 | `rejectAdminOperation` reverts when caller is not guardian | [N] | P0 |
| 62 | View functions callable by anyone | [U] | P3 |

---

## 5.5 Race Conditions & Signature Ordering

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 62.1 | [AUDIT] Admin removed after signing — operation fails if signer no longer admin at execution time | [S] | P0 |
| 62.2 | [AUDIT] Voting threshold increased — old signatures that met old threshold fail if below new threshold | [S] | P0 |
| 62.3 | [AUDIT] Mixed EOA+ERC-1271 signatures: offset accumulation correct for EOA→ERC1271→EOA sequence | [S] | P0 |
| 62.4 | [AUDIT] ERC-1271 admin with very large inner signature — offset correctly advances past entire signature | [E] | P0 |

---

## 6. Private Function Tests (Requires `private` → `internal` Conversion)

> **Prerequisite:** The functions below are currently `private` in `LibOrganizationAdmin`.
> Convert them to `internal` and create a test harness that exposes each via public wrappers.

### 6.1 `_areAdminSignaturesValid`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 68 | Empty signatures — returns false (not revert) | [N] | P0 |
| 69 | Exactly `votingThreshold` valid admin signatures — returns true | [U] | P0 |
| 70 | More signatures than threshold — returns true after threshold met (early exit) | [U] | P0 |
| 71 | Fewer valid signatures than threshold — returns false | [N] | P0 |
| 72 | Signer addresses not in ascending order — reverts `DuplicateOrOutOfOrderAdminSigner` | [S] | P0 |
| 73 | Duplicate signer — reverts `DuplicateOrOutOfOrderAdminSigner` | [S] | P0 |
| 74 | Non-admin signer — reverts `SignerIsNotAdmin` | [S] | P0 |
| 75 | Mixed EOA + ERC-1271 admin signatures — ascending order across both types | [U] | P0 |
| 76 | Malformed signature in array — reverts `SignatureRecoveryFailed` (from SignatureUtils) | [N] | P0 |

### 6.2 `_getAdminOperationHash`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 77 | Same inputs produce same hash (deterministic) | [U] | P1 |
| 78 | Different `operationType` — different hash | [U] | P1 |
| 79 | Different `operationData` — different hash | [U] | P1 |
| 80 | Different `salt` — different hash | [U] | P1 |
| 81 | Different `expirationTimestamp` — different hash | [U] | P1 |
| 82 | `isApproval=true` vs `isApproval=false` — different hash (approval/rejection separation) | [S] | P0 |
| 83 | Different `block.chainid` — different hash (cross-chain replay protection) | [S] | P0 |
| 84 | Different `address(this)` (different org) — different hash (cross-org replay protection) | [S] | P0 |
| 85 | Output matches manual EIP-712 `hashTypedData(structHash)` computation | [U] | P1 |

---

## 7. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 86 | Fuzz: Add N random members as admins, verify all are admins | [F] | P0 |
| 87 | Fuzz: Random threshold values within valid range always succeed | [F] | P0 |
| 88 | Fuzz: Random threshold values outside valid range always revert | [F] | P0 |
| 89 | Fuzz: Random expiration timestamps — future pass, past fail | [F] | P0 |
| 90 | Fuzz: Random salt values produce unique nonces for same operation | [F] | P1 |
| 91 | Fuzz: Random non-admin signers always rejected with `SignerIsNotAdmin` | [F] | P0 |
| 92 | Fuzz: Random admin modification arrays — `adminCount` never reaches 0 | [F] | P0 |
| 93 | Fuzz: Random admin addition with non-member addresses — always reverts `AdminNotMember` | [F] | P0 |

---

## 8. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 94 | **Minimum admins**: `adminCount >= 1` at all times after initialization | P0 |
| 95 | **Voting threshold bounds**: `1 <= votingThreshold <= adminCount` at all times | P0 |
| 96 | **Admin-must-be-member**: For every address where `isAdmin(addr) == true`, `isMember(addr) == true` | P0 |
| 97 | **Admin count consistency**: The number of addresses where `isAdmin(addr) == true` equals `adminCount` | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Authorization | 26 | P0 |
| Admin modification | 22 | P0 |
| Query functions | 5 | P3 |
| Operation rejection | 6 | P0 |
| Access control | 3 | P0 |
| Race conditions & ordering | 4 | P0 |
| Private function tests | 18 | P0-P1 |
| Fuzz tests | 8 | P0-P1 |
| Invariant tests | 4 | P0 |
| **Total** | **97** | |
