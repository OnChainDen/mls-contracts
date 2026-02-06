<objective>
Completely overhaul the README.md to make it ready for smart contract auditors.

The current README contains significantly outdated information that no longer reflects the actual codebase. Your task is to:
1. Thoroughly analyze the actual smart contract codebase to understand the current architecture
2. Compare against the existing README to identify all discrepancies
3. Rewrite the README with accurate, auditor-focused documentation

This is critical because auditors will use this document to understand the system before reviewing code. Inaccurate documentation wastes auditor time and can lead to missed vulnerabilities.
</objective>

<context>
This is a smart contract project for organizational custody - a policy-based system where:
- Organizations contain Members, Groups, Admins, Policies, and Whitelists
- Accounts are smart accounts that hold assets and execute transactions through Organizations
- All transaction execution is validated through a policy engine

Key architectural facts to verify and document accurately:
- Organizations use UUPS proxy pattern (OrganizationProxy.sol → OrganizationImplementation.sol)
- Accounts use Beacon proxy pattern (AccountProxy.sol → AccountImplementation.sol, with Organization as beacon)
- Policy order does NOT matter (the README incorrectly says it does)
- Diamond proxies (ERC-2535) are NOT used (the README incorrectly says they are)

Read CLAUDE.md for authoritative project context.
</context>

<research>
Before writing, thoroughly explore the codebase to understand the actual architecture:

1. **Proxy Architecture**
   - Read `src/organization/OrganizationProxy.sol` and `src/organization/OrganizationImplementation.sol`
   - Read `src/account/AccountProxy.sol` and `src/account/AccountImplementation.sol`
   - Identify how upgrades work for each

2. **Policy System**
   - Search for policy matching logic to understand if order matters
   - Identify policy types, filters, and validation flow
   - Document how transactions are matched to policies

3. **Transaction Flow**
   - Trace how a transaction is executed from initiation to completion
   - Document signature validation, guardian checks, and policy validation

4. **Contract Structure**
   - List all contracts and their purposes
   - Document inheritance hierarchies
   - Identify libraries and their usage

5. **Discrepancy Detection**
   - Compare README claims about Diamond/ERC-2535 with actual code
   - Verify policy ordering behavior
   - Check all file paths mentioned in README still exist
   - Identify any features mentioned that no longer exist or work differently
</research>

<requirements>
The new README must include these sections optimized for auditors:

1. **Overview** (brief)
   - What this system is in 2-3 sentences
   - Link to any additional documentation

2. **Architecture**
   - Contract hierarchy diagram (ASCII or description)
   - Proxy patterns used (UUPS for Org, Beacon for Account)
   - Storage patterns
   - How Organizations and Accounts relate

3. **Core Contracts**
   - For each major contract: purpose, key functions, storage layout
   - OrganizationProxy / OrganizationImplementation
   - AccountProxy / AccountImplementation
   - Any factory contracts
   - Libraries

4. **Security Model**
   - Guardian protection mechanism
   - Signature validation (EOA and ERC-1271)
   - Replay protection (non-sequential nonces)
   - Access control patterns

5. **Transaction Execution Flow**
   - Step-by-step flow with function references
   - Policy matching and validation
   - Signature requirements

6. **Admin Operations**
   - What operations require admin approval
   - Signature validation for admin ops
   - EIP-712 typed data formats

7. **Policies**
   - Policy types (auto-approval vs manual)
   - Policy filters and matching
   - IMPORTANT: Clarify whether order matters (verify from code)

8. **Cross-chain Deployment**
   - CREATE2 usage
   - Initialization flow
   - Address determinism guarantees

9. **Known Limitations & Open Questions**
   - Clearly marked section
   - Gas optimization opportunities
   - Design decisions still under consideration
   - Keep existing valid questions, remove resolved ones

10. **File Structure**
    - Updated directory tree reflecting actual structure
    - Brief description of each directory's purpose
</requirements>

<implementation>
Writing guidelines:

1. **Be accurate** - Every claim must match the actual code. When in doubt, read the code.

2. **Be specific** - Include file paths, function names, and line references where helpful.

3. **Auditor perspective** - Focus on:
   - Trust assumptions and threat model
   - Entry points and access control
   - State-changing operations
   - External calls and reentrancy considerations
   - Upgrade mechanisms and their constraints

4. **Remove outdated content**:
   - All references to Diamond proxies / ERC-2535 / facets
   - Any claims about policy order mattering (verify first)
   - File paths that no longer exist
   - Features that were planned but not implemented

5. **Keep valuable content** - The existing README has good explanations of:
   - Core concepts (Members, Groups, Policies, etc.)
   - Security layer philosophy
   - Signature formats
   - These can be updated and kept if accurate

6. **Format for readability**:
   - Use clear headers and hierarchy
   - Include code snippets for signature formats and hashes
   - Use tables for structured data (like signature types)
   - Keep diagrams if they're still accurate, remove if not
</implementation>

<output>
Modify the existing file:
- `./README.md` - Complete overhaul with accurate, auditor-ready documentation

Do NOT create new files unless absolutely necessary for organization (e.g., a separate ARCHITECTURE.md if README gets too long).
</output>

<verification>
Before declaring complete, verify your work:

1. **Accuracy check**: For every technical claim in the README, you should be able to point to the specific code that confirms it

2. **Discrepancy list**: Document what you changed from the old README and why:
   - List each major correction made
   - Note any sections removed and why
   - Note any sections significantly rewritten

3. **File path validation**: Ensure all file paths mentioned in the README actually exist

4. **Completeness**: Ensure an auditor reading only this README would understand:
   - What contracts exist and their relationships
   - How to trace a transaction through the system
   - What the security model and trust assumptions are
   - What upgrade mechanisms exist and who controls them
</verification>

<success_criteria>
- All technical claims match actual codebase
- Diamond proxy / ERC-2535 references removed (unless they actually exist)
- Policy ordering behavior correctly documented
- All file paths are valid
- Architecture clearly explains UUPS (Org) + Beacon (Account) pattern
- Security model and trust assumptions are explicit
- Auditors can use this as a reliable reference
</success_criteria>
