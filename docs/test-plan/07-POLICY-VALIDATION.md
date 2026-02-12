# 07 — Policy Validation Libraries Test Plan

**Files Under Test:**
- `src/organization/libraries/policy/LibPolicyApproval.sol`
- `src/organization/libraries/policy/LibPolicyInitiator.sol`
- `src/organization/libraries/policy/LibPolicyDestination.sol`
- `src/organization/libraries/policy/LibPolicyTokenTransfer.sol`
- `src/organization/libraries/policy/LibPolicyContractInteraction.sol`
- `src/organization/libraries/policy/LibPolicyParameterConstraints.sol`
- `src/organization/libraries/policy/LibPolicyRateLimits.sol` (already partially tested)

**Test File(s):** `test/LibPolicyApproval.t.sol`, `test/LibPolicyInitiator.t.sol`, `test/LibPolicyDestination.t.sol`, `test/LibPolicyTokenTransfer.t.sol`, `test/LibPolicyContractInteraction.t.sol`, `test/LibPolicyParameterConstraints.t.sol`

---

## 1. LibPolicyApproval

**Priority: P0 — Critical**

### 1.1 `areApprovalsValid`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Group approver: threshold=1, one valid group member signature — true | [U] | P0 |
| 2 | Group approver: threshold=2, two valid group member signatures — true | [U] | P0 |
| 3 | Group approver: threshold=2, one valid signature — false | [N] | P0 |
| 4 | Group approver: signer is org member but not in required group — reverts `UnauthorizedApprovalSigner` | [S] | P0 |
| 5 | Group approver: signer is not org member at all — reverts `UnauthorizedApprovalSigner` | [S] | P0 |
| 6 | Member approver: exact member signs — true (threshold=1) | [U] | P0 |
| 7 | Member approver: wrong member signs — reverts `UnauthorizedApprovalSigner` | [S] | P0 |
| 8 | Signers not in ascending address order — reverts `DuplicateOrOutOfOrderSigner` | [S] | P0 |
| 9 | Duplicate signer addresses — reverts `DuplicateOrOutOfOrderSigner` | [S] | P0 |
| 10 | Empty signatures — returns false | [N] | P0 |
| 11 | Group approver with deleted group — reverts `GroupDoesNotExist` | [S] | P0 |
| 12 | Mixed EOA + ERC-1271 approval signatures | [U] | P0 |
| 13 | More signers than threshold — succeeds after threshold met | [E] | P0 |
| 13.1 | Group approver with threshold=0 and valid signatures — reverts (zero threshold must not be allowed) | [S] | P0 |
| 13.2 | Group approver: authorized group member signs wrong message hash — recovered address is not an authorized approver, reverts `UnauthorizedApprovalSigner` | [S] | P0 |
| 13.3 | Member approver: authorized member signs wrong message hash — recovered address differs from approverMember, reverts `UnauthorizedApprovalSigner` | [S] | P0 |

### 1.2 `getRequiredApprovals`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 14 | Member approver type — returns 1 | [U] | P1 |
| 15 | Group approver type — returns `approvalThreshold` from config | [U] | P1 |
| 16 | Group approver with threshold=0 — reverts (zero threshold must not be allowed) | [S] | P0 |

---

## 2. LibPolicyInitiator

**Priority: P0 — Critical**

### 2.1 `isInitiatorAuthorized`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 19 | `anyInitiator=true`, initiator is org member — authorized | [U] | P0 |
| 20 | `anyInitiator=true`, initiator is NOT an org member — not authorized (must be member regardless) | [S] | P0 |
| 20.1 | `anyInitiator=true`, initiator is address(0) — not authorized (address(0) is never a member) | [S] | P0 |
| 21 | Member initiator type: exact member address — authorized | [U] | P0 |
| 22 | Member initiator type: different address — not authorized | [N] | P0 |
| 23 | Member initiator type: address is member but not the specified one — not authorized | [U] | P0 |
| 24 | Group initiator type: member in correct group — authorized | [U] | P0 |
| 25 | Group initiator type: member not in group — not authorized | [N] | P0 |
| 26 | Group initiator type: non-member of org — not authorized | [N] | P0 |
| 27 | Group initiator type: deleted group — not authorized (returns false) | [S] | P0 |
| 28 | Non-member of org with anyInitiator=false — not authorized | [U] | P0 |
| 29 | Initiator is member but group doesn't exist — returns false | [E] | P0 |

---

## 3. LibPolicyDestination

**Priority: P0 — Critical**

