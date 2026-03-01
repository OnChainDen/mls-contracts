# 14 — Upgradeability and Upgrade Execution Test Plan

**Files Under Test:**
- `src/organization/OrganizationImplementation.sol`
- `src/organization/base/OrganizationAccountFactoryBase.sol`
- `src/implementation-whitelist/ImplementationWhitelistImplementation.sol`

**Out of Scope for this plan (covered elsewhere):**
- Interface files (`src/interfaces/**/*.sol`)
- Storage libraries (`src/**/libraries/storage/**/*.sol`)

**Scope Notes:**
- Private functions in files under test should be converted from `private` to `internal` in test-only builds and verified via harness contracts.

---

## File 1: `OrganizationImplementation.sol`

### 1.1 `upgradeToAndCallWithAuthorization(address newImplementation, bytes data, AdminAuthParams authParams)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Valid guardian caller + valid admin auth + whitelisted Organization implementation + empty `data` upgrades successfully | [I] | P0 |
| 2 | Valid guardian caller + valid admin auth + whitelisted Organization implementation + non-empty `data` executes migration call successfully | [I] | P0 |
| 3 | Non-guardian caller reverts (onlyGuardian) | [N] | P0 |
| 4 | Expired admin auth reverts | [N] | P0 |
| 5 | Insufficient admin signatures reverts `InsufficientAdminAuthorization` | [N] | P0 |
| 6 | Replay with same admin auth nonce reverts | [S] | P0 |
| 7 | Signatures generated for a different `newImplementation` cannot be replayed for the current call (operationData binding) | [S] | P0 |
| 8 | Signatures generated for a different operation type (e.g. `UpgradeAccount`) cannot authorize Organization upgrade | [S] | P0 |
| 9 | Non-whitelisted target implementation reverts `ImplementationNotWhitelisted` | [N] | P0 |
| 10 | Implementation whitelisted only for `ContractType.Account` cannot be used for Organization upgrade | [N] | P0 |
| 11 | Upgrade to non-UUPS target reverts (UUPS safety check) | [S] | P0 |
| 12 | Upgrade to UUPS target with incompatible `proxiableUUID` reverts | [S] | P0 |
| 13 | Upgrade emits ERC-1967 `Upgraded` event with correct implementation address | [EV] | P1 |
| 14 | Existing Organization state (members/admins/groups/policies/guardian/recovery config) is preserved after upgrade | [I] | P0 |
| 14.1 | Existing account-factory state (`accountImplementation` pointer and deployed-account tracking) is preserved across Organization UUPS upgrades | [I] | P0 |
| 15 | Sequential upgrades (V1 -> V2 -> V3) preserve state and functionality at each step | [I] | P1 |
| 16 | If post-upgrade `data` call reverts, transaction fully reverts and implementation remains unchanged | [S] | P0 |
| 16.1 | Reverting upgrade paths (whitelist/UUPS/migration failure) do not consume admin auth nonce (same auth can be retried after root cause is fixed) | [S] | P1 |
| 17 | `isUpgradeAuthorized` flag is true only during authorized upgrade execution window and false before/after | [S] | P0 |
| 18 | Failed upgrade path never leaves `isUpgradeAuthorized` stuck true | [S] | P0 |
| 19 | Direct call to inherited `upgradeToAndCall` (bypassing wrapper) always reverts `UnauthorizedUpgrade` | [S] | P0 |
| 20 | Direct `upgradeToAndCall` reverts even if caller is the guardian (must still go through authorized flow) | [S] | P0 |
| 21 | **Desired behavior:** admin authorization must also bind the `data` payload (guardian cannot swap migration calldata after signatures are collected) | [S] | P0 |
| 22 | **Desired behavior:** migration `data` cannot trigger a nested second upgrade to bypass whitelist/admin authorization | [S] | P0 |
| 23 | **Desired behavior:** upgrades fail closed if configured whitelist address has no code (EOA/zero/misconfigured address) | [S] | P0 |
| 23.1 | **Desired behavior:** upgrades fail closed if whitelist validation call itself reverts or returns malformed data (implementation must remain unchanged) | [S] | P0 |
| 24 | **Desired behavior:** `newImplementation` must be a non-zero contract address (even if mistakenly whitelisted) | [S] | P0 |

