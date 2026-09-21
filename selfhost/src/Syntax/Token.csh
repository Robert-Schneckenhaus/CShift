// Tokens of the CShift language.

namespace CShift.Syntax;

enum TokenKind : int32
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
    KwTrue, KwFalse, KwNull, KwThis, KwSizeof,

    // Punctuation
    LBrace, RBrace, LParen, RParen, LBracket, RBracket,
    Semi, Comma, Dot, Colon, Question, Arrow, Ellipsis,
    Plus, Minus, Star, Slash, Percent, Amp, Pipe, Caret, Tilde, Bang,
    Assign, Lt, Gt, EqEq, NotEq, LtEq, GtEq, AmpAmp, PipePipe, Shl,
    PlusAssign, MinusAssign, StarAssign, SlashAssign, PercentAssign,
    AmpAssign, PipeAssign, CaretAssign, ShlAssign
    // '>>' and '>>=' are not single tokens (generics use '>'); the parser joins adjacent '>' tokens.
}

struct Token
{
    TokenKind Kind;
    SourceLoc Loc;
    string Text;         // identifier name or decoded string literal
    uint64 IntValue;     // IntLit / CharLit
    double FloatValue;   // FloatLit
    bool IsUnsigned;
    bool IsLong;
    bool IsFloat32;
}

// Name of a token kind for the debug dump and for error messages.
string TokenName(TokenKind kind)
{
    switch (kind)
    {
    case TokenKind.Eof: return "end of file";
    case TokenKind.Ident: return "identifier";
    case TokenKind.IntLit: return "integer literal";
    case TokenKind.FloatLit: return "float literal";
    case TokenKind.CharLit: return "char literal";
    case TokenKind.StringLit: return "string literal";
    case TokenKind.LBrace: return "'{'";
    case TokenKind.RBrace: return "'}'";
    case TokenKind.LParen: return "'('";
    case TokenKind.RParen: return "')'";
    case TokenKind.LBracket: return "'['";
    case TokenKind.RBracket: return "']'";
    case TokenKind.Semi: return "';'";
    case TokenKind.Comma: return "','";
    case TokenKind.Dot: return "'.'";
    case TokenKind.Colon: return "':'";
    case TokenKind.Assign: return "'='";
    case TokenKind.Lt: return "'<'";
    case TokenKind.Gt: return "'>'";
    case TokenKind.KwIn: return "'in'";
    case TokenKind.KwWhile: return "'while'";
    case TokenKind.KwStruct: return "'struct'";
    default: return "token";
    }
}
