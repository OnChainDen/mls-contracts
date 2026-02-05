## Disaster Recovery

MLS Wallet implements two independent recovery mechanisms to handle scenarios where the Guardian is compromised or unavailable.

### Recovery Architecture

| Mechanism | Purpose | Timelocked | Recovery Address |
|-----------|---------|------------|------------------|
| **Guardian Recovery** | Replace compromised/unavailable Guardian | Yes | `guardianRecoveryAddress` |
| **Transaction Recovery** | Execute transactions without Guardian | Yes (to enable) | `transactionAndERC1271RecoveryAddress` |

Both mechanisms use separate privileged addresses that can be configured either at Organization initialization OR after deployment (with admin authorization).

---

### Configuration Options

Recovery mechanisms can be set up in two ways:

**Option A: At Organization Initialization**
- Pass non-zero recovery addresses and timelock durations in `InitializationParams`
- Guardian recovery and/or transaction recovery are immediately configured
- Zero address means the mechanism is deferred for later setup

**Option B: Post-Deployment Initialization**
- Call `initializeGuardianRecovery()` or `initializeTransactionAndERC1271Recovery()` after deployment
- Requires Guardian to submit the transaction (`onlyGuardian` modifier)
- Requires admin signature authorization (same as other admin operations)
- Can only be called once per mechanism - reverts if already configured

| Function | Authorization | Can Only Be Called Once |
|----------|---------------|-------------------------|
| `initializeGuardianRecovery(recoveryAddress, timelockDurationSeconds, authParams)` | Guardian + Admin threshold signatures | Yes |
| `initializeTransactionAndERC1271Recovery(recoveryAddress, timelockDurationSeconds, authParams)` | Guardian + Admin threshold signatures | Yes |

---

### Guardian Recovery

Allows replacing the Guardian through a time-locked process.

**3-Step Flow:**

```
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: INITIATE                                                │
│ Caller: guardianRecoveryAddress                                 │
│ Function: initiateRecoveryGuardianUpdate(newGuardian)           │
│ Effect: Sets pendingGuardian, starts timelock                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Wait for timelock to expire
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: FINALIZE                                                │
│ Caller: guardianRecoveryAddress                                 │
│ Function: finalizeRecoveryGuardianUpdate()                      │
│ Effect: Marks update ready for acceptance                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: ACCEPT                                                  │
│ Caller: The new Guardian itself                                 │
│ Function: acceptGuardianRecovery()                              │
│ Effect: Updates Guardian address, clears pending state          │
└─────────────────────────────────────────────────────────────────┘
```

**Cancellation:** `cancelRecoveryGuardianUpdate()` - Can abort before finalization

Files: `OrganizationGuardianRecoveryBase.sol`, `LibOrganizationGuardianRecovery.sol`

---

### Transaction Recovery

Allows executing transactions and validating ERC-1271 signatures without the Guardian.

**Enable Flow (2-Step with Timelock):**

```
1. initiateEnableTransactionAndERC1271Recovery()
   └── Caller: transactionAndERC1271RecoveryAddress
   └── Effect: Starts timelock

2. finalizeEnableTransactionAndERC1271Recovery()
   └── Caller: transactionAndERC1271RecoveryAddress
   └── Effect: Enables recovery after timelock expires
```

**Usage (when enabled):**

- `executeRecoveryAccountTransaction(account, to, value, data)` - Execute without Guardian/policy checks
- ERC-1271 signatures with type `0x00` prefix - Bypass Guardian/policy validation

**Disable:** `disableTransactionAndERC1271Recovery()` - Immediate (no timelock required)

Files: `OrganizationTxRecoveryBase.sol`, `LibOrganizationTxRecovery.sol`

---

### Recovery vs Normal Operations

| Aspect | Normal Flow | Recovery Flow |
|--------|-------------|---------------|
| Guardian required | Yes | No |
| Policy validation | Yes | No (bypassed) |
| Nonce/policyId | Computed | Set to 0 |
| Authorization | Guardian + policy | Recovery address only |
| Timelock | None | Required to enable |

---

### Recovery Signatures (ERC-1271)

When transaction recovery is enabled, ERC-1271 signature validation supports a recovery path that bypasses Guardian and policy checks.

**Signature Format:**

```
┌───────────────┬─────────────────────────────┐
│ 0x00 (1 byte) │ recovery address signature  │
└───────────────┴─────────────────────────────┘
```

**Validation:**
1. Check transaction recovery is configured (`transactionAndERC1271RecoveryAddress != address(0)`)
2. Check `isRecoveryEnabledForTransactionsAndERC1271 == true`
3. Verify signature is from `transactionAndERC1271RecoveryAddress`

**Compared to Policy-Based (0x01):**

| Aspect | Recovery (0x00) | Policy-Based (0x01) |
|--------|-----------------|---------------------|
| Guardian required | No | Yes |
| Policy checks | Bypassed | Enforced |
| Expiration | None | Required |
| Use case | Emergency access | Normal operations |

File: `LibOrganizationAccountSignature.sol:79`

---

### Recovery Scenarios

**Scenario A: Guardian Compromised**
1. Guardian Recovery Address initiates new Guardian
2. Wait for timelock
3. Finalize and have new Guardian accept
4. Normal operations resume with new Guardian

**Scenario B: Guardian Unavailable (Lost Keys)**
1. Initiate Guardian recovery (same as A)
2. While waiting, enable Transaction Recovery if urgent transactions needed
3. Execute critical transactions via recovery
4. Complete Guardian recovery
5. Disable Transaction Recovery

**Scenario C: Emergency Disable**
- Call `disableTransactionAndERC1271Recovery()` immediately (no timelock)
- Restores normal Guardian-mediated operations

**Scenario D: Deferred Recovery Setup**
1. Deploy Organization without recovery addresses configured (pass zero addresses)
2. Later, decide to add Guardian Recovery and/or Transaction Recovery
3. Have admins sign authorization for the setup
4. Guardian calls `initializeGuardianRecovery()` or `initializeTransactionAndERC1271Recovery()`
5. Recovery mechanisms are now available

---

