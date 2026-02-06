<!-- bcba7b95-e668-4057-af10-67fa4d1d9ab5 2fc829dd-44fe-4c73-ad0e-4481d38233b4 -->
# Refactor Authorization Checks to OrganizationImplementation

## Overview

Move authorization checks (`enforceOnlyGuardian` and `validateAdminAuthorization`) from internal library functions to external wrapper functions in `OrganizationImplementation.sol`. Create a `onlyGuardian` modifier to replace direct `enforceOnlyGuardian()` calls.

## Files to Modify

### 1. OrganizationImplementation.sol

- Create `onlyGuardian` modifier that calls `LibOrganizationGuardian.enforceOnlyGuardian()`
- Update external wrapper functions to:
- Apply `onlyGuardian` modifier where needed
- Call `validateAdminAuthorization` before delegating to library functions
- Remove authorization parameters from library function calls where they're no longer needed

### 2. Library Files (Remove Authorization Calls)

Remove `enforceOnlyGuardian()` and `validateAdminAuthorization()` calls from these internal functions:

- **LibOrganizationPolicy.sol**: `modifyPolicies()` (lines 83, 103-105)
- **LibOrganizationAccountFactory.sol**: `deployAccount()` (lines 63-65) - only `validateAdminAuthorization`
- **LibOrganizationMembers.sol**: 
- `addMembers()` (lines 107, 118)
- `modifyMember()` (lines 165, 190-192)
- `removeMembers()` (lines 215, 226-228)
- **LibOrganizationGroups.sol**:
- `createGroup()` (lines 112, 130)
- `modifyGroup()` (lines 169, 188)
- `removeGroup()` (lines 225, 238)
- **LibOrganizationAdmin.sol**: `updateAdmin()` (lines 125, 131)
- **LibOrganizationGuardian.sol**: `updateGuardian()` (lines 62, 73-75)
- **LibOrganizationWhitelist.sol**: `modifyWhitelist()` (lines 55, 61-63)

## Implementation Steps

1. **Add `onlyGuardian` modifier to OrganizationImplementation.sol**

- Place after imports, before contract declaration or as first modifier
- Modifier should call `LibOrganizationGuardian.enforceOnlyGuardian()`

2. **Update wrapper functions in OrganizationImplementation.sol**:

- Functions needing `onlyGuardian` modifier:
- `modifyPolicies()` (line 143)
- `addMembers()` (line 72)
- `modifyMember()` (line 83)
- `removeMembers()` (line 87)
- `createGroup()` (line 111)
- `modifyGroup()` (line 115)
- `removeGroup()` (line 127)
- `updateAdmin()` (line 235)
- `updateGuardian()` (line 271)
- `modifyWhitelist()` (line 200)
- Functions needing `validateAdminAuthorization` call:
- All above functions plus `deployAccount()` (line 279)
- For each function:
- Add `onlyGuardian` modifier if it currently calls `enforceOnlyGuardian()` in library
- Add `validateAdminAuthorization` call before library function call
- Encode operation data as currently done in library functions

3. **Remove authorization calls from library functions**:

- Remove `LibOrganizationGuardian.enforceOnlyGuardian()` calls
- Remove `LibOrganizationAdmin.validateAdminAuthorization()` calls
- Keep all other logic intact

4. **Update function signatures**:

- Remove `salt` and `signatures` parameters from library functions (they are only used for authorization)
- Wrapper functions will keep these parameters and use them for `validateAdminAuthorization` calls

## Notes

- The `onlyGuardian` modifier will be applied at the function level, ensuring guardian check happens first (before function body executes)
- `validateAdminAuthorization` will be called as the first line in the function body (after modifier check, before delegating to library functions)
- Execution order: modifier check → validateAdminAuthorization → library function call
- Library functions will become pure business logic without authorization concerns
- Operation data encoding logic should remain in wrapper functions to match current library implementation

### To-dos

- [ ] Create `onlyGuardian` modifier in OrganizationImplementation.sol that calls LibOrganizationGuardian.enforceOnlyGuardian()
- [ ] Update modifyPolicies wrapper to add onlyGuardian modifier and validateAdminAuthorization call
- [ ] Update addMembers, modifyMember, removeMembers wrappers with onlyGuardian modifier and validateAdminAuthorization calls
- [ ] Update createGroup, modifyGroup, removeGroup wrappers with onlyGuardian modifier and validateAdminAuthorization calls
- [ ] Update updateAdmin, updateGuardian, modifyWhitelist wrappers with onlyGuardian modifier and validateAdminAuthorization calls
- [ ] Update deployAccount wrapper to add validateAdminAuthorization call (no onlyGuardian needed)
- [ ] Remove enforceOnlyGuardian and validateAdminAuthorization calls from LibOrganizationPolicy.modifyPolicies
- [ ] Remove enforceOnlyGuardian and validateAdminAuthorization calls from LibOrganizationMembers functions
- [ ] Remove enforceOnlyGuardian and validateAdminAuthorization calls from LibOrganizationGroups functions
- [ ] Remove enforceOnlyGuardian and validateAdminAuthorization calls from LibOrganizationAdmin.updateAdmin and LibOrganizationGuardian.updateGuardian
- [ ] Remove enforceOnlyGuardian and validateAdminAuthorization calls from LibOrganizationWhitelist.modifyWhitelist
- [ ] Remove validateAdminAuthorization call from LibOrganizationAccountFactory.deployAccount