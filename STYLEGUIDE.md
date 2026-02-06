# Solidity Smart Contract Style Guide & Rules

**Instructions for AI:**
When generating, refactoring, or auditing Solidity code, strictly adhere to the following style guide, formatting, and ordering rules.

## 1. File Layout & Imports

### Top-Level Ordering
1.  **License Identifier** (e.g., `// SPDX-License-Identifier: MIT`)
2.  **Pragma**
    * **Lock versions** for implementation contracts (e.g., `pragma solidity 0.8.24;`).
    * Avoid floating versions (`^`) unless writing a generic library or interface.
3.  **Imports** (See grouping rules below).
4.  **File-Level Errors/Constants** (if applicable).
5.  **Interfaces**.
6.  **Contracts**.

### Import Hygiene
* **Named Imports:** Always use named imports instead of importing entire files.
    * **Good:** `import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";`
    * **Bad:** `import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";`
* **Absolute Import Paths:** Always use absolute import paths based on the remapped imports defined in `foundry.toml`. Never use relative import paths.
    * **Good:** `import { IOrganization } from "interfaces/IOrganization.sol";`
    * **Good:** `import { PolicyConfig } from "types/Policies.sol";`
    * **Bad:** `import { IOrganization } from "../interfaces/IOrganization.sol";`
    * **Bad:** `import { PolicyConfig } from "./types/Policies.sol";`
* **Grouping:** Separate imports into two distinct groups, separated by a blank line:
    1.  **External/Dependencies** (e.g., `@openzeppelin`, `solady`).
    2.  **Internal/Project** (e.g., `interfaces/`, `libraries/`, `types/`).
* **Sorting:** Strictly **alphabetize** imports within their respective groups.

### Code Organization

#### Interface Files (`interfaces/` directory)
* All **public/external functions, events, errors, and storage variables** must be defined in interface files located in the `interfaces/` directory.
* All **private/internal functions and storage variables** must NOT be defined in interface files. Define them locally in the implementation contract or library where they are used.

#### Types Files (`types/` directory)
* All **types (structs and enums) that are exposed to public users** of contracts must be defined in type files located in the `types/` directory. A type is considered "exposed" if it is used in:
    * Public or external function signatures (parameters or return types)
    * Events
    * Errors
    * Public storage variables
* All **types (structs and enums) that are NOT exposed to public users** must be defined locally in the contract or library where they are used. These are types only used internally within the implementation.

## 2. Contract Definition

### Inheritance Listing
* List inherited contracts from **Base** to **Derived** (e.g., `contract MyContract is Initializable, Ownable, UUPSUpgradeable`).

### Interface Implementation
* Use the `override` keyword for **all functions that implement a function defined in an interface** that the contract inherits from.
    ```solidity
    // Good - explicit override for interface implementation
    function getMembersRoot() external view override returns (bytes32) {
        return LibOrganizationMembersStorage.layout().membersRoot;
    }
    
    // Bad - missing override keyword
    function getMembersRoot() external view returns (bytes32) {
        return LibOrganizationMembersStorage.layout().membersRoot;
    }
    ```

### Internal Contract Layout
Order declarations strictly as follows:
1.  **Type Declarations** (`struct`, `enum`)
2.  **State Variables** (Order by visibility: `constant` -> `immutable` -> `public` -> `internal` -> `private`)
3.  **Events** (Group all events together)
4.  **Errors** (Group all custom errors together; do not mix with Events)
5.  **Modifiers**
6.  **Functions**

## 3. Function Ordering 

Order functions strictly by visibility:
1.  Constructor
2.  Receive / Fallback
3.  External
4.  Public
5.  Internal
6.  Private

##### 4. Naming & Syntax

### File Naming Conventions

