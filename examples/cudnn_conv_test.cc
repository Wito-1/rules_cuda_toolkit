#include <cstdio>

#include "cudnn_conv.h"

// Exercises the cuDNN convolution descriptor pipeline. Requires a CUDA-capable
// GPU (cudnnCreate initializes a CUDA context); cuDNN's runtime shared libraries
// resolve thanks to the soname patch in //patches.
int main(int /*argc*/, char** /*argv*/) {
  int rc = ExerciseCudnnConvolution();
  std::printf("cuDNN convolution pipeline %s\n", rc == 0 ? "PASSED" : "FAILED");
  return rc;
}
