# 13 — Initialization and Contract Setup Test Plan

**Files Under Test:**
- `src/organization/OrganizationFactory.sol`
- `src/organization/base/OrganizationInitializationBase.sol`
- `src/organization/libraries/LibOrganizationInitialization.sol`
- `src/organization/OrganizationProxy.sol`

**Scope Notes:**
- This plan intentionally excludes interface files and storage libraries.
- Private functions should be tested via harnesses by changing `private` to `internal` in test-only builds.

---

## File 1: `OrganizationFactory.sol`

### 1.1 `constructor(address _deployerAddress)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Constructor with `address(0)` deployer — reverts `ZeroAddress` | [N] | P0 |
| 2 | Constructor with non-zero deployer — stores `DEPLOYER_ADDRESS` correctly | [U] | P1 |
| 3 | `DEPLOYER_ADDRESS` is immutable across all operations | [S] | P1 |

---

### 1.2 `deployOrganization(bytes32 salt, address implementationAddress, address whitelistAddress, InitializationParams initParams)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 4 | Authorized deployer + valid params — deploy succeeds and returns organization address | [I] | P0 |
| 5 | Returned address equals `computeOrganizationAddress(salt, implementationAddress, whitelistAddress)` | [U] | P0 |
| 6 | Emits `OrganizationDeployed(organizationAddress, salt, DEPLOYER_ADDRESS)` with correct values | [EV] | P1 |
| 7 | Unauthorized caller — reverts `UnauthorizedDeployer` | [N] | P0 |
| 8 | Non-whitelisted implementation — reverts via whitelist validation | [N] | P0 |
| 9 | `implementationAddress == address(0)` — reverts (desired behavior: invalid implementation must not deploy) | [N] | P0 |
| 10 | `implementationAddress` is EOA/non-contract — reverts (desired behavior: implementation must have code) | [N] | P0 |
| 11 | `whitelistAddress == address(0)` — reverts (desired behavior: whitelist must be configured) | [S] | P0 |
| 12 | `whitelistAddress` is EOA/non-contract — reverts (desired behavior: whitelist check cannot be bypassed) | [S] | P0 |
| 13 | Same `(salt, implementationAddress, whitelistAddress)` deployed twice — second deploy reverts (CREATE2 collision) | [N] | P1 |
| 14 | Same `salt` with different implementation — different address, both deployments can succeed | [U] | P1 |
| 15 | Same `salt` with different whitelist — different address, both deployments can succeed | [U] | P1 |
| 16 | Invalid init params (e.g. no members) — entire tx reverts and no contract code exists at computed address | [S] | P0 |
| 17 | If initialization reverts, `OrganizationDeployed` is not persisted in logs | [S] | P1 |
| 18 | After failed deploy with a salt, retrying same tuple with valid params succeeds (no stuck salt) | [U] | P1 |
| 19 | Successfully deployed organization is already initialized in same tx (`isInitialized() == true`) | [I] | P0 |
| 20 | Successfully deployed organization reports deployer as the factory address via `getDeployerAddress()` | [I] | P0 |
| 21 | Success path log order: `OrganizationDeployed` emitted before `OrganizationInitialized` | [EV] | P2 |
| 22 | Whitelisted but incompatible implementation (missing compatible `initialize`) — deploy reverts atomically | [S] | P1 |

---

### 1.3 `computeOrganizationAddress(bytes32 salt, address implementationAddress, address whitelistAddress)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 23 | Deterministic for same inputs | [U] | P1 |
| 24 | Different salts produce different addresses | [U] | P1 |
| 25 | Different implementations produce different addresses | [U] | P1 |
| 26 | Different whitelist addresses produce different addresses | [U] | P1 |
| 27 | Different factory contract addresses produce different computed addresses for same tuple | [U] | P1 |
| 28 | Output is caller-independent (same result regardless of `msg.sender`) | [U] | P2 |
| 29 | Matches deployed address from `deployOrganization` | [U] | P0 |
| 30 | Matches manual CREATE2 formula using proxy bytecode hash | [U] | P1 |
| 31 | Same result before and after deployment (pure precompute behavior) | [U] | P2 |

---

### 1.4 `_getOrganizationProxyBytecode(address implementationAddress, address whitelistAddress)` (private)

> **Harness prerequisite:** change visibility `private -> internal` in test-only build and expose via harness.

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 32 | Bytecode equals `abi.encodePacked(type(OrganizationProxy).creationCode, abi.encode(implementationAddress, whitelistAddress))` | [U] | P1 |
| 33 | Deterministic for same inputs | [U] | P1 |
| 34 | Changes when implementation changes | [U] | P1 |
| 35 | Changes when whitelist changes | [U] | P1 |
| 36 | `keccak256` of returned bytecode matches init code hash used by `computeOrganizationAddress` | [U] | P1 |

---

## File 2: `OrganizationInitializationBase.sol`

