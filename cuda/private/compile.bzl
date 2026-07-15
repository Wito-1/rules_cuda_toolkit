"""nvcc compile and device-link actions."""

load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":arch.bzl", "dlink_gencode_flags", "gencode_flags", "parse_archs")
load(":providers.bzl", "CudaArchsInfo", "CudaInfo")

# File extensions (without leading dot) that are compiled into objects, and
# those treated as headers.
COMPILE_EXTS = ["cu", "cc", "cpp", "cxx", "c"]
HEADER_EXTS = ["h", "hh", "hpp", "hxx", "cuh", "inc", "inl"]

# nvcc owns these flags; rejecting them keeps user copts from fighting the rule.
_RESERVED_COPTS = ["-c", "-o", "-dlink", "-rdc", "-x", "-gencode", "-arch", "--compile"]

def _validate_copts(kind, opts):
    for opt in opts:
        for reserved in _RESERVED_COPTS:
            if opt == reserved or opt.startswith(reserved + "="):
                fail("{} may not contain the rules_cuda_toolkit-managed flag \"{}\"".format(kind, opt))
    return opts

def _mode_flags(ctx):
    mode = ctx.var.get("COMPILATION_MODE", "fastbuild")
    if mode == "opt":
        return ["-O2", "-DNDEBUG"]
    if mode == "dbg":
        return ["-g", "-G"]
    return []

def _host_compiler(ctx, cc_toolchain):
    feature_config = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    return cc_common.get_tool_for_action(
        feature_configuration = feature_config,
        action_name = ACTION_NAMES.cpp_compile,
    )

def _nvcc_env(nvcc, host_compiler):
    # nvcc locates its own tools (cicc/ptxas/cudafe++) next to the driver and
    # invokes the host compiler through -ccbin. Give it a predictable PATH.
    path_dirs = [nvcc.dirname]
    if "/" in host_compiler:
        path_dirs.append(host_compiler.rsplit("/", 1)[0])
    path_dirs += ["/usr/local/bin", "/usr/bin", "/bin"]
    return {"PATH": ":".join(path_dirs)}

def resolve_arch_specs(ctx):
    """Per-target `archs` attr overrides the `//cuda:archs` build setting."""
    if ctx.attr.archs:
        return parse_archs(ctx.attr.archs)
    return ctx.attr._default_archs[CudaArchsInfo].arch_specs

# Flags in the host cc command line that nvcc must not receive (it manages the
# source/output/dependency handling itself, and these tokens carry values or
# gcc-isms clang rejects).
_DROP_HOST_FLAGS = ["-c", "-o", "-S", "-MD", "-MMD", "-MF", "-MT", "-MG", "-MP", "-fno-canonical-system-headers"]
_DROP_HOST_FLAG_PREFIXES = ["-frandom-seed", "-M"]
_HOST_PROBE_SRC = "cuda_host_flag_probe.cc"
_HOST_PROBE_OBJ = "cuda_host_flag_probe.o"

def _toolchain_host_flags(ctx, cc_toolchain):
    """Extracts the host C++ toolchain's default compile flags to forward to nvcc.

    nvcc invokes the host compiler bare through `-ccbin`, so it would otherwise
    miss the toolchain's `--sysroot`, builtin `-isystem` dirs, ABI flags, etc.
    We reconstruct the cc `c++-compile` command line and forward the survivors
    via `-Xcompiler`, keeping the build hermetic.
    """
    feature_config = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    compile_vars = cc_common.create_compile_variables(
        feature_configuration = feature_config,
        cc_toolchain = cc_toolchain,
        source_file = _HOST_PROBE_SRC,
        output_file = _HOST_PROBE_OBJ,
    )
    cmd = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_config,
        action_name = ACTION_NAMES.cpp_compile,
        variables = compile_vars,
    )

    flags = []
    skip_next = False
    for flag in cmd:
        if skip_next:
            skip_next = False
            continue
        if flag in (_HOST_PROBE_SRC, _HOST_PROBE_OBJ):
            continue
        if flag in ("-o", "-MF", "-MT"):
            skip_next = True
            continue
        if flag in _DROP_HOST_FLAGS:
            continue
        if [p for p in _DROP_HOST_FLAG_PREFIXES if flag.startswith(p)]:
            continue
        flags.append(flag)
    return flags

