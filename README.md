# rules_cuda_toolkit

Bazel rules for compiling CUDA code with **nvcc**, built on top of the hermetic
[`cuda_toolkit`](https://registry.bazel.build/modules/cuda_toolkit) module.

`cuda_toolkit` provides the CUDA toolkit (nvcc, ptxas, headers, runtime
libraries, cuDNN, …) hermetically but deliberately ships *no* compile rules.
`rules_cuda_toolkit` adds the missing piece: `cuda_library`, `cuda_binary` and
`cuda_test` rules that drive nvcc, in the same spirit as
[`rules_cuda`](https://github.com/bazel-contrib/rules_cuda), while sourcing the
entire toolchain from `cuda_toolkit`'s `@cuda` repository.

```
┌────────────────┐   provides nvcc / ptxas / headers / runtime   ┌──────────────────────┐
│  cuda_toolkit  │ ───────────────  @cuda//...  ───────────────► │  rules_cuda_toolkit  │
│ (hermetic BCR) │                                               │  cuda_library/binary │
└────────────────┘                                               └──────────────────────┘
```

## Features

- `cuda_library` — compiles `.cu` (and `.cc`/`.cpp`) sources with nvcc and
  returns a `CcInfo`, so the result links into any `cc_binary`, `cc_test` or
  `cc_library`.
- `cuda_binary` / `cuda_test` — convenience macros that compile CUDA sources
  and link them into a `cc_binary` / `cc_test`.
- Hermetic: nvcc, ptxas, the CUDA headers and the CUDA runtime all come from the
  `cuda_toolkit` redistributable pinned in your `MODULE.bazel`. No system CUDA
  install, no `CUDA_PATH`.
- Multi-version aware: `@cuda` resolves the right CUDA version per platform, so a
  single toolchain works across every version you register.
- nvcc extended arch notation (`compute_80:sm_80,sm_86`), relocatable device
  code + device linking (`rdc = True`), and `-Xcompiler` / `-Xptxas` pass-through.

## Installation

Add the module to your `MODULE.bazel`:

```starlark
bazel_dep(name = "rules_cuda_toolkit", version = "0.0.1")

# The hermetic toolkit. The root module must depend on it directly to use
# its module extension.
bazel_dep(name = "cuda_toolkit", version = "0.0.4")

# Pin the CUDA version(s) you want. @cuda picks the right one per platform.
cuda_ext = use_extension("@cuda_toolkit//extensions:cuda.bzl", "cuda")
cuda_ext.redist(
    name = "cuda_12_9_1",
    version = "12.9.1",
)
use_repo(cuda_ext, "cuda", "cuda_12_9_1")

# rules_cuda_toolkit needs a host C/C++ toolchain that nvcc drives via -ccbin.
# Any registered cc toolchain works; the `llvm` module is hermetic and simple.
bazel_dep(name = "llvm", version = "0.6.1")
register_toolchains("@llvm//toolchain:all")

# Register the CUDA toolchain declared in your BUILD (see below).
register_toolchains("//:cuda_toolchain")
```

Then declare the CUDA toolchain in a `BUILD.bazel` of the **root module**
(where `@cuda` is visible):

```starlark
load("@rules_cuda_toolkit//cuda:toolchains.bzl", "cuda_toolkit_toolchain")

cuda_toolkit_toolchain(
    name = "cuda_toolchain",
    exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    target_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
)
```

## Usage

```starlark
load("@rules_cuda_toolkit//cuda:defs.bzl", "cuda_binary", "cuda_library")

cuda_library(
    name = "vector_add",
    srcs = ["vector_add.cu"],
    hdrs = ["vector_add.h"],
)

cuda_binary(
    name = "vector_add_demo",
    srcs = ["main.cc"],
    deps = [":vector_add"],
)
```

Choosing architectures:

```sh
# Command line (build setting):
bazel build //:vector_add_demo --@rules_cuda_toolkit//cuda:archs=compute_80:sm_80,sm_90

# Per target:
cuda_library(name = "k", srcs = ["k.cu"], archs = "sm_90")
```

The default is set in `//cuda:archs` (`sm_75`); override it globally in your
`.bazelrc` with `common --@rules_cuda_toolkit//cuda:archs=...`.

A complete, runnable project lives in [`examples/`](examples/) — including a
CUDA vector-add library/binary/test and a **cuDNN** convolution example.

### cuDNN (and other CUDA libraries)

Pin the library version on the same `redist` tag and depend on the `@cuda`
target:

```starlark
# MODULE.bazel
cuda_ext.redist(name = "cuda_12_9_1", version = "12.9.1", cudnn_version = "8.9.7")

# BUILD.bazel
cuda_library(name = "net", srcs = ["net.cu"], deps = ["@cuda//cudnn:cudnn"])
```

The same pattern works for cuBLAS (`@cuda//cublas:cublas`), cuFFT, cuSPARSE,
cuSOLVER, cuRAND, NVRTC, etc. — any component `cuda_toolkit` exposes under
`@cuda//<component>`.

> **cuDNN runtime patch:** `cuda_toolkit` 0.0.4 wires cuDNN's (and nvrtc's)
> `cc_import`s to the fully-versioned shared objects (`libcudnn.so.8.9.7`)
> instead of the `DT_SONAME` files the redist also ships (`libcudnn.so.8`), so
> the dynamic loader can't resolve them at run time. This repo ships a small
> patch — [`patches/cuda_toolkit_sonames.patch`](patches/cuda_toolkit_sonames.patch)
> — that points those imports at the soname files. Apply it from your root
> `MODULE.bazel`:
>
> ```starlark
> single_version_override(
>     module_name = "cuda_toolkit",
>     version = "0.0.4",
>     patch_strip = 1,
>     patches = ["//patches:cuda_toolkit_sonames.patch"],
> )
> ```
>
> With the patch, the `examples/` cuDNN convolution test builds, links **and
> runs** — verified end-to-end on an NVIDIA L4.

## Public API

Loaded from `@rules_cuda_toolkit//cuda:defs.bzl`:

| Symbol | Kind | Description |
| --- | --- | --- |
| `cuda_library` | rule | Compile CUDA/C++ sources into a static library (`CcInfo` + `CudaInfo`). |
| `cuda_binary` | macro | `cuda_library` + `cc_binary`. |
| `cuda_test` | macro | `cuda_library` + `cc_test`. |
| `cuda_toolchain` | rule | Low-level toolchain rule (usually via `cuda_toolkit_toolchain`). |
| `CudaInfo` | provider | Tracks the four object flavors (pic/nopic × rdc/nordc). |
| `CudaToolchainInfo` | provider | The resolved toolchain contents. |

`cuda_library` attributes: `srcs`, `hdrs`, `deps`, `includes`, `copts`,
`defines`, `local_defines`, `host_copts`, `host_defines`, `host_local_defines`,
`host_linkopts`, `ptxasopts`, `archs`, `rdc`, `alwayslink`.

- `copts` → flags for the nvcc driver; `host_copts` → forwarded to the host
  compiler via `-Xcompiler`; `ptxasopts` → forwarded to ptxas via `-Xptxas`.
- `defines`/`local_defines` are device defines (`-D`); `host_*` variants are the
  host-side equivalents exported through `CcInfo`.

## How it works

`cuda_library` resolves two toolchains: the standard C++ toolchain (for the host
compiler path and the final archive) and `@rules_cuda_toolkit//cuda:toolchain_type`
(nvcc + support files + CUDA headers + runtime). For each source it runs

```
nvcc -x cu -ccbin <host-cc> <-gencode ...> [-rdc=true] [-Xcompiler -fPIC] \
     -I... -D... <copts> [-Xcompiler <host_copts>] [-Xptxas <ptxasopts>] \
     -c <src> -o <obj>
```

The resulting objects are archived with `cc_common` into a static library and
returned as a `CcInfo`, so ordinary `cc_*` rules link the CUDA code and the CUDA
runtime with no extra wiring. With `rdc = True` (or an `lto_` arch), an extra
`nvcc -dlink` step device-links the relocatable objects before archiving.

## Requirements & limitations

- Linux `x86_64` / `aarch64` (the platforms `cuda_toolkit` publishes for).
- A registered host C/C++ toolchain (nvcc requires `-ccbin`).
- The runtime libraries are attached through the toolchain; cross-compilation
  where the execution platform differs from the target platform for the CUDA
  *runtime* is not yet handled — build on the platform you target.
- This is an nvcc-only ruleset; the clang-CUDA path is out of scope.

## License

MIT — see [LICENSE](LICENSE).
