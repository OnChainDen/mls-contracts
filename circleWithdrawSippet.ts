import { DenClient, HsmSigner } from '@den/client';
import axios from 'axios';
import { v4 as uuidv4 } from 'uuid';
import { encodeFunctionData, erc20Abi } from 'viem';

// Initialize the Den SDK client
const denClient = new DenClient({apiKey: process.env.DEN_API_KEY, environment: 'production'});

// Initialize the HSM signer
const hsmSigner = new HsmSigner({url: process.env.HSM_URL, keyId: process.env.HSM_KEY_ID});

// Initialize the Circle API client
const circleClient = axios.create({
  baseURL: 'https://api.circle.com/v1',
  headers: { Authorization: `Bearer ${process.env.CIRCLE_API_KEY}` },
});

// Step 1: Create USDC transfer to Circle deposit address
const tx = await denClient.createTransaction({
  accountId: process.env.MLS_WALLET_ID,     // ID of MLS wallet in Den
  networkId: "1",                           // Ethereum Mainnet (1 = Ethereum Mainnet)
  policyId: process.env.POLICY_ID,          // ID of MLS policy that allows sending USDC to Circle
  transaction: {
    to: process.env.USDC_CONTRACT_ADDRESS,  // Address of USDC token contract
    data: encodeFunctionData({
      abi: erc20Abi,
      functionName: "transfer",
      args: [
        process.env.CIRCLE_DEPOSIT_ADDRESS, // Address for Circle deposits (from Circle dashboard)
        "10000000000000000000"              // 10,000 USDC (10,0000 * 10^6)
      ], 
    }),
  },
});

// Step 2: Sign transaction with HSM
await denClient.signTransaction(
  tx.id,
  { type: "initiator", signature: await hsmSigner.signTransaction(tx) }
);

// Step 3: Sign and execute transaction via MLS wallet
await denClient.executeTransaction(tx.id, { type: "approve" });

// Step 4: Create payout from Circle to bank account
await circleClient.post('/businessAccount/payouts', {
  idempotencyKey: uuidv4(),
  destination: {
    type: 'wire',
    id: process.env.CIRCLE_WIRE_ACCOUNT_ID, // ID of bank account for withdrawals (from Circle dashboard)
  },
  amount: { amount: "10000.00", currency: "USD" }, 
});
