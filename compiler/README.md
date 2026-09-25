# compiler/: the C++ compiler (frozen)

This is the first CShift compiler, written in C++17 against the LLVM API. It is **frozen**: its only job is to be the
**stage 0** of the bootstrap, the program that compiles the self-hosted compiler ([../selfhost/](../selfhost/README.md))
from source when no `cshiftc` release is at hand. The released `cshiftc` is the self-hosted compiler
([../selfhost/build-release.sh](../selfhost/build-release.sh)).

What that means in practice:

* **No new features here.** Language features, standard-library features that need compiler support, new diagnostics
  and fixes to behavior go into `selfhost/` only. The test suite (`tests/run_tests.sh`) runs against the self-hosted
  compiler; test cases may use features that the C++ compiler does not know.
* **What must keep working:** the C++ compiler must be able to compile `selfhost/` and the standard library
  (`stdlib/`, which it embeds and which is the prelude of `selfhost/` while stage 0 builds it). So the sources of
  `selfhost/` and `stdlib/` stay within the language this compiler understands. `tests/run_tests.sh` checks it
  indirectly: with a stage 0 present (`build/cshiftc`), the front ends of both compilers must still agree
  (`selfhost/compare.sh`), and the release workflow builds stage 1 with it.
* **Allowed changes:** keeping it building with newer LLVM versions and fixing bugs that stop it from building
  `selfhost/`.

Once there are releases of the self-hosted compiler, a released `cshiftc` can serve as stage 0 instead, and
`selfhost/` may then use every feature that release knows. At that point this folder can be retired.
