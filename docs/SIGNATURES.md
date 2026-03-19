## Signatures

All operations in MLS Wallet require cryptographic signatures for authorization. This section covers signature encoding, typed data signing, and replay protection.


### Signature Encoding Format

MLS Wallet uses a **hybrid signature format** that supports both EOA (Externally Owned Account) and ERC-1271 smart contract signers. This format is used **everywhere signatures are validated**:

- **Organization Member signatures** — Initiator and reviewer signatures for Account Transactions and Account Signatures
- **Admin signatures** — For Admin Operations that require admin authorization
- **Guardian signatures** — For ERC-1271 Account Signature validation (from Guardian directly or enabled modules)
- **Recovery address signatures** — For Disaster Recovery ERC-1271 Account Signatures

#### EOA Signatures (65 bytes)

Standard ECDSA signatures with `v`, `r`, `s` components:

```
┌─────────┬──────────────┬──────────────┐
│ v (1B)  │   r (32B)    │   s (32B)    │
└─────────┴──────────────┴──────────────┘
```

- `v` must be `27` or `28`
- Signatures with `s` in the upper half of the curve order are rejected (malleability protection)

#### ERC-1271 Smart Contract Signatures (23 + N bytes)

When the signer is a smart contract (e.g., a Safe multisig), the signature format includes the signer address and an inner signature that will be validated by that contract:

```
┌─────────┬────────────────┬─────────────────┬────────────────┐
│ v=0 (1B)│ signer (20B)   │ sig length (2B) │ sig data (NB)  │
└─────────┴────────────────┴─────────────────┴────────────────┘
```

- When `v = 0`, the system recognizes this as a contract signature
- The `signer` address is extracted and called via `IERC1271.isValidSignature(hash, sigData)`
- The inner `sig data` is passed to the signer contract for validation

**Example use case:** An Organization Admin is a Safe multisig. When the Safe signs an admin operation, the signature is encoded with `v=0`, the Safe's address, and the Safe's signature data.

Files: `SignatureUtils.sol`

---

### Guardian Signatures for ERC-1271 Account Signatures

For ERC-1271 Account Signature validation, the Guardian must sign a message approving the signature request. The Organization accepts Guardian signatures from two sources:

1. **Guardian address directly** — For EOA Guardians or Safes with owner signatures
2. **Enabled modules on the Guardian Safe** — Allows the `SafeExecutorModule`'s Authorized Executor to sign

#### Why Accept Module Signatures?

The Guardian is typically a Safe multisig whose owners are cold wallets used only for module rotation. Requiring owner signatures for every ERC-1271 Account Signature would be impractical. Instead, the `SafeExecutorModule` implements ERC-1271, allowing its `AUTHORIZED_EXECUTOR` to sign on behalf of the Guardian.

#### Module Signature Format

