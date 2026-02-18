# 05 — Organization Groups Test Plan (By File and Function)

**Goal:** Validate **desired** organization-groups behavior. This plan intentionally includes tests that may fail on current code to expose implementation gaps.

**Files Under Test:**
- `src/organization/libraries/LibOrganizationGroups.sol`
- `src/organization/base/OrganizationGroupsBase.sol`

**Test File(s):**
- `test/LibOrganizationGroups.t.sol`
- `test/OrganizationGroupsBase.t.sol`
- `test/harness/LibOrganizationGroupsHarness.sol` (for private-function coverage via `private` -> `internal` conversion)

---

## 1. `src/organization/libraries/LibOrganizationGroups.sol`

### 1.1 `modifyGroups(GroupModification[] calldata modifications)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Empty modifications array is a no-op (no state changes, no events) | [E] | P2 |
| 2 | Batch with create, update, and delete across multiple groups succeeds in-order | [U] | P0 |
| 3 | Order-sensitive batch: `Create -> Update` same group in one call succeeds | [U] | P0 |
| 4 | Order-sensitive batch: `Update -> Create` same group in one call reverts on update | [N] | P0 |
| 5 | Same-group multi-op: `Create -> Delete` in one call succeeds and leaves group deleted | [U] | P0 |
| 6 | Same-group multi-op: `Delete -> Create` reverts (`GroupAlreadyDeleted` on create) | [S] | P0 |
| 7 | Same-group multi-op: `Delete -> Update` reverts (`GroupDoesNotExist` on update) | [N] | P0 |
| 8 | Same-group multi-op: `Create -> Create` reverts (`GroupAlreadyExists` on second create) | [N] | P0 |
| 9 | Any failing modification causes full transaction revert (atomicity across batch) | [S] | P0 |
| 10 | Revert data from underlying helper path is bubbled correctly | [U] | P1 |
| 11 | **Desired behavior** Malformed enum value in calldata reverts and does not silently skip modification | [N] | P0 |
| 12 | Event ordering across a successful mixed batch follows modification order deterministically | [EV] | P1 |
| 13 | Boundary IDs: `groupId = 0` and `groupId = type(uint256).max` are handled correctly in batch execution | [E] | P1 |

### 1.2 `isGroup(uint256 groupId)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Returns `true` for active group | [U] | P3 |
| 2 | Returns `false` for group that never existed | [U] | P3 |
| 3 | Returns `false` after deletion | [U] | P3 |
| 4 | Boundary IDs `0` and `type(uint256).max` can be queried without revert | [E] | P3 |

### 1.3 `isGroupMember(uint256 groupId, address memberAddress)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Returns `true` for address currently in group | [U] | P3 |
| 2 | Returns `false` for address not in group | [U] | P3 |
| 3 | **Desired behavior:** checks group existence first and returns `false` for non-existent group | [U] | P1 |
| 4 | **Desired behavior:** checks group existence first and returns `false` for deleted group even if historical membership mapping contains ghost data | [S] | P1 |
| 5 | **Desired behavior:** member removed from org and/or group deletion cannot produce `isGroupMember == true` unless group currently exists and membership is active | [S] | P1 |

### 1.4 `_createGroup(GroupModification calldata mod)` *(private; test via `modifyGroups` create path and harness)*

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Create with valid new ID and valid members succeeds; sets `isGroup[groupId] = true` and sets `isGroupMember[groupId][member] = true` for each `membersToAdd` entry | [U] | P0 |
| 2 | Create with empty member list succeeds (empty group) and no memberships are added | [U] | P0 |
| 3 | Create existing group reverts `GroupAlreadyExists(groupId)` | [N] | P0 |
| 4 | Create previously-deleted group ID reverts `GroupAlreadyDeleted(groupId)` | [S] | P0 |
| 5 | Create with non-empty `membersToRemove` reverts `InvalidGroupCreationOperation(groupId)` | [N] | P0 |
| 6 | Emits `GroupCreated(groupId)` exactly once on successful creation | [EV] | P1 |
| 7 | Emits `GroupMemberAdded(groupId, member)` for each newly added unique member | [EV] | P1 |
| 8 | Duplicate members in `membersToAdd` are idempotent (no revert, no duplicate event) | [E] | P0 |
| 9 | `address(0)` in `membersToAdd` reverts with `InvalidMemberAddress(address(0))` | [N] | P0 |
| 10 | **Desired behavior:** non-organization member in `membersToAdd` reverts `MemberDoesNotExist(member)` | [S] | P0 |
| 11 | **Desired behavior:** mixed valid + invalid members reverts atomically (no partial member writes, no `GroupCreated`) | [S] | P0 |
| 12 | Boundary ID: create path supports `groupId = 0` with expected state/events | [E] | P1 |
| 13 | Boundary ID: create path supports `groupId = type(uint256).max` with expected state/events | [E] | P1 |

