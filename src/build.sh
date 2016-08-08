#!/bin/bash
#ファイルの結合とヘッダの削除
cat *.d | sed 's/import .*//g' > tmpFile
#ヘッダの再作成
cat <<EOF > releaseDheader
import std.algorithm;
import std.array;
import std.ascii;
import std.compiler;
import std.conv;
import std.datetime;
import std.format;
import std.random;
import std.stdio;
import std.string;
import std.range;
import std.regex;
import core.simd;
import std.socket;
import core.thread;
import core.bitop;
version(LDC){
  import ldc.intrinsics;
  import ldc.gccbuiltins_x86;
}

EOF
cat releaseDheader tmpFile > releaseBinary.d
rm tmpFile releaseDheader

#dmd -w -ofd_shogi -m64 -inline -release -boundscheck=off -unittest -J. -O releaseBinary.d
#ldc2 -w -ofd_shogi -m64 -inline -release -boundscheck=off -unittest -J. -mcpu=x86-64 -mattr=+sse4.2 -O -O5 releaseBinary.d
#ldc2 -w -ofd_shogi -m64 -inline -release -boundscheck=off -unittest -J. -mcpu=haswell -O5 releaseBinary.d
ldc2 -w -ofd_shogi -m64 -release -boundscheck=off -unittest -J. -mcpu=x86-64 -mattr=+sse4.2,bmi,bmi2 -O5 releaseBinary.d

mv releaseBinary.d releaseBinary.d.bak