| File Type | Pattern | Example |
|-----------|---------|---------|
| Domain Libraries | `Lib{Domain}{Feature}.sol` | `LibOrganizationAdmin.sol` |
| Storage Libraries | `Lib{Domain}{Feature}Storage.sol` | `LibOrganizationMembersStorage.sol` |
| Utility Libraries | `{Feature}Utils.sol` (no `Lib` prefix) | `TokenTransferUtils.sol`, `MerkleUtils.sol` |
| Implementation Contracts | `{Contract}Implementation.sol` | `OrganizationImplementation.sol` |
| Proxy Contracts | `{Contract}Proxy.sol` | `OrganizationProxy.sol` |
| Interfaces | `I{ContractName}.sol` | `IOrganization.sol` |

### Function Naming Conventions

* **Underscore Prefix Rules:**
    * `private` functions: **Always** use `_` prefix (e.g., `_computePolicyLeaf`, `_execute`).
    * `internal` library functions **used by other files**: **No** `_` prefix (e.g., `isMemberInOrg`, `setMembers`).
    * `internal` library functions **NOT used by other files**: Use `_` prefix (e.g., `_isAdminInTree`).
    * `external` / `public` functions: **Never** use `_` prefix.

* **Boolean Check Functions:**
    * Prefix with `is` or `are` (e.g., `isMemberInOrg`, `isGroupInOrg`).
    * Return `bool` type.

* **Validation Functions That Revert:**
    * Use `validate*OrRevert()` suffix (e.g., `validateAdminAuthAndConsumeNonceOrRevert`, `validateAllAdminsAreMembersOrRevert`).
    * These functions should revert on failure, not return `false`.

* **Getters and Setters:**
    * Getters: `get*` prefix (e.g., `getMembersRoot`, `getGroupsRoot`, `getAdminPermission`).
    * Setters: `set*` prefix (e.g., `setMembers`, `setGroups`, `setAdmins`).

### Variable Naming Conventions

* **Avoid Shadowing:**
    * Do NOT shadow state variables with function parameters.
    * Use distinct, descriptive names instead of trailing underscores.

* **Merkle Tree Roots:**
    * Use `{entity}Root` pattern (e.g., `membersRoot`, `groupsRoot`, `adminsRoot`, `policiesRoot`).

* **Merkle Proof Arrays:**
    * Use descriptive names indicating what the proof validates.
    * Pattern: `{subject}In{Tree}Proof` or `{subject}In{Tree}Proofs` for arrays.
    * Examples:
        * `adminInOrgAdminTreeProofs` - proves admin is in the admin tree
        * `initiatorInOrgMembersTreeProof` - proves initiator is in the members tree
        * `groupInOrgGroupsTreeProof` - proves group exists in the groups tree

### Type Naming Conventions

| Type | Case | Example |
|------|------|---------|
| Contracts | PascalCase | `OrganizationImplementation` |
| Libraries | PascalCase | `LibOrganizationAdmin` |
| Interfaces | PascalCase with `I` prefix | `IOrganization` |
| Structs | PascalCase | `AdminPermission`, `PolicyConfig` |
| Enums | PascalCase | `TransactionType`, `ApproverType` |
| Custom Errors | PascalCase | `AdminNotInTree`, `PolicyVerificationFailed` |
| Events | PascalCase (past tense for completed actions) | `MembersUpdated`, `TransactionExecuted` |
| Constants | CONSTANT_CASE | `STORAGE_SLOT` |
| Modifiers | mixedCase | `onlyGuardian`, `onlyOrganization` |

### Formatting

* **Indentation:**
    * Use **4 spaces** per indentation level (not tabs).

* **Blank Lines:**
    * Use **two blank lines** between top-level declarations (contracts, libraries, interfaces).
    * Use **one blank line** between function definitions within a contract.
    * Use blank lines sparingly inside functions to separate logical sections.

* **Line Length:**
    * Keep lines under **120 characters**.
    * Wrap long function arguments, event parameters, and modifiers onto new lines.
    * **When a line CAN be formatted to fit under 120 characters**, but `forge fmt` keeps reformatting it back to a long line, use `// forgefmt: skip-next-item` to preserve your formatting:
    ```solidity
    // Good - line is formatted to fit, forgefmt skip preserves it
    // forgefmt: disable-next-item
    revert IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance(
        msg.sender,
        pendingGuardianAddr
    );
    ```
    * **When a line genuinely CANNOT be shortened** (e.g., EIP-712 type hash strings that must stay on one line), use `// solhint-disable-next-line max-line-length` to suppress the linter warning:
    ```solidity
    // Good - string cannot be broken up, solhint comment suppresses warning
    bytes32 internal constant TYPEHASH = keccak256(
        // solhint-disable-next-line max-line-length
        "MyType(address field1,uint256 field2,bytes data,uint256 salt)"
    );
    ```