### 3.1 `getActualDestination`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 30 | Native transfer (empty data, value > 0) — returns `to` | [U] | P0 |
| 31 | ERC-20 transfer — returns extracted recipient | [U] | P0 |
| 32 | Contract interaction — returns `to` | [U] | P0 |
| 33 | ERC-20 transfer where recipient differs from `to` — returns recipient, not `to` | [U] | P0 |

### 3.2 `isDestinationAllowedByPolicy`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 34 | `destinationType=Any` — always returns true | [U] | P0 |
| 35 | `destinationType=CustomList` with valid Merkle proof — returns true | [U] | P0 |
| 36 | `destinationType=CustomList` with invalid proof — returns false | [N] | P0 |
| 37 | `destinationType=CustomList`, destination not in list — returns false | [N] | P0 |
| 38 | CustomList with ERC-20: validates actual recipient, not `to` address | [S] | P0 |
| 39 | Destination leaf uses double hashing | [U] | P1 |
| 40 | Invalid destination type (not Any or CustomList) — returns false | [E] | P0 |

---

## 4. LibPolicyTokenTransfer

**Priority: P0 — Critical**

### 4.1 `isTokenTransferAllowedByPolicy`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 41 | Native transfer, anyToken=true, no threshold — allowed | [U] | P0 |
| 42 | ERC-20 transfer, matching token address — allowed | [U] | P0 |
| 43 | ERC-20 transfer, wrong token address — not allowed | [N] | P0 |
| 44 | Native transfer, token address = address(0) — allowed | [U] | P0 |
| 45 | Native transfer, token address != address(0) — not allowed | [N] | P0 |

### 4.2 Amount Threshold

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 46 | `hasAmountThreshold=false` — any amount allowed | [U] | P0 |
| 47 | Amount below threshold — allowed | [U] | P0 |
| 48 | Amount exactly at threshold — NOT allowed (strict `<`) | [E][S] | P0 |
| 49 | Amount above threshold — not allowed | [N] | P0 |
| 50 | Amount = 0 — allowed (0 < any positive threshold) | [E] | P0 |
| 51 | Threshold = 1 — only 0-value transfers allowed | [E] | P0 |
| 52 | Threshold = type(uint256).max — virtually unlimited | [E] | P1 |

### 4.3 Destination Validation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 53 | Token transfer destination validated via `LibPolicyDestination` | [I] | P0 |
| 54 | All three checks must pass: token + amount + destination | [U] | P0 |

---

## 5. LibPolicyContractInteraction

**Priority: P0 — Critical**

### 5.1 Function Allowlist

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 55 | `anyFunction=true` — any function allowed | [U] | P0 |
| 56 | Specific function with valid Merkle proof — allowed | [U] | P0 |
| 57 | Specific function with invalid proof — not allowed | [N] | P0 |
| 58 | Data length < 4 bytes (no selector) — not allowed | [E] | P0 |
| 59 | Function leaf includes constraints hash (selector + constraintsHash) | [U] | P0 |
| 60 | Same selector with different constraints — different leaf | [U] | P0 |
| 61 | Empty constraints — specific hash (keccak256 of empty bytes) | [E] | P1 |

### 5.2 Combined Validation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 62 | All three must pass: destination + function + parameters | [U] | P0 |
| 63 | Destination allowed but function not — rejected | [N] | P0 |
| 64 | Function allowed but destination not — rejected | [N] | P0 |
| 65 | Function and destination allowed but parameters fail — rejected | [N] | P0 |

---

## 6. LibPolicyParameterConstraints

**Priority: P0 — Critical**

### 6.1 General Constraint Processing

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 66 | Empty constraints — allows any parameters | [U] | P0 |
| 67 | Constraint type = Any — allows any value for that parameter | [U] | P0 |
| 68 | Multiple constraints checked sequentially | [U] | P0 |
| 69 | First constraint fails — returns false immediately | [U] | P0 |
| 70 | `paramCalldataHeadSlotCount = 0` — returns false | [E] | P0 |
| 71 | Insufficient calldata for parameter — returns false | [E] | P0 |

### 6.2 Bool Constraints

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 72 | Bool constraint Exact(true): parameter=true — pass | [U] | P0 |
| 73 | Bool constraint Exact(true): parameter=false — fail | [N] | P0 |
| 74 | Bool constraint Exact(false): parameter=false — pass | [U] | P0 |
| 75 | Bool constraint Any: any bool value passes | [U] | P0 |
| 76 | Non-zero value treated as true (e.g., 2, 0xff) | [E] | P0 |