def create_common(ctx, cuda_toolchain, cc_toolchain):
    """Gathers deps/includes/defines/flags into a struct for the actions."""
    dep_cc_infos = [d[CcInfo] for d in ctx.attr.deps if CcInfo in d]
    all_cc_infos = dep_cc_infos + [cuda_toolchain.compile_ccinfo]
    merged_cc = cc_common.merge_cc_infos(
        direct_cc_infos = dep_cc_infos,
        cc_infos = [cuda_toolchain.compile_ccinfo],
    )
    cc_ctx = merged_cc.compilation_context

    # cc_common.merge_cc_infos drops `external_includes`, so collect it from the
    # unmerged contexts. Under the `external_include_paths` feature this is where
    # external repos' include dirs live (moved out of `includes`) -- including
    # the CUDA toolkit's own headers dir holding cuda_runtime.h.
    external_includes = depset(transitive = [
        ci.compilation_context.external_includes
        for ci in all_cc_infos
    ]).to_list()

    dep_defines = depset(
        ctx.attr.defines,
        transitive = [d[CudaInfo].defines for d in ctx.attr.deps if CudaInfo in d],
    )

    # Headers visible to the compile action: this target's hdrs + header-like
    # srcs + everything reachable through deps and the toolchain.
    direct_headers = ctx.files.hdrs + [f for f in ctx.files.srcs if f.extension in HEADER_EXTS]

    return struct(
        headers = depset(direct_headers, transitive = [cc_ctx.headers]),
        # nvcc has no `-iquote`; quote includes are merged into `-I`.
        includes = cc_ctx.includes.to_list() + cc_ctx.quote_includes.to_list() + ctx.attr.includes,
        # External-repo includes (see external_includes above) are emitted as
        # `-isystem`, matching what the external_include_paths feature does for
        # ordinary cc rules.
        system_includes = cc_ctx.system_includes.to_list() + external_includes,
        defines = dep_defines.to_list(),
        local_defines = ctx.attr.local_defines,
        compile_flags = _validate_copts("copts", ctx.attr.copts),
        host_compile_flags = ctx.attr.host_copts,
        toolchain_host_flags = _toolchain_host_flags(ctx, cc_toolchain),
        ptxas_flags = _validate_copts("ptxasopts", ctx.attr.ptxasopts),
        mode_flags = _mode_flags(ctx),
        gencode_flags = gencode_flags(resolve_arch_specs(ctx)),
        dlink_gencode_flags = dlink_gencode_flags(resolve_arch_specs(ctx)),
        dep_defines = dep_defines,
        transitive_linking_contexts =
            [ci.linking_context for ci in dep_cc_infos if ci.linking_context != None] +
            ([cuda_toolchain.runtime_ccinfo.linking_context] if cuda_toolchain.runtime_ccinfo.linking_context != None else []),
    )

def _obj_ext(pic, rdc):
    if rdc and pic:
        return ".rdc.pic.o"
    if rdc:
        return ".rdc.o"
    if pic:
        return ".pic.o"
    return ".o"

def compile_cuda(ctx, cuda_toolchain, cc_toolchain, srcs, common, pic, rdc):
    """Compiles each `.cu` in `srcs` to an object file; returns the list."""
    nvcc = cuda_toolchain.nvcc
    host_compiler = _host_compiler(ctx, cc_toolchain)
    env = _nvcc_env(nvcc, host_compiler)
    inputs = depset(
        srcs,
        transitive = [common.headers, cuda_toolchain.compiler_files, cc_toolchain.all_files],
    )

    objects = []
    seen = {}
    for src in srcs:
        # Disambiguate identical basenames coming from different directories.
        stem = src.basename
        count = seen.get(stem, 0)
        seen[stem] = count + 1
        if count:
            stem = "{}.{}".format(count, stem)
        obj = ctx.actions.declare_file(
            "_objs/{}/{}{}".format(ctx.label.name, stem, _obj_ext(pic, rdc)),
        )

        args = ctx.actions.args()
        args.add_all(["-x", "cu" if src.extension == "cu" else "c++"])
        args.add("-ccbin", host_compiler)
        args.add_all(common.gencode_flags)
        if rdc:
            args.add("-rdc=true")
        if pic:
            args.add_all(["-Xcompiler", "-fPIC"])
        args.add_all(common.mode_flags)
        args.add_all(common.system_includes, before_each = "-isystem")
        args.add_all(common.includes, format_each = "-I%s")
        args.add_all(common.defines, format_each = "-D%s")
        args.add_all(common.local_defines, format_each = "-D%s")
        args.add_all(common.compile_flags)
        args.add_all(common.toolchain_host_flags, before_each = "-Xcompiler")
        args.add_all(common.host_compile_flags, before_each = "-Xcompiler")
        args.add_all(common.ptxas_flags, before_each = "-Xptxas")
        args.add("-c", src)
        args.add("-o", obj)

        ctx.actions.run(
            executable = nvcc,
            arguments = [args],
            inputs = inputs,
            outputs = [obj],
            env = env,
            mnemonic = "CudaCompile",
            progress_message = "Compiling CUDA {}".format(src.short_path),
            toolchain = "@rules_cuda_toolkit//cuda:toolchain_type",
        )
        objects.append(obj)
    return objects

def device_link(ctx, cuda_toolchain, cc_toolchain, objects, common, pic):
    """Runs `nvcc -dlink` over `objects`, producing a single relocatable object."""
    nvcc = cuda_toolchain.nvcc
    host_compiler = _host_compiler(ctx, cc_toolchain)
    out = ctx.actions.declare_file(
        "_objs/{}/{}_dlink{}".format(ctx.label.name, ctx.label.name, ".pic.o" if pic else ".o"),
    )

    args = ctx.actions.args()
    args.add("-dlink")
    args.add("-ccbin", host_compiler)
    args.add_all(common.dlink_gencode_flags)
    if pic:
        args.add_all(["-Xcompiler", "-fPIC"])
    args.add_all(common.toolchain_host_flags, before_each = "-Xcompiler")
    args.add("-o", out)
    args.add_all(objects)

    ctx.actions.run(
        executable = nvcc,
        arguments = [args],
        inputs = depset(
            objects,
            transitive = [cuda_toolchain.compiler_files, cc_toolchain.all_files],
        ),
        outputs = [out],
        env = _nvcc_env(nvcc, host_compiler),
        mnemonic = "CudaDeviceLink",
        progress_message = "Device linking %{output}",
        toolchain = "@rules_cuda_toolkit//cuda:toolchain_type",
    )
    return out
