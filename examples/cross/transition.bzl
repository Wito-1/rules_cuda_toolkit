"""`build_for_platform`: build a target for a specific target platform.

Unlike the multi-version wrapper, this transitions ONLY the target platform,
not the execution platform — cross-compiling to aarch64 must keep nvcc and the
host compiler running on the x86_64 build host (exec configuration) while the
CUDA runtime and final binary are produced for aarch64 (target configuration).
"""

def _to_platform_impl(_settings, attr):
    return {"//command_line_option:platforms": [str(attr.platform)]}

_to_platform = transition(
    implementation = _to_platform_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _build_for_platform_impl(ctx):
    # Re-expose the transitioned target's default outputs so this target builds
    # `actual` for `platform` regardless of the command-line --platforms.
    return [DefaultInfo(files = ctx.attr.actual[0][DefaultInfo].files)]

build_for_platform = rule(
    doc = "Builds `actual` with `--platforms` set to `platform`.",
    implementation = _build_for_platform_impl,
    attrs = {
        "actual": attr.label(mandatory = True, cfg = _to_platform),
        "platform": attr.label(mandatory = True),
    },
)
