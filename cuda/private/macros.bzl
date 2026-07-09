"""`cuda_binary` and `cuda_test` macros.

Both wrap the device compilation in a hidden `cuda_library` (which owns nvcc
compilation + device linking and returns a `CcInfo`) and hand that library to a
plain `cc_binary` / `cc_test` for the final host link. The `host_*` attributes
map onto the C++ target so the executable's own compile/link flags are honored.
"""

load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_test.bzl", "cc_test")
load(":cuda_library.bzl", "cuda_library")

# Attributes consumed by the inner cuda_library.
_CUDA_LIBRARY_ATTRS = [
    "srcs",
    "hdrs",
    "deps",
    "includes",
    "copts",
    "defines",
    "local_defines",
    "host_copts",
    "host_defines",
    "host_local_defines",
    "host_linkopts",
    "ptxasopts",
    "archs",
    "rdc",
    "alwayslink",
]

# host_* attribute -> the cc_binary/cc_test attribute it maps to.
_HOST_ATTR_RENAMES = {
    "host_copts": "copts",
    "host_defines": "defines",
    "host_local_defines": "local_defines",
    "host_linkopts": "linkopts",
}

def _split_attrs(kwargs):
    lib_kwargs = {}
    cc_kwargs = {}
    for key, value in kwargs.items():
        if key in _CUDA_LIBRARY_ATTRS:
            lib_kwargs[key] = value
        else:
            cc_kwargs[key] = value

    # host_* flags belong on the final C++ target, so mirror them there.
    for host_attr, cc_attr in _HOST_ATTR_RENAMES.items():
        if host_attr in lib_kwargs:
            cc_kwargs[cc_attr] = cc_kwargs.get(cc_attr, []) + lib_kwargs[host_attr]
    return lib_kwargs, cc_kwargs

def _cuda_executable(cc_rule, name, testonly, kwargs):
    lib_kwargs, cc_kwargs = _split_attrs(kwargs)
    lib_name = "_" + name + "_cuda"

    # Default alwayslink so device symbols are not dropped during the host link.
    lib_kwargs.setdefault("alwayslink", True)

    cuda_library(
        name = lib_name,
        testonly = testonly,
        visibility = ["//visibility:private"],
        **lib_kwargs
    )

    cc_kwargs.setdefault("deps", [])
    cc_kwargs["deps"] = cc_kwargs["deps"] + [":" + lib_name]
    cc_rule(name = name, testonly = testonly, **cc_kwargs)

def cuda_binary(name, **kwargs):
    """Builds an executable from CUDA + C/C++ sources."""
    _cuda_executable(cc_binary, name, kwargs.pop("testonly", False), kwargs)

def cuda_test(name, **kwargs):
    """Builds a test executable from CUDA + C/C++ sources."""
    _cuda_executable(cc_test, name, kwargs.pop("testonly", True), kwargs)
