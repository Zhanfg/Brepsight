# Third-party licenses

BrepSight source code in this repository is licensed under Apache-2.0 unless a file states otherwise.

## Application/toolchain dependencies

- **Flutter / Dart SDK** — used as the application framework and toolchain.
- **Android SDK / NDK** — used for the Android application, JNI, EGL, and OpenGL ES integration.

## Native engineering providers

### Open CASCADE Technology (OCCT)

OCCT is used by the optional exact-CAD provider. OCCT remains under its upstream LGPL-2.1 terms with the Open CASCADE exception and is not relicensed as BrepSight code. BrepSight builds it as shared Android libraries and keeps the provider optional so the open core does not depend on proprietary CAD Assistant binaries.

### lib3mf 2.5.0

BrepSight's optional 3MF provider uses **lib3mf v2.5.0**, pinned to upstream commit `64bb454d1fcb53effa57d3cef752a10d740d41a2`.

lib3mf is distributed under the following 2-clause BSD terms:

> Copyright (C) 2019 3MF Consortium
>
> All rights reserved.
>
> Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
>
> 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
> 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The generated lib3mf C++ binding headers retain the same upstream copyright/license notice. BrepSight does not relicense lib3mf itself.

## Reference-application boundary

Do not copy proprietary binaries, QML, assets, or business logic from the reference CAD Assistant APK into this repository. The old application is used only as behavioral/reference material for an independent clean implementation.
