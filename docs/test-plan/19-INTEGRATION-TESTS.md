# 19 — Integration Tests Plan

**Scope:** End-to-end flows across multiple contracts and modules, tested through a fully deployed Organization with Accounts.

---

## Test Infrastructure Required

Before writing integration tests, create a test helper base contract:

```
test/helpers/OrganizationTestBase.sol
```

This should provide:
- Pre-deployed Organization via Factory (with proxy)
- Pre-deployed Accounts (BeaconProxy)
- Pre-configured members, admins, groups
- Pre-set policies (Merkle tree generation)
- Guardian wallet setup
- Helper functions: generateAdminAuth(), generateInitiatorSig(), generateReviewSigs()
- EIP-712 hash computation helpers

---

## 1. Organization Lifecycle

**Priority: P0 — Critical**

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 1 | Deploy factory → deploy organization → initialize → deploy account → execute transaction | [I] | P0 |
| 2 | Full lifecycle: add member → add to group → add as admin → create policy → execute tx | [I] | P0 |
| 3 | Remove member cascading: remove admin first, then remove member | [I] | P0 |
| 4 | Create group → add members → use group in policy → execute tx through group member | [I] | P0 |
| 5 | Delete group → policy using that group fails | [I] | P0 |

---

## 2. Transaction Flows (End-to-End)

**Priority: P0 — Critical**

### 2.1 AutoApprove Transactions

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 6 | Native ETH transfer via AutoApprove policy: initiator signs → guardian submits → Account sends ETH | [I] | P0 |
| 7 | ERC-20 transfer via AutoApprove: full flow with token deployed | [I] | P0 |
| 8 | Contract interaction via AutoApprove: call function on external contract | [I] | P0 |

### 2.2 ManualApproval Transactions

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 9 | ManualApproval with Group approvers: initiator signs → reviewers approve → guardian submits | [I] | P0 |
| 10 | ManualApproval with Member approver: single member approval | [I] | P0 |
| 11 | ManualApproval with insufficient approvals — reverts | [I] | P0 |

### 2.3 Transaction Rejection

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 12 | AutoApprove rejection: authorized initiator signs rejection | [I] | P0 |
| 13 | ManualApproval rejection: reviewers sign rejection | [I] | P0 |
| 14 | Rejection consumes nonce — prevents subsequent approval | [I] | P0 |

### 2.4 Rate-Limited Transactions

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 15 | Multiple transactions within rate limit — all succeed | [I] | P0 |
| 16 | Transaction exceeding rate limit — reverts | [I] | P0 |
| 17 | Rate limit resets after time window — transaction succeeds again | [I] | P0 |

---

## 3. ERC-1271 Signature Flows (End-to-End)

**Priority: P0 — Critical**

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 18 | Policy-based signature: AutoApprove with guardian — Account returns magic value | [I] | P0 |
| 19 | Policy-based signature: ManualApproval — multiple reviewers + guardian | [I] | P0 |
| 20 | Recovery signature: recovery address signs — Account returns magic value | [I] | P0 |
| 21 | Invalid signature: wrong policy — Account returns invalid value | [I] | P0 |

---

## 4. Policy Constraint Flows (End-to-End)

**Priority: P0 — Critical**

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 22 | Destination whitelist: allowed destination passes, disallowed fails | [I] | P0 |
| 23 | Token filter: allowed token passes, wrong token fails | [I] | P0 |
| 24 | Amount threshold: below threshold passes, at/above fails | [I] | P0 |
| 25 | Function whitelist: allowed function passes, disallowed fails | [I] | P0 |
| 26 | Parameter constraints: valid params pass, invalid fail | [I] | P0 |
| 27 | Combined constraints: all must pass for transaction to succeed | [I] | P0 |

---

## 5. Admin Operations Flow

**Priority: P1 — High**

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 28 | Modify members with admin auth: guardian calls, admins sign | [I] | P1 |
| 29 | Modify admins: add new admin (must be member first) | [I] | P1 |
| 30 | Modify groups: create + update + delete in single call | [I] | P1 |
| 31 | Set policies: update Merkle root with admin auth | [I] | P1 |
| 32 | Reject admin operation: prevents same operation from being approved | [I] | P1 |

---

## 6. Guardian Update Flows

