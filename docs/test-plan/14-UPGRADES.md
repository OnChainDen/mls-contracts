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

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OI-UTACWA-1 | Valid guardian caller + valid admin auth + whitelisted Organization implementation + empty `data` upgrades successfully | [I] | P0 |
| OI-UTACWA-2 | Valid guardian caller + valid admin auth + whitelisted Organization implementation + non-empty `data` executes migration call successfully | [I] | P0 |
| OI-UTACWA-3 | Non-guardian caller reverts (onlyGuardian) | [N] | P0 |
| OI-UTACWA-4 | Expired admin auth reverts | [N] | P0 |
| OI-UTACWA-5 | Insufficient admin signatures reverts `InsufficientAdminAuthorization` | [N] | P0 |
| OI-UTACWA-6 | Replay with same admin auth nonce reverts | [S] | P0 |
| OI-UTACWA-7 | Calling with an admin nonce that's already been rejected reverts | [S] | P0 |
| OI-UTACWA-8 | Signatures generated for a different `newImplementation` cannot be replayed for the current call (operationData binding) | [S] | P0 |
| OI-UTACWA-9 | Signatures generated for a different operation type (e.g. `UpgradeAccount`) cannot authorize Organization upgrade | [S] | P0 |
| OI-UTACWA-10 | Signatures generated for `isApproval = false` (rejection intent) cannot be reused to execute upgrade (`isApproval = true` required) | [S] | P1 |
| OI-UTACWA-11 | Non-whitelisted target implementation reverts `ImplementationNotWhitelisted` | [N] | P0 |
| OI-UTACWA-12 | Implementation whitelisted only for `ContractType.Account` cannot be used for Organization upgrade | [N] | P0 |
| OI-UTACWA-13 | Upgrade to non-UUPS target reverts (UUPS safety check) | [S] | P0 |
| OI-UTACWA-14 | Upgrade to UUPS target with incompatible `proxiableUUID` reverts | [S] | P0 |
| OI-UTACWA-15 | Upgrade emits ERC-1967 `Upgraded` event with correct implementation address | [EV] | P1 |
| OI-UTACWA-16 | Existing Organization state (members/admins/groups/policies/guardian/recovery config) is preserved after upgrade | [I] | P0 |
| OI-UTACWA-17 | Existing account-factory state (`accountImplementation` pointer and deployed-account tracking) is preserved across Organization UUPS upgrades | [I] | P0 |
| OI-UTACWA-18 | Sequential upgrades (V1 -> V2 -> V3) preserve state and functionality at each step | [I] | P1 |
| OI-UTACWA-19 | If post-upgrade `data` call reverts, transaction fully reverts and implementation remains unchanged | [S] | P0 |
| OI-UTACWA-20 | Reverting upgrade paths (whitelist/UUPS/migration failure) do not consume admin auth nonce (same auth can be retried after root cause is fixed) | [S] | P1 |
| OI-UTACWA-21 | `authorizedUpgradeImplementation` flag is only set during authorized upgrade execution window and is addreses zero before/after | [S] | P0 |
| OI-UTACWA-22 | Failed upgrade path never leaves `authorizedUpgradeImplementation` stuck to an address that isn't address zero | [S] | P0 |
| OI-UTACWA-23 | Direct call to inherited `upgradeToAndCall` (bypassing wrapper) always reverts `UnauthorizedUpgrade` | [S] | P0 |
| OI-UTACWA-24 | Direct `upgradeToAndCall` reverts even if caller is the guardian (must still go through authorized flow) | [S] | P0 |
| OI-UTACWA-25 | Admin authorization must also bind the `data` payload (guardian cannot swap migration calldata after signatures are collected) | [S] | P0 |
| OI-UTACWA-26 | Migration `data` cannot trigger a nested second upgrade to bypass whitelist/admin authorization | [S] | P0 |
| OI-UTACWA-27 | Nested second upgrade still fails when second target is also whitelisted and UUPS-compatible (must fail for missing fresh admin+guardian authorization, not whitelist/UUPS mismatch) | [S] | P0 |
| OI-UTACWA-28 | Upgrades fail closed if configured whitelist address has no code (EOA/zero/misconfigured address) | [S] | P0 |
| OI-UTACWA-29 | Upgrade reverts when whitelist validation call reverts | [S] | P0 |
| OI-UTACWA-30 | `newImplementation` must be a non-zero contract address (even if mistakenly whitelisted) | [S] | P0 |

### 1.2 `implementation()` (IBeacon override)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OI-IMP-1 | Returns the current Account implementation address from Organization account-factory storage | [U] | P1 |
| OI-IMP-2 | Reverts `AccountImplementationNotSet` when account implementation is unset (`address(0)`) | [N] | P1 |

