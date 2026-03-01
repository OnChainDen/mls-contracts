# 13 — Initialization and Contract Setup Test Plan

**Files Under Test:**
- `src/organization/OrganizationFactory.sol`
- `src/organization/base/OrganizationInitializationBase.sol`
- `src/organization/libraries/LibOrganizationInitialization.sol`
- `src/organization/OrganizationProxy.sol`

**Scope Notes:**
- This plan intentionally excludes interface files and storage libraries.
- All currently-private functions in these files (and any private initialization-path helpers) should be tested via harnesses by changing `private` to `internal` in test-only builds.

---

## File 1: `OrganizationFactory.sol`

### 1.1 `constructor(address _deployerAddress)`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OF-CTOR-1 | Constructor with `address(0)` deployer — reverts `ZeroAddress` | [N] | P0 |
| OF-CTOR-2 | Constructor with non-zero deployer — stores `DEPLOYER_ADDRESS` correctly | [U] | P1 |
| OF-CTOR-3 | `DEPLOYER_ADDRESS` is immutable across all operations | [S] | P1 |

---

### 1.2 `deployOrganization(bytes32 salt, address implementationAddress, address whitelistAddress, InitializationParams initParams)`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OF-DO-1 | Authorized deployer + valid params — deploy succeeds and returns organization address | [I] | P0 |
| OF-DO-2 | Returned address equals `computeOrganizationAddress(salt, implementationAddress, whitelistAddress)` | [U] | P0 |
| OF-DO-3 | Emits `OrganizationDeployed(organizationAddress, salt, DEPLOYER_ADDRESS)` with correct values | [EV] | P1 |
| OF-DO-4 | Unauthorized caller — reverts `UnauthorizedDeployer` | [N] | P0 |
| OF-DO-5 | Non-whitelisted implementation — reverts via whitelist validation | [N] | P0 |
| OF-DO-6 | Implementation whitelisted only for `ContractType.Account` (not `ContractType.Organization`) — reverts | [S] | P0 |
| OF-DO-7 | Factory calls whitelist validation with `ContractType.Organization` and the exact implementation address (spy/mock assertion) | [U] | P1 |
| OF-DO-8 | `implementationAddress == address(0)` — reverts (desired behavior: invalid implementation must not deploy) | [N] | P0 |
| OF-DO-9 | `implementationAddress` is EOA/non-contract — reverts (desired behavior: implementation must have code) | [N] | P0 |
| OF-DO-10 | `whitelistAddress == address(0)` — reverts (desired behavior: whitelist must be configured) | [S] | P0 |
| OF-DO-11 | `whitelistAddress` is EOA/non-contract — reverts (desired behavior: whitelist check cannot be bypassed) | [S] | P0 |
| OF-DO-12 | Same `(salt, implementationAddress, whitelistAddress)` deployed twice — second deploy reverts (CREATE2 collision) | [N] | P1 |
| OF-DO-13 | Same `salt` with different implementation — different address, both deployments can succeed | [U] | P1 |
| OF-DO-14 | Same `salt` with different whitelist — different address, both deployments can succeed | [U] | P1 |
| OF-DO-15 | Invalid init params (e.g. no members, no admins, fewer admins than threshold -- add tests for all these cases) — entire tx reverts and no contract code exists at computed address | [S] | P0 |
| OF-DO-16 | If initialization reverts, `OrganizationDeployed` is not persisted in logs | [S] | P1 |
| OF-DO-17 | After failed deploy with a salt, retrying same tuple with valid params succeeds (no stuck salt) | [U] | P1 |
| OF-DO-18 | Successfully deployed organization is already initialized in same tx (`isInitialized() == true`) | [I] | P0 |
| OF-DO-19 | Successfully deployed organization reports deployer as the factory address via `getDeployerAddress()` | [I] | P0 |
| OF-DO-20 | Successfully deployed address has proxy runtime code (not raw implementation runtime code) | [I] | P1 |
| OF-DO-21 | Success path log order: `OrganizationDeployed` emitted before `OrganizationInitialized` | [EV] | P2 |
| OF-DO-22 | Whitelisted but incompatible implementation (missing compatible `initialize`) — deploy reverts atomically | [S] | P1 |