### 1.2 `implementation()` (IBeacon override)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 25 | Returns the current Account implementation address from Organization account-factory storage | [U] | P1 |
| 26 | Reverts `AccountImplementationNotSet` when account implementation is unset (`address(0)`) | [N] | P1 |

### 1.3 `_authorizeUpgrade(address newImplementation)` (internal)

> Test via harness exposing `_authorizeUpgrade` for direct assertions.

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 27 | Reverts `UnauthorizedUpgrade` when authorization flag is false | [S] | P0 |
| 28 | Succeeds only when authorization flag is set by authorized wrapper flow | [S] | P0 |
| 29 | **Desired behavior:** authorization should be bound to the specific pre-approved `newImplementation` (not just a boolean flag) | [S] | P0 |

### 1.4 Inherited UUPS Entry Points (`upgradeToAndCall`, `proxiableUUID`)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 30 | Calling `upgradeToAndCall` on implementation contract directly (not via proxy) reverts due UUPS `onlyProxy` guard | [S] | P1 |
| 31 | Calling `proxiableUUID` through proxy reverts due `notDelegated` guard | [S] | P1 |

---

## File 2: `OrganizationAccountFactoryBase.sol`

### 2.1 `setAccountImplementation(address newImplementation, AdminAuthParams authParams)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 32 | Valid guardian caller + valid admin auth + whitelisted Account implementation updates beacon implementation | [I] | P0 |
| 33 | Non-guardian caller reverts (onlyGuardian) | [N] | P0 |
| 34 | Expired admin auth reverts | [N] | P0 |
| 35 | Insufficient admin signatures reverts | [N] | P0 |
| 36 | Replay with same admin auth nonce reverts | [S] | P0 |
| 36.1 | Calling `setAccountImplemenation` with admin nonce that has already been rejected reverts | [S] | P0 |
| 37 | Signatures for different target implementation cannot authorize current call | [S] | P0 |
| 38 | Signatures for wrong operation type cannot authorize Account implementation upgrade | [S] | P0 |
| 39 | Non-whitelisted target implementation reverts `ImplementationNotWhitelisted` | [N] | P0 |
| 40 | Implementation whitelisted only for `ContractType.Organization` cannot be used for Account upgrade | [N] | P0 |
| 41 | Emits `AccountImplementationUpdated(newImplementation)` on success | [EV] | P1 |
| 42 | All previously deployed accounts immediately execute code from new implementation | [I] | P0 |
| 43 | Newly deployed accounts after upgrade also use the new implementation | [I] | P1 |
| 43.1 | Sequential upgrades (V1 -> V2 -> V3) preserve state and functionality at each step for account contracts that use the organization as their beacon | [I] | P1 |
| 44 | No per-account upgrade path exists (all accounts under an org share one implementation pointer) | [S] | P1 |
| 45 | Upgrading account implementation does not alter Organization proxy implementation | [S] | P1 |
| 46 | **Desired behavior:** upgrade fails closed if whitelist address has no code (EOA/zero/misconfigured) | [S] | P0 |
| 47 | **Desired behavior:** `newImplementation` must be non-zero and have code (even if mistakenly whitelisted) | [S] | P0 |
| 47.1 | Reverting account-implementation upgrade paths (whitelist/no-code checks) do not consume admin auth nonce and do not mutate beacon implementation state | [S] | P1 |

### 2.2 `implementation()` (beacon implementation getter)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 48 | Returns latest account implementation after successive `setAccountImplementation` calls | [U] | P1 |
| 49 | Reverts `AccountImplementationNotSet` before any account implementation is configured | [N] | P1 |
| 50 | Organization UUPS upgrade preserves account implementation pointer used by beacon getter | [I] | P1 |

---

## File 3: `ImplementationWhitelistImplementation.sol`

