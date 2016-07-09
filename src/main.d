import std.random;
import std.datetime;
import std.stdio;
import std.conv;
import std.algorithm;
import std.array;
import std.regex;
import std.string;

import shogiban;
import move;
import testcode;

void main() {
  auto s = new Shogiban;
  s.writeln;

  //コマンド受付
  foreach (args; stdin.byLine.map !(a => a.chain(" (null)").to !string.strip.split))
    switch (args[0])
      mixin(strCommands);  //コマンドの展開
}

immutable string strCaseMain = q{
  case "init", "i":  //盤面の初期化
    s = new Shogiban;
    s.writeln;
    break;
  case "print", "p":  //盤面の表示
    s.writeln;
    break;
  case "quit", "q":  //終了
    return;
  case "help":  //ヘルプ(caseの表示)
  default:
    strCommandList.writeln;
    break;
};

//コンパイル時にファイル内を検索してコマンドっぽい文字列変数を収集して結合する
immutable string strCommands = mixin(import(__FILE__).strip.split.filter !(a => a.startsWith("strCase")).join("~"));
immutable string strCommandList = strCommands.split("\n").map !strip.filter !(a => a.startsWith("case")).map !(a => a[5.. $]).join("\n");
