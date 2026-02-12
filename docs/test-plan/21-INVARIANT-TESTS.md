# 21 — Invariant Tests Plan

**Scope:** System-wide properties that must hold true across ALL states, regardless of the sequence of operations. These use Foundry's invariant testing framework with handler contracts.

**Test File(s):** `test/invariant/InvariantOrganization.t.sol`, `test/invariant/handlers/OrganizationHandler.sol`

---

## Handler Design

Create handler contracts that perform random sequences of valid operations:
- `AdminHandler` — calls modifyAdmins, modifyMembers, modifyGroups, setPolicies
- `TransactionHandler` — calls executeAccountTransaction, rejectAccountTransaction
- `GuardianHandler` — calls guardian update flows
- `RecoveryHandler` — calls recovery enable/disable/execute flows

---

## 1. Membership Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 1 | **Admin-must-be-member**: For every address where `isAdmin(addr) == true`, `isMember(addr) == true` | P0 |
| 2 | **Minimum members**: There is always at least 1 member in the organization | P0 |
| 3 | **Minimum admins**: `adminCount >= 1` at all times | P0 |
| 4 | **Voting threshold bounds**: `1 <= votingThreshold <= adminCount` at all times | P0 |
| 5 | **Admin count consistency**: The number of addresses where `isAdmin(addr) == true` equals `adminCount` | P0 |

---

## 2. Group Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 6 | **Deleted group non-reuse**: If `wasGroupDeleted[groupId] == true`, then `isGroup[groupId] == false` | P0 |
| 7 | **Group existence**: `isGroupMember(groupId, addr)` can only be relied upon if `isGroup(groupId) == true` | P1 |

---

## 3. Nonce Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 8 | **Nonce monotonicity**: Once `isNonceUsed(nonce) == true`, it remains true forever | P0 |
| 9 | **No double-spend**: A nonce that was used for an approval cannot be used for a rejection (and vice versa) | P0 |

---

## 4. Policy Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 10 | **Rate limit monotonicity within window**: Within a time window, usage can only increase or stay the same | P1 |
| 11 | **Rate limit reset**: Usage resets to 0 when a new time window begins | P1 |

---

## 5. Guardian Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 12 | **Guardian always set**: `guardian() != address(0)` after initialization | P0 |
| 13 | **Pending guardian exclusivity**: At most one pending guardian update at a time | P0 |
| 14 | **Timelock enforcement**: Guardian cannot be changed without waiting for timelock | P0 |

---

## 6. Account Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 15 | **Account-org binding**: An account's organization address (beacon) never changes | P0 |
| 16 | **Account tracking**: Every account deployed via `deployAccount` is in `deployedAccounts` mapping | P0 |
| 17 | **Only org executes**: Account's `executeTransaction` can only be called by the organization | P0 |

---

## 7. Upgrade Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 18 | **Authorization flag reset**: `isUpgradeAuthorized` is always false outside of `upgradeToAndCallWithAuthorization` | P0 |
| 19 | **Whitelist enforcement**: No implementation can be set/upgraded to unless it's whitelisted | P0 |

---

## 8. Recovery Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 20 | **Recovery isolation**: Recovery state changes don't affect normal guardian state (and vice versa) | P0 |
| 21 | **Disable immediacy**: `disableTxRecovery` always works immediately without timelock | P0 |
| 22 | **Enable requires timelock**: Tx recovery can only be enabled after waiting for timelock | P0 |

---

## 9. Signature Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 23 | **Cross-chain replay**: Signatures from chain A are never valid on chain B | P0 |
| 24 | **Cross-org replay**: Signatures for org A are never valid on org B | P0 |
| 25 | **Approval/rejection separation**: Approval signatures never validate as rejection signatures | P0 |

---

## 9.5 Rate Limit & Parameter Constraint Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 25.1 | **Rate limit atomicity**: Rate limit usage value either increases by exact usageAmount or doesn't change | P0 |
| 25.2 | **Rate limit no-overflow**: currentUsage + usageAmount never wraps (function returns false first) | P0 |
| 25.3 | **Group deletion permanence**: Once `wasGroupDeleted[groupId] == true`, it can never become false | P0 |
| 25.4 | **Account beacon immutability**: An Account's beacon (Organization) address cannot be changed after deployment | P0 |
| 25.5 | **No orphaned admins**: Removing a member who is an admin always reverts | P0 |
| 25.6 | **Signature non-transferability**: A signature valid for Organization A is never valid for Organization B | P0 |

---

## 10. Storage Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 26 | **No slot collision**: ERC-7201 namespaced storage slots never collide with each other or with proxy storage | P1 |
| 27 | **Storage persistence**: Storage values survive across proxy delegate calls | P1 |

---

## 11. Initialization Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 28 | **Initialization permanence**: `isInitialized()` can only transition false→true, never back to false | P0 |
| 29 | **Member-before-admin ordering**: After initialization, all admins are members | P0 |

---

## 12. Timelock Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 30 | **Duration bounds**: All active timelock durations are in [2 days, 30 days] | P1 |
| 31 | **Timestamp monotonicity**: `computeCanFinalizeAtTimestamp` result is always >= `block.timestamp` | P1 |

---

## 13. Whitelist Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 32 | **Type independence**: Organization and Account implementation whitelists are independent mappings | P2 |
| 33 | **Owner exclusivity**: Only the owner can add/remove implementations from the whitelist | P2 |

---

## 14. EIP-712 Invariants

| # | Invariant | Priority |
|---|-----------|----------|
| 34 | **Domain separator determinism**: Same (chainId, verifying contract) always produces the same domain separator | P1 |
| 35 | **Type hash uniqueness**: All EIP-712 type hashes in the system are unique (no collisions) | P1 |
| 36 | **Prefix compliance**: All typed data hashes include `\x19\x01` prefix per EIP-712 | P1 |

---

## Summary

| Category | Invariants | Priority |
|----------|------------|----------|
| Membership | 5 | P0 |
| Groups | 2 | P0-P1 |
| Nonces | 2 | P0 |
| Policies | 2 | P1 |
| Guardian | 3 | P0 |
| Accounts | 3 | P0 |
| Upgrades | 2 | P0 |
| Recovery | 3 | P0 |
| Signatures | 3 | P0 |
| Rate limits & constraints | 6 | P0 |
| Storage | 2 | P1 |
| Initialization | 2 | P0 |
| Timelocks | 2 | P1 |
| Whitelist | 2 | P2 |
| EIP-712 | 3 | P1 |
| **Total** | **42** | |