### 1.3 `_authorizeUpgrade(address newImplementation)` (internal)

> Test via harness exposing `_authorizeUpgrade` for direct assertions.

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OI-AU-1 | Reverts `UnauthorizedUpgrade` when authorization flag is false | [S] | P0 |
| OI-AU-2 | Succeeds only when authorization flag is set by authorized wrapper flow | [S] | P0 |
| OI-AU-3 | Authorization should be bound to the specific pre-approved `newImplementation` (not just a boolean flag) | [S] | P0 |

### 1.4 Inherited UUPS Entry Points (`upgradeToAndCall`, `proxiableUUID`)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OI-UUPS-1 | Calling `upgradeToAndCall` on implementation contract directly (not via proxy) reverts due UUPS `onlyProxy` guard | [S] | P1 |
| OI-UUPS-2 | Calling `proxiableUUID` through proxy reverts due `notDelegated` guard | [S] | P1 |

---

## File 2: `OrganizationAccountFactoryBase.sol`

### 2.1 `setAccountImplementation(address newImplementation, AdminAuthParams authParams)`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OAFB-SAI-1 | Valid guardian caller + valid admin auth + whitelisted Account implementation updates beacon implementation | [I] | P0 |
| OAFB-SAI-2 | Non-guardian caller reverts (onlyGuardian) | [N] | P0 |
| OAFB-SAI-3 | Expired admin auth reverts | [N] | P0 |
| OAFB-SAI-4 | Insufficient admin signatures reverts | [N] | P0 |
| OAFB-SAI-5 | Replay with same admin auth nonce reverts | [S] | P0 |
| OAFB-SAI-6 | Calling `setAccountImplemenation` with admin nonce that has already been rejected reverts | [S] | P0 |
| OAFB-SAI-7 | Signatures for different target implementation cannot authorize current call | [S] | P0 |
| OAFB-SAI-8 | Signatures for wrong operation type cannot authorize Account implementation upgrade | [S] | P0 |
| OAFB-SAI-9 | Non-whitelisted target implementation reverts `ImplementationNotWhitelisted` | [N] | P0 |
| OAFB-SAI-10 | Implementation whitelisted only for `ContractType.Organization` cannot be used for Account upgrade | [N] | P0 |
| OAFB-SAI-11 | Emits `AccountImplementationUpdated(newImplementation)` on success | [EV] | P1 |
| OAFB-SAI-12 | All previously deployed accounts immediately execute code from new implementation | [I] | P0 |
| OAFB-SAI-13 | Newly deployed accounts after upgrade also use the new implementation | [I] | P1 |
| OAFB-SAI-14 | Sequential upgrades (V1 -> V2 -> V3) preserve state and functionality at each step for account contracts that use the organization as their beacon | [I] | P1 |
| OAFB-SAI-15 | No per-account upgrade path exists (all accounts under an org share one implementation pointer) | [S] | P1 |
| OAFB-SAI-16 | Upgrading account implementation does not alter Organization proxy implementation | [S] | P1 |
| OAFB-SAI-17 | Upgrade fails closed if whitelist address has no code (EOA/zero/misconfigured) | [S] | P0 |
| OAFB-SAI-18 | `newImplementation` must be non-zero and have code (even if mistakenly whitelisted) | [S] | P0 |
| OAFB-SAI-19 | Reverting account-implementation upgrade paths (whitelist/no-code checks) do not consume admin auth nonce and do not mutate beacon implementation state | [S] | P1 |

### 2.2 `implementation()` (beacon implementation getter)

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| OAFB-IMP-1 | Returns latest account implementation after successive `setAccountImplementation` calls | [U] | P1 |
| OAFB-IMP-2 | Reverts `AccountImplementationNotSet` before any account implementation is configured | [N] | P1 |
| OAFB-IMP-3 | Organization UUPS upgrade preserves account implementation pointer used by beacon getter | [I] | P1 |

---

## File 3: `ImplementationWhitelistImplementation.sol`

### 3.1 `initialize(address initialOwner, address[] organizationImplementations, address[] accountImplementations)`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| IWI-INIT-1 | Proxy initialization sets owner and seeds both type-specific whitelists correctly | [I] | P1 |
| IWI-INIT-2 | Emits `ImplementationWhitelistInitialized(initialOwner)` | [EV] | P1 |
| IWI-INIT-3 | Cannot initialize proxy twice | [N] | P1 |
| IWI-INIT-4 | Implementation contract constructor disables initializers (direct initialize on implementation reverts) | [S] | P1 |
| IWI-INIT-5 | `isInitialized()` is false before init and true after successful init | [U] | P1 |
| IWI-INIT-6 | `initialOwner == address(0)` reverts during initialization | [N] | P0 |
| IWI-INIT-7 | Empty initial implementation arrays still initialize successfully and set owner | [E] | P2 |
| IWI-INIT-8 | Same implementation address can be seeded independently under both `ContractType.Organization` and `ContractType.Account` in init | [S] | P1 |

