"""`cuda_version_test`: run one test target under a specific CUDA version.

`cuda_toolkit` lets you register several CUDA versions; `@cuda` then resolves
per platform via a `@cuda//:cuda_<version>` constraint. This rule transitions
both the target platform **and** the execution platform to a version-pinned
platform, so the nvcc that compiles the test (an exec-configuration tool) and
the CUDA runtime it links (target configuration) both come from the same,
chosen toolkit. That lets the identical test source run against two toolkits.
"""

def _cuda_platform_transition_impl(_settings, attr):
    platform = str(attr.platform)
    return {
        "//command_line_option:platforms": [platform],
        "//command_line_option:extra_execution_platforms": [platform],
    }

_cuda_platform_transition = transition(
    implementation = _cuda_platform_transition_impl,
    inputs = [],
    outputs = [
        "//command_line_option:platforms",
        "//command_line_option:extra_execution_platforms",
    ],
)

def _cuda_version_test_impl(ctx):
    # Attributes with an attached transition are always lists (to support split
    # transitions); this 1:1 transition yields a single element.
    inner = ctx.attr.actual[0]
    inner_default = inner[DefaultInfo]
    wrapper = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = wrapper,
        target_file = inner_default.files_to_run.executable,
        is_executable = True,
    )
    runfiles = ctx.runfiles(files = [wrapper]).merge(inner_default.default_runfiles)
    providers = [DefaultInfo(executable = wrapper, runfiles = runfiles)]
    if RunEnvironmentInfo in inner:
        providers.append(inner[RunEnvironmentInfo])
    return providers

cuda_version_test = rule(
    doc = "Runs `actual` (a test/binary) under the CUDA version pinned by `platform`.",
    implementation = _cuda_version_test_impl,
    attrs = {
        "actual": attr.label(
            mandatory = True,
            executable = True,
            cfg = _cuda_platform_transition,
            doc = "The test or binary target to run under the pinned CUDA version.",
        ),
        "platform": attr.label(
            mandatory = True,
            doc = "A platform carrying the `@cuda//:cuda_<version>` constraint.",
        ),
    },
    test = True,
)