---

### 1.3 `computeOrganizationAddress(bytes32 salt, address implementationAddress, address whitelistAddress)`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OF-COA-1 | Deterministic for same inputs | [U] | P1 |
| OF-COA-2 | Different salts produce different addresses | [U] | P1 |
| OF-COA-3 | Different implementations produce different addresses | [U] | P1 |
| OF-COA-4 | Different whitelist addresses produce different addresses | [U] | P1 |
| OF-COA-5 | Different factory contract addresses produce different computed addresses for same tuple | [U] | P1 |
| OF-COA-6 | Output is caller-independent (same result regardless of `msg.sender`) | [U] | P2 |
| OF-COA-7 | Matches deployed address from `deployOrganization` | [U] | P0 |
| OF-COA-8 | Matches manual CREATE2 formula using proxy bytecode hash | [U] | P1 |
| OF-COA-9 | Same result before and after deployment (pure precompute behavior) | [U] | P2 |

---

### 1.4 `_getOrganizationProxyBytecode(address implementationAddress, address whitelistAddress)` (private)

> **Harness prerequisite:** change visibility `private -> internal` in test-only build and expose via harness.

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OF-GOPB-1 | Bytecode equals `abi.encodePacked(type(OrganizationProxy).creationCode, abi.encode(implementationAddress, whitelistAddress))` | [U] | P1 |
| OF-GOPB-2 | Deterministic for same inputs | [U] | P1 |
| OF-GOPB-3 | Changes when implementation changes | [U] | P1 |
| OF-GOPB-4 | Changes when whitelist changes | [U] | P1 |
| OF-GOPB-5 | `keccak256` of returned bytecode matches init code hash used by `computeOrganizationAddress` | [U] | P1 |

---

## File 2: `OrganizationInitializationBase.sol`

### 2.1 `initialize(InitializationParams params)`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OIB-INIT-1 | Non-deployer caller on uninitialized proxy — reverts `UnauthorizedDeployer` | [N] | P0 |
| OIB-INIT-2 | Deployer caller with valid params — succeeds | [U] | P0 |
| OIB-INIT-3 | Re-initialization after success — reverts (initializer guard) | [S] | P0 |
| OIB-INIT-4 | Failed initialize call does not permanently lock initialization (later valid initialize by deployer can succeed) | [S] | P1 |
| OIB-INIT-5 | Direct call on implementation contract (not proxy) reverts `UnauthorizedDeployer` | [S] | P0 |
| OIB-INIT-6 | Successful call emits exactly one `OrganizationInitialized` event | [EV] | P1 |

---

### 2.2 `getDeployerAddress()` and `isInitialized()`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OIB-VIEW-1 | `getDeployerAddress()` returns deployer set by proxy constructor before initialization | [U] | P1 |
| OIB-VIEW-2 | `getDeployerAddress()` remains unchanged after initialization | [U] | P1 |
| OIB-VIEW-3 | `isInitialized()` returns false before successful initialization | [U] | P1 |
| OIB-VIEW-4 | `isInitialized()` returns true after successful initialization | [U] | P1 |
| OIB-VIEW-5 | `isInitialized()` remains false if initialize reverts | [U] | P1 |
| OIB-VIEW-6 | Direct call to implementation contract `getDeployerAddress()` returns `address(0)` (no proxy constructor storage) | [E] | P2 |

---

## File 3: `LibOrganizationInitialization.sol`

