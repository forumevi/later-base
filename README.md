# LATER  a time capsule on Base

**Write it now. Read it later. Nobody can open it early  not even you.**

LATER lets anyone seal a message to their future self (or someone they love). The capsule is stored on Base and stays locked until the date they choose. No wallet setup, no seed phrase, no gas: sign in with a passkey and the app sponsors the fees.

## Status
Interactive prototype (frontend only). All on-chain parts are **simulated** with demo data.

## Features (prototype)
- Composer: to myself / to someone (private link, X handle, Basename, email)
- Unlock: tonight, 1 week, 1 month, 1 year, next birthday, New Year 2030, custom date
- Passkey sign-in flow (mock)
- Sealing animation, live split-flap countdown, share on X
- Capsule Sky: public map of sealed capsules (contents stay secret)

## Roadmap
1. Capsule contract on Base (seal, unlock timestamp, recipient)
2. Encryption with time-locked key release
3. Base Smart Wallet (passkeys) + paymaster for gasless sealing
4. Basename support for recipients

## Run
Open `index.html` in a browser.

## Contract (`contracts/`)
`LaterCapsule.sol` — ownerless, non-upgradeable, nothing can be deleted.
- `seal(recipient, unlockAt, drandRound, onSky, ciphertext)`: the message is encrypted off-chain with drand timelock to `drandRound`; the ciphertext is emitted in the `Sealed` event and only its hash is stored.
- `open(id)`: records the opening moment after `unlockAt` (sender/recipient; link capsules: anyone).
- Lock window: 10 minutes to 100 years. Ciphertext up to 8 KB (media goes off-chain via a URI inside the ciphertext).

```bash
cd contracts
forge install foundry-rs/forge-std --no-git
forge test
```
