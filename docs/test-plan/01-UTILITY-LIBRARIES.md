# 01 — Utility Libraries Test Plan

**Files Under Test:**
- `src/libraries/SignatureUtils.sol`
- `src/libraries/MerkleUtils.sol`
- `src/libraries/TokenTransferUtils.sol`
- `src/libraries/ContractInteractionUtils.sol`
- `src/libraries/TimelockUtils.sol`
- `src/libraries/BytesUtils.sol` (already tested — gap analysis only)

**Test File(s):** `test/SignatureUtils.t.sol`, `test/MerkleUtils.t.sol`, `test/TokenTransferUtils.t.sol`, `test/ContractInteractionUtils.t.sol`, `test/TimelockUtils.t.sol`

---

## 1. SignatureUtils

**Priority: P0 — Critical (all signature validation depends on this)**

> **Implementation note:** `tryRecoverSigner` is the core implementation; `recoverSignerOrRevert`
> is a thin wrapper that calls it and reverts on failure. Same relationship for the offset variants
> (`tryRecoverSignerAtOffset` → `recoverSignerAtOffsetOrRevert`). Both the core and wrapper get
> full edge case coverage: `tryRecoverSigner` verifies return values (correctness), while
> `recoverSignerOrRevert` verifies the same cases either return the correct signer or revert with
> `SignatureRecoveryFailed` (security). This is the function the rest of the codebase actually
> calls, so auditors need to see every property asserted on the production-path function too.
> The offset `*OrRevert` wrapper gets a focused set covering each major failure class.

### 1.1 Single Signature Recovery — `tryRecoverSigner` (core implementation)

#### EOA Signatures

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Valid ECDSA signature (v=27) returns (true, correct signer) | [U] | P0 |
| 2 | Valid ECDSA signature (v=28) returns (true, correct signer) | [U] | P0 |
| 3 | Empty signature returns (false, address(0)) | [N] | P0 |
| 4 | Signature with length != 65 for EOA returns (false, address(0)) | [N] | P0 |
| 5 | Signature with invalid v byte (not 0, 27, 28) returns (false, address(0)) | [N] | P0 |
| 6 | Signature with high s value (malleability) returns (false, address(0)) | [S] | P0 |
| 7 | Signature with s = HALF_CURVE_ORDER (boundary) returns (true, signer) | [E] | P0 |
| 8 | Signature with s = HALF_CURVE_ORDER + 1 returns (false, address(0)) | [E] | P0 |
| 9 | Signature for wrong hash returns (true, different signer) | [U] | P0 |
| 10 | Signature with zeroed r or s returns (false, address(0)) | [S] | P0 |
| 11 | ecrecover returning address(0) returns (false, address(0)) | [S] | P0 |

#### ERC-1271 Contract Signatures

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 12 | Valid ERC-1271 signature (v=0) with valid contract signer returns (true, signer) | [U] | P0 |
| 13 | ERC-1271 signature where contract returns magic value — (true, signer) | [U] | P0 |
| 14 | ERC-1271 signature where contract returns wrong magic value — (false, address(0)) | [N] | P0 |
| 15 | ERC-1271 signature where contract reverts — (false, address(0)) | [N] | P0 |
| 16 | ERC-1271 signature with signer that is not a contract (EOA) — (false, address(0)) | [N] | P0 |
| 17 | ERC-1271 signature with zero-length inner signature — (false, address(0)) | [E] | P0 |
| 18 | ERC-1271 signature with length field exceeding actual data — (false, address(0)) | [N] | P0 |
| 19 | ERC-1271 signature with contract signer at address(0) — (false, address(0)) | [S] | P0 |
| 20 | ERC-1271 header too short (< 23 bytes after v=0) — (false, address(0)) | [N] | P0 |

### 1.2 Single Signature Recovery — `recoverSignerOrRevert` (production-path verification)

> The rest of the codebase calls this function, not `tryRecoverSigner`. Every edge case from §1.1
> is mirrored here: success cases verify the correct signer is returned, failure cases verify the
> function reverts with `SignatureRecoveryFailed`.

#### EOA Signatures

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 21 | Valid ECDSA signature (v=27) — returns correct signer | [U] | P0 |
| 22 | Valid ECDSA signature (v=28) — returns correct signer | [U] | P0 |
| 23 | Empty signature — reverts `SignatureRecoveryFailed` | [N] | P0 |
| 24 | Signature with length != 65 for EOA — reverts `SignatureRecoveryFailed` | [N] | P0 |
| 25 | Signature with invalid v byte (not 0, 27, 28) — reverts `SignatureRecoveryFailed` | [N] | P0 |
| 26 | Signature with high s value (malleability) — reverts `SignatureRecoveryFailed` | [S] | P0 |
| 27 | Signature with s = HALF_CURVE_ORDER (boundary) — returns correct signer | [E] | P0 |
| 28 | Signature with s = HALF_CURVE_ORDER + 1 — reverts `SignatureRecoveryFailed` | [E] | P0 |
| 29 | Signature for wrong hash — returns different signer (not a revert) | [U] | P0 |
| 30 | Signature with zeroed r or s — reverts `SignatureRecoveryFailed` | [S] | P0 |
| 31 | ecrecover returning address(0) — reverts `SignatureRecoveryFailed` | [S] | P0 |

