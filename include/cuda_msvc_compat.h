#ifndef CUDA_MSVC_COMPAT_H
#define CUDA_MSVC_COMPAT_H

// Force-included into every NVCC host-compiler pass by the MSVC branch of
// CMakeLists.txt (--compiler-options /FI...). Nothing #includes it directly.
//
// It exists because MSVC toolsets outrun the versions a given CUDA release
// declares support for; the MSVC STL then refuses to compile under nvcc. The
// macros below switch off those gates. Built and used with MSVC 14.51 against
// CUDA 12.8.

#ifdef __CUDACC__
#define _ALLOW_KEYWORD_MACROS 1
#define _ALLOW_COMPILER_AND_STL_VERSION_MISMATCH 1
#define _ENABLE_EXTENDED_ALIGNED_STORAGE 1
#define _HAS_DEPRECATED_RESULT_OF 1
#define _SILENCE_CXX17_RESULT_OF_DEPRECATION_WARNING 1

// Required. Confirmed by removing it and rebuilding on 2026-08-02: ggml's
// argsort.cu then fails with five errors like
//
//   type_traits(1946): error: static assertion failed with
//     "result_of<CallableType> is invalid; ..."
//   functional(1194):  error: static assertion failed with
//     "std::function only accepts function types as template arguments."
//   utility(714):      error: static assertion failed with
//     "tuple index out of bounds"
//
// None of those are real. They sit in the *primary* template of
// _Get_function_impl, _Result_of and friends, written as static_assert(false,
// ...) on the assumption that the compiler only evaluates them once that
// primary template is actually instantiated. MSVC waits; nvcc's EDG front-end
// evaluates them while parsing, so they fire whether or not anything
// instantiates the bad specialisation. Including <functional> under nvcc is
// enough to trip it.
//
// So this is not the version gate -- _ALLOW_COMPILER_AND_STL_VERSION_MISMATCH
// above covers that -- and no narrower switch exists, because the preprocessor
// cannot tell an always-false STL assertion from a real one.
//
// The cost is real and worth restating: static_assert becomes a no-op in every
// translation unit nvcc compiles, ggml's CUDA kernels included. Genuine size,
// alignment and type checks there stop being checked, and a mismatch that
// should have been a compile error becomes runtime behaviour instead. Host-only
// translation units are unaffected: the whole file is behind __CUDACC__, so the
// CPU build never sees this.
//
// Revisit when either side moves -- a newer CUDA front-end, or an MSVC STL that
// guards these with a dependent-false idiom rather than a bare false.
#define static_assert(...)

#endif

#endif // CUDA_MSVC_COMPAT_H