### 2.1 `initialize(InitializationParams params)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 37 | Non-deployer caller on uninitialized proxy — reverts `UnauthorizedDeployer` | [N] | P0 |
| 38 | Deployer caller with valid params — succeeds | [U] | P0 |
| 39 | Re-initialization after success — reverts (initializer guard) | [S] | P0 |
| 40 | Failed initialize call does not permanently lock initialization (later valid initialize by deployer can succeed) | [S] | P1 |
| 41 | Direct call on implementation contract (not proxy) reverts `UnauthorizedDeployer` | [S] | P0 |
| 42 | Successful call emits exactly one `OrganizationInitialized` event | [EV] | P1 |

---

### 2.2 `getDeployerAddress()` and `isInitialized()`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 43 | `getDeployerAddress()` returns deployer set by proxy constructor before initialization | [U] | P1 |
| 44 | `getDeployerAddress()` remains unchanged after initialization | [U] | P1 |
| 45 | `isInitialized()` returns false before successful initialization | [U] | P1 |
| 46 | `isInitialized()` returns true after successful initialization | [U] | P1 |
| 47 | `isInitialized()` remains false if initialize reverts | [U] | P1 |

---

## File 3: `LibOrganizationInitialization.sol`

### 3.1 `initialize(InitializationParams params)` — happy path state setup

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 48 | Valid params initialize members correctly | [I] | P0 |
| 49 | Valid params initialize admins correctly | [I] | P0 |
| 50 | `adminCount` and `votingThreshold` match initialized admin config | [U] | P0 |
| 51 | Valid group create operations in `params.groups` initialize group state correctly | [I] | P1 |
| 52 | Guardian set correctly | [U] | P0 |
| 53 | `adminOperationTimelockDurationSeconds` set correctly | [U] | P0 |
| 54 | `OrganizationInitialized` event fields match input params exactly | [EV] | P1 |
| 55 | Duplicate members in `params.members` are idempotent (init still succeeds, no duplicate state effect) | [E] | P1 |
| 56 | Empty `params.groups` is a valid no-op | [E] | P2 |

---

### 3.2 `initialize(InitializationParams params)` — optional recovery configuration

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 57 | Non-zero `guardianRecoveryAddress` configures guardian recovery state | [U] | P1 |
| 58 | Non-zero `transactionAndERC1271RecoveryAddress` configures tx recovery state | [U] | P1 |
| 59 | Tx recovery configured at initialization starts with `isEnabled == false` | [U] | P0 |
| 60 | Both recovery addresses non-zero — both mechanisms configured in one initialization | [U] | P1 |
| 61 | `guardianRecoveryAddress == address(0)` leaves guardian recovery unconfigured (deferred setup) | [E] | P1 |
| 62 | `transactionAndERC1271RecoveryAddress == address(0)` leaves tx recovery unconfigured (deferred setup) | [E] | P1 |
| 63 | Deferred recovery paths have zeroed pending fields immediately after initialization | [U] | P1 |

---

### 3.3 `initialize(InitializationParams params)` — validation and revert coverage

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 64 | No members provided — reverts `NoMembersProvided` | [N] | P0 |
| 65 | `params.members` contains `address(0)` — reverts `InvalidMemberAddress` | [N] | P0 |
| 66 | Empty admins array — reverts `InvalidAdminConfig` | [N] | P0 |
| 67 | `params.admins` contains `address(0)` — reverts `InvalidMemberAddress` | [N] | P0 |
| 68 | Admin not included in members — reverts `AdminNotMember` | [N] | P0 |
| 69 | Duplicate admin in initialization array — reverts `AdminAlreadyExists` | [N] | P1 |
| 70 | Voting threshold = 0 — reverts `InvalidAdminVotingThreshold` | [N] | P0 |
| 71 | Voting threshold > final admin count — reverts `InvalidAdminVotingThreshold` | [N] | P0 |
| 72 | Guardian is zero address — reverts `InvalidGuardianAddress` | [N] | P0 |
| 73 | Admin-operation timelock < 2 days — reverts `InvalidTimelockDuration` | [N] | P0 |
| 74 | Admin-operation timelock > 30 days — reverts `InvalidTimelockDuration` | [N] | P0 |
| 75 | Non-zero guardian recovery address with invalid timelock — reverts `InvalidTimelockDuration` | [N] | P1 |
| 76 | Non-zero tx recovery address with invalid timelock — reverts `InvalidTimelockDuration` | [N] | P1 |
| 77 | Group creation with non-empty `membersToRemove` inside init params — reverts `InvalidGroupCreationOperation` | [N] | P1 |
| 78 | Group update/delete on non-existent group during initialization — reverts `GroupDoesNotExist` | [N] | P1 |
| 79 | Group member includes `address(0)` during initialization — reverts `InvalidMemberAddress` | [N] | P1 |

---

