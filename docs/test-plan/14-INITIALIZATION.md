# 14 — Initialization Test Plan

**Files Under Test:**
- `src/organization/libraries/LibOrganizationInitialization.sol`
- `src/organization/base/OrganizationInitializationBase.sol`
- `src/organization/OrganizationFactory.sol`
- `src/organization/OrganizationProxy.sol`
- `src/interfaces/organization/IOrganizationInitialization.sol`
- `src/interfaces/IOrganizationFactory.sol`

**Test File(s):** `test/OrganizationInitialization.t.sol`, `test/OrganizationFactory.t.sol`

---

## 1. Organization Factory

**Priority: P1 — High**

### 1.1 Deployment

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Deploy organization with valid params — succeeds, returns address | [I] | P1 |
| 2 | Deployed address matches `computeOrganizationAddress` | [U] | P1 |
| 3 | Only authorized deployer can call `deployOrganization` — others revert `UnauthorizedDeployer` | [N] | P1 |
| 4 | Implementation must be whitelisted — reverts if not | [N] | P1 |
| 5 | Factory emits `OrganizationDeployed` event | [EV] | P1 |
| 6 | Deploy with same salt twice — reverts (CREATE2 collision) | [N] | P1 |

### 1.2 Constructor

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 7 | Constructor with address(0) deployer — reverts `ZeroAddress` | [N] | P1 |
| 8 | `DEPLOYER_ADDRESS()` returns correct deployer | [U] | P1 |

### 1.3 CREATE2 Address Computation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 9 | `computeOrganizationAddress` deterministic for same inputs | [U] | P1 |
| 10 | Different salts produce different addresses | [U] | P1 |
| 11 | Different implementations produce different addresses | [U] | P1 |
| 12 | Different whitelist addresses produce different addresses | [U] | P1 |

---

## 2. Organization Initialization

**Priority: P1 — High**

### 2.1 Happy Path

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 13 | Initialize with valid params: members, admins, groups, guardian, timelock — succeeds | [I] | P1 |
| 14 | After init: members are set correctly | [U] | P1 |
| 15 | After init: admins are set correctly | [U] | P1 |
| 16 | After init: voting threshold is set correctly | [U] | P1 |
| 17 | After init: groups are created correctly | [U] | P1 |
| 18 | After init: guardian is set correctly | [U] | P1 |
| 19 | After init: timelock duration is set correctly | [U] | P1 |
| 20 | After init: `isInitialized()` returns true | [U] | P1 |
| 21 | Organization emits `OrganizationInitialized` event | [EV] | P1 |

### 2.2 Optional Recovery Initialization

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 22 | Init with guardian recovery address — recovery configured | [U] | P1 |
| 23 | Init with address(0) guardian recovery — recovery NOT configured (deferred) | [E] | P1 |
| 24 | Init with tx recovery address — tx recovery configured | [U] | P1 |
| 25 | Init with address(0) tx recovery — tx recovery NOT configured (deferred) | [E] | P1 |

### 2.3 Error Cases

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 26 | Init with no members — reverts `NoMembersProvided` | [N] | P1 |
| 27 | Init called twice — reverts `AlreadyInitialized` | [S] | P1 |
| 28 | Init by non-deployer — reverts `UnauthorizedDeployer` | [S] | P1 |
| 29 | Init with admin who is not in members list — reverts `AdminNotMember` | [N] | P1 |
| 30 | Init with zero voting threshold — reverts `InvalidAdminVotingThreshold` | [N] | P1 |
| 31 | Init with threshold > admin count — reverts | [N] | P1 |
| 32 | Init with address(0) guardian — reverts `InvalidGuardianAddress` | [N] | P1 |
| 33 | Init with invalid timelock duration — reverts `InvalidTimelockDuration` | [N] | P1 |

### 2.4 Initialization Ordering

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 34 | Members added before admins (admin-must-be-member invariant enforced) | [U] | P1 |
| 35 | Groups created after members (group members may be org members) | [U] | P1 |
| 36 | Timelock initialized before guardian recovery (recovery uses timelock) | [U] | P1 |

---

## 3. Proxy Setup

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 37 | OrganizationProxy stores deployer address correctly | [U] | P1 |
| 38 | OrganizationProxy stores whitelist address correctly | [U] | P1 |
| 39 | OrganizationProxy sets implementation correctly | [U] | P1 |
| 40 | Proxy delegates all calls to implementation | [I] | P1 |

---

## 4. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 41 | Fuzz: Random valid initialization params — always succeeds | [F] | P1 |
| 42 | Fuzz: Random salt values produce unique organization addresses | [F] | P1 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Factory deployment | 6 | P1 |
| Factory constructor | 2 | P1 |
| CREATE2 computation | 4 | P1 |
| Initialization happy path | 9 | P1 |
| Optional recovery | 4 | P1 |
| Error cases | 8 | P1 |
| Initialization ordering | 3 | P1 |
| Proxy setup | 4 | P1 |
| Fuzz tests | 2 | P1 |
| **Total** | **42** | |
