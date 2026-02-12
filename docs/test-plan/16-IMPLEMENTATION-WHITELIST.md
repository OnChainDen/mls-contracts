# 16 — Implementation Whitelist Test Plan

**Files Under Test:**
- `src/implementation-whitelist/ImplementationWhitelistImplementation.sol`
- `src/implementation-whitelist/ImplementationWhitelistProxy.sol`
- `src/implementation-whitelist/libraries/storage/LibImplementationWhitelistStorage.sol`
- `src/interfaces/IImplementationWhitelist.sol`

**Test File(s):** `test/ImplementationWhitelist.t.sol`

---

## 1. Initialization

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Initialize with owner and implementation lists — succeeds | [U] | P2 |
| 2 | After init: owner set correctly | [U] | P2 |
| 3 | After init: organization implementations whitelisted | [U] | P2 |
| 4 | After init: account implementations whitelisted | [U] | P2 |
| 5 | `isInitialized()` returns true after init | [U] | P2 |
| 6 | Initialize emits `ImplementationWhitelistInitialized` event | [EV] | P2 |
| 7 | Cannot initialize twice — reverts | [N] | P2 |

---

## 2. Whitelist Management

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 8 | Add organization implementation — whitelisted | [U] | P2 |
| 9 | Add account implementation — whitelisted | [U] | P2 |
| 10 | Remove organization implementation — unwhitelisted | [U] | P2 |
| 11 | Add then remove same implementation — net unwhitelisted | [U] | P2 |
| 12 | Add emits `ImplementationWhitelisted` event | [EV] | P2 |
| 13 | Remove emits `ImplementationUnwhitelisted` event | [EV] | P2 |
| 14 | Only owner can call `whitelistImplementations` | [N] | P2 |
| 15 | Non-owner caller — reverts | [N] | P2 |

---

## 3. Validation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 16 | `isImplementationWhitelisted` returns true for whitelisted impl | [U] | P2 |
| 17 | `isImplementationWhitelisted` returns false for non-whitelisted impl | [U] | P2 |
| 18 | `validateIsImplementationWhitelistedOrRevert` succeeds for whitelisted | [U] | P2 |
| 19 | `validateIsImplementationWhitelistedOrRevert` reverts for non-whitelisted | [N] | P2 |
| 20 | Organization vs Account contract types checked independently | [U] | P2 |

---

## 4. Upgrade Authorization

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 21 | `_authorizeUpgrade` only callable by owner (Ownable2StepUpgradeable) | [N] | P2 |
| 22 | Whitelist itself upgradeable via UUPS | [I] | P2 |

---

## 5. Private Function Tests (Requires `private` → `internal` Conversion)

> **Prerequisite:** The functions below are currently `private` in `ImplementationWhitelistImplementation`.
> For contract functions, create a test contract that inherits from the implementation
> and exposes each private function via a public wrapper (requires converting `private` to `internal`).

### 5.1 `_addToWhitelist`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 25 | Add single implementation — `whitelisted[type][impl] = true` | [U] | P2 |
| 26 | Add multiple implementations — all whitelisted | [U] | P2 |
| 27 | Add same implementation twice — second is no-op (idempotent, still true) | [E] | P2 |
| 28 | Emits `ImplementationWhitelisted` for each address | [EV] | P2 |
| 29 | Organization and Account types are independent — adding to one doesn't affect other | [U] | P2 |
| 30 | Empty implementations array — no-op, no revert | [E] | P2 |

### 5.2 `_removeFromWhitelist`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 31 | Remove whitelisted implementation — `whitelisted[type][impl] = false` | [U] | P2 |
| 32 | Remove non-whitelisted implementation — no-op (idempotent, still false) | [E] | P2 |
| 33 | Emits `ImplementationUnwhitelisted` for each address | [EV] | P2 |
| 34 | Empty implementations array — no-op, no revert | [E] | P2 |

---

## 6. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 23 | Fuzz: Random addresses whitelisted and verified correctly | [F] | P2 |
| 24 | Fuzz: Random addresses not whitelisted correctly rejected | [F] | P2 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Initialization | 7 | P2 |
| Whitelist management | 8 | P2 |
| Validation | 5 | P2 |
| Upgrade auth | 2 | P2 |
| Private function tests | 10 | P2 |
| Fuzz tests | 2 | P2 |
| **Total** | **34** | |