### 6.3 Uint Constraints

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 77 | Uint Exact: matching value — pass | [U] | P0 |
| 78 | Uint Exact: non-matching value — fail | [N] | P0 |
| 79 | Uint Range: value within range — pass | [U] | P0 |
| 80 | Uint Range: value at min boundary — pass (inclusive) | [E] | P0 |
| 81 | Uint Range: value at max boundary — pass (inclusive) | [E] | P0 |
| 82 | Uint Range: value below min — fail | [N] | P0 |
| 83 | Uint Range: value above max — fail | [N] | P0 |
| 84 | Uint Range: min == max — only that exact value passes | [E] | P0 |
| 85 | Uint Range: min > max — no value passes | [E][S] | P0 |

### 6.4 Int Constraints

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 86 | Int Exact: matching positive value — pass | [U] | P0 |
| 87 | Int Exact: matching negative value — pass | [U] | P0 |
| 88 | Int Range: negative to positive range — pass for values in range | [U] | P0 |
| 89 | Int Range: min = type(int256).min, max = type(int256).max — all pass | [E] | P0 |
| 90 | Int two's complement: bytes32 with high bit set correctly interpreted | [E] | P0 |

### 6.5 Address Constraints

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 91 | Address Exact: matching address — pass | [U] | P0 |
| 92 | Address Exact: non-matching address — fail | [N] | P0 |
| 93 | Address OneOf: address in Merkle tree — pass | [U] | P0 |
| 94 | Address OneOf: address not in tree — fail | [N] | P0 |
| 95 | Address extraction from bytes32 (right-aligned 160 bits) correct | [U] | P0 |
| 96 | Address OneOf with address(0) — passes if in tree | [E] | P0 |

### 6.6 FixedBytes Constraints

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 97 | FixedBytes Exact: matching bytes32 — pass | [U] | P0 |
| 98 | FixedBytes Exact: non-matching — fail | [N] | P0 |
| 99 | bytes1 value (left-aligned): correct padding comparison | [E] | P0 |

### 6.7 Bytes/String Constraints (Hash-Based)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 100 | Bytes Exact: hash matches — pass | [U] | P0 |
| 101 | Bytes Exact: hash doesn't match — fail | [N] | P0 |
| 102 | String Exact: hash matches — pass | [U] | P0 |
| 103 | Empty bytes: keccak256("") hash works correctly | [E] | P0 |
| 104 | Large bytes data: offset and length computed correctly | [E] | P0 |
| 105 | Invalid offset (points beyond calldata) — returns false | [E][S] | P0 |

### 6.8 Array/Struct Constraints

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 106 | Array parameter with Any constraint — passes | [U] | P0 |
| 107 | Array parameter with non-Any constraint — fails (unsupported) | [N] | P0 |
| 108 | Struct parameter with Any constraint — passes | [U] | P0 |
| 109 | Struct parameter with non-Any constraint — fails (unsupported) | [N] | P0 |

### 6.9 Multi-Parameter Constraints

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 110 | Two uint parameters: both pass — overall pass | [U] | P0 |
| 111 | Two uint parameters: first passes, second fails — overall fail | [U] | P0 |
| 112 | Mixed parameter types: address + uint + bool — all validated | [U] | P0 |
| 113 | Parameter offset accumulation correct across multiple params | [U] | P0 |
| 114 | Multi-slot parameter (2 slots) with Any constraint — offset advances by 2 slots | [E] | P0 |

---

## 7. LibPolicyRateLimits (Gap Analysis)

**Existing tests cover 24 cases. Gaps to fill:**

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 115 | Rate limit with `usageAmount = 0` — allowed, no state change | [E] | P1 |
| 116 | Rate limit with `timeIntervalLimit = 0` — blocks all usage | [E] | P0 |
| 117 | Rate limit with `usageAmount = type(uint256).max` — exceeds any realistic limit | [E] | P0 |
| 118 | Fuzz: Random usage amounts below limit always succeed | [F] | P0 |
| 119 | Fuzz: Random usage amounts above limit always fail | [F] | P0 |
| 120 | Multiple rate-limited operations in same block — cumulative tracking | [I] | P0 |

---

## 7.5 LibPolicyRateLimits — Rate Limit Overflow Safety

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 115.1 | Rate limit: currentUsage + usageAmount would overflow uint256 — returns false (no overflow) | [S] | P0 |
| 115.2 | Rate limit: usageAmount = type(uint256).max with currentUsage > 0 — returns false | [S] | P0 |