When the Authorized Executor signs for the Guardian, the signature uses the [ERC-1271 Smart Contract Signature format](#erc-1271-smart-contract-signatures-23--n-bytes) with the **module address** as the signer (not the Safe address). Both the outer signature and the inner signature follow the universal [Signature Encoding Format](#signature-encoding-format).

- `signer` — The `SafeExecutorModule` contract address (not the Safe)
- `sig data` — Inner signature from `AUTHORIZED_EXECUTOR` (typically a 65-byte EOA signature)

#### Validation Flow

```
1. SignatureUtils extracts moduleAddress from outer signature (v=0)
2. SignatureUtils calls module.isValidSignature(hash, innerSignature)
3. Module uses SignatureUtils.tryRecoverSigner to recover signer from inner signature
4. Module checks if recovered signer == AUTHORIZED_EXECUTOR
5. Module returns magic value (0x1626ba7e) if valid
6. Organization verifies: Safe.isModuleEnabled(moduleAddress) == true
7. Signature is accepted
```

#### Benefits

| Benefit | Description |
|---------|-------------|
| **No cold wallet signatures** | Authorized Executor (hot wallet) signs instead of Safe owners |
| **Automatic rotation** | Rotating the module automatically rotates the signer |
| **No Organization changes** | Module rotation doesn't require updating Organization state |
| **Security preserved** | Safe owners control module lifecycle via multisig |

Files: `SafeExecutorModule.sol`, `LibOrganizationAccountSignature.sol`

---

### EIP-712 Typed Data Domain

All typed data signing in MLS Wallet uses EIP-712 with a shared domain separator:

| Field | Value |
|-------|-------|
| **name** | `MLSWalletOrganization` |
| **version** | `1` |
| **chainId** | `block.chainid` (current chain) |
| **verifyingContract** | Organization contract address |

```solidity
keccak256(abi.encode(
    EIP712_DOMAIN_TYPEHASH,
    keccak256("MLSWalletOrganization"),
    keccak256("1"),
    block.chainid,
    address(this)  // Organization address
))
```

This domain is used for all EIP-712 typed data hashes across the system.

Files: `LibOrganizationEIP712.sol`

---

### Signature Expiration (Optional)

All signed messages include an **`expirationTimestamp`** field that can optionally specify when the signature becomes invalid:

```solidity
AdminOperation(
    ...
    uint256 expirationTimestamp,  // Signature expires after this timestamp
    ...
)
```

- If `block.timestamp > expirationTimestamp`, the signature is rejected
- Signers choose the expiration based on their security requirements (e.g., 1 hour, 24 hours, 1 week)

**Making signatures indefinite:** To create a signature that never expires, set `expirationTimestamp` to `type(uint256).max`. Since this value is far in the future (~10^77 years), the expiration check will always pass.

**Use cases for expiration:**
- **Time-sensitive approvals** — Ensure a transaction approval can't be executed days after it was signed when circumstances may have changed
- **Limiting exposure** — If a signature is leaked but hasn't been used, it will eventually expire
- **Coordinated operations** — Ensure all parties sign within a reasonable timeframe

---

### Replay Protection & Non-Sequential Nonces

MLS Wallet uses a **salt-based, non-sequential nonce** system that provides replay protection while enabling flexible operation execution.

#### How Nonces Work

Each signed message includes a **`salt`** — a unique value chosen by the signer. The nonce is computed deterministically:

```solidity
nonce = keccak256(abi.encode(
    address(this),           // Organization address
    operationType,           // Type of operation
    keccak256(operationData), // Hashed operation data
    salt                     // User-provided salt
))
```

When an operation is executed or rejected, its nonce is **burned** (marked as used) and cannot be reused.

#### Why Sign a Salt?

The salt is critical for enabling **repeated operations**. Without the salt:

- If the nonce was derived only from the operation data, executing the same operation twice (e.g., transferring 100 USDC to the same address) would be impossible
- The second attempt would fail because the nonce would already be burned from the first execution

With the salt:

- Different salts produce different nonces, even for identical operation data
- Users can execute the same operation multiple times by using different salts
- This is not a replay attack — each execution requires fresh signatures with a new salt

#### Comparison to Traditional Multisigs

Most multisigs (like Safe) use **sequential nonces** (0, 1, 2, 3...). This creates **blocking**:

| System | Nonce Type | Behavior |
|--------|------------|----------|
| **Safe** | Sequential | Transaction #5 cannot execute until #0-4 complete |
| **MLS Wallet** | Salt-based | Any operation can execute independently |

MLS Wallet's approach allows parallel operations — approvals for different transactions don't block each other.

#### Cross-Chain Replay Protection

All EIP-712 typed data structs include `chainId` as a signed field:

```solidity
InitiateAccountTransaction(
    ...
    uint256 chainId  // ← Prevents cross-chain replay
)
```

A signature created for Chain A (e.g., Ethereum mainnet) cannot be replayed on Chain B (e.g., Arbitrum) because the `chainId` differs, producing a different message hash.

#### Check-Effects-Interactions (CEI) Pattern

Nonces are consumed **before** any external calls to prevent reentrancy attacks:

```solidity
// 1. CHECKS: Compute and validate nonce
uint256 nonce = LibOrganizationSignatures.computeNonce(...);

// 2. EFFECTS: Consume nonce BEFORE external call
LibOrganizationSignatures.validateAndConsumeNonceOrRevert(nonce);

// 3. INTERACTIONS: External call (e.g., execute transaction on Account)
IAccount(account).executeTransaction(...);
```

This ensures that even if the external call triggers a reentrant call back to the Organization, the nonce is already consumed and the replay attempt fails.

#### Full-Revert Semantics (Intentional Design)

> [!IMPORTANT]
> Admin Operations and Account Transactions use **full-revert semantics**. If the underlying operation or transaction reverts after signature validation and nonce consumption, the **entire EVM transaction reverts** — including the nonce consumption. This means on revert, the nonce is **not** burned/consumed. This is an intentional design decision.

While the CEI pattern above consumes the nonce before external calls within the *internal execution flow*, a revert in the external call (Step 3) causes the EVM to roll back all state changes in the transaction, including the nonce consumption in Step 2. This is standard EVM behavior for reverts, and MLS Wallet intentionally does **not** use `try/catch` or other mechanisms to isolate the nonce burn from the operation execution.

**Why this is intentional:**

1. **Atomic batched transactions** — The Guardian uses `BatchedTransaction` to execute multiple operations atomically. If one operation in a batch fails, the entire batch reverts, preserving nonce integrity for all operations. Partial-revert semantics (where nonces are burned even on failure) would make atomic batching impossible.

2. **Retryability** — Reverted operations can be retried with the same signatures when conditions change (e.g., sufficient token balance is restored), avoiding the cost of re-collecting organizational signatures.

**Replay risk mitigation:**

The risk of an attacker replaying signatures from a reverted operation is mitigated by:

| Protection | How It Mitigates Replay |
|------------|------------------------|
| **Guardian protection** | Only the Guardian (`msg.sender`) can submit operations. An attacker cannot replay signatures without control of the Guardian. |
| **Signature expiration** | All signed messages include `expirationTimestamp`. Signatures expire and become unusable after their deadline. |
| **Explicit rejection** | Admin Operations and Account Transactions can be explicitly rejected to burn the nonce, permanently invalidating the associated signatures. If a user decides a reverted operation should not be retried, they can reject it. |

A successful replay attack would require simultaneously: (1) control of the Guardian, (2) possession of un-expired signatures from a reverted operation that was not explicitly rejected, and (3) blockchain state changes that make the previously-reverted operation succeed. This combination is extremely unlikely.

Files: `LibOrganizationSignatures.sol`, `LibOrganizationSignaturesStorage.sol`

---

### ERC-1271 Account Signature Format

When validating ERC-1271 signatures on an Account (`Account.isValidSignature(hash, signature)`), the `signature` parameter uses a **type-prefixed format**:

```
┌───────────────┬────────────────────────────────┐
│ type (1 byte) │ signature data (variable)      │
└───────────────┴────────────────────────────────┘
```

#### Type `0x01`: Policy-Based Signatures (Normal Flow)

Standard Account Signatures that go through Guardian and policy validation:

```
┌────────┬──────────────────────────────────────────────────────────────┐
│ 0x01   │ ABI-encoded policy data and signatures                       │
└────────┴──────────────────────────────────────────────────────────────┘
```

The signature data is ABI-encoded with these fields:

```solidity
abi.encode(
    uint256 policyId,              // Policy authorizing this signature
    uint256 expirationTimestamp,   // When the signature request expires
    bytes initiatorSignature,      // Initiator's EIP-712 signature
    bytes reviewSignatures,        // Reviewer signatures (if manual approval policy)
    bytes guardianSignature,       // Guardian's approval signature
    ValidationProofs proofs        // Merkle proofs for policy and member validation
)
```

**Validation flow:**
1. Check expiration timestamp
2. Validate initiator signature against `InitiateSignatureValidation` hash
3. Validate Guardian signature against `ReviewSignatureValidation` hash
4. Verify policy exists and applies to the account
5. Verify initiator is authorized by policy
6. For `RequireManualApproval` policies: validate reviewer signatures meet threshold

#### Type `0x00`: Recovery Signatures (Disaster Recovery)

Disaster Recovery Account Signatures that bypass Guardian and policy checks:

```
┌────────┬──────────────────────────────────────────────────────────────┐
│ 0x00   │ Raw signature from transactionAndERC1271RecoveryAddress      │
└────────┴──────────────────────────────────────────────────────────────┘
```

The signature data is simply the raw signature (65 bytes for EOA, or 23+N bytes for ERC-1271) from the recovery address signing the message hash directly.

**Validation flow:**
1. Check `isRecoverySupportedForTransactionsAndERC1271 == true`
2. Check `isRecoveryEnabledForTransactionsAndERC1271 == true`
3. Validate signature is from `transactionAndERC1271RecoveryAddress`

**Key differences:**

| Aspect | Policy-Based (`0x01`) | Recovery (`0x00`) |
|--------|----------------------|-------------------|
| Guardian required | Yes | No |
| Policy checks | Full validation | Bypassed |
| Expiration | Required | None |
| Merkle proofs | Required | None |
| Use case | Normal operations | Emergency access |

Files: `LibOrganizationAccountSignature.sol`, `LibOrganizationTxRecovery.sol`

---

### Signed Message Types Reference

#### Admin Operations

```solidity
AdminOperation(
    uint8 operationType,
    bytes operationData,
    uint256 salt,
    uint256 expirationTimestamp,
    bool isApproval,
    uint256 chainId,
    address organization
)
```

#### Account Transactions

**Initiator signature:**
```solidity
InitiateAccountTransaction(
    address organization,
    address account,
    address to,
    uint256 value,
    bytes data,
    uint256 salt,
    uint256 expirationTimestamp,
    uint256 policyId,
    bool isApproval,
    uint256 chainId
)
```

**Reviewer signature:**
```solidity
ReviewAccountTransaction(
    address organization,
    address account,
    address to,
    uint256 value,
    bytes data,
    uint256 salt,
    uint256 expirationTimestamp,
    uint256 policyId,
    bool isApproval,
    uint256 chainId,
    bytes initiatorSignature  // Binds approval to specific initiation
)
```

#### Account Signatures (ERC-1271)

**Initiator signature:**
```solidity
InitiateSignatureValidation(
    address organization,
    address account,
    bytes32 hash,
    uint256 policyId,
    uint256 expirationTimestamp,
    uint256 chainId
)
```

**Reviewer/Guardian signature:**
```solidity
ReviewSignatureValidation(
    address organization,
    address account,
    bytes32 hash,
    uint256 policyId,
    uint256 expirationTimestamp,
    uint256 chainId,
    bytes initiatorSignature  // Binds approval to specific initiation
)
```

---

### Key Files

| File | Purpose |
|------|---------|
| `SignatureUtils.sol` | Hybrid EOA + ERC-1271 signature validation |
| `LibOrganizationSignatures.sol` | Nonce computation and consumption |
| `LibOrganizationEIP712.sol` | EIP-712 domain separator and type hashes |
| `LibOrganizationAdmin.sol` | Admin signature validation |
| `LibOrganizationAccountTransaction.sol` | Transaction signature validation |
| `LibOrganizationAccountSignature.sol` | ERC-1271 signature validation and encoding |
| `LibOrganizationTxRecovery.sol` | Recovery signature validation |

---