**Priority: P1 — High**

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 33 | Normal guardian update: initiate → time passes → finalize → new guardian accepts | [I] | P1 |
| 34 | Guardian recovery: recovery address initiates → time passes → finalize → new guardian accepts | [I] | P1 |
| 35 | Both flows in parallel: normal and recovery proceed independently | [I] | P1 |
| 36 | Cancel normal flow while recovery proceeds | [I] | P1 |

---

## 7. Recovery Flows

**Priority: P1 — High**

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 37 | Tx recovery: enable → execute recovery transaction → funds moved | [I] | P1 |
| 38 | Tx recovery: disable immediately stops recovery capability | [I] | P1 |
| 39 | Deferred guardian recovery init: guardian initiates → time passes → finalize → recovery address can now act | [I] | P1 |
| 40 | Deferred tx recovery init: guardian initiates → time passes → finalize → recovery address can enable | [I] | P1 |

---

## 8. Upgrade Flows

**Priority: P1 — High**

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 41 | Full organization upgrade: whitelist new impl → guardian + admins authorize → upgrade | [I] | P1 |
| 42 | Account implementation upgrade: set new impl → all accounts use new code | [I] | P1 |
| 43 | Storage persistence after upgrade: members, admins, groups, policies preserved | [I] | P1 |

---

## 9. Cross-Module Interaction Tests

**Priority: P0 — Critical**

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 44 | Remove member → policies referencing that member's initiator config no longer authorize them | [I] | P0 |
| 45 | Delete group → policies using that group for approval fail | [I] | P0 |
| 46 | Remove admin → admin auth threshold still met with remaining admins | [I] | P0 |
| 47 | Change voting threshold → subsequent operations require new threshold | [I] | P0 |
| 48 | Deploy multiple accounts → each can execute independently with same policy | [I] | P0 |
| 49 | Multiple organizations on same chain → no cross-org signature replay | [I] | P0 |

---

## 9.5 Modifier Access Control Isolation

**Priority: P0 — Critical**

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 49.1 | Guardian recovery address cannot call onlyGuardian-protected functions | [S] | P0 |
| 49.2 | Tx recovery address cannot call onlyGuardian-protected functions | [S] | P0 |
| 49.3 | Guardian cannot call onlyTxRecoveryAddress-protected functions | [S] | P0 |
| 49.4 | Guardian cannot call onlyGuardianRecoveryAddress-protected functions | [S] | P0 |
| 49.5 | Pending guardian (not yet accepted) cannot call onlyGuardian-protected functions | [S] | P0 |
| 49.6 | All six modifiers produce correct error message for wrong caller | [N] | P0 |

---

## 10. Multi-Account Scenarios

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 50 | Execute transactions from different accounts in same org | [I] | P1 |
| 51 | Same policy applies to multiple accounts (anySourceAccount) | [I] | P1 |
| 52 | Policy restricted to one account doesn't work for another | [I] | P1 |

---

## 11. Fuzz-Driven Integration Tests

| # | Test Case | Type | Priority |
|---|-----------|------|----------|
| 53 | Fuzz: Random valid transaction parameters through full AutoApprove flow — always executes | [F][I] | P0 |
| 54 | Fuzz: Random member/group configurations — policy enforcement always consistent | [F][I] | P0 |
| 55 | Fuzz: Random rate limit configurations — cumulative usage tracked correctly across multiple transactions | [F][I] | P0 |
| 56 | Fuzz: Random policy constraint combinations — all sub-validations enforced end-to-end | [F][I] | P0 |
| 57 | Fuzz: Random salt values for account deployment — all accounts independently executable | [F][I] | P1 |
| 58 | Fuzz: Random guardian update timestamps — timelock always enforced end-to-end | [F][I] | P1 |

---

## Summary

| Category | New Tests | Priority |
|----------|-----------|----------|
| Organization lifecycle | 5 | P0 |
| Transaction flows | 12 | P0 |
| ERC-1271 flows | 4 | P0 |
| Policy constraint flows | 6 | P0 |
| Admin operations | 5 | P1 |
| Guardian update flows | 4 | P1 |
| Recovery flows | 4 | P1 |
| Upgrade flows | 3 | P1 |
| Cross-module interactions | 6 | P0 |
| Modifier access control | 6 | P0 |
| Multi-account | 3 | P1 |
| Fuzz-driven integration | 6 | P0-P1 |
| **Total** | **64** | |