---

## 8. Private Function Tests (Requires `private` → `internal` Conversion)

> **Prerequisite:** The functions below are `private` in their respective libraries.
> Convert them to `internal` and expose via test harnesses. Direct testing enables precise
> assertions on authorization routing and Merkle leaf computation that can't be fully
> isolated through the public interface.

### 8.1 `_isSignerAuthorizedForPolicy` (LibPolicyApproval)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 120.1 | Non-member of org — returns false (not revert) | [N] | P0 |
| 120.2 | Member, ApproverType.Member, signer == approverMember — returns true | [U] | P0 |
| 120.3 | Member, ApproverType.Member, signer != approverMember — returns false | [N] | P0 |
| 120.4 | Member, ApproverType.Group, signer in group — returns true | [U] | P0 |
| 120.5 | Member, ApproverType.Group, signer not in group — returns false | [N] | P0 |
| 120.6 | Member, unrecognized ApproverType — returns false | [E] | P0 |

### 8.2 `_isFunctionAllowedByPolicy` (LibPolicyContractInteraction)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 120.7 | `anyFunction = true` — returns true regardless of data | [U] | P0 |
| 120.8 | Data length < 4 bytes — returns false | [E] | P0 |
| 120.9 | Valid selector + constraints with valid Merkle proof — returns true | [U] | P0 |
| 120.10 | Valid selector but invalid proof — returns false | [N] | P0 |
| 120.11 | Same selector with different constraints — different leaf, different proof | [S] | P0 |

### 8.3 `_computeFunctionLeaf` (LibPolicyContractInteraction)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 120.12 | Known selector + constraintsHash → known leaf (golden test) | [U] | P1 |
| 120.13 | Double hashing: leaf != keccak256(abi.encode(selector, constraintsHash)) | [S] | P0 |
| 120.14 | Different selectors produce different leaves | [U] | P1 |
| 120.15 | Same selector, different constraintsHash — different leaves | [U] | P1 |
| 120.16 | Empty constraints (keccak256("")) — produces valid non-zero leaf | [E] | P1 |

---

## 9. Cross-Library Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 121 | Fuzz: Random policy configs with TokenTransfer type validate correctly | [F] | P0 |
| 122 | Fuzz: Random policy configs with ContractInteraction type validate correctly | [F] | P0 |
| 123 | Fuzz: Random parameter constraint values match expected behavior | [F] | P0 |
| 124 | Fuzz: Random address in/not in Merkle tree — correct validation | [F] | P0 |
| 125 | Fuzz: Random bool parameter values match Exact constraint correctly | [F] | P0 |
| 126 | Fuzz: Random uint values against Exact constraint — only matching value passes | [F] | P0 |
| 127 | Fuzz: Random int values against Range — two's complement comparison correct | [F] | P0 |
| 128 | Fuzz: Random fixed bytes values against Exact constraint — correct matching | [F] | P0 |
| 129 | Fuzz: Random approval thresholds with exact number of valid group signers — always pass | [F] | P0 |
| 130 | Fuzz: Random destination addresses in/not in Merkle tree — correct validation result | [F] | P0 |
| 131 | Fuzz: Random amount values against threshold — strict `<` boundary correct | [F] | P0 |
| 132 | Fuzz: Random function selectors with valid Merkle proofs — always verified | [F] | P0 |

---

## 10. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 133 | **Rate limit monotonicity**: Within a time window, policy usage can only increase or stay the same | P0 |
| 134 | **Rate limit reset**: Usage resets to 0 when a new time window begins | P0 |
| 135 | **Rate limit no-overflow**: `currentUsage + usageAmount` never wraps — function returns false first | P0 |
| 136 | **Parameter constraint termination**: Constraint validation always terminates (no infinite loops) | P0 |

---

## Summary

| Library | New Tests | Priority |
|---------|-----------|----------|
| LibPolicyApproval | 19 | P0 |
| LibPolicyInitiator | 12 | P0 |
| LibPolicyDestination | 11 | P0 |
| LibPolicyTokenTransfer | 14 | P0 |
| LibPolicyContractInteraction | 11 | P0 |
| LibPolicyParameterConstraints | 49 | P0 |
| LibPolicyRateLimits (gaps) | 6 | P0-P1 |
| Rate limit overflow safety | 2 | P0 |
| Private function tests | 16 | P0-P1 |
| Cross-library fuzz | 12 | P0 |
| Invariant tests | 4 | P0 |
| **Total** | **156** | |
