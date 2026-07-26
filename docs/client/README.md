# Client API documentation

These files are **copies** of the customer-facing endpoint documentation maintained with
the private NeuroVerify API.

**They are not the source of truth.** Edit them in the API repository and re-copy them
here, exactly as with `spec/public.yaml`. A change made here alone will be silently lost
the next time they are refreshed, and it will not reach customers.

They are kept in this repo for one reason: the JSON examples in them are the raw material
for the shared contract-test fixtures. Every response scenario the SDK facade must map
correctly — a no-face rejection arriving as HTTP 200, a silent video with null audio
fields, a 400 that still carries the envelope — has a worked example here.

| File | Endpoint |
|---|---|
| `unified-face-authenticity.md` | `POST /detect/image` |
| `unified-video-authenticity.md` | `POST /detect/video` |
