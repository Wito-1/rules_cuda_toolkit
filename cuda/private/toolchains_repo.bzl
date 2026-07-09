"""Repository rule that materializes CUDA `toolchain()` targets wired to `@cuda`.

The generated BUILD references the CUDA repository by its **canonical** name
(`@@…`), which the module extension extracts from an anchor label the root
module passes in. Canonical labels resolve regardless of repo mapping, so the
generated repo can name `@cuda`'s targets even though `@cuda` is created by a
different module's extension.
"""

_TOOLCHAIN_TEMPLATE = """
cuda_toolchain(
    name = "{name}_impl",
    nvcc = "{cuda}//nvcc:nvcc",
    compiler_files = "{cuda}//nvcc:bin",
    compile_deps = [
        "{cuda}//cuda:cuda_headers",
        "{cuda}//cccl:headers",
    ],
    runtime = [
        "{cuda}//cudart",
        "{cuda}//cudart:cuda_driver",
    ],
)

toolchain(
    name = "{name}",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:{exec_cpu}",
    ],
    target_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:{target_cpu}",
    ],
    toolchain = ":{name}_impl",
    toolchain_type = "@rules_cuda_toolkit//cuda:toolchain_type",
)
"""

def _cuda_toolchains_repo_impl(rctx):
    cuda = "@@" + rctx.attr.cuda_repo
    parts = [
        '''load("@rules_cuda_toolkit//cuda/private:toolchain.bzl", "cuda_toolchain")\n''',
        "package(default_visibility = [\"//visibility:public\"])\n",
    ]
    for exec_cpu in rctx.attr.exec_cpus:
        for target_cpu in rctx.attr.target_cpus:
            parts.append(_TOOLCHAIN_TEMPLATE.format(
                name = "cuda_{}_to_{}".format(exec_cpu, target_cpu),
                cuda = cuda,
                exec_cpu = exec_cpu,
                target_cpu = target_cpu,
            ))
    rctx.file("BUILD.bazel", "".join(parts))
    return rctx.repo_metadata(reproducible = True)

cuda_toolchains_repo = repository_rule(
    implementation = _cuda_toolchains_repo_impl,
    attrs = {
        "cuda_repo": attr.string(
            mandatory = True,
            doc = "Canonical repo name (no leading @@) of the @cuda repository.",
        ),
        "exec_cpus": attr.string_list(mandatory = True),
        "target_cpus": attr.string_list(mandatory = True),
    },
)
