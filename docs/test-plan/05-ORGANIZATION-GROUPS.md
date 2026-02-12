# 05 — Organization Groups Test Plan

**Files Under Test:**
- `src/organization/libraries/LibOrganizationGroups.sol`
- `src/organization/base/OrganizationGroupsBase.sol`
- `src/organization/libraries/storage/LibOrganizationGroupsStorage.sol`
- `src/interfaces/organization/IOrganizationGroups.sol`

**Test File(s):** `test/LibOrganizationGroups.t.sol`, `test/OrganizationGroupsBase.t.sol`

---

## 1. Group Creation

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Create group with valid ID and members — succeeds | [U] | P0 |
| 2 | Create group with no members — succeeds (empty group) | [U] | P0 |
| 3 | Create group that already exists — reverts with `GroupAlreadyExists` | [N] | P0 |
| 4 | Create group with previously deleted ID — reverts with `GroupAlreadyDeleted` | [S] | P0 |
| 5 | Create group with `membersToRemove` non-empty — reverts with `InvalidGroupCreationOperation` | [N] | P0 |
| 6 | Group creation emits `GroupCreated(groupId)` event | [EV] | P1 |
| 7 | Group member addition emits `GroupMemberAdded(groupId, member)` for each | [EV] | P1 |
| 8 | Create group with address(0) member — reverts with `InvalidMemberAddress` | [N] | P0 |
| 8.1 | Create group with member who is not an organization member — reverts with `MemberDoesNotExist` | [S] | P0 |
| 9 | Create group with duplicate members — second add is no-op (idempotent) | [E] | P0 |

---

## 2. Group Modification (Update)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 10 | Add members to existing group — succeeds | [U] | P0 |
| 11 | Remove members from existing group — succeeds | [U] | P0 |
| 12 | Add and remove members in same modification — succeeds | [U] | P0 |
| 13 | Modify non-existent group — reverts with `GroupDoesNotExist` | [N] | P0 |
| 14 | Modify deleted group — reverts with `GroupDoesNotExist` | [N] | P0 |
| 15 | Remove member not in group — reverts with `MemberNotInGroup` | [N] | P0 |
| 16 | Remove member emits `GroupMemberRemoved(groupId, member)` | [EV] | P1 |
| 17 | Add already-existing group member — no-op (idempotent) | [E] | P0 |
| 18 | Add address(0) to group — reverts | [N] | P0 |
| 18.1 | Add non-organization-member to existing group — reverts with `MemberDoesNotExist` | [S] | P0 |
| 18.2 | Add mix of org members and non-org-members — reverts (entire operation fails atomically) | [S] | P0 |
| 18.3 | Remove address from organization, then try to add to group — reverts with `MemberDoesNotExist` | [S] | P0 |

---

## 3. Group Deletion

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 19 | Delete existing group — succeeds, `isGroup` returns false | [U] | P0 |
| 20 | Delete non-existent group — reverts with `GroupDoesNotExist` | [N] | P0 |
| 21 | Delete with `membersToAdd` non-empty — reverts with `InvalidGroupDeletionOperation` | [N] | P0 |
| 22 | Delete with `membersToRemove` non-empty — reverts with `InvalidGroupDeletionOperation` | [N] | P0 |
| 23 | Deleted group's `wasGroupDeleted` flag is true (prevents reuse) | [U] | P0 |
| 24 | Group deletion emits `GroupDeleted(groupId)` event | [EV] | P1 |
| 25 | After deletion, `isGroup` returns false | [U] | P0 |
| 26 | After deletion, `isGroupMember` still returns true for old members (ghost data) | [E] | P0 |

---

## 4. Group ID Non-Reuse

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 27 | Create group ID 1, delete it, try to create group ID 1 again — reverts | [S] | P0 |
| 28 | Different group IDs are independent — creating/deleting one does not affect others | [U] | P1 |
| 29 | `wasGroupDeleted` persists even after many operations | [U] | P1 |

---

## 5. Batch Modifications (`modifyGroups` with array)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 30 | Multiple group modifications in single call — all succeed | [U] | P0 |
| 31 | Create + modify + delete different groups in single call | [U] | P0 |
| 32 | First modification fails — entire call reverts (atomicity) | [U] | P0 |
| 33 | Empty modifications array — no-op succeeds | [E] | P2 |

---

## 6. Query Functions

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 34 | `isGroup` returns true for existing group | [U] | P3 |
| 35 | `isGroup` returns false for non-existent group | [U] | P3 |
| 36 | `isGroup` returns false for deleted group | [U] | P3 |
| 37 | `isGroupMember` returns true for member in group | [U] | P3 |
| 38 | `isGroupMember` returns false for non-member | [U] | P3 |
| 39 | `isGroupMember` returns false for non-existent group (no revert) | [E] | P3 |