#### ERC-1271 Contract Signatures

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 32 | Valid ERC-1271 signature (v=0) with valid contract signer — returns signer | [U] | P0 |
| 33 | ERC-1271 signature where contract returns magic value — returns signer | [U] | P0 |
| 34 | ERC-1271 signature where contract returns wrong magic value — reverts `SignatureRecoveryFailed` | [N] | P0 |
| 35 | ERC-1271 signature where contract reverts — reverts `SignatureRecoveryFailed` | [N] | P0 |
| 36 | ERC-1271 signature with signer that is not a contract (EOA) — reverts `SignatureRecoveryFailed` | [N] | P0 |
| 37 | ERC-1271 signature with zero-length inner signature — reverts `SignatureRecoveryFailed` | [E] | P0 |
| 38 | ERC-1271 signature with length field exceeding actual data — reverts `SignatureRecoveryFailed` | [N] | P0 |
| 39 | ERC-1271 signature with contract signer at address(0) — reverts `SignatureRecoveryFailed` | [S] | P0 |
| 40 | ERC-1271 header too short (< 23 bytes after v=0) — reverts `SignatureRecoveryFailed` | [N] | P0 |

### 1.3 Multi-Signature Offset Recovery — `tryRecoverSignerAtOffset` (core implementation)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 41 | Recover first EOA signer (offset=0) — returns (true, signer, 65) | [U] | P0 |
| 42 | Recover second EOA signer (offset=65) — returns (true, signer, 130) | [U] | P0 |
| 43 | Recover ERC-1271 signer at offset — returns (true, signer, offset + 23 + innerLength) | [U] | P0 |
| 44 | Mixed EOA + ERC-1271 signatures, recover each at correct offset | [U] | P0 |
| 45 | Three consecutive EOA signatures iterated correctly via nextOffset chaining | [U] | P0 |
| 46 | Three consecutive ERC-1271 signatures iterated correctly via nextOffset chaining | [U] | P0 |
| 47 | Offset beyond signatures length — returns (false, address(0), 0) | [N] | P0 |
| 48 | Offset at exactly the end of signatures — returns (false, address(0), 0) | [E] | P0 |
| 49 | Invalid signature at offset (bad v byte) — returns (false, address(0), 0) | [N] | P0 |
| 50 | Malleable signature at offset — returns (false, address(0), 0) | [S] | P0 |

### 1.4 Multi-Signature Offset Recovery — `recoverSignerAtOffsetOrRevert` (security-critical revert cases)

> Same rationale as `recoverSignerOrRevert` (§1.2): this is the function the codebase calls for
> multi-sig iteration, so auditors need to see each major failure class asserted here.

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 51 | Valid EOA signature at offset — returns (signer, nextOffset) (smoke test) | [U] | P0 |
| 52 | Valid ERC-1271 signature at offset — returns (signer, nextOffset) (smoke test) | [U] | P0 |
| 53 | Invalid signature at offset (bad v) — reverts `SignatureRecoveryFailed` | [N] | P0 |
| 54 | Malleable signature at offset — reverts `SignatureRecoveryFailed` | [S] | P0 |
| 55 | Offset beyond signatures length — reverts `SignatureRecoveryFailed` | [N] | P0 |
| 56 | ERC-1271 at offset where contract returns wrong magic — reverts `SignatureRecoveryFailed` | [N] | P0 |

### 1.5 Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 57 | Fuzz: Any valid private key produces recoverable signature via tryRecoverSigner | [F] | P0 |
| 58 | Fuzz: Random bytes never successfully recover a signer (tryRecoverSigner returns false) | [F] | P1 |
| 59 | Fuzz: Signature malleability — flipping s value always rejected by tryRecoverSigner | [F][S] | P0 |

---

## 2. MerkleUtils

**Priority: P1 — High**

#### `computeAddressLeaf(address addr)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 60 | Known address produces known leaf (golden test) | [U] | P1 |
| 61 | Double hashing: leaf != keccak256(abi.encode(addr)) (single hash) | [U] | P1 |
| 62 | address(0) produces valid non-zero leaf | [U] | P1 |
| 63 | Two different addresses produce different leaves | [U] | P1 |
| 64 | Same address always produces same leaf (deterministic) | [U] | P1 |
| 65 | Fuzz: No two random addresses produce the same leaf | [F] | P1 |

