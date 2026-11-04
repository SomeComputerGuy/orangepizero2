#!/usr/bin/env bash
# Build the ISO/IEC 14496-5 (Amd 5, 2004) MPEG-4 Visual reference decoder vm_dec on the host.
# Mirrors Fluster's build (fluendo/fluster PR #413: download_deps.py source fixes + compat headers +
# subprojects/packagefiles/mpeg4video/meson.build flags/sources), without meson.
# Input: iso-refsoft-dl/c039392_14496-5_Amd5_2004_refsoft.zip (ISO, licence accepted 2026-11-04).
# Output: iso-refsoft-dl/vm_dec. The ISO code stays in iso-refsoft-dl/ (git-ignored).
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)/iso-refsoft-dl
cd "$D"; rm -rf src compat; mkdir -p src compat
unzip -q c039392_14496-5_Amd5_2004_refsoft.zip 'C039392e Electronic inserts/microsoft-v2.5-040207-NTU/*' -d x
mv 'x/C039392e Electronic inserts/microsoft-v2.5-040207-NTU/'* src/; rm -rf x
# Fluster's source rewrites: drop forward declarations of iostream classes, ios::bin -> ios::binary
find src -type f \( -name '*.c' -o -name '*.cpp' -o -name '*.h' -o -name '*.hpp' \) -print0 | xargs -0 perl -0pi -e 's/^[ \t]*class[ \t]+(istream|ostream|ifstream|strstreambuf)[ \t]*;[ \t]*\r?\n//mg; s/\bios::bin\b/ios::binary/g'
for h in fstream iomanip ios iostream istream ostream strstream; do echo "#include <$h>" > compat/$h.h; done
cat > compat/compat.h <<'H'
/*
 * Fluster - testing framework for decoders conformance
 * Copyright (C) 2026, Fluendo, S.A.
 *
 * Force-included (-include) when building the MPEG-4 Visual reference software (vm_dec):
 * its pre-standard C++ uses iostream names without the std:: prefix.
 */

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <istream>
#include <ostream>
#include <string>
#include <strstream>

class CVideoObjectDecoder;
class CVideoObjectDecoderTPS;
class CEnhcBufferEncoder;

using std::cerr;
using std::cin;
using std::cout;
using std::dec;
using std::endl;
using std::ends;
using std::fixed;
using std::flush;
using std::fstream;
using std::hex;
using std::ifstream;
using std::ios;
using std::iostream;
using std::istream;
using std::istrstream;
using std::left;
using std::ofstream;
using std::oct;
using std::ostream;
using std::ostrstream;
using std::right;
using std::scientific;
using std::setfill;
using std::setprecision;
using std::setw;
using std::streambuf;
using std::streamoff;
using std::streampos;
using std::strstream;
using std::strstreambuf;
using std::ws;
H
SRCS="app/decoder/decoder.cpp sys/block.cpp sys/cae.cpp sys/dct.cpp sys/decoder/blkdec.cpp sys/decoder/bp_fgs_dec.cpp sys/decoder/errdec.cpp sys/decoder/mbdec.cpp sys/decoder/mbheaddec.cpp sys/decoder/mbinterlacedec.cpp sys/decoder/mcdec.cpp sys/decoder/mvdec.cpp sys/decoder/newpdec.cpp sys/decoder/rvlcdec.cpp sys/decoder/shpdec.cpp sys/decoder/sptdec.cpp sys/decoder/vopmbdec.cpp sys/decoder/vopsedec.cpp sys/error.cpp sys/gmc_motion.cpp sys/gmc_util.cpp sys/mb.cpp sys/mc.cpp sys/mcpad.cpp sys/mode.cpp sys/mv.cpp sys/newpred.cpp sys/rrv.cpp sys/shape.cpp sys/spt.cpp sys/tps_bfshape.cpp sys/tps_enhcbuf.cpp sys/vopses.cpp tools/entropy/bitstrm.cpp tools/entropy/huffman.cpp tools/sadct/sadct.cpp type/basic.cpp type/geom.cpp type/grayc.cpp type/grayf.cpp type/grayi.cpp type/svd.cpp type/typeapi.cpp type/vop.cpp type/warp.cpp type/yuvac.cpp type/yuvai.cpp vtc/main/seg.cpp vtc/main/vtcdec.cpp vtc/main/wavelet.cpp vtc/main/write_image.cpp vtc/pezw/PEZW_ac.cpp vtc/pezw/PEZW_globals.cpp vtc/pezw/PEZW_textureLayerBQ.cpp vtc/pezw/PEZW_utils.cpp vtc/pezw/wvtPEZW.cpp vtc/pezw/wvtpezw_tree_decode.cpp vtc/pezw/wvtpezw_tree_encode.cpp vtc/pezw/wvtpezw_tree_init_decode.cpp vtc/pezw/wvtpezw_tree_init_encode.cpp vtc/shape/BinArCodec.cpp vtc/shape/ShapeBaseCommon.cpp vtc/shape/ShapeBaseDecode.cpp vtc/shape/ShapeBaseEncode.cpp vtc/shape/ShapeDecoding.cpp vtc/shape/ShapeEncoding.cpp vtc/shape/ShapeEnhCommon.cpp vtc/shape/ShapeEnhDecode.cpp vtc/shape/ShapeEnhEncode.cpp vtc/shape/ShapeUtil.cpp vtc/wavelet/download_filter.cpp vtc/wavelet/dwt.cpp vtc/wavelet/dwt_aux.cpp vtc/wavelet/dwtmask.cpp vtc/wavelet/idwt.cpp vtc/wavelet/idwt_aux.cpp vtc/wavelet/idwtmask.cpp vtc/wavelet/imagebox.cpp vtc/zte/ac.cpp vtc/zte/bitpack.cpp vtc/zte/ztscanUtil.cpp vtc/zte/ztscan_dec.cpp vtc/ztq/QMInit.cpp vtc/ztq/QMUtils.cpp vtc/ztq/Utils.cpp vtc/ztq/decQM.cpp vtc/ztq/errorHandler.cpp vtc/ztq/msg.cpp vtc/ztq/quant.cpp "
INC="-Isrc/sys -Isrc/sys/encoder -Isrc/sys/decoder -Isrc/type -Isrc/tools -Isrc/tools/entropy -Isrc/vtc/include -Isrc/vtc/ztq -Isrc/vtc/zte -Isrc/vtc/wavelet -Isrc/vtc/pezw -Isrc/vtc/shape"
FLAGS="-std=gnu++98 -O2 -w -D_VTC_DECODER_ -D_ERSSP_ -D__DOUBLE_PRECISION_ -D_OBSS_ -DFGSPOSTCLIP -fpermissive -fno-operator-names -Icompat -include compat/compat.h"
mkdir -p obj; export INC FLAGS
printf '%s\n' $SRCS | xargs -P"$(nproc)" -I{} sh -c 'o=obj/$(echo {} | tr / _).o; g++ $FLAGS $INC -c src/{} -o $o'
g++ -o vm_dec obj/*.o -lm
echo "built $D/vm_dec"; ./vm_dec 2>&1 | head -3 || true
