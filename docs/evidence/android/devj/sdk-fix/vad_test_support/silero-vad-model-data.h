// Test-only embedded model substitute. Never include this in a packaged SDK.
// Fake ORT does not parse or run a model; only constructor control flow is tested.
static const unsigned char silero_vad_onnx[] = {0};
static const unsigned int silero_vad_onnx_len = sizeof(silero_vad_onnx);
