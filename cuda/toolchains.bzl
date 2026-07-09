"""Convenience macro that wires a `cuda_toolchain` to the `@cuda` repository.

Invoke this from a BUILD file in a module that can see the `@cuda` repository
created by the `cuda_toolkit` module extension (normally the root module). The
`@cuda//...` targets it references are platform- and version-resolving, so a
single toolchain works across every CUDA version you registered.

```starlark
load("@rules_cuda_toolkit//cuda:toolchains.bzl", "cuda_toolkit_toolchain")

cuda_toolkit_toolchain(
    name = "cuda_toolchain",
    exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    target_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
)
```

Then register it in MODULE.bazel:

```starlark
register_toolchains("//path/to:cuda_toolchain")
```
"""

load("//cuda/private:toolchain.bzl", "cuda_toolchain")

def cuda_toolkit_toolchain(
        name,
        cuda_repo = "@cuda",
        nvcc = None,
        compiler_files = None,
        compile_deps = None,
        runtime = None,
        version_major = "",
        version_minor = "",
        exec_compatible_with = None,
        target_compatible_with = None,
        **kwargs):
    """Declares a `cuda_toolchain` plus its `toolchain()` registration target.

    Args:
      name: name of the `toolchain()` target to register.
      cuda_repo: apparent name of the cuda_toolkit repository (default `@cuda`).
      nvcc: label of the nvcc driver. Defaults to `<cuda_repo>//nvcc:nvcc`.
      compiler_files: label of nvcc's support files. Defaults to
        `<cuda_repo>//nvcc:bin`.
      compile_deps: header labels available to every compile. Defaults to
        `<cuda_repo>//cuda:cuda_headers` and `<cuda_repo>//cccl:headers`.
      runtime: runtime library labels linked into dependents. Defaults to
        `<cuda_repo>//cudart` and `<cuda_repo>//cudart:cuda_driver`.
      version_major: optional CUDA major version string.
      version_minor: optional CUDA minor version string.
      exec_compatible_with: `exec_compatible_with` for the `toolchain()`.
      target_compatible_with: `target_compatible_with` for the `toolchain()`.
      **kwargs: forwarded to the `toolchain()` target (e.g. `visibility`).
    """
    impl_name = name + "_impl"

    cuda_toolchain(
        name = impl_name,
        nvcc = nvcc or (cuda_repo + "//nvcc:nvcc"),
        compiler_files = compiler_files or (cuda_repo + "//nvcc:bin"),
        compile_deps = compile_deps if compile_deps != None else [
            cuda_repo + "//cuda:cuda_headers",
            cuda_repo + "//cccl:headers",
        ],
        runtime = runtime if runtime != None else [
            cuda_repo + "//cudart",
            cuda_repo + "//cudart:cuda_driver",
        ],
        version_major = version_major,
        version_minor = version_minor,
        visibility = ["//visibility:private"],
    )

    native.toolchain(
        name = name,
        toolchain = ":" + impl_name,
        toolchain_type = "@rules_cuda_toolkit//cuda:toolchain_type",
        exec_compatible_with = exec_compatible_with or [],
        target_compatible_with = target_compatible_with or [],
        **kwargs
    )
