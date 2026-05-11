## Guardian Protection

The Guardian is a critical security component in MLS Wallet. This section explains what the Guardian is, how it's protected, and how it can be updated.

### What is the Guardian?

The Guardian is an **offchain service** operated by Den that:
1. **Validates transactions independently** — Before submitting any transaction to the Organization contract, the Guardian validates it against policies, member/group membership, and signature requirements
2. **Acts as a redundant security layer** — Even if vulnerabilities exist in the client or smart contracts, the Guardian provides an independent check
3. **Prevents exploitation** — An attacker would need to compromise the Guardian in addition to other layers to execute unauthorized transactions

The Guardian address is stored on each Organization contract and is the **only address** allowed to call most external functions.

---

### The `onlyGuardian` Modifier

Most external functions on the Organization contract are protected by the `onlyGuardian` modifier, which delegates to `LibOrganizationGuardian.enforceOnlyGuardian()`:

```solidity
// OrganizationModifiers.sol
modifier onlyGuardian() {
    LibOrganizationGuardian.enforceOnlyGuardian();
    _;
}

// LibOrganizationGuardian.sol
function enforceOnlyGuardian() internal view {
    LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();
    if (msg.sender != guardianLayout.guardian) {
        revert IOrganizationGuardian.UnauthorizedGuardian(msg.sender, guardianLayout.guardian);
    }
}
```

#### Guardian-Protected Functions

The following functions require `msg.sender` to be the Guardian:

| Category | Functions |
|----------|-----------|
| **Admin Management** | `modifyAdmins()`, `rejectAdminOperation()` |
| **State Management** | `modifyMembers()`, `modifyGroups()`, `setPolicies()` |
| **Guardian Updates (Normal)** | `initiateGuardianUpdate()`, `finalizeGuardianUpdate()`, `cancelGuardianUpdate()` |
| **Account Operations** | `deployAccount()`, `setAccountImplementation()` |
| **Account Transactions** | `executeAccountTransaction()`, `rejectAccountTransaction()` |
| **Upgrades** | `upgradeToAndCallWithAuthorization()` |
| **Deferred Recovery Init** | `initiateInitializeGuardianRecovery()`, `finalizeInitializeGuardianRecovery()`, `cancelInitializeGuardianRecovery()`, `initiateInitializeTransactionAndERC1271Recovery()`, `finalizeInitializeTransactionAndERC1271Recovery()`, `cancelInitializeTransactionAndERC1271Recovery()` |

In the case of ERC-1271 Account Signatures, any `msg.sender` can call `isValidSignature` on the Account contract, but a signed message from the Guardian must be provided as part of the packed `signature` function parameters. 

#### Exceptions (Functions Protected by Other Modifiers)

Some functions use different access control modifiers for specific security reasons:

| Modifier | Functions | Purpose |
|----------|-----------|---------|
| `onlyDeployer` | `initialize()` | Only the factory can initialize a new Organization |
| `onlyPendingGuardian` | `acceptGuardian()` | Only the new Guardian can accept the role (prevents front-running) |
| `onlyRecoveryPendingGuardian` | `acceptGuardianRecovery()` | Only the new Guardian can accept via recovery flow |
| `onlyGuardianRecoveryAddress` | `initiateRecoveryGuardianUpdate()`, `finalizeRecoveryGuardianUpdate()`, `cancelRecoveryGuardianUpdate()` | Guardian recovery bypasses the compromised Guardian |
| `onlyTxRecoveryAddress` | `initiateEnableTransactionAndERC1271Recovery()`, `finalizeEnableTransactionAndERC1271Recovery()`, `cancelEnableTransactionAndERC1271Recovery()`, `disableTransactionAndERC1271Recovery()`, `executeRecoveryAccountTransaction()` | Transaction recovery bypasses the Guardian when enabled |

Files: `OrganizationModifiers.sol`, `LibOrganizationGuardian.sol`

---

### Guardian Safe Architecture

The Guardian address is not a simple EOA—it is a **Safe multisig** with a custom module that enables automated operations while maintaining security.

#### Why a Safe Multisig with a custom module?

Using a Safe multisig with a custom module as the Guardian provides several benefits:
- **Key rotation** — If the automated signing key is compromised, Safe owners can remove the compromised module
- **Multi-party control** — Multiple signers control the underlying Safe, preventing single points of failure
- **Auditability** — All transactions are logged and can be traced

