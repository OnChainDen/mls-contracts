Right now, this project contains two main types of contracts:
1. The Organization contract
2. The Account contract

Accounts are smart accounts (smart contract wallets) that store assets.

Organizations are analogous to real-world organizations with Members, Groups, Admins, and Policies.

An Organization can have one or more Accounts. An Account can only have one Organization.

Both the Organization contract and Account contracts are both upgradable proxies.

There are two different types of "operations" in our system:
1. Admin Operations (a.k.a. Organization Operations): these include things like adding/removing Members, modifying policies, modifying admins, etc.
2. Account Transactions: sending transactions from Accounts 

In order to execute an Account Transaction from an Account, you need to execute an `executeTransaction` function on the Account countract. When the function runs, it does a bunch of CALLs to the Organization contract to read/write state and other stuff.

In order to execute an Admin/Organization Operation you need to call the relevant function on the Organization contract (e.g. `addMembers` to add a member).

Both Admin/Organization Operations and Account Transactions require signatures to be validated (kind of like a multisig) in order to be executed. In the case of Admin/Organization Operations, some number of signatures from the organization's members are required. In the case of Account transactions, the signatures required depend on the Policy that's being used to execute the transaction.

Currently, there are two different "nonces" that are "burned" after signature validation:
- a nonce that lives in the Organization contract for Admin/Organization Operations
- a nonce that lives in the Account contract for Accoutn Transactions

Now, we actually want to simplify our contracts.

Specifically, we want to make the following change.

Instead of needing to execute an Account Transaction by executing an `executeTransaction` function on the Account contract, and the Account contract then having to interact back-and-forth with the Organization contract to do things like checking that the transaction is coming from the guardian, getting a list of admins, etc., we want the Account Transactions to be executed by calling a new `executeAccountTransaction` on the Organization contract that will do all the validation that previously happened in the old `executeTransaction` function on the Account Transactoin ( likechecking that the transaction came from the guardian, that the attached policy for the transaction matches the actual transaction data being executed, that the signatures are valid according to the policy attached, and burning the nonce, etc.), and forward the transaction to the Account contract to execute the transaction via the Account's `executeTransaction` function. The Account's `executeTransaction` function should no longer do any of those old checks/validations that are moved into the Organization contract, but it should make sure that only its associated Organization contract can execute the `executeTransaction` function.

As part of this change, remove the old "nonce" system in the Account contract and extend the nonce system in the Organization contract to accomodate the Account Transactions too. Specifically, the organization contract uses something called the "admin nonce" and is computed by `computeAdminNonce` and is kept track of with the `usedAdminNonces` storage variable. As part of this change, rename "admin nonce" to just "nonce" (and all associated functions, variables, events, etc.), and use that same nonce and system for the Account Transaction too, similar to how that nonce is used for all the different types of organization/admin operations.

Note that the proxy contract for the Organization is `organization/OrganizationProxy.sol` and its implementation contract is `organization/OrganizationImplementation.sol`. The implementation contract calls libraries in `organization/libraries` which contain the actuall business logic and storage libraries.

Similarly, the proxy contract for the Account is `account/AccountProxy.sol` and its implementation contract is `account/AccountImplementation.sol`. The implementation contract calls libraries in `account/libraries` which contain the actual business logic and storage libraries.