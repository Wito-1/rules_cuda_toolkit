#include <cuda_runtime.h>
#include <cudnn.h>

#include "cudnn_conv.h"

namespace {

#define CHECK_CUDNN(expr)                       \
  do {                                          \
    if ((expr) != CUDNN_STATUS_SUCCESS) {       \
      return 1;                                 \
    }                                           \
  } while (0)

}  // namespace

int ExerciseCudnnConvolution() {
  cudnnHandle_t handle = nullptr;
  cudnnTensorDescriptor_t x = nullptr;
  cudnnTensorDescriptor_t y = nullptr;
  cudnnFilterDescriptor_t w = nullptr;
  cudnnConvolutionDescriptor_t conv = nullptr;

  CHECK_CUDNN(cudnnCreate(&handle));
  CHECK_CUDNN(cudnnCreateTensorDescriptor(&x));
  CHECK_CUDNN(cudnnCreateTensorDescriptor(&y));
  CHECK_CUDNN(cudnnCreateFilterDescriptor(&w));
  CHECK_CUDNN(cudnnCreateConvolutionDescriptor(&conv));

  CHECK_CUDNN(cudnnSetTensor4dDescriptor(x, CUDNN_TENSOR_NCHW, CUDNN_DATA_FLOAT,
                                         1, 1, 4, 4));
  CHECK_CUDNN(cudnnSetFilter4dDescriptor(w, CUDNN_DATA_FLOAT, CUDNN_TENSOR_NCHW,
                                         1, 1, 3, 3));
  CHECK_CUDNN(cudnnSetConvolution2dDescriptor(
      conv, 0, 0, 1, 1, 1, 1, CUDNN_CROSS_CORRELATION, CUDNN_DATA_FLOAT));

  int n = 0, c = 0, h = 0, ww = 0;
  CHECK_CUDNN(
      cudnnGetConvolution2dForwardOutputDim(conv, x, w, &n, &c, &h, &ww));
  CHECK_CUDNN(cudnnSetTensor4dDescriptor(y, CUDNN_TENSOR_NCHW, CUDNN_DATA_FLOAT,
                                         n, c, h, ww));

  size_t workspace = 0;
  CHECK_CUDNN(cudnnGetConvolutionForwardWorkspaceSize(
      handle, x, w, conv, y, CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_PRECOMP_GEMM,
      &workspace));

  cudnnDestroyConvolutionDescriptor(conv);
  cudnnDestroyFilterDescriptor(w);
  cudnnDestroyTensorDescriptor(y);
  cudnnDestroyTensorDescriptor(x);
  cudnnDestroy(handle);
  return 0;
}