### 1.5 `_updateGroup(GroupModification calldata mod)` *(private; test via `modifyGroups` update path and harness)*

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Update existing group with adds succeeds; each `membersToAdd` address becomes `isGroupMember[groupId][addr] = true` and unrelated members remain unchanged | [U] | P0 |
| 2 | Update existing group with removals succeeds; each `membersToRemove` address becomes `isGroupMember[groupId][addr] = false` and unrelated members remain unchanged | [U] | P0 |
| 3 | Update existing group with adds + removals in same mod succeeds and results in the exact expected final membership set (`_addGroupMembers` then `_removeGroupMembers`) | [U] | P0 |
| 4 | Update non-existent group reverts `GroupDoesNotExist(groupId)` | [N] | P0 |
| 5 | Update deleted group reverts `GroupDoesNotExist(groupId)` | [N] | P0 |
| 6 | Removing member not in group is a no-op (no revert, no state change, no `GroupMemberRemoved` event) | [E] | P0 |
| 7 | Adding already-existing member is idempotent (no revert, no duplicate event) | [E] | P0 |
| 8 | Adding `address(0)` reverts `InvalidMemberAddress(address(0))` | [N] | P0 |
| 9 | **Desired behavior:** adding non-organization member reverts `MemberDoesNotExist(member)` | [S] | P0 |
| 10 | **Desired behavior:** mixed valid + invalid additions revert atomically | [S] | P0 |
| 11 | **Desired behavior:** member removed from org cannot be added/re-added to group (`MemberDoesNotExist`) | [S] | P0 |
| 12 | Overlap semantics: same member in `membersToAdd` and `membersToRemove` when initially absent ends removed (add then remove) | [E] | P0 |
| 13 | Overlap semantics: same member in `membersToAdd` and `membersToRemove` when initially present ends removed | [E] | P0 |
| 14 | Event ordering in mixed update: `GroupMemberAdded` events occur before `GroupMemberRemoved` events | [EV] | P1 |

### 1.6 `_deleteGroup(GroupModification calldata mod)` *(private; test via `modifyGroups` delete path and harness)*

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Delete existing group succeeds; sets `isGroup[groupId] = false` | [U] | P0 |
| 2 | Delete sets `wasGroupDeleted[groupId] = true` and flag never resets | [U] | P0 |
| 3 | Delete non-existent group is a no-op (no revert, no state change, no `GroupDeleted` event) | [E] | P0 |
| 4 | Delete with non-empty `membersToAdd` reverts `InvalidGroupDeletionOperation(groupId)` | [N] | P0 |
| 5 | Delete with non-empty `membersToRemove` reverts `InvalidGroupDeletionOperation(groupId)` | [N] | P0 |
| 6 | Emits `GroupDeleted(groupId)` exactly once on successful deletion | [EV] | P1 |
| 7 | Recreate of deleted `groupId` always reverts `GroupAlreadyDeleted(groupId)` | [S] | P0 |
| 8 | Historical `isGroupMember[groupId][member]` entries persist after delete (ghost data) | [E] | P0 |

### 1.7 `_addGroupMembers(Layout storage, uint256 groupId, address[] calldata members)` *(private; harness target)*

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Adds new members and marks `isGroupMember[groupId][member] = true` | [U] | P0 |
| 2 | Emits `GroupMemberAdded(groupId, member)` for each newly added member | [EV] | P1 |
| 3 | Duplicate members are no-op (state unchanged after first add; no duplicate event) | [E] | P0 |
| 4 | `address(0)` member reverts `InvalidMemberAddress(address(0))` | [N] | P0 |
| 5 | **Desired behavior:** non-organization member reverts `MemberDoesNotExist(member)` | [S] | P0 |
| 6 | **Desired behavior:** mixed valid + invalid members in one call revert atomically | [S] | P0 |
| 7 | **Desired behavior:** addresses removed from org are treated as invalid for group add | [S] | P0 |

