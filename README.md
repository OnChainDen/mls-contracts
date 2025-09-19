# Onchain Custody Smart Contracts
This repository contains the smart contracts for Onchain Custody.

> [!WARNING]
> The contracts in this repository are a "rough draft" whose only purpose is to reason through how Onchain Custody might be implemented.
>
> **This code is not production-ready, or even audit-ready, and should not be trusted.** It is not gas-optimized, tested, or fully functional.

## Onchain Custody Overview
Onchain Custody is a new category of cryptocurrency custody. It is non-custodial and provides all the benefits of self-custody while being significantly more secure than all other forms of custody (traditional custody, self-custody, and MPC).


### Policy Engine
The heart of Onchain Custody is the **policy engine**. The policy engine allows users to specify rules (a.k.a. "policies") that dictate:
1. what transactions can be executed
2. who can execute them

 For example, an organization might set a policy that allows its finance team to transfer up to $100,000 in USDC per month, so long as 2 out of 3 members of the finance team approve the transaction.

Policies aren't limited to just simple token transfers, however. They can also be used to set rules for complex smart contract interactions and DeFi activities.


### Multiple Redundant Layers of Security
What makes Onchain Custody significantly more secure than all other existing forms of custody is that it uses **multiple redundant layers of security**.

Each of the layers operates independantly and all layers need to be compromised simultaneously in order for funds to be stolen. In contrast, other forms of custody, such as traditional custody, self-custody, and MPC, only need a single layer of security to be compromised.

In Onchain Custody, the three redundant layers of security are:
1. The dedicated mobile wallet
2. The offchain "Guardian" service 
3. The onchain smart contracts

![Onchain Custody Security Layers Diagram](docs/images/OnchainCustodySecurityLayersDiagram.svg)



In order to execute a transaction, all three layers independently run the policy engine to verify that the transaction is valid.

The order of operations is the following:
1. **The dedicated mobile wallet runs the policy engine locally.** 

    It will not allows users to approve a transaction if its policy engine fails to validate the transaction.
2. **The offchain Guardian service runs the policy engine in a secure centralized server.**
    
    It will not approve the transaction if its policy engine fails to validate the transaction.
3. **The smart contracts run the policy engine onchain.** 

    It will not allow the transaction to execute if its policy engines fails to validate the transaction. It will also prevent the transaction from executing if any approvals are missing from the account owners or the offchain Guardian service.

## Core Concepts
There are several core concepts in Onchain Custody:

1. **Organizations**

    An organization is a business or other non-individual entity that is using Onchain Custody.

2. **Members**

    Members are individuals who are a part of an Organization.

3. **Groups**

    Groups are collections of Members within an Organization. For example, an Organization might have a "Finance team" Group.

4. **Accounts**
    
    Accounts are where funds are stored and where transactions are executed. An Organization can have many Accounts.

5. **Policies**

    Policies are rules that dictate what types of transactions can be executed and by whom.

5. **Admins**

    An organization's Admin is a privileged Member or Group that can modify the Organization. Specifically, Admins can manage an Organization's Members, Groups, Accounts, Policies, Whitelist, and Admins. 
    
    If the Admin for an Organization is set to a Group, then an Approval Threshold must also be set. The Approval Threshold dictates how many Members of the Admin Group must approve an operation. 
    
    Any Member of the Admin Group can *propose* a change to the Organization (e.g. adding a new Member), but the change will not take effect until enough Members in the Admin Group approve the proposed change.

6. **Address Whitelists**

    Address Whitelists are lists of trusted addresses. By default, transactions cannot be sent to non-whitelisted addresses, however this is a setting that Admins can change.

7. **Transactions**

    Transactions can send tokens, take a DeFi action, or interact with any arbitrary smart contract from an Account. A Transaction can only be executed if a Policy has been set that explicitly allows the Transaction. 
    
    Dependening on the Policy, the Transaction may be automatically approved, automatically rejected, or require other Members of the Organization to approve it.



## Policies
TODO: @ittai Explain policies in depth. Outline all configurable parameters of a policy, how proposing and approving transactions are influenced by policies, and give specific examples with diagrams.

