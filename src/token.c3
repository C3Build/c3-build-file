module token;

struct Token
{
    TokenType type;
    String    value;
    Range     range;
}

struct Range
{
    int line;
    int col;
}

enum TokenType : const inline String
{
    IDENT      = "identifier",
    VERSION    = "version",
    STRING     = "string",

    LPAREN     = "(",
    RPAREN     = ")",
    EQUALS     = "=",

    KW_VERSION = "VERSION",
    KW_MIN     = "MIN",
    KW_MAX     = "MAX",
    KW_LIB     = "LIB",
    KW_EXE     = "EXE",
    KW_LINK    = "LINK",
    KW_DIR     = "DIR",
    KW_FILE    = "FILE",

    COMPILER   = "compiler",
    PROJECT    = "project",
    REQUIRE    = "require",
    FIND       = "find",
    IFDEF      = "ifdef",
    OPTION     = "option",
    ENDIF      = "endif",
    TASK       = "task",
    CMD        = "cmd",
    ENDTASK    = "endtask",
    PROGRAM    = "program",
    CREATE     = "create",
    COPY       = "copy",
    PRINT      = "print",
    REMOVE     = "remove",
    ADD        = "add",

    EOF        = "EOF",
}
