---
title: Token template — what your coin can and cannot do
---

# Token template — what your coin can and cannot do

When you create a coin with the Token Deployer, a new Sui package is published for it. This page
explains what that coin can do afterwards, who controls it, and the choices that are permanent.

## Permanent from the moment you publish

- **Name, symbol and decimals** can never change.
- The **coin type** (`<package>::<module>::<STRUCT>`) is fixed — a new coin always means a new
  package and a new type.
- If the package is made **immutable** (the default), its code can never change.

## Controlled by whoever holds the capabilities

| You hold… | You can… | You can give it up by… |
| --- | --- | --- |
| the **TreasuryCap** | mint new coins and burn coins you own | choosing *fixed supply* (the cap is frozen after the initial mint — nobody can ever mint again) |
| the **MetadataCap** | change the description and icon | choosing *frozen metadata* (the cap is frozen — nobody can change them again) |

Whoever holds a capability has that power — keep it in a wallet you control, or give it up
deliberately. Sending a capability to someone else transfers the power with it.

## Things to know

- **Fixed supply is final.** After choosing it you can never mint more, even if you made a mistake
  in the initial amount.
- **Icon URLs point to files hosted elsewhere** (for example on Walrus). If that file expires or is
  removed, wallets show a broken icon; keep the storage alive or update the icon while you still
  hold the MetadataCap.
- **Wallets find your coin through the registry.** Registration is completed automatically after
  publishing; if it was interrupted, anyone can finish it.
- **The deployer fee** (if the site charges one) is paid once, in the publish transaction; the coin
  itself never charges fees on transfers.