### 1.8 `_removeGroupMembers(Layout storage, uint256 groupId, address[] calldata members)` *(private; harness target)*

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Removing existing member sets `isGroupMember[groupId][member] = false` | [U] | P0 |
| 2 | Emits `GroupMemberRemoved(groupId, member)` on successful removal | [EV] | P1 |
| 3 | Removing non-member is a no-op (no revert, no state change, no `GroupMemberRemoved` event) | [E] | P0 |
| 4 | Removing same member twice in one call is a no-op on the second removal (no revert); final state remains `false` and only the first successful removal emits `GroupMemberRemoved` | [E] | P0 |

### 1.9 Library-Level Fuzz & Invariants

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Fuzz: random create/update/delete batches preserve atomicity on any failing item | [F] | P0 |
| 2 | Fuzz: deleted group IDs are never reusable | [F] | P0 |
| 3 | Fuzz: duplicate additions are idempotent | [F] | P1 |
| 4 | Fuzz: zero-address member add always reverts `InvalidMemberAddress` | [F] | P0 |
| 5 | Fuzz (desired): random non-member addresses always revert `MemberDoesNotExist` on add | [F] | P0 |
| 6 | Invariant: if `wasGroupDeleted[groupId] == true`, then `isGroup[groupId] == false` forever | [I] | P0 |
| 7 | Invariant: `wasGroupDeleted[groupId]` is monotonic (`false -> true` only) | [I] | P0 |
| 8 | Invariant: no zero-address group membership can ever be set | [I] | P0 |
| 9 | Invariant (desired): active group membership implies org membership (`isGroupMember => isMember`) | [I] | P0 |

---

## 2. `src/organization/base/OrganizationGroupsBase.sol`

### 2.1 `modifyGroups(GroupModification[] calldata modifications, AdminAuthParams calldata authParams)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Guardian + valid admin auth: forwards to library and applies expected state transition | [I] | P0 |
| 2 | Non-guardian caller reverts with guardian access-control error | [N] | P0 |
| 3 | Invalid/insufficient admin signatures revert via admin auth validation | [N] | P0 |
| 4 | Expired auth params revert via admin auth validation | [N] | P0 |
| 5 | Replay using same nonce/salt reverts after a successful first execution | [S] | P0 |
| 6 | **Desired behavior:** failed auth attempt does not consume nonce; same salt/operation can succeed after corrected signatures | [S] | P0 |
| 7 | Any modification-data tampering after signatures invalidates auth and reverts | [S] | P0 |
| 8 | Empty modifications still require valid auth and consume nonce on success | [E] | P1 |
| 9 | Library custom errors bubble through base unchanged (including desired `MemberDoesNotExist` once implemented) | [U] | P0 |
| 10 | Malformed enum in modifications reverts through base path and leaves state unchanged | [N] | P0 |

### 2.2 `isGroup(uint256 groupId)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Pure passthrough to library value for active/non-existent/deleted groups | [U] | P3 |

### 2.3 `isGroupMember(uint256 groupId, address memberAddress)`

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Pure passthrough to library value for existing-group member and non-member queries | [U] | P3 |
| 2 | **Desired behavior:** returns `false` for non-existent groups via library existence check | [U] | P1 |
| 3 | **Desired behavior:** returns `false` for deleted groups via library existence check (no ghost-membership leak through base getter) | [S] | P1 |

---

## Summary (Coverage by File)

| File | Functions Covered | Test Cases | Priority Focus |
|------|-------------------|------------|----------------|
| `src/organization/libraries/LibOrganizationGroups.sol` | 9 | 77 | P0 state machine, atomicity, and desired behavior gaps |
| `src/organization/base/OrganizationGroupsBase.sol` | 3 | 14 | P0 auth/access control and revert propagation |
| **Total** | **12** | **91** | **P0-heavy** |
