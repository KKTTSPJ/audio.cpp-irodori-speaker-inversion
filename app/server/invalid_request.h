#pragma once

#include <stdexcept>

namespace minitts::server {

// Thrown when a request is well-formed JSON but asks for something the server
// cannot honor -- e.g. a voice reference that names a file which does not
// exist. Mapped to HTTP 400 so the caller can tell its own mistake apart from
// a server-side failure, which surfaces as 500.
//
// Without this, a bare std::runtime_error would be caught by the generic
// handler in http.cpp and reported as 500 server_error.
class InvalidRequestError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

}  // namespace minitts::server