### 3.1 `initialize(InitializationParams params)` — happy path state setup

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOI-HPS-1 | Valid params initialize members correctly | [I] | P0 |
| LOI-HPS-2 | Valid params initialize admins correctly | [I] | P0 |
| LOI-HPS-3 | `adminCount` and `votingThreshold` match initialized admin config | [U] | P0 |
| LOI-HPS-4 | Valid group create operations in `params.groups` initialize group state correctly | [I] | P1 |
| LOI-HPS-5 | Guardian set correctly | [U] | P0 |
| LOI-HPS-6 | `adminOperationTimelockDurationSeconds` set correctly | [U] | P0 |
| LOI-HPS-7 | `adminOperationTimelockDurationSeconds == 2 days` is accepted | [E] | P0 |
| LOI-HPS-8 | `adminOperationTimelockDurationSeconds == 30 days` is accepted | [E] | P0 |
| LOI-HPS-9 | `OrganizationInitialized` event fields match input params exactly | [EV] | P1 |
| LOI-HPS-10 | Duplicate members in `params.members` are idempotent (init still succeeds, no duplicate state effect) | [E] | P1 |
| LOI-HPS-11 | Empty `params.groups` is a valid no-op | [E] | P2 |

---

### 3.2 `initialize(InitializationParams params)` — optional recovery configuration

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOI-REC-1 | Non-zero `guardianRecoveryAddress` and valid `guardianRecoveryTimelockDurationSeconds` configures guardian recovery state | [U] | P1 |
| LOI-REC-2 | Non-zero `transactionAndERC1271RecoveryAddress` and valid `txRecoveryTimelockDurationSeconds` configures tx recovery state | [U] | P1 |
| LOI-REC-3 | Tx recovery configured at initialization starts with `isEnabled == false` | [U] | P0 |
| LOI-REC-4 | Both recovery addresses non-zero — both mechanisms configured in one initialization | [U] | P1 |
| LOI-REC-5 | Guardian recovery configured with timelock exactly `2 days` succeeds | [E] | P1 |
| LOI-REC-6 | Guardian recovery configured with timelock exactly `30 days` succeeds | [E] | P1 |
| LOI-REC-7 | Tx recovery configured with timelock exactly `2 days` succeeds and remains disabled | [E] | P1 |
| LOI-REC-8 | Tx recovery configured with timelock exactly `30 days` succeeds and remains disabled | [E] | P1 |
| LOI-REC-9 | `guardianRecoveryAddress == address(0)` leaves guardian recovery unconfigured (deferred setup) | [E] | P1 |
| LOI-REC-10 | `transactionAndERC1271RecoveryAddress == address(0)` leaves tx recovery unconfigured (deferred setup) | [E] | P1 |
| LOI-REC-11 | Deferred recovery paths have zeroed pending fields immediately after initialization | [U] | P1 |

---

### 3.3 `initialize(InitializationParams params)` — validation and revert coverage

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOI-VAL-1 | No members provided — reverts `NoMembersProvided` | [N] | P0 |
| LOI-VAL-2 | `params.members` contains `address(0)` — reverts `InvalidMemberAddress` | [N] | P0 |
| LOI-VAL-3 | Empty admins array — reverts `InvalidAdminConfig` | [N] | P0 |
| LOI-VAL-4 | `params.admins` contains `address(0)` — reverts `InvalidMemberAddress` | [N] | P0 |
| LOI-VAL-5 | Admin not included in members — reverts `AdminNotMember` | [N] | P0 |
| LOI-VAL-6 | Duplicate admin in initialization array — reverts `AdminAlreadyExists` | [N] | P1 |
| LOI-VAL-7 | Voting threshold = 0 — reverts `InvalidAdminVotingThreshold` | [N] | P0 |
| LOI-VAL-8 | Voting threshold > final admin count — reverts `InvalidAdminVotingThreshold` | [N] | P0 |
| LOI-VAL-9 | Guardian is zero address — reverts `InvalidGuardianAddress` | [N] | P0 |
| LOI-VAL-10 | Non whitelisted account implementation address — reverts `ImplementationNotWhitelisted` | [N] | P0 |
| LOI-VAL-11 | Admin-operation timelock < 2 days — reverts `InvalidTimelockDuration` | [N] | P0 |
| LOI-VAL-12 | Admin-operation timelock > 30 days — reverts `InvalidTimelockDuration` | [N] | P0 |
| LOI-VAL-13 | Non-zero guardian recovery address with invalid timelock — reverts `InvalidTimelockDuration` | [N] | P1 |
| LOI-VAL-14 | Non-zero tx recovery address with invalid timelock — reverts `InvalidTimelockDuration` | [N] | P1 |
| LOI-VAL-15 | Group creation with non-empty `membersToRemove` inside init params — reverts `InvalidGroupCreationOperation` | [N] | P1 |
| LOI-VAL-16 | Group update/delete on non-existent group during initialization — reverts `GroupDoesNotExist` | [N] | P1 |
| LOI-VAL-17 | Group member includes `address(0)` during initialization — reverts `InvalidMemberAddress` | [N] | P1 |
| LOI-VAL-18 | Duplicate group creation entries for the same `groupId` in one init batch — reverts `GroupAlreadyExists` | [N] | P1 |
| LOI-VAL-19 | Group update removing an address that is not currently in the group — reverts `MemberNotInGroup` | [N] | P1 |
| LOI-VAL-20 | Group delete with non-empty `membersToAdd`/`membersToRemove` — reverts `InvalidGroupDeletionOperation` | [N] | P1 |
| LOI-VAL-21 | Group ID deleted earlier in init batch cannot be recreated later in same batch — reverts `GroupAlreadyDeleted` | [S] | P1 |
| LOI-VAL-22 | Group member not present in organization `params.members` — reverts `MemberDoesNotExist` (desired behavior) | [S] | P0 |

