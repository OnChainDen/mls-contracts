# 04 — Organization Members Test Plan

**Files Under Test:**
- `src/organization/libraries/LibOrganizationMembers.sol`
- `src/organization/base/OrganizationMembersBase.sol`
- `src/organization/libraries/storage/LibOrganizationMembersStorage.sol`
- `src/interfaces/organization/IOrganizationMembers.sol`

**Test File(s):** `test/LibOrganizationMembers.t.sol`, `test/OrganizationMembersBase.t.sol`

---

## 1. Member Addition

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Add single member — succeeds, `isMember` returns true | [U] | P0 |
| 2 | Add multiple members — all added | [U] | P0 |
| 3 | Add address(0) — reverts with `InvalidMemberAddress(address(0))` | [N] | P0 |
| 4 | Add already-existing member — no-op (idempotent), no revert | [E] | P0 |
| 5 | Member added emits `MemberAdded` event | [EV] | P1 |
| 6 | Adding existing member does NOT emit `MemberAdded` again | [EV] | P1 |

---

## 2. Member Removal

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 7 | Remove existing member — succeeds, `isMember` returns false | [U] | P0 |
| 8 | Remove multiple members — all removed | [U] | P0 |
| 9 | Remove non-existent member — reverts with `MemberDoesNotExist` | [N] | P0 |
| 10 | Remove member who is an admin — reverts with `MemberIsAdmin` | [S] | P0 |
| 11 | Remove member who is in a group — succeeds (group membership not checked) | [E] | P0 |
| 12 | Member removed emits `MemberRemoved` event | [EV] | P1 |

---

## 3. Admin-Member Invariant

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 13 | Cannot remove member who is admin without first removing admin status | [S] | P0 |
| 14 | After removing admin status, member can be removed | [U] | P0 |
| 15 | Adding admin (in admin module) requires address to already be member | [I] | P0 |

---

## 4. Combined Add/Remove Operations

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 16 | Add and remove different members in same call | [U] | P0 |
| 17 | Both arrays empty — no-op succeeds | [E] | P2 |
| 18 | Add then remove same address in same call — net effect: removed (add processed first) | [E] | P0 |
| 19 | Remove an address then add it back in same call — reverts on remove (not member yet) | [E] | P0 |

---

## 5. Query Functions

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 20 | `isMember` returns true for existing member | [U] | P3 |
| 21 | `isMember` returns false for non-member | [U] | P3 |
| 22 | `isMember` returns false for address(0) | [U] | P3 |

---

## 6. Access Control (Base Contract Level)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 23 | `modifyMembers` requires admin auth (valid signatures) | [U] | P0 |
| 24 | `modifyMembers` reverts when caller is not guardian | [N] | P0 |
| 25 | `modifyMembers` with insufficient admin signatures reverts | [N] | P0 |
| 26 | `isMember` callable by anyone | [U] | P3 |

---

## 7. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 27 | Fuzz: Add N random non-zero addresses, all become members | [F] | P0 |
| 28 | Fuzz: Add then remove N random addresses, none remain members | [F] | P0 |
| 29 | Fuzz: Adding same address twice is idempotent | [F] | P1 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Member addition | 6 | P0 |
| Member removal | 6 | P0 |
| Admin-member invariant | 3 | P0 |
| Combined operations | 4 | P0 |
| Query functions | 3 | P3 |
| Access control | 4 | P0 |
| Fuzz tests | 3 | P0-P1 |
| **Total** | **29** | |