---

## 7. Access Control (Base Contract Level)

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 40 | `modifyGroups` requires admin auth | [U] | P0 |
| 41 | `modifyGroups` reverts when caller is not guardian | [N] | P0 |
| 42 | View functions callable by anyone | [U] | P3 |

---

## 8. Fuzz Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 43 | Fuzz: Create group with N random members, all are group members | [F] | P0 |
| 44 | Fuzz: Random group IDs (non-deleted) can be created | [F] | P1 |
| 45 | Fuzz: Add then remove random members, none remain in group | [F] | P0 |
| 46 | Fuzz: Deleted group ID always rejected on re-creation attempt | [F] | P0 |
| 46.1 | Fuzz: Random group member additions are idempotent (adding existing member is no-op) | [F] | P1 |
| 46.2 | Fuzz: Create, modify, and delete multiple random groups in single call — atomicity preserved | [F] | P0 |
| 46.3 | Fuzz: Random address(0) members always rejected with `InvalidMemberAddress` | [F] | P0 |
| 46.4a | Fuzz: Random non-organization-member addresses always rejected when adding to group | [F] | P0 |

---

## 8.5 Invariant Tests

| # | Invariant | Priority |
|---|-----------|----------|
| 46.4b | **Deleted group non-reuse**: If `wasGroupDeleted[groupId] == true`, then `isGroup[groupId] == false` forever | P0 |
| 46.5 | **Deletion permanence**: `wasGroupDeleted[groupId]` can only transition from false to true, never back | P0 |
| 46.6 | **No zero-address group members**: `isGroupMember(groupId, address(0))` is never set to true | P0 |
| 46.7 | **Group-members-are-org-members**: For every `(groupId, addr)` where `isGroupMember(groupId, addr) == true` and `isGroup(groupId) == true`, `isMember(addr) == true` | P0 |

---

## 9. Private Function Tests (Requires `private` → `internal` Conversion)

> **Prerequisite:** The functions below are currently `private` in `LibOrganizationGroups`.
> Convert them to `internal` and create a test harness that exposes each via public wrappers.
> Note: Many edge cases of these functions ARE already covered through the public `modifyGroups`
> interface (sections 1-5). The tests below target behaviors best verified with direct access.

### 9.1 `_createGroup`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 47 | Create group — sets `isGroup[groupId] = true` | [U] | P0 |
| 48 | Create group with previously deleted ID — reverts `GroupAlreadyDeleted` | [S] | P0 |
| 49 | Create group that already exists — reverts `GroupAlreadyExists` | [N] | P0 |
| 50 | Create group with `membersToRemove` non-empty — reverts `InvalidGroupCreationOperation` | [N] | P0 |
| 51 | Create group calls `_addGroupMembers` for initial members | [U] | P0 |

### 9.2 `_updateGroup`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 52 | Update non-existent group — reverts `GroupDoesNotExist` | [N] | P0 |
| 53 | Update calls `_addGroupMembers` then `_removeGroupMembers` in order | [U] | P1 |

### 9.3 `_deleteGroup`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 54 | Delete sets `isGroup = false` and `wasGroupDeleted = true` atomically | [U] | P0 |
| 55 | Delete non-existent group — reverts `GroupDoesNotExist` | [N] | P0 |
| 56 | Delete with non-empty `membersToAdd` — reverts `InvalidGroupDeletionOperation` | [N] | P0 |
| 57 | Delete with non-empty `membersToRemove` — reverts `InvalidGroupDeletionOperation` | [N] | P0 |

### 9.4 `_addGroupMembers`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 58 | Add address(0) — reverts `InvalidMemberAddress` | [N] | P0 |
| 58.1 | Add address that is not an organization member — reverts `MemberDoesNotExist` | [S] | P0 |
| 59 | Add already-existing member — no-op (idempotent, no event) | [E] | P0 |
| 60 | Add new member — sets `isGroupMember = true`, emits `GroupMemberAdded` | [U] | P0 |

### 9.5 `_removeGroupMembers`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 61 | Remove member not in group — reverts `MemberNotInGroup` | [N] | P0 |
| 62 | Remove existing member — sets `isGroupMember = false`, emits `GroupMemberRemoved` | [U] | P0 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Group creation | 10 | P0 |
| Group modification | 12 | P0 |
| Group deletion | 8 | P0 |
| Group ID non-reuse | 3 | P0-P1 |
| Batch modifications | 4 | P0 |
| Query functions | 6 | P3 |
| Access control | 3 | P0 |
| Fuzz tests | 8 | P0-P1 |
| Invariant tests | 4 | P0 |
| Private function tests | 17 | P0-P1 |
| **Total** | **75** | |
