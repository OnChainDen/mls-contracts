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
| 17 | ERC-1271 signature with zero-length inner signature accepted by signer contract — (true, signer) | [E] | P0 |
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
| 37 | ERC-1271 signature with zero-length inner signature accepted by signer contract — returns signer | [E] | P0 |
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

### 1.5 Private Helper Tests (Requires `private` → `internal` Conversion)

> **Prerequisite:** The functions below are currently `private` in the `SignatureUtils` library.
> To test them directly, convert them to `internal` and create a test harness contract that
> exposes each via a public wrapper (e.g., `SignatureUtilsHarness.sol`). This enables precise
> assertions on the assembly logic that cannot be fully validated through the public interface.

#### `_getVByte` — v byte extraction via `byte(0, mload(...))`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 57 | Extract v byte at offset=0 — returns correct byte | [U] | P0 |
| 58 | Extract v byte at large offset (e.g., 200) — returns correct byte | [U] | P0 |
| 59 | Extract v byte when surrounding bytes are non-zero — only target byte returned | [E] | P0 |

#### `_getContractSigner` — Address extraction via `shr(96, mload(...))`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 60 | Extract signer surrounded by non-zero bytes — only 20-byte address, no dirty upper bits | [U][S] | P0 |
| 61 | Signer with leading zeros (e.g., `0x0000...0001`) — correctly recovered | [E] | P0 |
| 62 | Signer with all `0xff` bytes — correctly recovered without truncation | [E] | P0 |

#### `_getContractSignatureLength` — Big-endian 2-byte extraction via `shr(240, mload(...))`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 63 | Length = 1 (0x0001) — correctly parsed as 1 | [E] | P0 |
| 64 | Length = 256 (0x0100) — verifies big-endian parsing (not little-endian 1) | [E][S] | P0 |
| 65 | Length = 65535 (0xFFFF, max uint16) — correctly parsed | [E] | P0 |
| 66 | Length = 0 (0x0000) — returns 0 | [E] | P0 |

#### `_extractContractInnerSignature` — Assembly copy loop (32-byte chunks)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 67 | Inner sig length = 1 — extracted byte matches source exactly | [U] | P0 |
| 68 | Inner sig length = 31 — no over-copy into returned bytes (non-aligned) | [E] | P0 |
| 69 | Inner sig length = 32 — exact one-chunk copy, data integrity verified | [U] | P0 |
| 70 | Inner sig length = 33 — two-chunk copy, only 33 bytes returned (not 64) | [E] | P0 |
| 71 | Inner sig length = 65 (EOA sig size) — full data integrity byte-for-byte | [U] | P0 |
| 72 | Inner sig with all 0xff bytes — no corruption during chunk copy | [E] | P0 |
| 72.1 | Inner sig length = 96 — exact 3-chunk copy, data integrity byte-for-byte | [U] | P0 |
| 72.2 | Inner sig length = 97 — 4-chunk copy, only 97 bytes returned (not 128) | [E] | P0 |
| 72.3 | Inner sig length = 160 — exact 5-chunk copy, data integrity byte-for-byte | [U] | P0 |
| 72.4 | Inner sig length = 161 — 6-chunk copy, only 161 bytes returned (not 192) | [E] | P0 |
| 72.5 | Inner sig length = 1600 — exact 50-chunk copy, data integrity byte-for-byte | [U] | P0 |
| 72.6 | Inner sig length = 1601 — 51-chunk copy, only 1601 bytes returned (not 1632) | [E] | P0 |
| 72.7 | Fuzz: Random sigLength in [1, 2000] — extracted bytes always match source exactly and returned length == sigLength | [F] | P0 |

#### `_tryRecoverEOASigner` — Assembly extraction of r, s at offset

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 73 | r and s extracted correctly at offset > 0 (second sig in concat array) | [U] | P0 |
| 74 | Preceding bytes are non-zero — no bleed into r or s values | [S] | P0 |
| 75 | s = HALF_CURVE_ORDER at non-zero offset — accepted (boundary) | [E] | P0 |
| 76 | s = HALF_CURVE_ORDER + 1 at non-zero offset — rejected | [E] | P0 |
| 76.1 | offset = 0, valid signature — r and s extracted correctly from start of array | [U] | P0 |
| 76.2 | offset + 65 > signatures.length (insufficient bytes) — returns (false, address(0)) | [N] | P0 |
| 76.3 | offset + 65 == signatures.length (exactly fits) — succeeds | [E] | P0 |
| 76.4 | r = bytes32(0) — ecrecover returns address(0), function returns (false, address(0)) | [S] | P0 |
| 76.5 | s = bytes32(0) — ecrecover returns address(0), function returns (false, address(0)) | [S] | P0 |
| 76.6 | v = 27 at offset — recovered signer matches expected | [U] | P0 |
| 76.7 | v = 28 at offset — recovered signer matches expected | [U] | P0 |
| 76.8 | Three consecutive EOA signatures — each extracted correctly at offsets 0, 65, 130 | [U] | P0 |
| 76.9 | Trailing garbage bytes after valid 65-byte signature — does not affect recovery | [E] | P0 |
| 76.10 | Fuzz: Random valid private keys at random offsets within array — always recovers correct signer | [F] | P0 |