---

## 3. TokenTransferUtils

**Priority: P0 — Critical (policy validation depends on correct detection)**

### 3.1 Transfer Detection

#### `isTransactionTokenTransfer(bytes calldata data, uint256 value)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 66 | Native transfer: data empty, value > 0 — returns true | [U] | P0 |
| 67 | ERC-20 transfer: correct selector, value = 0 — returns true | [U] | P0 |
| 68 | Contract interaction: data with non-transfer selector — returns false | [U] | P0 |
| 69 | No data, no value — returns false | [E] | P0 |
| 70 | ERC-20 selector but value > 0 — returns false (native takes priority) | [E][S] | P0 |
| 71 | Data length exactly 4 bytes (selector only) — returns false | [E] | P0 |

#### `isTransactionNativeTokenTransfer(bytes calldata data, uint256 value)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 72 | Empty data, value > 0 — returns true | [U] | P0 |
| 73 | Empty data, value = 0 — returns false | [U] | P0 |
| 74 | Non-empty data, value > 0 — returns false | [U] | P0 |

#### `isTransactionERC20TokenTransfer(bytes calldata data, uint256 value)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 75 | transfer(address,uint256) selector, value = 0 — returns true | [U] | P0 |
| 76 | transfer selector, value > 0 — returns false | [U] | P0 |
| 77 | approve(address,uint256) selector — returns false (different selector) | [U] | P0 |
| 78 | transferFrom selector — returns false | [U] | P0 |
| 79 | Data too short (< 4 bytes) — returns false | [E] | P0 |

### 3.2 Extraction Functions

#### `extractERC20TransferRecipient(bytes calldata data)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 80 | Valid transfer calldata — extracts correct recipient | [U] | P0 |
| 81 | Data too short — reverts with `MalformedTokenTransfer` | [N] | P0 |
| 82 | Recipient is address(0) — extracts correctly (no validation) | [E] | P0 |

#### `extractTokenAddress(address to, bytes calldata data)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 83 | Native transfer — returns address(0) | [U] | P0 |
| 84 | ERC-20 transfer — returns `to` (token contract address) | [U] | P0 |

#### `extractTransferAmount(bytes calldata data, uint256 value)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 85 | Native transfer — returns `value` | [U] | P0 |
| 86 | ERC-20 transfer — extracts amount from calldata | [U] | P0 |
| 87 | Amount is 0 — returns 0 | [E] | P0 |
| 88 | Amount is type(uint256).max — returns max | [E] | P0 |
| 89 | Data too short — reverts with `MalformedTokenTransfer` | [N] | P0 |

### 3.3 Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 90 | Fuzz: Any valid ERC-20 transfer calldata extracts correct recipient | [F] | P0 |
| 91 | Fuzz: Any valid ERC-20 transfer calldata extracts correct amount | [F] | P0 |
| 92 | Fuzz: Random data never classified as both native and ERC-20 | [F] | P0 |

---

## 4. ContractInteractionUtils

**Priority: P2 — Medium**

#### `extractFunctionSelector(bytes calldata data)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 93 | Valid calldata — extracts correct 4-byte selector | [U] | P2 |
| 94 | Exactly 4 bytes — returns those 4 bytes | [E] | P2 |
| 95 | Known function selectors (transfer, approve, etc.) match | [U] | P2 |

---

## 5. TimelockUtils

**Priority: P1 — High**

#### `validateTimelockDurationOrRevert(uint256 timelockDurationSeconds)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 96 | Duration at MIN (2 days) — succeeds | [E] | P1 |
| 97 | Duration at MAX (30 days) — succeeds | [E] | P1 |
| 98 | Duration at MIN - 1 — reverts with `InvalidTimelockDuration` | [N] | P1 |
| 99 | Duration at MAX + 1 — reverts with `InvalidTimelockDuration` | [N] | P1 |
| 100 | Duration of 0 — reverts | [N] | P1 |
| 101 | Mid-range duration (7 days) — succeeds | [U] | P1 |
| 102 | Fuzz: Any duration in [MIN, MAX] succeeds | [F] | P1 |
| 103 | Fuzz: Any duration outside [MIN, MAX] reverts | [F] | P1 |

---

## 6. BytesUtils (Gap Analysis)

**Already tested in `test/BytesUtils.t.sol` (47 tests).** No additional tests needed. Existing coverage is comprehensive including fuzz tests.

---

## Summary

| Library | New Tests | Priority |
|---------|-----------|----------|
| SignatureUtils | 59 | P0 |
| MerkleUtils | 6 | P1 |
| TokenTransferUtils | 27 | P0 |
| ContractInteractionUtils | 3 | P2 |
| TimelockUtils | 8 | P1 |
| **Total** | **103** | |
