# Dynexus Forge CLI

Command-line interface for managing Dynexus tokens on the Aptos blockchain.

## Configuration

Set the contract address:

```bash
export CA='0x0a942e3fc8e3a5b88c7f9aa7b55a0be4ded9764294d97bb75f32e064a25f057d'
```

## Commands

### Create Dynexus Token

Creates a new Dynexus token with initial parameters.

```bash
aptos move run \
  --function-id $CA::token_factory::create_token \
  --args \
    string:"DYNEXUS" \
    string:"DYNEXUS" \
    u8:8 \
    u64:1000000000000 \
    string:"https://lavender-binding-jackal-744.mypinata.cloud/ipfs/bafybeiega65r37e6htyrgfxkqsxt36pnldpjmhmw7imyemfrub62l6sjiy" \
    string:"https://dynexus.netlify.app/"
```

Parameters:
- Token name: `DYNEXUS`
- Token symbol: `DYNEXUS`
- Decimals: `8`
- Initial supply: `1,000,000,000,000` (1 trillion)
- Metadata URI: IPFS hosted metadata
- Website: Project homepage

### Set Token Address

Registers the deployed token address in the contract.

```bash
aptos move run \
  --function-id $CA::token_factory::set_dynexus_token \
  --args address:0xf8ec309b09efa2ca5b4f697ce012ebb0597b96c0b8f1893af34764a7e8ed809f
```

### Faucet Tokens

Claims tokens from the faucet.

```bash
aptos move run \
  --function-id $CA::token_factory::faucet_dynexus
```

## Quick Setup

```bash
# Set contract address
export CA='0x0a942e3fc8e3a5b88c7f9aa7b55a0be4ded9764294d97bb75f32e064a25f057d'

# Create token
aptos move run --function-id $CA::token_factory::create_token --args string:"DYNEXUS" string:"DYNEXUS" u8:8 u64:1000000000000 string:"https://lavender-binding-jackal-744.mypinata.cloud/ipfs/bafybeiega65r37e6htyrgfxkqsxt36pnldpjmhmw7imyemfrub62l6sjiy" string:"https://dynexus.netlify.app/"

# Set token address
aptos move run --function-id $CA::token_factory::set_dynexus_token --args address:0xf8ec309b09efa2ca5b4f697ce012ebb0597b96c0b8f1893af34764a7e8ed809f

# Claim faucet tokens
aptos move run --function-id $CA::token_factory::faucet_dynexus
```

## Batch Script

```bash
#!/bin/bash
# dynexus-setup.sh

CA='0x0a942e3fc8e3a5b88c7f9aa7b55a0be4ded9764294d97bb75f32e064a25f057d'
TOKEN_ADDRESS='0xf8ec309b09efa2ca5b4f697ce012ebb0597b96c0b8f1893af34764a7e8ed809f'

echo "Setting up Dynexus..."

aptos move run --function-id $CA::token_factory::set_dynexus_token --args address:$TOKEN_ADDRESS
aptos move run --function-id $CA::token_factory::faucet_dynexus

echo "Setup complete!"
```