### 3.2 `whitelistImplementations(ContractType contractType, address[] toWhitelist, address[] toUnwhitelist)`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| IWI-WI-1 | Owner can add and remove implementations in a single call | [U] | P1 |
| IWI-WI-2 | Non-owner caller reverts | [N] | P1 |
| IWI-WI-3 | Organization and Account whitelists are two independent whitelisted within the same whitelist contract| [S] | P1 |
| IWI-WI-4 | Emits `ImplementationWhitelisted` and `ImplementationUnwhitelisted` for each processed address | [EV] | P2 |
| IWI-WI-7 | Same address present in both `toWhitelist` and `toUnwhitelist` in one call ends unwhitelisted (add then remove order) | [E] | P2 |
| IWI-WI-8 | Both arrays empty is a no-op and does not revert | [E] | P2 |
| IWI-WI-9 | Pending owner (before `acceptOwnership`) cannot call `whitelistImplementations` | [S] | P1 |
| IWI-WI-10 | After ownership transfer acceptance, new owner can mutate whitelist and old owner can no longer mutate it | [S] | P1 |

### 3.3 `isImplementationWhitelisted` / `validateIsImplementationWhitelistedOrRevert`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| IWI-VIW-1 | `isImplementationWhitelisted` returns true only for addresses whitelisted under matching `ContractType` | [U] | P1 |
| IWI-VIW-2 | `validateIsImplementationWhitelistedOrRevert` reverts for non-whitelisted targets with `ImplementationNotWhitelisted` | [N] | P1 |
| IWI-VIW-3 | `validateIsImplementationWhitelistedOrRevert` succeeds for whitelisted targets | [U] | P1 |
| IWI-VIW-4 | `validateIsImplementationWhitelistedOrRevert` reverts when implementation is whitelisted only under the other `ContractType` | [N] | P1 |

### 3.4 `_authorizeUpgrade(address newImplementation)` and inherited UUPS upgrade path

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| IWI-UUPS-1 | Owner can upgrade whitelist proxy via UUPS `upgradeToAndCall` | [I] | P1 |
| IWI-UUPS-2 | Non-owner cannot upgrade whitelist proxy | [N] | P1 |
| IWI-UUPS-3 | Pending owner (before `acceptOwnership`) cannot upgrade | [S] | P1 |
| IWI-UUPS-4 | After ownership transfer acceptance, old owner loses upgrade rights and new owner gains them | [S] | P1 |
| IWI-UUPS-5 | Upgrade with migration calldata executes migration logic | [I] | P1 |
| IWI-UUPS-6 | Whitelist storage persists across upgrades | [I] | P1 |
| IWI-UUPS-7 | Upgrade to non-UUPS / incompatible implementation reverts | [S] | P1 |
| IWI-UUPS-8 | Calling `upgradeToAndCall` on implementation contract directly (not proxy) reverts due UUPS `onlyProxy` guard | [S] | P1 |
| IWI-UUPS-9 | Calling `proxiableUUID` through proxy reverts due UUPS `notDelegated` guard | [S] | P1 |
| IWI-UUPS-10 | Owner cannot upgrade whitelist proxy to zero/no-code targets (must fail closed even with owner auth) | [S] | P0 |

### 3.5 Private Function Tests (Requires `private` -> `internal` Conversion for Harness)

> **Harness note:** `_addToWhitelist` and `_removeFromWhitelist` are currently `private`. For direct unit tests, expose them via an inherited harness contract after changing visibility to `internal` in the test branch.

#### 3.5.1 `_addToWhitelist(ContractType contractType, address[] implementations)`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| IWI-ATW-1 | Marks each input address as whitelisted for the given `ContractType` | [U] | P1 |
| IWI-ATW-2 | Leaves the other `ContractType` mapping unchanged for same addresses | [S] | P1 |
| IWI-ATW-3 | Emits one `ImplementationWhitelisted` event per input entry | [EV] | P2 |
| IWI-ATW-4 | Empty input array is a no-op and does not revert | [E] | P2 |
| IWI-ATW-6 | Duplicate entries are idempotent at state level (mapping stays `true`) | [E] | P2 |

