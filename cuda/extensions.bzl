"""Module extension that generates CUDA toolchains wired to `@cuda`.

Usage in a consumer `MODULE.bazel` (after setting up the `cuda` extension from
`cuda_toolkit` so that `@cuda` exists):

```starlark
cuda_toolchains = use_extension("@rules_cuda_toolkit//cuda:extensions.bzl", "cuda_toolchains")
cuda_toolchains.configure(cuda = "@cuda//nvcc:nvcc")
use_repo(cuda_toolchains, "cuda_toolchains")

register_toolchains("@cuda_toolchains//:all")
```

`configure.cuda` is an **anchor** — any label in the `@cuda` repository. The
extension derives the concrete nvcc/headers/runtime targets from it and emits a
`cuda_toolchain` + `toolchain()` for each exec/target CPU combination (Linux
`x86_64` and `arm64` by default), covering native builds and x86_64→aarch64
cross-compilation in one shot. You still register a host/cross C++ toolchain
yourself (nvcc drives it via `-ccbin`).
"""

load("//cuda/private:toolchains_repo.bzl", "cuda_toolchains_repo")

_DEFAULT_CPUS = ["x86_64", "arm64"]

def _cuda_toolchains_impl(mctx):
    anchor = None
    exec_cpus = None
    target_cpus = None

    # Root module wins; otherwise take the first configure tag seen.
    for mod in mctx.modules:
        for tag in mod.tags.configure:
            if anchor == None or mod.is_root:
                anchor = tag.cuda
                exec_cpus = list(tag.exec_cpus) if tag.exec_cpus else None
                target_cpus = list(tag.target_cpus) if tag.target_cpus else None

    if anchor == None:
        fail("the cuda_toolchains extension requires a configure(cuda = \"@cuda//nvcc:nvcc\") tag")

    cuda_toolchains_repo(
        name = "cuda_toolchains",
        cuda_repo = anchor.repo_name,
        exec_cpus = exec_cpus or _DEFAULT_CPUS,
        target_cpus = target_cpus or _DEFAULT_CPUS,
    )

    return mctx.extension_metadata(reproducible = True)

_configure = tag_class(
    attrs = {
        "cuda": attr.label(
            mandatory = True,
            doc = "Any label in the @cuda repository (e.g. @cuda//nvcc:nvcc); " +
                  "used only to locate the repository.",
        ),
        "exec_cpus": attr.string_list(
            doc = "Execution CPUs to generate toolchains for (default x86_64, arm64).",
        ),
        "target_cpus": attr.string_list(
            doc = "Target CPUs to generate toolchains for (default x86_64, arm64).",
        ),
    },
)

cuda_toolchains = module_extension(
    implementation = _cuda_toolchains_impl,
    tag_classes = {"configure": _configure},
)
