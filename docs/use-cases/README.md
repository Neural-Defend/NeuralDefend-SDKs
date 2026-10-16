# Industry use cases

Step-by-step guides for adding NeuroVerify to real products. Each guide explains the fraud
problem, shows where the check fits in your flow, gives a clear decision table, and includes
complete code for **every SDK**: Python, TypeScript, Go, Java, Kotlin, Dart, and Swift.

| Guide | For | What it checks |
|---|---|---|
| [eKYC onboarding](ekyc-onboarding.md) | Digital banks, fintechs, eKYC providers | The selfie at sign-up |
| [KYC re-verification](kyc-reverification.md) | Banks, wallets, marketplaces | A fresh selfie before risky actions |
| [Video KYC](video-kyc.md) | Video KYC platforms, banks, insurers | The recorded session: face **and** voice |
| [HR tech](hr-tech.md) | Hiring platforms, background checks | Interview recordings and ID photos |
| [Video conferencing](video-conferencing.md) | Meeting, webinar, and telehealth platforms | Short clips of participants during calls |

## How every guide works

All the code follows the same three rules, whatever the language or industry:

1. **Check the status first.** A *rejected* result (no face, blurry, wrong format) is a
   normal answer. Ask for new media; don't treat it as fraud or as an error.
2. **Then use the risk level** (`low`, `medium`, `high`), never your own score threshold.
3. **Save the transaction ID** of every check for audit, support, and billing.

The code always runs on **your backend**. Mobile and web apps capture and upload the media;
only your server holds the API key.

Ready-to-run Python and TypeScript versions are in [`examples/python/use_cases`](../../examples/python/use_cases)
and [`examples/typescript/use-cases`](../../examples/typescript/use-cases).

New to the SDKs? Start with the [quick start](../../README.md#quick-start).
