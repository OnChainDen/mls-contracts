# 10 — Account Factory Test Plan

**Files Under Test:**
- `src/organization/libraries/LibOrganizationAccountFactory.sol`
- `src/organization/base/OrganizationAccountFactoryBase.sol`
- `src/account/AccountProxy.sol`
- `src/interfaces/organization/IOrganizationAccountFactory.sol`

**Test File(s):** `test/AccountFactory.t.sol`

---

## 1. Account Deployment

**Priority: P1 — High**

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Deploy account with valid salt — succeeds, returns correct address | [U] | P1 |
| 2 | Deployed address matches `computeAccountAddress` result | [U] | P1 |
| 3 | Deployed account's beacon is the Organization | [U] | P1 |
| 4 | Deployed account is tracked in `deployedAccounts` mapping | [U] | P1 |
| 5 | Deploy account emits `AccountDeployed` event | [EV] | P1 |
| 6 | Deploy same salt twice — second reverts (CREATE2 collision) | [N] | P1 |
| 7 | Deploy account requires admin authorization | [U] | P1 |
| 8 | Account implementation must be set before deployment | [N] | P1 |

---

## 2. Account Implementation Management

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 9 | Set account implementation — succeeds | [U] | P1 |
| 10 | Implementation must be whitelisted — reverts if not | [N] | P1 |
| 11 | Set implementation emits `AccountImplementationUpdated` event | [EV] | P1 |
| 12 | Set implementation requires admin authorization | [U] | P1 |
| 13 | `implementation()` returns current implementation (IBeacon interface) | [U] | P1 |
| 14 | `implementation()` reverts with `AccountImplementationNotSet` when not set | [N] | P1 |

---

## 3. CREATE2 Address Computation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 15 | `computeAccountAddress` is deterministic for same salt | [U] | P1 |
| 16 | Different salts produce different addresses | [U] | P1 |
| 17 | Computed address matches deployed address | [U] | P1 |
| 18 | Address computation includes organization address (deployer) | [U] | P1 |

---

## 4. Account Validation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 19 | `isAccountDeployedByOrganization` returns true for deployed account | [U] | P1 |
| 20 | `isAccountDeployedByOrganization` returns false for unknown address | [U] | P1 |
| 21 | `validateIsAccountDeployedByOrgOrRevert` succeeds for deployed account | [U] | P1 |
| 22 | `validateIsAccountDeployedByOrgOrRevert` reverts for non-org account | [N] | P1 |

---

## 5. Beacon Proxy Behavior

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 23 | Account proxy delegates calls to implementation from beacon | [I] | P1 |
| 24 | Updating implementation on Organization changes Account behavior | [I] | P1 |
| 25 | Account's `getOrganizationAddress()` returns correct organization | [U] | P1 |

---

## 6. Access Control

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 26 | `deployAccount` reverts when caller is not guardian | [N] | P1 |
| 27 | `setAccountImplementation` reverts when caller is not guardian | [N] | P1 |
| 28 | View functions callable by anyone | [U] | P3 |

---

## 7. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 29 | Fuzz: Random salts always produce unique addresses | [F] | P1 |
| 30 | Fuzz: Random salts always produce deployable accounts | [F] | P1 |
| 31 | Fuzz: Random non-whitelisted implementation addresses always rejected | [F] | P1 |
| 32 | Fuzz: Computed address matches deployed address for any valid salt | [F] | P1 |

---

## 8. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 33 | **Account tracking**: Every account deployed via `deployAccount` is tracked in `deployedAccounts` mapping | P0 |
| 34 | **Account-org binding**: An Account's beacon (Organization) address never changes after deployment | P0 |
| 35 | **Whitelist enforcement**: No account implementation can be set unless it's whitelisted | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Account deployment | 8 | P1 |
| Implementation management | 6 | P1 |
| CREATE2 computation | 4 | P1 |
| Account validation | 4 | P1 |
| Beacon proxy behavior | 3 | P1 |
| Access control | 3 | P1-P3 |
| Fuzz tests | 4 | P1 |
| Invariant tests | 3 | P0 |
| **Total** | **35** | |