#### The SafeExecutorModule

The Guardian Safe has a custom module (`SafeExecutorModule`) installed that allows a single authorized address (the "Authorized Executor") to execute transactions on behalf of the Safe without having full control over the Safe itself.

> [!NOTE]
> At the module level, the Authorized Executor may be **either an EOA or a contract**. The constructor only rejects the zero address. It does not enforce that the executor has no code. ERC-1271 signature validation uses `SignatureUtils.tryRecoverSigner`, which accepts both EOA and ERC-1271 inner signatures. In Den's Guardian deployment the Authorized Executor is an EOA (the "Guardian Executor EOA"), but the contract itself supports either signer type. See [`DEPLOYMENT.md`](./DEPLOYMENT.md) for the Den-specific deployment path.

**Key restrictions enforced by SafeExecutorModule:**

| Restriction | Purpose |
|-------------|---------|
| **No calls to the Safe itself** | Prevents the Authorized Executor from modifying Safe owners, modules, or threshold |
| **Only CALL operations** | DelegateCall is only allowed to `BatchedTransaction` (see below) |
| **Immutable Authorized Executor** | To rotate the executor, Safe owners must deploy a new module and swap it via multisig |
| **No ETH value transfers** | Value is hardcoded to 0, preventing ETH draining. This is an extra precaution and gas optimization, as no tokens are expected to be held by the Safe anyway |

**Security benefit:** If the Authorized Executor's signing credentials are compromised (e.g., the Guardian Executor EOA's private key, or a contract Authorized Executor's signer), the attacker:
- ✅ Can execute transactions as the Guardian (call Organization functions)
- ✅ Can sign ERC-1271 Account Signature validations
- ❌ Cannot rotate the Safe's owners
- ❌ Cannot remove themselves from the Safe
- ❌ Cannot add malicious modules
- ❌ Cannot drain ETH from the Safe (although no tokens should be held by the Safe anyway)

This design allows Den to run an automated EOA in cloud infrastructure while limiting the impact if that key is compromised.

#### ERC-1271 Signature Validation

The `SafeExecutorModule` implements ERC-1271 (`isValidSignature`) to enable the Authorized Executor to sign messages on behalf of the Guardian Safe. This is critical for ERC-1271 Account Signature validation, where a Guardian signature must be provided.

**Why is this needed?**

For ERC-1271 Account Signatures, the Guardian must sign a message approving the signature request. Without this feature:
- The Safe's owners (cold wallets) would need to sign every Account Signature request
- This defeats the purpose of having an automated Guardian service

**How it works:**

1. When `SafeExecutorModule.isValidSignature(hash, signature)` is called:
   - The module uses `SignatureUtils.tryRecoverSigner` to recover the signer
   - This supports the universal signature encoding format (both EOA and ERC-1271)
   - If the recovered signer equals `AUTHORIZED_EXECUTOR`, it returns the ERC-1271 magic value (`0x1626ba7e`)
   - Otherwise, it returns the invalid value (`0xffffffff`)

2. The Organization contract accepts Guardian signatures from:
   - The Guardian address directly (for EOA Guardians or Safes with owner signatures)
   - Any enabled module on the Guardian Safe (validated via `Safe.isModuleEnabled()`)

**Signature format for module-based Guardian signatures:**

