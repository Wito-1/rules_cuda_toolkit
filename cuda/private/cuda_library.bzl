"""The `cuda_library` rule."""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cpp_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":compile.bzl", "COMPILE_EXTS", "compile_cuda", "create_common", "device_link", "resolve_arch_specs")
load(":arch.bzl", "uses_rdc")
load(":providers.bzl", "CudaInfo", "create_cuda_info")
load(":toolchain.bzl", "CUDA_TOOLCHAIN_TYPE", "find_cuda_toolchain", "use_cuda_toolchain")

# Source/header extensions accepted by cuda_library.
_ALLOW_CUDA_SRCS = [".cu", ".cc", ".cpp", ".cxx", ".c"]
_ALLOW_CUDA_HDRS = [".h", ".hh", ".hpp", ".hxx", ".cuh", ".inc", ".inl"]

def _cuda_library_impl(ctx):
    cc_toolchain = find_cpp_toolchain(ctx)
    cuda_toolchain = find_cuda_toolchain(ctx)
    common = create_common(ctx, cuda_toolchain, cc_toolchain)

    src_files = [f for f in ctx.files.srcs if f.extension in COMPILE_EXTS]
    use_rdc = ctx.attr.rdc or uses_rdc(resolve_arch_specs(ctx))

    # Compile the sources. Non-RDC libraries compile both a PIC and a
    # non-PIC object so downstream static/shared links can pick either.
    if use_rdc:
        objects = []
        pic_objects = []
        rdc_objects = compile_cuda(ctx, cuda_toolchain, cc_toolchain, src_files, common, pic = False, rdc = True)
        rdc_pic_objects = compile_cuda(ctx, cuda_toolchain, cc_toolchain, src_files, common, pic = True, rdc = True)
        if rdc_objects:
            rdc_objects.append(device_link(ctx, cuda_toolchain, cc_toolchain, rdc_objects, common, pic = False))
        if rdc_pic_objects:
            rdc_pic_objects.append(device_link(ctx, cuda_toolchain, cc_toolchain, rdc_pic_objects, common, pic = True))
    else:
        objects = compile_cuda(ctx, cuda_toolchain, cc_toolchain, src_files, common, pic = False, rdc = False)
        pic_objects = compile_cuda(ctx, cuda_toolchain, cc_toolchain, src_files, common, pic = True, rdc = False)
        rdc_objects = []
        rdc_pic_objects = []

    archive_objects = objects + rdc_objects
    archive_pic_objects = pic_objects + rdc_pic_objects

    # Archive the objects into a (pic) static library and expose them as CcInfo
    # so ordinary cc_binary/cc_test/cc_library can link the CUDA code.
    cc_feature_config = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    compilation_ctx = cc_common.create_compilation_context(
        headers = common.headers,
        includes = depset(common.includes),
        system_includes = depset(common.system_includes),
        defines = depset(ctx.attr.host_defines),
        local_defines = depset(ctx.attr.host_local_defines),
    )
    linking_ctx, linking_outputs = cc_common.create_linking_context_from_compilation_outputs(
        name = ctx.label.name,
        actions = ctx.actions,
        feature_configuration = cc_feature_config,
        cc_toolchain = cc_toolchain,
        compilation_outputs = cc_common.create_compilation_outputs(
            objects = depset(archive_objects),
            pic_objects = depset(archive_pic_objects),
        ),
        user_link_flags = ctx.attr.host_linkopts,
        alwayslink = ctx.attr.alwayslink,
        linking_contexts = common.transitive_linking_contexts,
        disallow_dynamic_library = True,
    )

    lib = linking_outputs.library_to_link
    output_files = []
    if lib != None:
        if lib.static_library != None:
            output_files.append(lib.static_library)
        if lib.pic_static_library != None:
            output_files.append(lib.pic_static_library)

    cc_info = CcInfo(compilation_context = compilation_ctx, linking_context = linking_ctx)

    cuda_info = create_cuda_info(
        defines = common.dep_defines,
        objects = depset(objects),
        pic_objects = depset(pic_objects),
        rdc_objects = depset(rdc_objects),
        rdc_pic_objects = depset(rdc_pic_objects),
    )

    return [
        DefaultInfo(files = depset(output_files)),
        cc_info,
        cuda_info,
        OutputGroupInfo(
            objects = depset(objects),
            pic_objects = depset(pic_objects),
            rdc_objects = depset(rdc_objects),
            rdc_pic_objects = depset(rdc_pic_objects),
        ),
    ]

cuda_library = rule(
    doc = """Compiles CUDA (`.cu`) and C/C++ sources with nvcc into a static library.

Returns a `CcInfo` so the result links into any `cc_binary`, `cc_test` or
`cc_library`, plus a `CudaInfo` describing the relocatable object files for
device linking through `rdc = True`.
""",
    implementation = _cuda_library_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = _ALLOW_CUDA_SRCS + _ALLOW_CUDA_HDRS,
            doc = "CUDA (`.cu`) and C/C++ source files, plus private headers.",
        ),
        "hdrs": attr.label_list(
            allow_files = _ALLOW_CUDA_HDRS,
            doc = "Public headers made available to dependents.",
        ),
        "deps": attr.label_list(
            providers = [[CcInfo], [CudaInfo]],
            doc = "`cc_library`/`cuda_library` dependencies.",
        ),
        "includes": attr.string_list(doc = "Include dirs added as `-I` (package-relative)."),
        "copts": attr.string_list(doc = "Extra flags passed to nvcc (device compiler driver)."),
        "defines": attr.string_list(doc = "Device `-D` defines, also propagated to dependents."),
        "local_defines": attr.string_list(doc = "Device `-D` defines for this target only."),
        "host_copts": attr.string_list(doc = "Flags forwarded to the host compiler via `-Xcompiler`."),
        "host_defines": attr.string_list(doc = "Host `-D` defines exported through CcInfo."),
        "host_local_defines": attr.string_list(doc = "Host `-D` defines for this target only."),
        "host_linkopts": attr.string_list(doc = "Link flags exported through CcInfo."),
        "ptxasopts": attr.string_list(doc = "Flags forwarded to ptxas via `-Xptxas`."),
        "archs": attr.string(doc = "Per-target arch spec; overrides `//cuda:archs` when set."),
        "rdc": attr.bool(default = False, doc = "Enable relocatable device code + device linking."),
        "alwayslink": attr.bool(default = False, doc = "Keep every object at final link time."),
        "_default_archs": attr.label(default = "//cuda:archs"),
        "_cc_toolchain": attr.label(default = "@bazel_tools//tools/cpp:current_cc_toolchain"),
    },
    toolchains = use_cuda_toolchain() + use_cc_toolchain(),
    fragments = ["cpp"],
    provides = [DefaultInfo, CcInfo, CudaInfo],
)