* **Whitespace:**
    * No trailing whitespace at end of lines.
    * One space after commas: `foo(a, b, c)` not `foo(a,b,c)`.
    * No space before commas: `foo(a, b)` not `foo(a , b)`.
    * No spaces inside parentheses: `foo(a)` not `foo( a )`.
    * No spaces inside brackets: `arr[i]` not `arr[ i ]`.
    * One space around operators: `a + b` not `a+b`.

* **Function Declarations:**
    * Opening brace on same line as function declaration.
    * Closing brace on its own line.
    * For long declarations, each parameter on its own line:
    ```solidity
    function validateAdminAuthAndConsumeNonceOrRevert(
        OperationType operationType,
        bytes memory operationData,
        uint256 salt,
        uint256 expirationTimestamp,
        bool isApproval,
        bytes memory signatures,
        SigningAdminsInOrgProofs memory signingAdminsInOrgProofs
    )
        internal
    {
        // function body
    }
    ```

* **Data Location:**
    * Use `calldata` instead of `memory` for read-only array/struct arguments in external functions to save gas.

## 5. Safety & Best Practices

* **NatSpec Documentation:**
    * All `public` and `external` functions must have NatSpec comments.
    * Required tags: `/// @notice` (what the function does) and `/// @param` (each parameter).
    * Include `/// @return` for functions that return values.
    * Include `/// @dev` for implementation details relevant to developers.
    * Example:
    ```solidity
    /// @notice Verifies that an address is a member of the organization
    /// @dev Uses merkle proof verification against the stored members root
    /// @param memberAddress The address to verify
    /// @param proof The merkle proof for the address
    /// @return True if the address is a verified member, false otherwise
    function isMemberInOrg(address memberAddress, bytes32[] memory proof) external view returns (bool) {
        // ...
    }
    ```

    * All `public` and `external` constants, storage variables, etc. must also have relevant NatSpec comments.

    * All `internal` and `private` constants, storage variables, functions, etc. must also have relevant NatSpec comments, however they should not use the `@notice` tag. They should use the `@dev` tag, plus other relevant tags depending on the usecase.
* **Error Handling:**
    * **Production Contracts (`src/`):** Use custom errors without revert strings (e.g., `error MyError();`) for gas efficiency.
    * **Scripts (`script/`):** Use revert strings (e.g., `require(condition, "Error message")` or `revert("Error message")`) for better debugging and readability during deployment.
* **Visibility:** Explicitly define visibility for all state variables and functions.
* **Checks-Effects-Interactions:** Follow the CEI pattern to prevent reentrancy:
    1. Perform all checks (require/revert conditions)
    2. Make all state changes
    3. Perform external calls last

## 6. Code Patterns

### Early Return Pattern (Avoid Arrow Anti-Pattern)

Prefer early returns over deeply nested if-else statements. This improves readability and reduces cognitive load.

**Bad (Arrow Anti-Pattern):**
```solidity
function processTransaction(address user, uint256 amount) external {
    if (user != address(0)) {
        if (amount > 0) {
            if (balances[user] >= amount) {
                // actual logic buried deep
                balances[user] -= amount;
            }
        }
    }
}
```

**Good (Early Return Pattern):**
```solidity
function processTransaction(address user, uint256 amount) external {
    if (user == address(0)) return;
    if (amount == 0) return;
    if (balances[user] < amount) return;
    
    // actual logic at minimal indentation
    balances[user] -= amount;
}
```

### Case Comments

Use `// Case:` comments to document what each conditional branch handles. This makes complex validation logic self-documenting.

