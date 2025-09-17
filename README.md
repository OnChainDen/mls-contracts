# Onchain Custody Smart Contracts

## Overview: What is Onchain Custody?
Onchain Custody is a new category of cryptocurrency custody. It is non-custodial and provides all the benefits of self-custody while being significantly more secure than all other forms of custody (traditional custody, self-custody, and MPC).

The heart of Onchain Custody is the **policy engine**, which allows users to specify rules (a.k.a. "policies") that dictate:
1. what transactions can be executed
2. who can execute them

 For example, an organization might set a policy that allows its finance team to transfer up to $100,000 in USDC per month, so long as 2 out of 3 members of the finance team approve the transaction.

Policies aren't limited to just governing simple token transfers, however. They can also be used to set rules for complex smart contract interactions and DeFi activities.

What makes Onchain Custody significantly more secure than all other existing forms of custody is that it uses **multiple redundant layers of security**. Each of the layers operates independantly and all layers need to be compromised simultaneously in order to steal funds. In contrast, other forms of custody, such as traditional custody, self-custody, and MPC, only need a single layer of security to be compromised.

In Onchain Custody, the three redundant layers of security are:
1. The dedicated mobile wallet
2. The offchain "Guardian" service 
3. The onchain smart contracts

![Onchain Custody Security Layers Diagram](docs/images/OnchainCustodySecurityLayersDiagram.svg)



In order to execute a transaction, all three layers independently run the policy engine to verify that the transaction is valid.

The order of operations is the following:
1. **The dedicated mobile wallet runs the policy engine locally.** 

    It will not allows users to approve a transaction if its policy engine fails to validate the transaction.
2. **The offchain Guardian service runs the policy engine in a secure centralize server.**
    
    It will not approve the transaction if its policy engine fails to validate the transaction.
3. **The smart contracts run the policy engine onchain.** 

    It will not allow the transaction to execute if its policy engines fails to validate the transaction. It will also prevent the transaction from executing if any approvals are missing from the account owners or the offchain Guardian service.



## Smart contracts
### Overview
There are two main abstrations represented as smart contracts in Onchain Custody:
1. Organizations (`src/organization/OnchainCustodyOrganizationDiamond.sol`)
2. Accounts (`src/account/OnchainCustodyAccountDiamond.sol`)

Each real world organization that uses Onchain Custody is represented onchain by a dedicated Organization contract. Each organization may have one or more Accounts (i.e. "smart accounts" or "smart contract wallets"), which are smart contracts that holds funds on behalf of the organization. 

The contracts representing organizations and accounts are both ERC-2535 Diamond proxies, and all functionalities are implemented in facets.

### Organizations
#### Files
```
src/organization
├── facets
│   ├── OrganizationAccountFactoryFacet.sol
│   ├── OrganizationAdminFacet.sol
│   ├── OrganizationGroupsFacet.sol
│   ├── OrganizationGuardianFacet.sol
│   ├── OrganizationInitializationFacet.sol
│   ├── OrganizationMembersFacet.sol
│   ├── OrganizationPolicyFacet.sol
│   └── OrganizationWhitelistFacet.sol
├── interfaces
│   ├── IOrganizationGroupsFacet.sol
│   ├── IOrganizationGuardianFacet.sol
│   └── IOrganizationMembersFacet.sol
├── OnchainCustodyOrganizationDiamond.sol
├── OnchainCustodyOrganizationFactory.sol
├── OrganizationInit.sol
└── OrganizationStorage.sol
```