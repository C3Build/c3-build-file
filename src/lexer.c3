module lexer;

import token;
import std::collections::list, std::io, std::os;

fn Token[] lex(String content)
{
    int         line = 1;
    int         col  = 1;
    int         pos  = 0;
    List{Token} tokens;

    while (current(content, pos) != '\0')
    {
        while (current(content, pos).is_space())
        {
            col++;
            if (current(content, pos) == '\n' ||
                current(content, pos) == '\r')
            {
                col = 1;
                line++;
            }
            pos++;
        }
        
        if (current(content, pos) == '\0') break;

        int start = pos;

        if (current(content, pos) == '(') { tokens.push({ LPAREN, "(", { line, col } }); pos++; col++; }
        if (current(content, pos) == ')') { tokens.push({ RPAREN, ")", { line, col } }); pos++; col++; }
        if (current(content, pos) == '=') { tokens.push({ EQUALS, "=", { line, col } }); pos++; col++; }

        if (current(content, pos) == '-' && peek(content, pos) == '-')
        {
            while (current(content, pos) != '\n' && current(content, pos) != '\r') pos++;
        }

        if (current(content, pos) == '"')     tokens.push(string(content, &pos, line, &col));
        if (current(content, pos).is_digit()) tokens.push(version(content, &pos, line, &col));
        if (current(content, pos).is_alpha()) tokens.push(ident(content, &pos, line, &col));

        if (pos <= start && !current(content, pos).is_space() && current(content, pos) != '\0')
        {
            io::eprintfn("Undefined character `%s`[%d:%d]", (String){current(content, pos)}, line, col);
            os::exit(1);
        }
    }

    tokens.push({ EOF, "", { -1, -1 } });

    return tokens.to_array(mem);
}

fn Token string(String content, int* pos, int line, int* col) => @pool()
{
    DString result;
    result.tinit();
    int column = *col;

    *pos = *pos + 1;
    *col = *col + 1;

    while (current(content, *pos) != '"')
    {
        result.append_char(current(content, *pos));
        *pos = *pos + 1;
        *col = *col + 1;
    }

    *pos = *pos + 1;
    *col = *col + 1;

    return { STRING, result.copy_str(mem), { line, column } };
}

fn Token version(String content, int* pos, int line, int* col) => @pool()
{
    DString result;
    result.tinit();

    int column = *col;
    int dot_count = 0;
    
    while (current(content, *pos).is_digit())
    {
        result.append_char(current(content, *pos));
        *pos = *pos + 1;
        *col = *col + 1;
    }

    while (dot_count < 2)
    {
        result.append_char('.');
        *pos = *pos + 1;
        *col = *col + 1;
        dot_count = dot_count + 1;

        while (current(content, *pos).is_digit())
        {
            result.append_char(current(content, *pos));
            *pos = *pos + 1;
            *col = *col + 1;
        }
    }

    return { VERSION, result.copy_str(mem), { line, column } };
}

fn Token ident(String content, int* pos, int line, int* col) => @pool()
{
    DString result;
    result.tinit();

    int column = *col;

    while (current(content, *pos).is_alpha() ||
           current(content, *pos).is_digit() ||
           current(content, *pos) == '_')
    {
        result.append_char(current(content, *pos));
        *pos = *pos + 1;
        *col = *col + 1;
    }

    String value = result.copy_str(mem);

    switch (value)
    {
        case "VERSION":  return { KW_VERSION, value, { line, column } };
        case "MIN":      return { KW_MIN,     value, { line, column } };
        case "MAX":      return { KW_MAX,     value, { line, column } };
        case "LIB":      return { KW_LIB,     value, { line, column } };
        case "EXE":      return { KW_EXE,     value, { line, column } };
        case "LINK":     return { KW_LINK,    value, { line, column } };
        case "DIR":      return { KW_DIR,     value, { line, column } };
        case "FILE":     return { KW_FILE,    value, { line, column } };
        case "compiler": return { COMPILER,   value, { line, column } };
        case "project":  return { PROJECT,    value, { line, column } };
        case "require":  return { REQUIRE,    value, { line, column } };
        case "find":     return { FIND,       value, { line, column } };
        case "ifdef":    return { IFDEF,      value, { line, column } };
        case "endif":    return { ENDIF,      value, { line, column } };
        case "option":   return { OPTION,     value, { line, column } };
        case "task":     return { TASK,       value, { line, column } };
        case "endtask":  return { ENDTASK,    value, { line, column } };
        case "cmd":      return { CMD,        value, { line, column } };
        case "program":  return { PROGRAM,    value, { line, column } };
        case "create":   return { CREATE,     value, { line, column } };
        case "copy":     return { COPY,       value, { line, column } };
        case "print":    return { PRINT,      value, { line, column } };
        case "remove":   return { REMOVE,     value, { line, column } };
        case "add":      return { ADD,        value, { line, column } };
    }

    return { IDENT, value, { line, column } };
}

macro char current(content, pos) => pos < content.len ? content[pos]     : '\0';
macro char peek(content, pos)    => pos < content.len ? content[pos + 1] : '\0';
