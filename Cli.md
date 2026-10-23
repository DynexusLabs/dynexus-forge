# Dynexus Forge CLI

Command-line reference for deploying and operating Dynexus Forge on Aptos.

## Configuration

The package uses a placeholder named address (`dynexus_forge = "_"`). Pick the deployer
profile and export its address:

```bash
export PROFILE=dynexus-testnet
export CA=$(aptos config show-profiles --profile $PROFILE | grep '"account"' | cut -d'"' -f4)
```

## Deploy

```bash
aptos move publish --profile $PROFILE --named-addresses dynexus_forge=$CA
```

## Bootstrap DYNEXUS

### Create the DYNEXUS token

The admin is exempt from the creation fee, so this works before DYNEXUS exists.

```bash
aptos move run --profile $PROFILE \
  --function-id $CA::token_factory::create_token \
  --args \
    string:"DYNEXUS" \
    string:"DYNEXUS" \
    u8:8 \
    u64:1000000000000 \
    string:"https://lavender-binding-jackal-744.mypinata.cloud/ipfs/bafybeiega65r37e6htyrgfxkqsxt36pnldpjmhmw7imyemfrub62l6sjiy" \
    string:"https://dynexus.netlify.app/"
```

### Register it as the platform token

```bash
export DYNEXUS=$(aptos move view --profile $PROFILE \
  --function-id $CA::token_factory::get_token_fa_address \
  --args address:$CA string:"DYNEXUS" string:"DYNEXUS" | grep 0x | tr -d ' "')

aptos move run --profile $PROFILE \
  --function-id $CA::token_factory::set_dynexus_token \
  --args address:$DYNEXUS
```

## Admin

| Function                         | Args             | Notes                                   |
| -------------------------------- | ---------------- | --------------------------------------- |
| `set_dynexus_plateform_fee_rate` | `u64` fee        | Flat fee per token creation, base units |
| `set_dynexus_faucet_period`      | `u64` seconds    | Cooldown between faucet claims          |
| `set_dynexus_faucet_amount`      | `u64` amount     | Base units per claim                    |
| `add_dynexus_minter`             | `address` minter | Allow a contract to call `mint_dynexus` |
| `remove_dynexus_minter`          | `address` minter | Revoke                                  |

Example — allow the Dynexus Core emissions minter:

```bash
aptos move run --profile $PROFILE \
  --function-id $CA::token_factory::add_dynexus_minter \
  --args address:$CORE_MINTER
```

## Users

```bash
# Claim faucet DYNEXUS
aptos move run --function-id $CA::token_factory::faucet_dynexus

# Mint more of a token you created
aptos move run --function-id $CA::token_factory::mint_token \
  --args address:$TO address:$TOKEN u64:1000

# Burn your own balance of a factory token
aptos move run --function-id $CA::token_factory::burn_token \
  --args address:$TOKEN u64:1000
```

## Views

```bash
aptos move view --function-id $CA::token_factory::get_dynexus_config
aptos move view --function-id $CA::token_factory::get_tokens --args u64:0 u64:50
aptos move view --function-id $CA::token_factory::get_tokens_by_creator --args address:$USER
aptos move view --function-id $CA::token_factory::get_token_info --args address:$TOKEN
aptos move view --function-id $CA::token_factory::get_next_faucet_time --args address:$USER
```
