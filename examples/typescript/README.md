# TypeScript examples

## API key

Request an API key from **[neuraldefend.com](https://neuraldefend.com/)** (choose **Book a
Demo**) or contact [support@neuraldefend.com](mailto:support@neuraldefend.com). After
onboarding, export it before running the Node example:

```sh
export NEURALDEFEND_API_KEY="your-api-key"
```

## Files

- `node.ts` uploads an image path using `NEURALDEFEND_API_KEY`.
- `browser.ts` exports a browser helper that accepts a user-selected `File` and a
  short-lived credential from your backend (not a long-lived production key).

Install `@neuraldefend/sdk`, then run the Node example with a TypeScript runner:

```sh
npx tsx node.ts ./selfie.jpg
```