When the Authorized Executor signs for the Guardian, the signature uses the universal [Signature Encoding Format](./SIGNATURES.md#signature-encoding-format), specifically the ERC-1271 contract signature format with the module address as the signer and the Authorized Executor's signature as the inner signature. In Den's deployment the inner signature is a 65-byte EOA signature, but the module accepts ERC-1271 inner signatures as well (via `SignatureUtils.tryRecoverSigner`) so a contract Authorized Executor would sign via ERC-1271 instead.

**Module rotation:**

When the Authorized Executor needs to be rotated:
1. Safe owners deploy a new `SafeExecutorModule` with a new `AUTHORIZED_EXECUTOR`
2. Safe owners enable the new module and disable the old one via multisig transaction
3. New signatures automatically use the new module address
4. The Organization validates the new module is enabled—no Organization state changes required

Files: `SafeExecutorModule.sol`, `ISafeExecutorModule.sol`

---

### BatchedTransaction Contract

The Guardian often needs to execute multiple transactions atomically (e.g., submitting many account transactions in one batch). We created a custom `BatchedTransaction` contract to batch transactions while providing some safety guarantees. The `BatchedTransaction` is only intended to be used by the Guardian Safe.

#### Why a Custom Contract?

`BatchedTransaction` provides security guarantees specific to MLS Wallet's Guardian.

| Security Feature | Description |
|------------------|-------------|
| **`address(this)` validation** | When delegatecalled from the Safe, `address(this)` is the Safe address—sub-transactions targeting `address(this)` are blocked |
| **CALL-only** | Only `call` operations are supported (no `delegatecall` within batches) |
| **Atomic execution** | If any sub-transaction fails, the entire batch reverts — including all nonce consumption and state changes from other operations in the batch |
| **No value field in encoding** | ETH value is hardcoded to 0 for all sub-transactions, preventing ETH transfers. Note that no tokens should be held by the Guardian Safe anyway, but this serves as an extra precaution and gas optimization |

> [!NOTE]
> Atomic batch execution is made possible by the **full-revert semantics** of Admin Operations and Account Transactions. Because nonces are not consumed on revert (the entire EVM transaction rolls back), a single failed operation in a batch causes all operations to revert cleanly — no nonces are burned and no partial state changes are applied. This is an intentional design decision. See [Full-Revert Semantics](../README.md#full-revert-semantics-intentional-design) in the README and [Full-Revert Semantics](./SIGNATURES.md#full-revert-semantics-intentional-design) in SIGNATURES.md for the full design rationale and replay risk analysis.

#### Why Block `address(this)`?

When `BatchedTransaction.execute()` is delegatecalled from the Safe:
- `address(this)` equals the Safe's address
- If a sub-transaction could target `address(this)`, it could call Safe functions like `addOwnerWithThreshold()` or `enableModule()`
- This would allow a compromised Authorized Executor to take over the Safe

By blocking `address(this)`, we ensure that even via batched transactions, the Authorized Executor cannot modify the Safe itself.

#### Transaction Encoding Format

Transactions are encoded in a packed format (no padding) for gas efficiency:

```
┌─────────────────┬──────────────────┬─────────────────┐
│  to (20 bytes)  │ dataLength (8B)  │  data (N bytes) │
└─────────────────┴──────────────────┴─────────────────┘
          ↑               ↑                  ↑
    Target address   uint64 length    Calldata bytes
```
Each transaction is 28 + N bytes, where N is the length of `data`

**Repeating structure:** Multiple transactions are concatenated:
```
[to0][dataLength0][data0][to1][dataLength1][data1][to2][dataLength2][data2]...
```


Files: `BatchedTransaction.sol`, `IBatchedTransaction.sol`

---

### Updating the Guardian (Normal Flow)

In the event that an organization wants to self-host the Guardian or use a different 3rd party operated Guardian, the Guardian can be changed to a new address.

An Organization's Guardian can be updated through a **timelocked 3-step process** that requires both Guardian and Admin authorization.

#### Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: INITIATE                                                │
│ Caller: Current Guardian (msg.sender must be Guardian)          │
│ Authorization: Admin signatures required                        │
│ Function: initiateGuardianUpdate(newGuardian, adminAuthParams)  │
│ Effect: Sets pendingGuardian, starts timelock                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Wait for timelock to expire
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: FINALIZE                                                │
│ Caller: Current Guardian (msg.sender must be Guardian)          │
│ Authorization: Admin signatures required (new set)              │
│ Function: finalizeGuardianUpdate(adminAuthParams)               │
│ Effect: Marks update ready for acceptance                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: ACCEPT                                                  │
│ Caller: The new Guardian itself (onlyPendingGuardian)           │
│ Function: acceptGuardian()                                      │
│ Effect: Updates Guardian address, clears pending state          │
└─────────────────────────────────────────────────────────────────┘
```

#### Security Rationale for Each Step

| Step | Requirement | Security Rationale |
|------|-------------|-------------------|
| **Initiate** | Guardian + Admin signatures | Prevents unilateral changes; both parties must agree |
| **Timelock** | Wait period between initiate and finalize | Gives time to detect malicious updates and cancel them |
| **Finalize** | Guardian + Admin signatures (new set) | Confirms intent after reflection period; prevents replay of old signatures |
| **Accept** | New Guardian must call | Proves new Guardian is operational and has correct keys; prevents setting Guardian to a non-functional address |

**Cancellation:** At any point before acceptance, the Guardian can call `cancelGuardianUpdate()` (with Admin signatures) to abort the process.

Files: `OrganizationGuardianBase.sol`, `LibOrganizationGuardian.sol`


### Updating the Guardian via Disaster Recovery

If the Guardian is compromised or unavailable, the Guardian can also be updated through the **Disaster Recovery** mechanism. This flow uses a separate privileged address (`guardianRecoveryAddress`) and follows a similar timelocked process, but does **not** require the current Guardian to participate.

For details on the disaster recovery flow, see [Disaster Recovery](./DISASTER_RECOVERY.md#guardian-recovery).

Files: `OrganizationGuardianRecoveryBase.sol`, `LibOrganizationGuardianRecovery.sol`

---

### Concurrent Guardian Update Flows

> [!IMPORTANT]
> The normal guardian update flow and the recovery guardian update flow are **intentionally independent** and can run concurrently. Each flow maintains its own pending state in separate storage, and neither flow checks or invalidates the other's state.

#### How the Two Flows Interact

The normal flow stores pending state in `LibOrganizationGuardianStorage` (`pendingGuardian`, `pendingGuardianUpdateTimestamp`, `isGuardianUpdateReadyForAcceptance`). The recovery flow stores pending state in `LibOrganizationRecoveryStorage.guardianRecovery` (`pendingGuardian`, `pendingGuardianTimestamp`, `isUpdateReadyForAcceptance`). Both flows ultimately write to the same live guardian slot at `LibOrganizationGuardianStorage.layout().guardian`.

This means:
- Both flows can have pending or ready-for-acceptance updates active at the same time
- If both flows reach the acceptance stage, the **last to accept** determines the final guardian (last-write-wins)
- Accepting via one flow does **not** clear the other flow's pending state

#### Why This Is Intentional

Coupling the two flows would undermine the core purpose of the recovery mechanism:

1. **Recovery must work when the Guardian is compromised.** The recovery flow is designed to replace the Guardian *without* requiring the current Guardian's participation. If `initiateRecoveryGuardianUpdate()` were blocked whenever a normal-flow update was pending, a compromised Guardian could initiate a bogus normal-flow update and then refuse to cancel or finalize it — effectively vetoing recovery and defeating its purpose.

2. **The normal flow must not be blocked by recovery.** Similarly, if `initiateGuardianUpdate()` were blocked whenever a recovery-flow update was pending, a compromised or misbehaving `guardianRecoveryAddress` could initiate a recovery update and block all normal guardian rotations.

3. **Both flows are already independently secured.**
   - The normal flow requires the current Guardian (`onlyGuardian`) + admin threshold signatures at every step, plus a timelock.
   - The recovery flow requires the `guardianRecoveryAddress` (`onlyGuardianRecoveryAddress`) at every step, plus a separate timelock.
   - The final acceptance step in both flows requires the *new* guardian itself to call `acceptGuardian()` or `acceptGuardianRecovery()`, proving it is operational.

4. **Last-write-wins is the correct outcome.** If both flows complete acceptance, the most recently accepted guardian is the one that has demonstrated it is operational and was authorized through a complete timelocked flow. Any previously set guardian was overwritten by a fully authorized process.

#### Operational Guidance

In practice, concurrent flows are expected only during adversarial scenarios (e.g., recovery initiated because the Guardian is believed to be compromised, while the Guardian simultaneously attempts a normal rotation). The Den Guardian service monitors for concurrent flows and alerts operators.

If concurrent flows are detected during normal (non-adversarial) operations, admins should cancel the unintended flow:
- To cancel a normal-flow update: the current Guardian calls `cancelGuardianUpdate()` with admin authorization
- To cancel a recovery-flow update: the `guardianRecoveryAddress` calls `cancelRecoveryGuardianUpdate()`

Files: `LibOrganizationGuardian.sol`, `LibOrganizationGuardianRecovery.sol`, `LibOrganizationGuardianStorage.sol`, `LibOrganizationRecoveryStorage.sol`

---

