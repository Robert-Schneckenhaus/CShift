#pragma once

#include "Common.h"

enum class Tok
{
    Eof,
    Ident,
    IntLit,
    FloatLit,
    CharLit,
    StringLit,

    // Keywords
    KwNamespace, KwUsing, KwStruct, KwInterface, KwEnum, KwExtern, KwUnsafe, KwUnchecked,
    KwIf, KwElse, KwWhile, KwDo, KwFor, KwForeach, KwIn, KwSwitch, KwCase, KwDefault,
    KwBreak, KwContinue, KwReturn, KwNew, KwTry, KwIs, KwWhere, KwConst, KwRef, KwStatic,
    KwTrue, KwFalse, KwNull, KwThis, KwSizeof, KwThread,

    // Punctuation
    LBrace, RBrace, LParen, RParen, LBracket, RBracket,
    Semi, Comma, Dot, Colon, Question, Arrow, Ellipsis,
    Plus, Minus, Star, Slash, Percent, Amp, Pipe, Caret, Tilde, Bang,
    Assign, Lt, Gt, EqEq, NotEq, LtEq, GtEq, AmpAmp, PipePipe, Shl,
    PlusAssign, MinusAssign, StarAssign, SlashAssign, PercentAssign,
    AmpAssign, PipeAssign, CaretAssign, ShlAssign,
    // Note: '>>' and '>>=' are not lexed as single tokens (generics use '>').
    // The parser joins adjacent '>' tokens.
};

struct Token
{
    Tok kind = Tok::Eof;
    SourceLoc loc;
    std::string text;      // identifier name or decoded string literal
    uint64_t intValue = 0; // IntLit / CharLit
    double floatValue = 0; // FloatLit
    bool isUnsigned = false;
    bool isLong = false;
    bool isFloat32 = false;
};

class Lexer
{
public:
    Lexer(const std::string& source, int fileId, Diagnostics& diag);
    std::vector<Token> tokenize();

private:
    char peek(size_t ahead = 0) const;
    char advance();
    bool atEnd() const { return pos >= src.size(); }
    SourceLoc here() const { return SourceLoc{fileId, line, col}; }

    void skipTrivia();
    Token lexNumber();
    Token lexString();
    Token lexChar();
    Token lexIdentifier();
    Token lexPunct();
    uint32_t lexEscape();
    static void appendUtf8(std::string& out, uint32_t codePoint);

    const std::string& src;
    int fileId;
    Diagnostics& diag;
    size_t pos = 0;
    int line = 1;
    int col = 1;
};

const char* tokenName(Tok kind);
