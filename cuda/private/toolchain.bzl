"""The CUDA toolchain: wires nvcc + support files from `cuda_toolkit`."""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

CUDA_TOOLCHAIN_TYPE = "@rules_cuda_toolkit//cuda:toolchain_type"

def use_cuda_toolchain():
    """Returns the toolchain types to request from a rule."""
    return [CUDA_TOOLCHAIN_TYPE]

def find_cuda_toolchain(ctx):
    """Returns the resolved `CudaToolchainInfo` for `ctx`."""
    return ctx.toolchains[CUDA_TOOLCHAIN_TYPE].cuda

CudaToolchainInfo = provider(
    doc = "Everything the compile/device-link actions need from the CUDA toolkit.",
    fields = {
        "nvcc": "File: the nvcc driver executable.",
        "compiler_files": "depset[File]: all files required to run nvcc (bin dir, cicc, ptxas, libdevice, headers).",
        "compile_ccinfo": "CcInfo: builtin CUDA headers merged for the compile action (exec cfg).",
        "runtime_ccinfo": "CcInfo: CUDA runtime libraries linked into dependents (target cfg).",
        "version_major": "str: CUDA major version, or \"\" if unknown.",
        "version_minor": "str: CUDA minor version, or \"\" if unknown.",
    },
)

def _cuda_toolchain_impl(ctx):
    compile_ccinfo = cc_common.merge_cc_infos(
        cc_infos = [d[CcInfo] for d in ctx.attr.compile_deps],
    )
    runtime_ccinfo = cc_common.merge_cc_infos(
        cc_infos = [d[CcInfo] for d in ctx.attr.runtime],
    )

    compiler_files = depset(
        ctx.files.nvcc + ctx.files.compiler_files,
        transitive = [compile_ccinfo.compilation_context.headers],
    )

    cuda = CudaToolchainInfo(
        nvcc = ctx.executable.nvcc,
        compiler_files = compiler_files,
        compile_ccinfo = compile_ccinfo,
        runtime_ccinfo = runtime_ccinfo,
        version_major = ctx.attr.version_major,
        version_minor = ctx.attr.version_minor,
    )

    return [platform_common.ToolchainInfo(cuda = cuda)]

cuda_toolchain = rule(
    doc = """Defines a CUDA toolchain backed by the hermetic `cuda_toolkit` module.

Instantiate one per exec/target platform and register it with
`register_toolchains`. See `//cuda:toolchains.bzl` for the
`cuda_toolkit_toolchain` convenience macro which fills the standard `@cuda`
targets in.
""",
    implementation = _cuda_toolchain_impl,
    attrs = {
        "nvcc": attr.label(
            doc = "The nvcc driver (e.g. `@cuda//nvcc:nvcc`).",
            mandatory = True,
            executable = True,
            allow_files = True,
            cfg = "exec",
        ),
        "compiler_files": attr.label(
            doc = "All files nvcc needs at runtime (e.g. `@cuda//nvcc:nvcc_directory`).",
            mandatory = True,
            allow_files = True,
            cfg = "exec",
        ),
        "compile_deps": attr.label_list(
            doc = "CUDA headers made available to every compile (e.g. `@cuda//cuda:cuda_headers`).",
            providers = [CcInfo],
            cfg = "exec",
        ),
        "runtime": attr.label_list(
            doc = "CUDA runtime libraries linked into dependents (e.g. `@cuda//cudart`).",
            providers = [CcInfo],
        ),
        "version_major": attr.string(),
        "version_minor": attr.string(),
    },
    provides = [platform_common.ToolchainInfo],
)