#### `_tryRecoverContractSigner` — End-to-end ERC-1271 recovery at offset

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 77 | Header exactly at boundary of signatures array (offset + 23 == length, sigLength=0) — succeeds if signer accepts empty signature | [E] | P0 |
| 78 | Full signature exactly at boundary (offset + 23 + sigLength == length) — succeeds | [E] | P0 |
| 79 | Signer is address(0) — staticcall to 0x0 returns false gracefully | [S] | P0 |
| 79.1 | offset + 23 > signatures.length (not enough bytes for header) — returns (false, address(0)) | [N] | P0 |
| 79.2 | Header fits but inner sig doesn't (offset + 23 + sigLength > length) — returns (false, address(0)) | [N] | P0 |
| 79.3 | Valid signer, valid ERC-1271 response — returns (true, signer) | [U] | P0 |
| 79.4 | Valid signer but ERC-1271 returns wrong magic value — returns (false, address(0)) | [N] | P0 |
| 79.5 | Valid signer but ERC-1271 contract reverts — returns (false, address(0)) | [N] | P0 |
| 79.6 | sigLength = 0 (empty inner signature) — header-only, delegates to ERC-1271 with empty bytes | [E] | P0 |
| 79.7 | Signer is an EOA (no code) — staticcall returns empty result, returns (false, address(0)) | [S] | P0 |
| 79.8 | Contract signature at offset > 0, preceded by EOA signature — correct signer and sigLength extraction | [U] | P0 |
| 79.9 | Two consecutive contract signatures — each recovered correctly at sequential offsets | [U] | P0 |
| 79.10 | Very large sigLength (e.g., 1000 bytes) — extracts and validates correctly | [E] | P0 |
| 79.11 | Fuzz: Random valid ERC-1271 signatures at random offsets — always recovers correct signer | [F] | P0 |

#### `_isValidERC1271SignatureNow` — staticcall edge cases

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 80 | Contract returns magic value with extra trailing bytes (result.length > 32) — valid | [E] | P0 |
| 81 | Contract returns exactly 32 bytes but wrong magic — invalid | [N] | P0 |
| 82 | Contract returns fewer than 32 bytes — invalid (result.length < 32 check) | [E][S] | P0 |
| 83 | Contract consumes all gas (out-of-gas in staticcall) — returns false, no revert | [S] | P0 |
| 84 | Contract returns empty bytes (length 0) — invalid | [E] | P0 |
| 84.1 | Contract returns exactly 32 bytes with correct magic value — valid (happy path) | [U] | P0 |
| 84.2 | Signer has no code (EOA) — staticcall success=true but empty result — returns false | [S] | P0 |
| 84.3 | Contract reverts (staticcall success=false) — returns false | [N] | P0 |
| 84.4 | Contract returns very large result (>1000 bytes) starting with magic — valid (length >= 32) | [E] | P0 |
| 84.5 | Contract returns 31 bytes (one short of valid) — invalid | [E] | P0 |
| 84.6 | Contract returns magic value right-padded differently (e.g., `0x1626ba7e00...01`) — invalid (returns false, no revert) | [E] | P0 |
| 84.7 | Contract that attempts state modification during staticcall — reverts, returns false | [S] | P0 |
| 84.8 | Fuzz: Random bytes4 return values — only `0x1626ba7e` (ERC1271_MAGIC_VALUE) produces true | [F] | P0 |

### 1.6 Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 85 | Fuzz: Any valid private key produces recoverable signature via tryRecoverSigner | [F] | P0 |
| 86 | Fuzz: Random bytes never successfully recover a signer (tryRecoverSigner returns false) | [F] | P1 |
| 87 | Fuzz: Signature malleability — flipping s value always rejected by tryRecoverSigner | [F][S] | P0 |
| 87.1 | Fuzz: Random ERC-1271 inner signature lengths — offset calculation always produces correct nextOffset | [F] | P0 |
| 87.2 | Fuzz: Random multi-sig arrays (N EOA + M ERC-1271) — offset chaining iterates all signers correctly | [F] | P0 |
| 87.3 | Fuzz: Random hash values — signature for hash A never validates for hash B | [F][S] | P0 |

