# TypeScript examples

## API key

Request an API key from **[neuraldefend.com](https://neuraldefend.com/)** (choose **Book a
Demo**) or contact [support@neuraldefend.com](mailto:support@neuraldefend.com). After
onboarding, export it before running the Node example:

```sh
export NEURALDEFEND_API_KEY="replace-with-your-api-key"
```

## Files

- `node.ts` uploads an image path using `NEURALDEFEND_API_KEY`.
- `browser.ts` exports a browser helper that accepts a user-selected `File` and a
  short-lived credential from your backend (not a long-lived production key).

Install `@neuraldefend/sdk`, then run the Node example with a TypeScript runner:

```sh
npx tsx node.ts ./selfie.jpg
```

## Industry use cases

Each file in [`use-cases/`](use-cases/) is a complete, runnable integration that turns a
NeuroVerify result into a business decision and writes an audit line per API call:

- [`ekyc-onboarding.ts`](use-cases/ekyc-onboarding.ts): check a new applicant's selfie
  during digital onboarding.
- [`kyc-reverification.ts`](use-cases/kyc-reverification.ts): re-verify an existing
  customer before a sensitive action such as a large withdrawal.
- [`video-kyc.ts`](use-cases/video-kyc.ts): review a recorded video KYC session for face
  swaps and cloned voices.
- [`hr-tech.ts`](use-cases/hr-tech.ts): screen a candidate's interview recording and ID
  photo.
- [`video-conferencing.ts`](use-cases/video-conferencing.ts): check a meeting
  participant's clip for deepfakes.

Run one from the `use-cases/` folder with the sample media file it names next to it:

```sh
npx tsx ekyc-onboarding.ts
```