---

### 3.4 `initialize(InitializationParams params)` — atomicity and ordering guarantees

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOI-AOG-1 | Revert in a later step (e.g. invalid guardian) rolls back earlier members/admin writes; state remains uninitialized | [S] | P0 |
| LOI-AOG-2 | Revert in groups step rolls back prior members/admin writes; no partial initialization persists | [S] | P0 |
| LOI-AOG-3 | Revert in recovery setup rolls back all prior initialization writes | [S] | P0 |
| LOI-AOG-4 | Admins are always members immediately after successful initialization | [S] | P0 |
| LOI-AOG-5 | `OrganizationInitialized` is never emitted on reverting initialization attempts | [S] | P1 |
| LOI-AOG-6 | Initialization can only transition once (`false -> true`) and reverts with error `AlreadyInitialized` if initialized already occurred | [S] | P0 |

---

### 3.5 `enforceOnlyDeployer()`, `getDeployerAddress()`, `isInitialized()`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| LOI-VIEW-1 | `enforceOnlyDeployer()` succeeds for stored deployer | [U] | P0 |
| LOI-VIEW-2 | `enforceOnlyDeployer()` reverts `UnauthorizedDeployer` for non-deployer | [N] | P0 |
| LOI-VIEW-3 | `getDeployerAddress()` returns stored deployer address | [U] | P1 |
| LOI-VIEW-4 | `isInitialized()` returns false when admin count is zero | [U] | P1 |
| LOI-VIEW-5 | `isInitialized()` returns true when admin count is non-zero | [U] | P1 |

---

## File 4: `OrganizationProxy.sol`

### 4.1 `constructor(address implementation, address whitelistAddress)`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OPX-CTOR-1 | Stores constructor `msg.sender` as deployer address in organization deployer slot | [U] | P0 |
| OPX-CTOR-2 | Stores `whitelistAddress` in upgrade storage slot | [U] | P0 |
| OPX-CTOR-3 | Sets ERC1967 implementation slot to `implementation` | [U] | P0 |
| OPX-CTOR-4 | **Desired Behavior:** Deployment with non-contract implementation reverts (proxy safety expectation) | [N] | P0 |
| OPX-CTOR-5 | Deployment with `whitelistAddress == address(0)` reverts with error ZeroAddress | [S] | P0 |
| OPX-CTOR-6 | **Desired Behavior:** Deployment with EOA/non-contract `whitelistAddress` reverts | [S] | P0 |
| OPX-CTOR-7 | Direct proxy deployment (without factory) sets deployer to direct deployer and enforces only that deployer can initialize | [S] | P1 |

---

