# CryptoSafe Transfer Smart Contract

## Overview
The **CryptoSafe Transfer Smart Contract** provides a secure, trustless solution for digital asset custody, enabling the management and transfer of assets between parties with verification and arbitration capabilities. This contract supports secure vault management, which includes:

- Deposits and transfers of assets.
- Withdrawal options for depositors before recipient confirmation.
- Vault lifetime extensions and recovery of expired vaults.

## Features
- **Vault Registry**: Stores vault data including depositors, recipients, asset IDs, amounts, vault state, and time constraints.
- **Transfer Completion**: Ensures secure release of funds to the recipient upon conditions being met.
- **Return Funds**: Allows vault administrators to return funds to the depositor if necessary.
- **Fund Withdrawal**: Deposit holders can withdraw funds before confirmation if needed.
- **Vault Extensions**: Extend the vault's lifetime for an additional period if required.
- **Expired Vault Recovery**: Enable recovery of funds from expired vaults by authorized parties.

## Smart Contract Functions

### Core Functions:
- **complete-transfer(vault-id uint)**: Release funds to the recipient.
- **return-funds(vault-id uint)**: Return funds to the depositor.
- **withdraw-funds(vault-id uint)**: Allow the depositor to withdraw funds before recipient confirmation.

### Vault Management:
- **extend-vault-time(vault-id uint, additional-blocks uint)**: Extend the vault's lifetime by the given number of blocks.
- **recover-expired-vault(vault-id uint)**: Recover funds from a vault after it has expired.

### Helper Functions:
- **validate-recipient(recipient principal)**: Validate that the recipient isn't the contract caller.
- **vault-exists(vault-id uint)**: Check if the given vault ID exists.

## Installation

1. **Install Dependencies**:
   Make sure you have the appropriate environment set up for deploying smart contracts. You will need:
   - [Stacks CLI](https://github.com/stacks/stack-cli) to interact with the Stacks blockchain.
   - A Stacks wallet for testnet/mainnet deployment.

2. **Deploying the Contract**:
   - Navigate to the smart contract directory.
   - Run the following command to deploy the contract:
     ```bash
     stacks deploy <contract-name>.clar
     ```

## Usage

1. **Deploy Contract**: Deploy the contract to your desired network (Testnet or Mainnet).
2. **Interact with Vaults**:
   - **Create a Vault**: Depositors can initiate a vault creation, and the smart contract will record the details.
   - **Transfer Funds**: Once the conditions are met, either the recipient or vault admin can complete the transfer.
   - **Withdraw Funds**: If needed, depositors can withdraw their funds before the recipient confirms.
   - **Extend Vault Time**: If the vault has not yet been completed, time can be extended.
   - **Recover Expired Vaults**: If the vault expires, the funds can be recovered by the depositor or vault admin.

## Contract Events
- `transfer_completed`: Triggered when the transfer to the recipient is completed successfully.
- `funds_returned`: Triggered when the funds are returned to the depositor.
- `withdrawal_completed`: Triggered when the depositor successfully withdraws funds.
- `vault_extended`: Triggered when the vault’s lifetime is extended.
- `expired_vault_recovered`: Triggered when expired vault funds are recovered.

## Error Codes
The contract includes the following error codes for different failure scenarios:
- **ERR_NOT_ALLOWED**: When an unauthorized action is attempted.
- **ERR_VAULT_NOT_FOUND**: When the vault ID is not found in the registry.
- **ERR_ALREADY_HANDLED**: When an action has already been processed.
- **ERR_TRANSFER_FAILED**: When the transfer to the recipient or depositor fails.
- **ERR_BAD_ID**: Invalid vault ID.
- **ERR_BAD_VALUE**: Invalid value (such as negative or excessive amounts).
- **ERR_BAD_RECIPIENT**: Invalid recipient.
- **ERR_VAULT_EXPIRED**: When the vault has expired.

## Security Considerations
- Ensure the contract's Vault Admin (`VAULT_ADMIN`) has restricted access and is not vulnerable to privilege escalation.
- Vault expiration logic and withdrawal conditions are designed to prevent fund mismanagement.

## License
This project is licensed under the [MIT License](LICENSE).

---

## Contributing
1. Fork the repository.
2. Create a new branch for your feature or bugfix.
3. Ensure tests are added or updated to reflect your changes.
4. Submit a pull request with a description of your changes.
