#pragma once

#include <Standard_Handle.hxx>
#include <Standard_Version.hxx>

// BrepSight's Android SDK is pinned to OCCT 8.0+, where occ::handle is native.
// Ubuntu 24.04 currently ships OCCT 7.6.3; define only the new namespace alias
// for this host semantic smoke so the production importer source is exercised
// unchanged across both API generations.
#if OCC_VERSION_HEX < 0x080000
namespace occ {
template <class T>
using handle = opencascade::handle<T>;
}
#endif