### 3.1 `initialize(address initialOwner, address[] organizationImplementations, address[] accountImplementations)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 51 | Proxy initialization sets owner and seeds both type-specific whitelists correctly | [I] | P1 |
| 52 | Emits `ImplementationWhitelistInitialized(initialOwner)` | [EV] | P1 |
| 53 | Cannot initialize proxy twice | [N] | P1 |
| 54 | Implementation contract constructor disables initializers (direct initialize on implementation reverts) | [S] | P1 |
| 55 | `isInitialized()` is false before init and true after successful init | [U] | P1 |
| 55.1 | `initialOwner == address(0)` reverts during initialization | [N] | P0 |
| 55.2 | Empty initial implementation arrays still initialize successfully and set owner | [E] | P2 |
| 55.3 | Same implementation address can be seeded independently under both `ContractType.Organization` and `ContractType.Account` in init | [S] | P1 |
| 55.4 | **Desired behavior:** initialization rejects zero-address implementation entries in seed arrays | [S] | P0 |
| 55.5 | **Desired behavior:** initialization rejects non-contract implementation entries in seed arrays | [S] | P0 |

### 3.2 `whitelistImplementations(ContractType contractType, address[] toWhitelist, address[] toUnwhitelist)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 56 | Owner can add and remove implementations in a single call | [U] | P1 |
| 57 | Non-owner caller reverts | [N] | P1 |
| 58 | Organization and Account whitelists are two independent whitelisted within the same whitelist contract| [S] | P1 |
| 59 | Emits `ImplementationWhitelisted` and `ImplementationUnwhitelisted` for each processed address | [EV] | P2 |
| 60 | **Desired behavior:** reject zero-address entries in whitelist updates | [S] | P0 |
| 61 | **Desired behavior:** reject non-contract addresses in whitelist updates | [S] | P0 |
| 61.1 | Same address present in both `toWhitelist` and `toUnwhitelist` in one call ends unwhitelisted (add then remove order) | [E] | P2 |
| 61.2 | Both arrays empty is a no-op and does not revert | [E] | P2 |
| 61.3 | Pending owner (before `acceptOwnership`) cannot call `whitelistImplementations` | [S] | P1 |
| 61.4 | After ownership transfer acceptance, new owner can mutate whitelist and old owner can no longer mutate it | [S] | P1 |

### 3.3 `isImplementationWhitelisted` / `validateIsImplementationWhitelistedOrRevert`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 62 | `isImplementationWhitelisted` returns true only for addresses whitelisted under matching `ContractType` | [U] | P1 |
| 63 | `validateIsImplementationWhitelistedOrRevert` reverts for non-whitelisted targets with `ImplementationNotWhitelisted` | [N] | P1 |
| 64 | `validateIsImplementationWhitelistedOrRevert` succeeds for whitelisted targets | [U] | P1 |
| 64.1 | `validateIsImplementationWhitelistedOrRevert` reverts when implementation is whitelisted only under the other `ContractType` | [N] | P1 |

### 3.4 `_authorizeUpgrade(address newImplementation)` and inherited UUPS upgrade path

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 65 | Owner can upgrade whitelist proxy via UUPS `upgradeToAndCall` | [I] | P1 |
| 66 | Non-owner cannot upgrade whitelist proxy | [N] | P1 |
| 67 | Pending owner (before `acceptOwnership`) cannot upgrade | [S] | P1 |
| 68 | After ownership transfer acceptance, old owner loses upgrade rights and new owner gains them | [S] | P1 |
| 69 | Upgrade with migration calldata executes migration logic | [I] | P1 |
| 70 | Whitelist storage persists across upgrades | [I] | P1 |
| 71 | Upgrade to non-UUPS / incompatible implementation reverts | [S] | P1 |
| 72 | Calling `upgradeToAndCall` on implementation contract directly (not proxy) reverts due UUPS `onlyProxy` guard | [S] | P1 |
| 73 | Calling `proxiableUUID` through proxy reverts due UUPS `notDelegated` guard | [S] | P1 |
| 73.1 | **Desired behavior:** owner cannot upgrade whitelist proxy to zero/no-code targets (must fail closed even with owner auth) | [S] | P0 |

### 3.5 Private Function Tests (Requires `private` -> `internal` Conversion for Harness)

> **Harness note:** `_addToWhitelist` and `_removeFromWhitelist` are currently `private`. For direct unit tests, expose them via an inherited harness contract after changing visibility to `internal` in the test branch.