```solidity
function isTransactionAllowedByPolicy(...) internal view returns (bool) {
    // Case: The policy does not exist in the organization
    if (!isPolicyInOrg(policyId, proofs.policy, proofs.policyProof)) return false;

    // Case: The source account is not allowed by the policy
    if (!isSourceAccountAllowedByPolicy(proofs.policy, sourceAccount, proofs.sourceAccountProof)) {
        return false;
    }

    // Case: The initiator is not authorized by the policy
    if (!isInitiatorAuthorized(proofs.policy, initiator, proofs.initiatorProofs)) {
        return false;
    }

    // Case: Policy matches only transactions that are token transfers
    if (txType == Policies.TransactionType.TokenTransfers) {
        // Case: The transaction is not a token transfer
        if (!TokenTransferUtils.isTransactionTokenTransfer(data, value)) return false;
        // ...
    }
}
```

### Control Structures

* **Braces:** Always use braces for control structures, even for single statements.
    ```solidity
    // Good
    if (condition) {
        doSomething();
    }
    
    // Bad
    if (condition)
        doSomething();
    ```

* **Opening Brace:** On same line as the control structure.
    ```solidity
    // Good
    if (condition) {
        // ...
    }
    
    // Bad
    if (condition)
    {
        // ...
    }
    ```

* **Else Placement:** `else` and `else if` on same line as closing brace.
    ```solidity
    if (condition1) {
        // ...
    } else if (condition2) {
        // ...
    } else {
        // ...
    }
    ```

### Section Headers

DO NOT use section comment headers to organize code into logical groups within a file.

Below is an example of what not to do:

```solidity
// ================================
// STRUCTS
// ================================

struct AdminPermission { ... }

// ================================
// EVENTS
// ================================

event AdminPermissionUpdated(...);

// ================================
// ERRORS
// ================================

error AdminNotInTree(address admin);

// ================================
// ADMIN TREE VERIFICATION
// ================================

function _isAdminInTree(...) private pure returns (bool) { ... }
```

## 7. Storage Library Pattern (ERC-7201)

For upgradeable contracts, use ERC-7201 namespaced storage pattern:

### Storage Library Structure

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Members Storage
 * @dev ERC-7201 namespaced storage for merkle-based members functionality.
 *      Members are stored in a merkle tree. Only the root is stored on-chain.
 * @author Den Technologies Inc
 */
library LibOrganizationMembersStorage {
    /**
     * @dev Storage layout for members functionality
     * @custom:storage-location erc7201:den.mls-wallet.organization.members
     * @param membersRoot Global merkle root containing ALL members
     */
    struct Layout {
        bytes32 membersRoot;
    }

    /// @dev Storage location for MembersStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.members")) - 1)) & ~bytes32(uint256(0xff))
    /// @dev Verify: `cast index-erc7201 "den.mls-wallet.organization.members"`
    bytes32 internal constant STORAGE_LOCATION = 0xb80799cfa22e7d42bb36b2b397b5d0bd56930d54ee4f345397b8ece603c6f300;

    /**
     * @dev Returns the storage layout at the namespaced slot
     * @return _layout The storage layout struct
     */
    function layout() internal pure returns (Layout storage _layout) {
        assembly {
            _layout.slot := STORAGE_LOCATION
        }
    }
}
```

### Key Requirements

* **Layout Struct:** Always name the storage struct `Layout`.
* **layout() Function:** Provide a `layout()` function that returns `Layout storage`. Use `STORAGE_LOCATION` directly in assembly (no intermediate variable).
* **Storage Location:** Use ERC-7201 pre-computed storage slots with namespace format `den.mls-wallet.<contract-type>.<feature>`.
* **Pre-computation:** Use `cast index-erc7201 "<namespace>"` to compute storage locations.
* **Constants:** Name storage location constants `STORAGE_LOCATION`.
* **NatSpec:** Include `@custom:storage-location erc7201:<namespace>` on the `Layout` struct.
* **Comments:** Document the ERC-7201 formula and verification command above the constant.
* **Accessing Storage:** Use `LibXxxStorage.layout().fieldName` pattern throughout the codebase.