### 4.2 Delegation behavior (inherited ERC1967 proxy path)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OPX-DEL-1 | Calls to initialization view functions through proxy delegate correctly to implementation logic | [I] | P1 |
| OPX-DEL-2 | Multiple proxies using same implementation keep isolated initialization state | [I] | P1 |
| OPX-DEL-3 | Factory deployment path leaves no externally reachable uninitialized proxy instance | [S] | P0 |
| OPX-DEL-4 | Successful initialization via proxy does not overwrite stored deployer/whitelist slots (no storage collision) | [S] | P0 |

---

## 5. Cross-File Integration (Factory + Proxy + Initialization)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| CFI-FLOW-1 | End-to-end deploy: precompute address, deploy via factory, assert address/state/event consistency | [I] | P0 |
| CFI-FLOW-2 | End-to-end failed deploy: no code at computed address, no initialized state, no persisted deployment event | [S] | P0 |
| CFI-FLOW-3 | End-to-end retry after failed init with same tuple succeeds deterministically | [I] | P1 |
| CFI-FLOW-4 | Post-deploy `initialize` re-call from non-deployer always reverts | [S] | P0 |
| CFI-FLOW-5 | Post-deploy `initialize` re-call from deployer also reverts (single-use init guard) | [S] | P0 |
| CFI-FLOW-6 | Initialization config wires downstream module defaults correctly (guardian/timelock/recovery default states) | [I] | P1 |

---

## 6. Fuzz Tests

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| INIT-FUZZ-1 | Fuzz valid initialization params (bounded lengths, non-zero required addresses) — initialization succeeds and invariants hold | [F] | P1 |
| INIT-FUZZ-2 | Fuzz member arrays with duplicates — resulting membership matches set semantics | [F] | P1 |
| INIT-FUZZ-3 | Fuzz admin subsets + valid thresholds — initialization succeeds | [F] | P1 |
| INIT-FUZZ-4 | Fuzz invalid thresholds (`0` or `> adminCount`) — always revert | [F] | P1 |
| INIT-FUZZ-5 | Fuzz timelocks inside `[2 days, 30 days]` — accepted | [F] | P1 |
| INIT-FUZZ-6 | Fuzz timelocks outside `[2 days, 30 days]` — revert `InvalidTimelockDuration` | [F] | P1 |
| INIT-FUZZ-7 | Fuzz salts and constructor tuples — `computeOrganizationAddress` always matches actual deployment address | [F] | P1 |
| INIT-FUZZ-8 | Fuzz failed-then-retry init flow — failed attempt leaves tuple deployable on retry | [F] | P1 |

---

## 7. Invariant Tests

| ID | Invariant | Priority |
|---|-----------|----------|
| INIT-INV-1 | **Initialization permanence:** `isInitialized()` can only transition `false -> true` | P0 |
| INIT-INV-2 | **Admin/member consistency:** whenever initialized, every admin is also a member, there's at least one admin in the org, and adminCount >= votingThreshold  | P0 |
| INIT-INV-3 | **Factory deterministic deploy:** successful deployments always occur at computed CREATE2 address | P0 |
| INIT-INV-4 | **No partial state on failed init:** reverting initialization never leaves persisted partial member/admin/group/recovery state | P0 |
| INIT-INV-5 | **Proxy deployer immutability:** deployer address set by proxy constructor does not change | P0 |
| INIT-INV-6 | **Tx recovery default safety:** tx recovery is never initialized as enabled; explicit enable flow is required | P1 |
| INIT-INV-7 | **Group/member consistency:** for active groups, every group member address is also an organization member | P0 |
| INIT-INV-8 | **Failed initialization deploy atomicity:** if `deployOrganization` hits an `initialize` revert, `deployOrganization` reverts and no organization proxy code exists at the computed address | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| `OrganizationFactory.sol` | 39 | P0-P2 |
| `OrganizationInitializationBase.sol` | 12 | P0-P2 |
| `LibOrganizationInitialization.sol` | 54 | P0-P1 |
| `OrganizationProxy.sol` | 11 | P0-P1 |
| Cross-file integration | 6 | P0-P1 |
| Fuzz tests | 8 | P1 |
| Invariant tests | 8 | P0-P1 |
| **Total** | **138** | |
