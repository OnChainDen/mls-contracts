# 14 — Upgrade System Test Plan

**Files Under Test:**
- `src/organization/OrganizationImplementation.sol` (upgrade functions)
- `src/implementation-whitelist/ImplementationWhitelistImplementation.sol`

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

### 1.4 Upgrade Flag Edge Cases

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 13.1 | [AUDIT] Failed upgrade (bad init data in `data` param): flag does NOT remain stuck true (tx reverts entirely) | [S] | P0 |
| 13.2 | [AUDIT] `_authorizeUpgrade` succeeds regardless of newImplementation param value when flag is true | [S] | P1 |
| 13.3 | [AUDIT] Multiple inheritance: all base contract functions accessible through OrganizationImplementation | [I] | P1 |

---

## 3. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 18 | Fuzz: Random non-whitelisted addresses always rejected for upgrade | [F] | P1 |
| 19 | Fuzz: Random whitelisted implementations with valid auth — upgrade always succeeds | [F] | P1 |
| 20 | Fuzz: Random calldata in upgrade `data` parameter — always forwarded to new implementation | [F] | P1 |

---

## 4. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 21 | **Authorization flag reset**: `isUpgradeAuthorized` is always false outside of `upgradeToAndCallWithAuthorization` | P0 |
| 22 | **Whitelist enforcement**: No implementation can be set/upgraded to unless it's whitelisted | P0 |
| 23 | **Storage preservation**: All organization state (members, admins, groups, policies) survives upgrades | P1 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Authorization flow | 6 | P1 |
| Post-upgrade | 4 | P1 |
| Authorization flag | 3 | P1 |
| Account beacon upgrade | 4 | P1 |
| Upgrade flag edge cases | 3 | P0-P1 |
| Fuzz tests | 3 | P1 |
| Invariant tests | 3 | P0-P1 |
| **Total** | **26** | |
