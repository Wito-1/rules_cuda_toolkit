#ifndef RULES_CUDA_TOOLKIT_EXAMPLES_CUDNN_CONV_H_
#define RULES_CUDA_TOOLKIT_EXAMPLES_CUDNN_CONV_H_

// Creates a cuDNN handle and a small NCHW convolution pipeline (input, filter,
// convolution and output descriptors), queries the forward output dimensions
// and required workspace size, then tears everything down.
//
// Returns 0 on success or 1 on any cuDNN error. Requires a CUDA-capable GPU at
// run time (cudnnCreate initializes a CUDA context).
int ExerciseCudnnConvolution();

#endif  // RULES_CUDA_TOOLKIT_EXAMPLES_CUDNN_CONV_H_
