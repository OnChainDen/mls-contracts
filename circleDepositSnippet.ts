import { DenClient } from '@den/client';
import axios from 'axios';
import { v4 as uuidv4 } from 'uuid';

// Initialize the Den SDK client
const denClient = new DenClient({apiKey: process.env.DEN_API_KEY, environment: 'production'});

// Initialize the Circle API client
const circleClient = axios.create({
  baseURL: 'https://api.circle.com/v1',
  headers: {
    Authorization: `Bearer ${process.env.CIRCLE_API_KEY}`,
  },
});

// Get the MLS wallet address from Den
const { address: mlsWalletAddress } = await denClient.getAccount(process.env.MLS_WALLET_ID); 

// Register the address with Circle
// This a one-time setup to allowlist the MLS wallet address with Circle
const walletRegistrationResponse = await circleClient.post(
  '/businessAccount/wallets/addresses/recipient',
  {
    idempotencyKey: uuidv4(),
    address: mlsWalletAddress,
    chain: 'POLY',
    currency: 'USD',
    description: 'MLS Wallet',
  }
);

// Deposit 10,000 USD from Circle to the MLS wallet
await circleClient.post('/businessAccount/transfers', {
  idempotencyKey: uuidv4(),
  amount: { amount: "10000.00", currency: "USD" },     // 10,000 USD
  destination: {
    type: 'verified_blockchain',
    addressId: walletRegistrationResponse.data.data.id // ID of the MLS wallet address with Circle
  },
});