---

## 2. MerkleUtils

**Priority: P1 — High**

#### `computeAddressLeaf(address addr)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 88 | Known address produces known leaf (golden test) | [U] | P1 |
| 89 | Double hashing: leaf != keccak256(abi.encode(addr)) (single hash) | [U] | P1 |
| 90 | address(0) produces valid non-zero leaf | [U] | P1 |
| 91 | Two different addresses produce different leaves | [U] | P1 |
| 92 | Same address always produces same leaf (deterministic) | [U] | P1 |
| 93 | Fuzz: No two random addresses produce the same leaf | [F] | P1 |
| 93.1 | Fuzz: Random tree sizes (2-100 leaves) — each leaf verifiable with correct proof | [F] | P1 |
| 93.2 | Fuzz: Modifying any single byte of a valid proof — verification always fails | [F] | P0 |

---

## 3. TokenTransferUtils

**Priority: P0 — Critical (policy validation depends on correct detection)**

### 3.1 Transfer Detection

#### `isTransactionTokenTransfer(bytes calldata data, uint256 value)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 94 | Native transfer: data empty, value > 0 — returns true | [U] | P0 |
| 95 | ERC-20 transfer: correct selector, value = 0 — returns true | [U] | P0 |
| 96 | Contract interaction: data with non-transfer selector — returns false | [U] | P0 |
| 97 | No data, no value — returns false | [E] | P0 |
| 98 | ERC-20 selector but value > 0 — returns false (native takes priority) | [E][S] | P0 |
| 99 | Data length exactly 4 bytes (selector only) — returns false | [E] | P0 |

#### `isTransactionNativeTokenTransfer(bytes calldata data, uint256 value)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 100 | Empty data, value > 0 — returns true | [U] | P0 |
| 101 | Empty data, value = 0 — returns false | [U] | P0 |
| 102 | Non-empty data, value > 0 — returns false | [U] | P0 |
| 102.1 | Non-empty data, value = 0 — returns false | [U] | P0 |

#### `isTransactionERC20TokenTransfer(bytes calldata data, uint256 value)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 103 | transfer(address,uint256) selector, value = 0 — returns true | [U] | P0 |
| 104 | transfer selector, value > 0 — returns false | [U] | P0 |
| 105 | approve(address,uint256) selector — returns false (different selector) | [U] | P0 |
| 106 | transferFrom selector — returns false | [U] | P0 |
| 107 | Data too short (< 4 bytes) — returns false | [E] | P0 |
| 107.1 | Fuzz: Random non-transfer selector with value = 0 — returns false | [F] | P0 |

### 3.2 Extraction Functions

#### `extractERC20TransferRecipient(bytes calldata data)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 108 | Valid transfer calldata — extracts correct recipient | [U] | P0 |
| 109 | Data too short — reverts with `MalformedTokenTransfer` | [N] | P0 |
| 110 | Recipient is address(0) — extracts correctly (no validation) | [E] | P0 |
| 110.1 | data.length == 35 (one byte short of minimum 36) — reverts `MalformedTokenTransfer` | [E] | P0 |
| 110.2 | data.length == 36 (exact minimum: selector + address, no amount word) — succeeds | [E] | P0 |
| 110.3 | Non-transfer selector (`approve`) with valid-length data — reverts `MalformedTokenTransfer` | [N] | P0 |
| 110.4 | Non-transfer selector (`transferFrom`) with valid-length data — reverts `MalformedTokenTransfer` | [N] | P0 |
| 110.5 | Dirty upper bytes in address word (data[4:16] non-zero) — ignores upper bytes, extracts data[16:36] correctly | [S] | P0 |
| 110.6 | Extra trailing data beyond 68 bytes — extracts correct recipient regardless | [E] | P0 |
| 110.7 | data.length == 4 (selector only, no parameters) — reverts `MalformedTokenTransfer` | [E] | P0 |
| 110.8 | Fuzz: Random non-transfer selectors with valid-length data — always reverts `MalformedTokenTransfer` | [F] | P0 |

#### `extractTokenAddress(address to, bytes calldata data)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 111 | Native transfer — returns address(0) | [U] | P0 |
| 112 | ERC-20 transfer — returns `to` (token contract address) | [U] | P0 |
| 112.1 | data is 1 byte (non-empty but minimal) — returns `to` regardless of content | [E] | P0 |
| 112.2 | `to` == address(0), data non-empty — returns address(0), indistinguishable from native path | [E] | P0 |
| 112.4 | Fuzz: Random `to` address with random non-empty data — always returns `to` | [F] | P0 |
| 112.5 | Fuzz: Random `to` address with empty data — always returns address(0) regardless of `to` | [F] | P0 |