#### 3.5.1 `_addToWhitelist(ContractType contractType, address[] implementations)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 74 | Marks each input address as whitelisted for the given `ContractType` | [U] | P1 |
| 75 | Leaves the other `ContractType` mapping unchanged for same addresses | [S] | P1 |
| 76 | Emits one `ImplementationWhitelisted` event per input entry | [EV] | P2 |
| 77 | Empty input array is a no-op and does not revert | [E] | P2 |
| 78 | **Desired behavior:** rejects zero/non-contract addresses | [S] | P0 |
| 78.1 | Duplicate entries are idempotent at state level (mapping stays `true`) | [E] | P2 |

#### 3.5.2 `_removeFromWhitelist(ContractType contractType, address[] implementations)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 79 | Marks each input address as not whitelisted for the given `ContractType` | [U] | P1 |
| 80 | Leaves the other `ContractType` mapping unchanged for same addresses | [S] | P1 |
| 81 | Emits one `ImplementationUnwhitelisted` event per input entry | [EV] | P2 |
| 82 | Removing non-whitelisted entries is a no-op and does not revert | [E] | P2 |
| 83 | Empty input array is a no-op and does not revert | [E] | P2 |
| 83.1 | Duplicate removal entries are idempotent at state level (mapping stays `false`) | [E] | P2 |

---

## 4. Cross-File Upgrade Security Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 84 | Full flow: whitelist new Organization impl -> guardian + admins authorize -> Organization UUPS upgrade succeeds | [I] | P0 |
| 85 | Full flow: whitelist new Account impl -> guardian + admins authorize -> beacon update upgrades all accounts | [I] | P0 |
| 86 | Unwhitelisting an implementation blocks future upgrades to that implementation but does not mutate already-active implementation pointers | [I] | P1 |
| 86.1 | Unwhitelisting an implementation does not prevent organizations using the unwhitelisted implementation from upgrading to a new whitelisted implementation | [I] | P1 |
| 86.2 | Unwhitelisting an implementation does not prevent organizations using the unwhitelisted implementation from upgrading the account implementation to a new whitelisted implementation | [I] | P1 |
| 87 | Upgrading Organization implementation does not bypass Account implementation whitelist/type checks | [S] | P0 |
| 88 | Compromised guardian assumption test: without valid admin auth, neither Organization nor Account upgrade path executes | [S] | P0 |
| 88.1 | If an implementation is unwhitelisted after signatures are collected but before execution, execution still fails (whitelist enforced at execution time) | [S] | P0 |
| 88.2 | Re-whitelisting a previously removed implementation re-enables upgrade paths only when fresh valid admin auth is provided | [I] | P1 |

---

## 5. Upgrade Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 89 | Fuzz Organization upgrade targets: any non-whitelisted candidate always rejected | [F] | P0 |
| 90 | Fuzz Account implementation targets: any non-whitelisted candidate always rejected | [F] | P0 |
| 91 | Fuzz successful upgrade sequences (whitelisted targets + valid auth): state remains consistent across repeated upgrades | [F] | P1 |
| 92 | Fuzz migration calldata: malformed payloads revert atomically (no partial upgrade state) | [F] | P0 |
| 93 | **Desired behavior fuzz:** random calldata cannot trigger unauthorized nested second upgrade | [F] | P0 |

---

## 6. Upgrade Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 94 | `isUpgradeAuthorized` is false outside authorized upgrade execution | P0 |
| 95 | Organization upgrades only target whitelisted Organization implementations | P0 |
| 96 | Account upgrades only target whitelisted Account implementations | P0 |
| 97 | All accounts under the same organization always resolve the same beacon implementation address | P0 |
| 98 | Organization UUPS implementation pointer and Account beacon implementation pointer are independent state variables | P1 |
| 98.1 | **Desired behavior:** Organization proxy-stored whitelist address used for upgrade checks remains immutable across Organization upgrades | P1 |

---

## Summary

| Category | Tests | Priority |
|----------|-------|----------|
| `OrganizationImplementation.sol` | 34 | P0-P1 |
| `OrganizationAccountFactoryBase.sol` | 20 | P0-P1 |
| `ImplementationWhitelistImplementation.sol` | 46 | P0-P2 |
| Cross-file upgrade security | 7 | P0-P1 |
| Fuzz tests | 5 | P0-P1 |
| Invariants | 6 | P0-P1 |
| **Total** | **118** | |
