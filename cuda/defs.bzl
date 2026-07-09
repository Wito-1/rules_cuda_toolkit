"""Public API for rules_cuda_toolkit.

```starlark
load("@rules_cuda_toolkit//cuda:defs.bzl", "cuda_binary", "cuda_library", "cuda_test")
```
"""

load("//cuda/private:cuda_library.bzl", _cuda_library = "cuda_library")
load("//cuda/private:macros.bzl", _cuda_binary = "cuda_binary", _cuda_test = "cuda_test")
load("//cuda/private:providers.bzl", _CudaInfo = "CudaInfo")
load("//cuda/private:toolchain.bzl", _CudaToolchainInfo = "CudaToolchainInfo", _cuda_toolchain = "cuda_toolchain")

cuda_library = _cuda_library
cuda_binary = _cuda_binary
cuda_test = _cuda_test
cuda_toolchain = _cuda_toolchain

CudaInfo = _CudaInfo
CudaToolchainInfo = _CudaToolchainInfo
