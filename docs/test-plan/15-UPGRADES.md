# 15 — Upgrade System Test Plan

**Files Under Test:**
- `src/organization/OrganizationImplementation.sol` (upgrade functions)
- `src/organization/libraries/storage/LibOrganizationUpgradeStorage.sol`
- `src/implementation-whitelist/ImplementationWhitelistImplementation.sol`

**Test File(s):** `test/OrganizationUpgrade.t.sol`

---

## 1. Organization UUPS Upgrade

**Priority: P1 — High**

### 1.1 Authorization Flow

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | `upgradeToAndCallWithAuthorization`: valid guardian + admin auth + whitelisted impl — succeeds | [I] | P1 |
| 2 | Caller is not guardian — reverts | [N] | P1 |
| 3 | Admin signatures insufficient — reverts | [N] | P1 |
| 4 | Implementation not whitelisted — reverts `ImplementationNotWhitelisted` | [N] | P1 |
| 5 | Authorization flag set before upgrade call and reset after | [S] | P1 |
| 6 | Direct call to `upgradeToAndCall` (bypassing authorization) — reverts `UnauthorizedUpgrade` | [S] | P1 |

### 1.2 Post-Upgrade Behavior

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 7 | After upgrade: new implementation code active | [I] | P1 |
| 8 | After upgrade: existing storage preserved | [I] | P1 |
| 9 | After upgrade: all modules still function correctly | [I] | P1 |
| 10 | Upgrade with `data` parameter — calls function on new implementation | [I] | P1 |

### 1.3 Authorization Flag Safety

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 11 | Flag is true only during upgrade execution | [S] | P1 |
| 12 | Flag reset to false even on upgrade failure | [S] | P1 |
| 13 | Concurrent upgrade attempts — flag prevents race conditions | [S] | P1 |

---

## 2. Account Beacon Upgrade

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 14 | `setAccountImplementation` updates beacon implementation | [U] | P1 |
| 15 | All existing accounts now use new implementation | [I] | P1 |
| 16 | New accounts also use new implementation | [I] | P1 |
| 17 | Account implementation must be whitelisted | [N] | P1 |

---

## 3. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 18 | Fuzz: Random non-whitelisted addresses always rejected for upgrade | [F] | P1 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Authorization flow | 6 | P1 |
| Post-upgrade | 4 | P1 |
| Authorization flag | 3 | P1 |
| Account beacon upgrade | 4 | P1 |
| Fuzz tests | 1 | P1 |
| **Total** | **18** | |
