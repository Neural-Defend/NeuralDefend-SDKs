# The NeuroVerify SDK uses no reflection, serialization codegen, or dynamic class loading,
# so R8 may shrink, optimize, and obfuscate it freely. OkHttp, Okio, kotlinx-coroutines,
# and kotlinx-serialization ship their own consumer rules.
