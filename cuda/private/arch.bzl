"""Parsing of the CUDA architecture specification and `-gencode` generation.

The grammar follows nvcc's extended notation, matching what `rules_cuda`
accepts so that existing arch strings are portable:

    ARCH_SPECS   ::= ARCH_SPEC [ ';' ARCH_SPECS ]
    ARCH_SPEC    ::= [ VIRTUAL_ARCH ':' ] GPU_ARCHS
    GPU_ARCHS    ::= GPU_ARCH [ ',' GPU_ARCHS ]
    GPU_ARCH     ::= 'sm_' NUM | 'lto_' NUM | 'compute_' NUM
    VIRTUAL_ARCH ::= 'compute_' NUM | 'lto_' NUM

Examples:

- `sm_80`                    -> -gencode arch=compute_80,code=sm_80
- `compute_80:sm_80,sm_86`   -> two -gencode groups sharing compute_80 PTX
- `compute_80`               -> embed compute_80 PTX only
- `sm_80;sm_90`              -> two independent specs
- `native`                   -> -arch=native (build host GPU only, non-hermetic)
"""

load(":providers.bzl", "CudaArchsInfo")

def parse_archs(spec_str):
    """Parses an arch spec string into `"native"` or a list of structs.

    Each struct has:
      - `virtual`: the virtual arch number (str), used for `arch=compute_<n>`.
      - `gpus`: list of `struct(kind = "sm"|"compute"|"lto", num = str)`.
    """
    spec_str = spec_str.strip()
    if spec_str == "native":
        return "native"
    if not spec_str:
        fail("cuda archs specification must not be empty (got \"\")")

    specs = []
    for raw_spec in spec_str.split(";"):
        raw_spec = raw_spec.strip()
        if not raw_spec:
            continue

        virtual = None
        if ":" in raw_spec:
            virtual_str, gpus_str = raw_spec.split(":", 1)
            virtual = _arch_num(virtual_str.strip())
        else:
            gpus_str = raw_spec

        gpus = []
        min_num = None
        min_raw = None
        for raw_gpu in gpus_str.split(","):
            raw_gpu = raw_gpu.strip()
            if not raw_gpu:
                continue
            kind = _arch_kind(raw_gpu)
            num = _arch_num(raw_gpu)
            gpus.append(struct(kind = kind, num = num))
            n = _arch_int(num)
            if min_num == None or n < min_num:
                min_num = n
                min_raw = num

        if not gpus:
            fail("cuda arch spec \"{}\" does not list any GPU architectures".format(raw_spec))

        # When the virtual arch is omitted, nvcc uses the minimum requested arch,
        # preserving any accelerated-arch suffix (e.g. sm_90a -> compute_90a).
        if virtual == None:
            virtual = min_raw

        specs.append(struct(virtual = virtual, gpus = gpus))

    if not specs:
        fail("cuda archs specification \"{}\" produced no specs".format(spec_str))
    return specs

def _arch_kind(arch):
    kind = arch.split("_", 1)[0]
    if kind not in ("sm", "compute", "lto"):
        fail("unsupported cuda arch prefix in \"{}\" (expected sm_/compute_/lto_)".format(arch))
    return kind

def _arch_num(arch):
    parts = arch.split("_", 1)
    if len(parts) != 2 or not parts[1]:
        fail("malformed cuda arch \"{}\" (expected e.g. sm_80)".format(arch))
    return parts[1]

def _arch_int(num):
    # Numeric arch value with any trailing accelerated-arch suffix stripped (the
    # 'a'/'f' in sm_90a, sm_100f, ...), for magnitude comparison only. int()
    # cannot parse the suffixed form; the full suffixed string is preserved on
    # the gpu struct (and as the derived virtual arch) so gencode still emits
    # e.g. arch=compute_90a,code=sm_90a.
    digits = ""
    for ch in num.elems():
        if ch not in "0123456789":
            break
        digits += ch
    if not digits:
        fail("malformed cuda arch number \"{}\" (expected leading digits)".format(num))
    return int(digits)

def gencode_flags(specs):
    """Returns the nvcc `-gencode`/`-arch` flags for a compile action."""
    if specs == "native":
        return ["-arch=native"]
    flags = []
    for spec in specs:
        for gpu in spec.gpus:
            flags += [
                "-gencode",
                "arch=compute_{v},code={k}_{n}".format(v = spec.virtual, k = gpu.kind, n = gpu.num),
            ]
    return flags

def dlink_gencode_flags(specs):
    """Returns the nvcc `-gencode`/`-arch` flags for a device-link action.

    Device linking only targets real GPU (`sm_`/`lto_`) code; `compute_` PTX
    entries are lowered to their `sm_` equivalent.
    """
    if specs == "native":
        return ["-arch=native"]
    flags = []
    for spec in specs:
        for gpu in spec.gpus:
            code = "{}_{}".format("sm" if gpu.kind == "compute" else gpu.kind, gpu.num)
            flags += [
                "-gencode",
                "arch=compute_{v},code={c}".format(v = spec.virtual, c = code),
            ]
    return flags

def uses_rdc(specs):
    """Whether the arch spec requires relocatable device code (LTO archs do)."""
    if specs == "native":
        return False
    for spec in specs:
        for gpu in spec.gpus:
            if gpu.kind == "lto":
                return True
    return False

def _cuda_archs_flag_impl(ctx):
    return CudaArchsInfo(arch_specs = parse_archs(ctx.build_setting_value))

cuda_archs_flag = rule(
    doc = "Build setting controlling the default CUDA architectures to compile for.",
    implementation = _cuda_archs_flag_impl,
    build_setting = config.string(flag = True),
    provides = [CudaArchsInfo],
)