#### `extractTransferAmount(bytes calldata data, uint256 value)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 113 | Native transfer (value > 0) — returns `value` | [U] | P0 |
| 114 | ERC-20 transfer — extracts amount from calldata | [U] | P0 |
| 115 | Amount is 0 — returns 0 | [E] | P0 |
| 116 | Amount is type(uint256).max — returns max | [E] | P0 |
| 117 | Data too short — reverts with `MalformedTokenTransfer` | [N] | P0 |
| 117.1 | data.length == 67 (one byte short of minimum 68) — reverts `MalformedTokenTransfer` | [E] | P0 |
| 117.2 | data.length == 68 (exact minimum: selector + address + amount) — succeeds | [E] | P0 |
| 117.3 | data.length > 68 (trailing data beyond amount) — extracts from data[36:68] only, ignores rest | [E] | P0 |
| 117.4 | data.length in [1, 3] (partial selector, not empty) — reverts `MalformedTokenTransfer` | [E] | P0 |
| 117.5 | data.length == 4 (selector only, no params) — reverts `MalformedTokenTransfer` | [E] | P0 |
| 117.6 | data.length == 36 (selector + address, no amount) — reverts `MalformedTokenTransfer` | [E] | P0 |
| 117.7 | Native transfer (empty data), value = 0 — returns 0 (no validation on value) | [E] | P0 |
| 117.8 | Fuzz: Random uint256 amounts encoded in valid 68-byte transfer calldata — always extracts correctly | [F] | P0 |
| 117.9 | Fuzz: Random data lengths in [1, 67] — always reverts `MalformedTokenTransfer` | [F] | P0 |

### 3.3 Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 118 | Fuzz: Any valid ERC-20 transfer calldata extracts correct recipient | [F] | P0 |
| 119 | Fuzz: Any valid ERC-20 transfer calldata extracts correct amount | [F] | P0 |
| 120 | Fuzz: Random data never classified as both native and ERC-20 | [F] | P0 |
| 120.1 | Fuzz: `extractTokenAddress` with random `to` and random data length — returns `to` when non-empty, address(0) when empty | [F] | P0 |
| 120.2 | Fuzz: `extractTransferAmount` with random value and empty data — always returns value exactly | [F] | P0 |

---

## 4. ContractInteractionUtils

**Priority: P2 — Medium**

#### `extractFunctionSelector(bytes calldata data)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 121 | Valid calldata — extracts correct 4-byte selector | [U] | P2 |
| 122 | Exactly 4 bytes — returns those 4 bytes | [E] | P2 |
| 123 | Known function selectors (transfer, approve, etc.) match | [U] | P2 |
| 123.1 | Fuzz: Random calldata (>= 4 bytes) — always extracts correct first 4 bytes | [F] | P2 |
| 123.2 | Data too short (< 4 bytes) — reverts with out-of-bounds slice | [N] | P2 |

---

## 5. TimelockUtils

**Priority: P1 — High**

#### `validateTimelockDurationOrRevert(uint256 timelockDurationSeconds)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 124 | Duration at MIN (2 days) — succeeds | [E] | P1 |
| 125 | Duration at MAX (30 days) — succeeds | [E] | P1 |
| 126 | Duration at MIN - 1 — reverts with `InvalidTimelockDuration` | [N] | P1 |
| 127 | Duration at MAX + 1 — reverts with `InvalidTimelockDuration` | [N] | P1 |
| 128 | Duration of 0 — reverts | [N] | P1 |
| 129 | Mid-range duration (7 days) — succeeds | [U] | P1 |
| 130 | Fuzz: Any duration in [MIN, MAX] succeeds | [F] | P1 |
| 131 | Fuzz: Any duration outside [MIN, MAX] reverts | [F] | P1 |

---

## 6. BytesUtils (Gap Analysis)

**Already tested in `test/BytesUtils.t.sol` (47 tests).** No additional tests needed. Existing coverage is comprehensive including fuzz tests.

---

## Summary

| Library | New Tests | Priority |
|---------|-----------|----------|
| SignatureUtils (public interface) | 59 | P0 |
| SignatureUtils (private helpers) | 64 | P0 |
| SignatureUtils (additional fuzz) | 3 | P0 |
| MerkleUtils | 8 | P1 |
| TokenTransferUtils | 51 | P0 |
| ContractInteractionUtils | 4 | P2 |
| TimelockUtils | 8 | P1 |
| **Total** | **197** | |
