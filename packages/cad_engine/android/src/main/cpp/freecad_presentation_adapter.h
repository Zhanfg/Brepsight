#pragma once

#include <string>

#include "freecad_fcstd_importer.h"

namespace brepsight {

// Maps the provider-specific FCStd object payload into BrepSight's
// provider-neutral mesh presentation state, then validates and refreshes it.
bool attachFcStdObjectPresentation(FcStdImportResult& fcstd, std::string& error);

}  // namespace brepsight
