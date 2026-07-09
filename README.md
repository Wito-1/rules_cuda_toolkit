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

# Generate and register the CUDA toolchains straight from @cuda. `configure.cuda`
# is an anchor — any label in the @cuda repo; the extension derives the rest and
# emits native x86_64/arm64 toolchains plus the x86_64->aarch64 cross toolchain.
cuda_toolchains = use_extension("@rules_cuda_toolkit//cuda:extensions.bzl", "cuda_toolchains")
cuda_toolchains.configure(cuda = "@cuda//nvcc:nvcc")
use_repo(cuda_toolchains, "cuda_toolchains")
register_toolchains("@cuda_toolchains//:all")
```

That's the whole toolchain setup — no per-platform `cuda_toolchain` targets in
your BUILD files. (Prefer to wire it by hand, or need custom constraints? The
[`cuda_toolkit_toolchain`](cuda/toolchains.bzl) macro does exactly what the
extension generates; see [`examples/cross/`](examples/cross/) for the shape.)

Restrict which toolchains are generated with `exec_cpus` / `target_cpus`:

```starlark
cuda_toolchains.configure(cuda = "@cuda//nvcc:nvcc", target_cpus = ["x86_64"])
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

### Multiple CUDA versions

Register more than one version; `@cuda` resolves whichever one the active
platform pins via a `@cuda//:cuda_<version>` constraint (the default, unpinned
platform uses the highest registered version):

```starlark
# MODULE.bazel
cuda_ext.redist(name = "cuda_12_9_1", version = "12.9.1")
cuda_ext.redist(name = "cuda_12_8_1", version = "12.8.1")
use_repo(cuda_ext, "cuda", "cuda_12_8_1", "cuda_12_9_1")

# BUILD.bazel — a version-pinned platform
platform(
    name = "cuda_12_8_1",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
        "@cuda//:cuda_12_8_1",
    ],
)
```

```sh
bazel test //:my_test --platforms=//:cuda_12_8_1   # build against CUDA 12.8
```

The `examples/` directory runs the **same** tests against CUDA 12.8 **and** 12.9
as separate targets via a small platform-transition wrapper,
[`examples/multi_version.bzl`](examples/multi_version.bzl):

- `//:vector_add_test_cuda_12_8` / `//:vector_add_test_cuda_12_9`
- `//:cudnn_conv_test_cuda_12_8` / `//:cudnn_conv_test_cuda_12_9` (cuDNN 8.9.7 on both)

The wrapper transitions both the target platform and the execution platform, so
the CUDA runtime/cuDNN *and* the exec-configuration nvcc come from the pinned
toolkit — verified on an L4: each target compiles with its own
`cuda_12_8_1`/`cuda_12_9_1` nvcc and the cuDNN pipeline runs under both.

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

### Cross-compiling to aarch64 (SBSA / Grace / Jetson)

The exec/target split makes cross-compilation natural: nvcc and the host
compiler run on the x86_64 build host (execution configuration) while the CUDA
runtime and final binary are produced for aarch64 (target configuration).
`@cuda` maps `@platforms//cpu:arm64` to the `linux-sbsa` redistribution
automatically. The `cuda_toolchains` extension already generates the
`x86_64`→`arm64` CUDA toolchain, so the only cross-specific thing you provide is
an **aarch64 host C/C++ cross toolchain** for nvcc's `-ccbin` and the final link
(system `aarch64-linux-gnu-*`, or a hermetic one such as `toolchains_llvm` with
an aarch64 sysroot).

A complete, working setup is in [`examples/cross/`](examples/cross/): it builds
the same `vector_add` program for aarch64 with

```sh
bazel build //cross:vector_add_aarch64 --platforms=//cross:linux_aarch64
# or, platform pinned by a transition (no flag needed):
bazel test //cross:vector_add_aarch64_test
```

Verified on an x86_64 host: the output is an `ELF 64-bit … ARM aarch64`
executable, compiled by the host `…linux_x86_64/bin/nvcc` with
`-ccbin aarch64-linux-gnu-gcc` and linked against the SBSA CUDA runtime.
(The example uses the system `g++-aarch64-linux-gnu`; running the result needs
real aarch64 CUDA hardware.)

#### Jetson / embedded (L4T)

`arm64` defaults to NVIDIA's **`linux-sbsa`** (server ARM) redistribution. Jetson
uses a *different* aarch64 build, `linux-aarch64` (L4T), which `cuda_toolkit`
0.0.4 doesn't expose. This repo ships a patch —
[`patches/cuda_toolkit_jetson.patch`](patches/cuda_toolkit_jetson.patch) — that
adds the `linux-aarch64` platform and a `@cuda_toolkit//:jetson` constraint to
disambiguate it from SBSA (both are the aarch64 ISA, so a plain
`@platforms//cpu:arm64` can't tell them apart). Apply it in the same
`single_version_override`, then define a Jetson platform:

```starlark
platform(
    name = "linux_jetson",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:arm64",
        "@cuda_toolkit//:jetson",   # -> linux-aarch64 instead of linux-sbsa
    ],
)
```

The host cc toolchain and the generated CUDA toolchain are identical to the SBSA
case — only the CUDA redistribution changes. Verified on an x86_64 host
(`examples/cross/`): `//cross:linux_jetson` resolves the runtime to
`cuda_cudart__linux_jetson` while `//cross:linux_aarch64` stays on
`cuda_cudart__linux_sbsa`.

## Requirements & limitations

- Linux `x86_64` / `aarch64` (the platforms `cuda_toolkit` publishes for).
- A registered host C/C++ toolchain (nvcc requires `-ccbin`).
- The runtime libraries are attached through the toolchain; cross-compilation
  where the execution platform differs from the target platform for the CUDA
  *runtime* is not yet handled — build on the platform you target.
- This is an nvcc-only ruleset; the clang-CUDA path is out of scope.

## License

MIT — see [LICENSE](LICENSE).