## Mobile Wallet
TODO: @ittai Explain the security and UX benefits of the Mobile Wallet, what the User Flow will look like, and specific security features we're implementing for it


## Smart Contracts
### Organizations and Accounts
There are two main abstractions represented as smart contracts in Onchain Custody:
1. **Organizations**
        
    Each real-world organization is represented onchain by a dedicated organization smart contract. That contract is a source of truth for the organization's state, such as its members, groups, policies, admins, etc. Funds are *not* stored in the organization contract.

    *Located at `src/organization/OnchainCustodyOrganizationDiamond.sol`*

2. **Accounts**

    Funds are stored in "account" smart contracts (i.e. "smart accounts" or "smart contract wallets"). Each organization can have one or more accounts. Account smart contracts interact with their corresponding organization contracts to access important information regarding the organization. For example, when executing a transaction, an account contract will fetch its  organization's policies from the organization contract.

    *Located at `src/account/OnchainCustodyAccountDiamond.sol`*



![Onchain Custody Core Contracts Diagram](docs/images/OnchainCustodyCoreContractsDiagram.svg)

### Upgradability (ERC-2535 Diamond Standard)

> [!WARNING]
> We are exploring using the [ERC-1822 Universal Upgradeable Proxy Standard (UUPS)](https://eips.ethereum.org/EIPS/eip-1822) instead of the [ERC-2535 Diamond Standard](https://eips.ethereum.org/EIPS/eip-2535) for upgradability due to the heavy interdepencies between the diamond cut facets in Onchain Custody.

The smart contracts are upgradable according to the [ERC-2535 Diamond Standard](https://eips.ethereum.org/EIPS/eip-2535) by Nick Mudgen.


Onchain Custody's implementation of the ERC-2535 Diamond Standard is based on Nick Mudgen's [diamond-3-hardhat](https://github.com/mudgen/diamond-3-hardhat) reference implementation, with some notable changes:

1. **Facet cuts must be whitelisted.**

    In order to "cut the diamond", the facet cuts (facet addresses and selectors) must be whitelisted by a separate and global whitelist. 

    This is to negate attacks where users might be tricked into signing malicious payloads that cut the diamond in n efarious ways.

    The whitelist is implemented by `src/diamond/FacetCutsWhitelist.sol`. It is referenced by `src/diamond/libraries/LibDiamond.sol` in the function `enforceFacetsAreWhitelisted`.

2. **Diamond cuts require approval from an organization's admins.**

    In order to cut a diamond, sufficient approval signatures must be provided from the organization's admins.

    This is implemented in `src/diamond/facets/DiamondCutFacet.sol` in the function `diamondCut`.

3. **Diamond cuts require approval the offchain Guardian service.**

    In order to cut a diamond, the offchain Guardian service must also explicitly approve the action. This is part of Onchain Custody's **"multiple redundant layers of security"** model.

    This is implemented in `src/diamond/facets/DiamondCutFacet.sol` in the function `diamondCut`.


The implementation of the ERC-2535 Diamond Standard for Onchain Custody can be found in the directory `src/diamond`:
```
src/
├── diamond/
│   ├── Diamond.sol
│   ├── FacetCutsWhitelist.sol
│   ├── facets/
│   │   ├── DiamondCutFacet.sol
│   │   └── DiamondLoupeFacet.sol
│   ├── interfaces/
│   │   ├── IDiamondCut.sol
│   │   ├── IDiamondLoupe.sol
│   │   ├── IERC165.sol
│   │   └── IFacetCutsWhitelist.sol
│   └── libraries/
│       └── LibDiamond.sol
```


There are only two smart contracts in Onchain Custody that are upgradable:
1. **The Organization smart contract**
        
    Diamond is located at `sr/corganization/OnchainCustodyOrganizationDiamond.sol`

    Facets are located at `src/organization/facets/`

2. **The Account smart contract**

    Diamond is located at `src/account/OnchainCustodyAccountDiamond.sol`

    Facets are located at `src/account/facets/`




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