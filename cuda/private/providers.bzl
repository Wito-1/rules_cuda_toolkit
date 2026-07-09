"""Providers used by rules_cuda_toolkit."""

CudaInfo = provider(
    doc = """Information about the CUDA object files produced by a target.

Analogous to `CcInfo` but tracks the four flavors of relocatable object files
that nvcc can emit. It flows along `deps` so that an `rdc = True` library can
device-link the transitive closure of relocatable device code.
""",
    fields = {
        "defines": "depset[str]: device (`-D`) defines propagated to dependents.",
        "objects": "depset[File]: non-PIC, non-RDC object files.",
        "pic_objects": "depset[File]: PIC, non-RDC object files.",
        "rdc_objects": "depset[File]: non-PIC, relocatable-device-code object files.",
        "rdc_pic_objects": "depset[File]: PIC, relocatable-device-code object files.",
    },
)

CudaArchsInfo = provider(
    doc = "Parsed CUDA architecture specification (see `//cuda:archs`).",
    fields = {
        "arch_specs": "Either the string \"native\" or a list of parsed arch spec structs.",
    },
)

def create_cuda_info(defines = None, objects = None, pic_objects = None, rdc_objects = None, rdc_pic_objects = None):
    """Convenience constructor that defaults every field to an empty depset."""
    return CudaInfo(
        defines = defines if defines != None else depset([]),
        objects = objects if objects != None else depset([]),
        pic_objects = pic_objects if pic_objects != None else depset([]),
        rdc_objects = rdc_objects if rdc_objects != None else depset([]),
        rdc_pic_objects = rdc_pic_objects if rdc_pic_objects != None else depset([]),
    )
