#pragma once

// Text dumps of the token list and of the syntax tree (cshiftc --dump-tokens / --dump-ast). They are used to check
// the CShift implementation of the front end (selfhost/) against this one: both must print the same text.

#include <ostream>

#include "AST.h"
#include "Lexer.h"

void dumpTokens(const std::vector<Token>& tokens, std::ostream& out);
void dumpUnit(const CompilationUnit& unit, std::ostream& out);