### 3.4 `initialize(InitializationParams params)` — atomicity and ordering guarantees

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 80 | Revert in a later step (e.g. invalid guardian) rolls back earlier members/admin writes; state remains uninitialized | [S] | P0 |
| 81 | Revert in groups step rolls back prior members/admin writes; no partial initialization persists | [S] | P0 |
| 82 | Revert in recovery setup rolls back all prior initialization writes | [S] | P0 |
| 83 | Admins are always members immediately after successful initialization | [S] | P0 |
| 84 | `OrganizationInitialized` is never emitted on reverting initialization attempts | [S] | P1 |
| 85 | Initialization can only transition once (`false -> true`) | [S] | P0 |

---

### 3.5 `enforceOnlyDeployer()`, `getDeployerAddress()`, `isInitialized()`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 86 | `enforceOnlyDeployer()` succeeds for stored deployer | [U] | P0 |
| 87 | `enforceOnlyDeployer()` reverts `UnauthorizedDeployer` for non-deployer | [N] | P0 |
| 88 | `getDeployerAddress()` returns stored deployer address | [U] | P1 |
| 89 | `isInitialized()` returns false when admin count is zero | [U] | P1 |
| 90 | `isInitialized()` returns true when admin count is non-zero | [U] | P1 |

---

## File 4: `OrganizationProxy.sol`

### 4.1 `constructor(address implementation, address whitelistAddress)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 91 | Stores constructor `msg.sender` as deployer address in organization deployer slot | [U] | P0 |
| 92 | Stores `whitelistAddress` in upgrade storage slot | [U] | P0 |
| 93 | Sets ERC1967 implementation slot to `implementation` | [U] | P0 |
| 94 | Deployment with non-contract implementation reverts (proxy safety expectation) | [N] | P0 |
| 95 | Direct proxy deployment (without factory) sets deployer to direct deployer and enforces only that deployer can initialize | [S] | P1 |

---

### 4.2 Delegation behavior (inherited ERC1967 proxy path)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 96 | Calls to initialization view functions through proxy delegate correctly to implementation logic | [I] | P1 |
| 97 | Multiple proxies using same implementation keep isolated initialization state | [I] | P1 |
| 98 | Factory deployment path leaves no externally reachable uninitialized proxy instance | [S] | P0 |

---

## 5. Cross-File Integration (Factory + Proxy + Initialization)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 99 | End-to-end deploy: precompute address, deploy via factory, assert address/state/event consistency | [I] | P0 |
| 100 | End-to-end failed deploy: no code at computed address, no initialized state, no persisted deployment event | [S] | P0 |
| 101 | End-to-end retry after failed init with same tuple succeeds deterministically | [I] | P1 |
| 102 | Post-deploy `initialize` re-call from non-deployer always reverts | [S] | P0 |
| 103 | Post-deploy `initialize` re-call from deployer also reverts (single-use init guard) | [S] | P0 |
| 104 | Initialization config wires downstream module defaults correctly (guardian/timelock/recovery default states) | [I] | P1 |

---

## 6. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 105 | Fuzz valid initialization params (bounded lengths, non-zero required addresses) — initialization succeeds and invariants hold | [F] | P1 |
| 106 | Fuzz member arrays with duplicates — resulting membership matches set semantics | [F] | P1 |
| 107 | Fuzz admin subsets + valid thresholds — initialization succeeds | [F] | P1 |
| 108 | Fuzz invalid thresholds (`0` or `> adminCount`) — always revert | [F] | P1 |
| 109 | Fuzz timelocks inside `[2 days, 30 days]` — accepted | [F] | P1 |
| 110 | Fuzz timelocks outside `[2 days, 30 days]` — revert `InvalidTimelockDuration` | [F] | P1 |
| 111 | Fuzz salts and constructor tuples — `computeOrganizationAddress` always matches actual deployment address | [F] | P1 |
| 112 | Fuzz failed-then-retry init flow — failed attempt leaves tuple deployable on retry | [F] | P1 |

---

## 7. Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 113 | **Initialization permanence:** `isInitialized()` can only transition `false -> true` | P0 |
| 114 | **Admin/member consistency:** whenever initialized, every admin is also a member | P0 |
| 115 | **Factory deterministic deploy:** successful deployments always occur at computed CREATE2 address | P0 |
| 116 | **No partial state on failed init:** reverting initialization never leaves persisted partial member/admin/group/recovery state | P0 |
| 117 | **Proxy deployer immutability:** deployer address set by proxy constructor does not change | P0 |
| 118 | **Tx recovery default safety:** tx recovery is never initialized as enabled; explicit enable flow is required | P1 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| `OrganizationFactory.sol` | 36 | P0-P2 |
| `OrganizationInitializationBase.sol` | 11 | P0-P1 |
| `LibOrganizationInitialization.sol` | 43 | P0-P1 |
| `OrganizationProxy.sol` | 8 | P0-P1 |
| Cross-file integration | 6 | P0-P1 |
| Fuzz tests | 8 | P1 |
| Invariant tests | 6 | P0-P1 |
| **Total** | **118** | |