#### 3.5.2 `_removeFromWhitelist(ContractType contractType, address[] implementations)`

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| IWI-RTW-1 | Marks each input address as not whitelisted for the given `ContractType` | [U] | P1 |
| IWI-RTW-2 | Leaves the other `ContractType` mapping unchanged for same addresses | [S] | P1 |
| IWI-RTW-3 | Emits one `ImplementationUnwhitelisted` event per input entry | [EV] | P2 |
| IWI-RTW-4 | Removing non-whitelisted entries is a no-op and does not revert | [E] | P2 |
| IWI-RTW-5 | Empty input array is a no-op and does not revert | [E] | P2 |
| IWI-RTW-6 | Duplicate removal entries are idempotent at state level (mapping stays `false`) | [E] | P2 |

---

## 4. Cross-File Upgrade Security Tests

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| UPG-CFS-1 | Full flow: whitelist new Organization impl -> guardian + admins authorize -> Organization UUPS upgrade succeeds | [I] | P0 |
| UPG-CFS-2 | Full flow: whitelist new Account impl -> guardian + admins authorize -> beacon update upgrades all accounts | [I] | P0 |
| UPG-CFS-3 | Unwhitelisting an implementation blocks future upgrades to that implementation but does not mutate already-active implementation pointers | [I] | P1 |
| UPG-CFS-4 | Unwhitelisting an implementation does not prevent organizations using the unwhitelisted implementation from upgrading to a new whitelisted implementation | [I] | P1 |
| UPG-CFS-5 | Unwhitelisting an implementation does not prevent organizations using the unwhitelisted implementation from upgrading the account implementation to a new whitelisted implementation | [I] | P1 |
| UPG-CFS-6 | Upgrading Organization implementation does not bypass Account implementation whitelist/type checks | [S] | P0 |
| UPG-CFS-7 | Compromised guardian assumption test: without valid admin auth, neither Organization nor Account upgrade path executes | [S] | P0 |
| UPG-CFS-8 | If an implementation is unwhitelisted after signatures are collected but before execution, execution still fails (whitelist enforced at execution time) | [S] | P0 |
| UPG-CFS-9 | Re-whitelisting a previously removed implementation re-enables upgrade paths only when fresh valid admin auth is provided | [I] | P1 |
| UPG-CFS-10 | Admin signatures created for Organization A cannot authorize the same upgrade call on Organization B (per-contract domain separation) | [S] | P0 |

---

## 5. Upgrade Fuzz Tests

| ID | Test Case | Type | Priority |
|---|-----------|------|----------|
| UPG-FZ-1 | Fuzz Organization upgrade targets: any non-whitelisted candidate always rejected | [F] | P0 |
| UPG-FZ-2 | Fuzz Account implementation targets: any non-whitelisted candidate always rejected | [F] | P0 |
| UPG-FZ-3 | Fuzz successful upgrade sequences (whitelisted targets + valid auth): state remains consistent across repeated upgrades | [F] | P1 |
| UPG-FZ-4 | Fuzz migration calldata: malformed payloads revert atomically (no partial upgrade state) | [F] | P0 |
| UPG-FZ-5 | Random calldata cannot trigger unauthorized nested second upgrade | [F] | P0 |

---

## 6. Upgrade Invariants

| ID | Invariant | Priority |
|---|-----------|----------|
| UPG-INV-1 | `isUpgradeAuthorized` is false outside authorized upgrade execution | P0 |
| UPG-INV-2 | Organization upgrades only target whitelisted Organization implementations | P0 |
| UPG-INV-3 | Account upgrades only target whitelisted Account implementations | P0 |
| UPG-INV-4 | All accounts under the same organization always resolve the same beacon implementation address | P0 |
| UPG-INV-5 | Organization UUPS implementation pointer and Account beacon implementation pointer are independent state variables | P1 |
| UPG-INV-6 | Organization proxy-stored whitelist address used for upgrade checks remains immutable across Organization upgrades | P1 |
| UPG-INV-7 | Direct calls to UUPS upgrade selectors on the Organization proxy (`upgradeToAndCall` and raw `upgradeTo` selector) never change implementation unless wrapper authorization succeeds in the same transaction | P0 |

---

## Summary

| Category | Tests | Priority |
|----------|-------|----------|
| `OrganizationImplementation.sol` | 36 | P0-P1 |
| `OrganizationAccountFactoryBase.sol` | 20 | P0-P1 |
| `ImplementationWhitelistImplementation.sol` | 41 | P0-P2 |
| Cross-file upgrade security | 8 | P0-P1 |
| Fuzz tests | 5 | P0-P1 |
| Invariants | 7 | P0-P1 |
| **Total** | **117** | |
