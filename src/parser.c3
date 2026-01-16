module parser;

import std::collections::list;
import std::os;
import std::io;
import node, token;

fn ASTNode*[] parse(Token[] tokens)
{
    int pos = 0;
    List{ASTNode*} children;

    while (current(tokens, pos).type != EOF)
    {
        children.push(parse_stmt(tokens, &pos));
    }

    consume(tokens, &pos, TokenType.EOF);

    return children.to_array(mem);
}

fn ASTNode* parse_stmt(Token[] tokens, int* pos)
{
    switch (current(tokens, *pos).type)
    {
        case COMPILER: return parse_compiler(tokens, pos);
        case PROJECT:  return parse_project(tokens, pos);
        case REQUIRE:  return parse_require(tokens, pos);
        case FIND:     return parse_find(tokens, pos);
        case IFDEF:    return parse_ifdef(tokens, pos);
        case OPTION:   return parse_option(tokens, pos);
        case TASK:     return parse_task(tokens, pos);
        case CMD:      return parse_cmd(tokens, pos);
        case PROGRAM:  return parse_program(tokens, pos);
        case CREATE:   return parse_create(tokens, pos);
        case COPY:     return parse_copy(tokens, pos);
        case PRINT:    return parse_print(tokens, pos);
        case REMOVE:   return parse_remove(tokens, pos);
        case ADD:      return parse_add(tokens, pos);
        case IDENT:    return parse_ident(tokens, pos);
        default:       consume(tokens, pos, TokenType.EOF);
    }

    return null;
}

fn ASTNode* parse_compiler(Token[] tokens, int* pos)
{
    ASTNode* node    = malloc(ASTNode.sizeof);
    ASTNode* version = malloc(ASTNode.sizeof);

    consume(tokens, pos, TokenType.COMPILER);
    consume(tokens, pos, TokenType.LPAREN);
    consume(tokens, pos, TokenType.KW_VERSION);

    if (current(tokens, *pos).type == TokenType.VERSION)
    {
        *version = { NodeType.VERSION, { .version_node = { .type = VersionType.EXACT, .exact_version = current(tokens, *pos).value } } };
    
        consume(tokens, pos, TokenType.VERSION);
    } else if (current(tokens, *pos).type == TokenType.KW_MIN)
    {
        consume(tokens, pos, TokenType.KW_MIN);

        Token min_token = current(tokens, *pos);

        consume(tokens, pos, TokenType.VERSION);

        if (current(tokens, *pos).type == TokenType.KW_MAX)
        {
            consume(tokens, pos, TokenType.KW_MAX);
            
            *version = { NodeType.VERSION, { .version_node = { .type = VersionType.RANGE, .version_range = (String[2]){ min_token.value, current(tokens, *pos).value } } } };
        
            consume(tokens, pos, TokenType.VERSION);
        } else
        {
            *version = { NodeType.VERSION, { .version_node = { .type = VersionType.MIN, .min_version = min_token.value } } };
        }
    } else if (current(tokens, *pos).type == TokenType.KW_MAX)
    {
        consume(tokens, pos, TokenType.KW_MAX);
        
        *version = { NodeType.VERSION, { .version_node = { .type = VersionType.MAX, .max_version = current(tokens, *pos).value } } };
        
        consume(tokens, pos, TokenType.VERSION);
    }

    consume(tokens, pos, TokenType.RPAREN);

    *node = { NodeType.COMPILER, { .compiler_node = { version } } };
    return node;
}

fn ASTNode* parse_project(Token[] tokens, int* pos)
{
    ASTNode* node    = malloc(ASTNode.sizeof);
    ASTNode* version = malloc(ASTNode.sizeof);

    consume(tokens, pos, TokenType.PROJECT);
    consume(tokens, pos, TokenType.LPAREN);

    String name = current(tokens, *pos).value;

    consume(tokens, pos, TokenType.IDENT);
    consume(tokens, pos, TokenType.KW_VERSION);

    *version = { NodeType.VERSION, { .version_node = { .type = VersionType.EXACT, .exact_version = current(tokens, *pos).value } } };

    consume(tokens, pos, TokenType.VERSION);
    consume(tokens, pos, TokenType.RPAREN);

    *node = { NodeType.PROJECT, { .project_node = { name, version } } };
    return node;
}

fn ASTNode* parse_require(Token[] tokens, int* pos)
{
    ASTNode* node = malloc(ASTNode.sizeof);

    consume(tokens, pos, TokenType.REQUIRE);
    consume(tokens, pos, TokenType.LPAREN);

    String type;
    if (current(tokens, *pos).type == TokenType.KW_LIB ||
        current(tokens, *pos).type == TokenType.KW_EXE)
    {
        type = current(tokens, *pos).value;
        consume(tokens, pos, current(tokens, *pos).type);
    }

    ASTNode* name = parse_string(tokens, pos);

    consume(tokens, pos, TokenType.RPAREN);

    *node = { NodeType.REQUIRE, { .require_node = { type, name } } };
    return node;
}

fn ASTNode* parse_find(Token[] tokens, int* pos)
{
    ASTNode* node = malloc(ASTNode.sizeof);

    consume(tokens, pos, TokenType.FIND);
    consume(tokens, pos, TokenType.LPAREN);

    String type;
    if (current(tokens, *pos).type == TokenType.KW_LIB ||
        current(tokens, *pos).type == TokenType.KW_EXE)
    {
        type = current(tokens, *pos).value;
        consume(tokens, pos, current(tokens, *pos).type);
    }

    ASTNode* name = parse_string(tokens, pos);

    consume(tokens, pos, TokenType.RPAREN);

    *node = { NodeType.FIND, { .find_node = { type, name } } };
    return node;
}

fn ASTNode* parse_ifdef(Token[] tokens, int* pos)
{
    ASTNode* node = malloc(ASTNode.sizeof);

    consume(tokens, pos, TokenType.IFDEF);
    consume(tokens, pos, TokenType.LPAREN);

    String cond = current(tokens, *pos).value;

    consume(tokens, pos, TokenType.IDENT);
    consume(tokens, pos, TokenType.RPAREN);

    List{ASTNode*} body;
    while (current(tokens, *pos).type != TokenType.ENDIF)
    {
        body.push(parse_stmt(tokens, pos));
    }

    consume(tokens, pos, TokenType.ENDIF);
    consume(tokens, pos, TokenType.LPAREN);
    consume(tokens, pos, TokenType.RPAREN);

    *node = { NodeType.IFDEF, { .ifdef_node = { cond, body } }};
    return node;
}

fn ASTNode* parse_option(Token[] tokens, int* pos)
{
    ASTNode* node = malloc(ASTNode.sizeof);

    consume(tokens, pos, TokenType.OPTION);
    consume(tokens, pos, TokenType.LPAREN);

    ASTNode* option = parse_string(tokens, pos);

    consume(tokens, pos, TokenType.RPAREN);

    *node = { NodeType.OPTION, { .option_node = { option } } };
    return node;
}

fn ASTNode* parse_task(Token[] tokens, int* pos)
{
    ASTNode* node = malloc(ASTNode.sizeof);

    consume(tokens, pos, TokenType.TASK);
    consume(tokens, pos, TokenType.LPAREN);

    ASTNode* name = parse_string(tokens, pos);

    consume(tokens, pos, TokenType.RPAREN);

    List{ASTNode*} body;
    while (current(tokens, *pos).type != TokenType.ENDTASK)
    {
        body.push(parse_stmt(tokens, pos));
    }

    consume(tokens, pos, TokenType.ENDTASK);
    consume(tokens, pos, TokenType.LPAREN);
    consume(tokens, pos, TokenType.RPAREN);

    *node = { NodeType.TASK, { .task_node = { name, body } }};
    return node;
}

fn ASTNode* parse_cmd(Token[] tokens, int* pos)
{
    ASTNode* node = malloc(ASTNode.sizeof);

    consume(tokens, pos, TokenType.CMD);
    consume(tokens, pos, TokenType.LPAREN);

    ASTNode* cmd = parse_string(tokens, pos);

    consume(tokens, pos, TokenType.RPAREN);

    *node = { NodeType.CMD, { .cmd_node = { cmd } } };
    return node;
}

fn ASTNode* parse_print(Token[] tokens, int* pos)
{
    ASTNode* node = malloc(ASTNode.sizeof);

    consume(tokens, pos, TokenType.PRINT);
    consume(tokens, pos, TokenType.LPAREN);

    ASTNode* string = parse_string(tokens, pos);

    consume(tokens, pos, TokenType.RPAREN);

    *node = { NodeType.PRINT, { .print_node = { string } } };
    return node;
}

fn ASTNode* parse_create(Token[] tokens, int* pos)
{
    ASTNode* node = malloc(ASTNode.sizeof);

    consume(tokens, pos, TokenType.CREATE);
    consume(tokens, pos, TokenType.LPAREN);

    String type;
    if (current(tokens, *pos).type == TokenType.KW_DIR ||
        current(tokens, *pos).type == TokenType.KW_FILE)
    {
        type = current(tokens, *pos).value;
        consume(tokens, pos, current(tokens, *pos).type);
    }

    ASTNode* path = parse_string(tokens, pos);

    consume(tokens, pos, TokenType.RPAREN);

    *node = { NodeType.CREATE, { .create_node = { type, path } } };
    return node;
}

fn ASTNode* parse_copy(Token[] tokens, int* pos)
{
    ASTNode* node = malloc(ASTNode.sizeof);

    consume(tokens, pos, TokenType.COPY);
    consume(tokens, pos, TokenType.LPAREN);

    String type;
    if (current(tokens, *pos).type == TokenType.KW_DIR ||
        current(tokens, *pos).type == TokenType.KW_FILE)
    {
        type = current(tokens, *pos).value;
        consume(tokens, pos, current(tokens, *pos).type);
    }

    ASTNode* source      = parse_string(tokens, pos);
    ASTNode* destination = parse_string(tokens, pos);

    consume(tokens, pos, TokenType.RPAREN);

    *node = { NodeType.COPY, { .copy_node = { type, source, destination } } };
    return node;
}

fn ASTNode* parse_remove(Token[] tokens, int* pos)
{
    ASTNode* node = malloc(ASTNode.sizeof);

    consume(tokens, pos, TokenType.REMOVE);
    consume(tokens, pos, TokenType.LPAREN);

    String type;
    if (current(tokens, *pos).type == TokenType.KW_DIR ||
        current(tokens, *pos).type == TokenType.KW_FILE)
    {
        type = current(tokens, *pos).value;
        consume(tokens, pos, current(tokens, *pos).type);
    }

    ASTNode* path = parse_string(tokens, pos);

    consume(tokens, pos, TokenType.RPAREN);

    *node = { NodeType.REMOVE, { .remove_node = { type, path } } };
    return node;
}

fn ASTNode* parse_program(Token[] tokens, int* pos)
{
    ASTNode* node = malloc(ASTNode.sizeof);

    consume(tokens, pos, TokenType.PROGRAM);
    consume(tokens, pos, TokenType.LPAREN);

    String name = current(tokens, *pos).value;
    consume(tokens, pos, TokenType.IDENT);

    List{String} links;
    if (current(tokens, *pos).type == TokenType.KW_LINK)
    {
        consume(tokens, pos, TokenType.KW_LINK);
        while (current(tokens, *pos).type == TokenType.IDENT)
        {
            links.push(current(tokens, *pos).value);
            consume(tokens, pos, TokenType.IDENT);
        }
    }

    consume(tokens, pos, TokenType.RPAREN);

    *node = { NodeType.PROGRAM, { .program_node = { name, links } } };
    return node;
}

fn ASTNode* parse_add(Token[] tokens, int* pos)
{
    ASTNode* node = malloc(ASTNode.sizeof);

    consume(tokens, pos, TokenType.ADD);
    consume(tokens, pos, TokenType.LPAREN);

    List{ASTNode*} paths;
    paths.push(parse_string(tokens, pos));

    while (current(tokens, *pos).type == TokenType.STRING)
    {
        paths.push(parse_string(tokens, pos));
    }

    consume(tokens, pos, TokenType.RPAREN);

    *node = { NodeType.ADD, { .add_node = { paths } } };
    return node;
}

fn ASTNode* parse_ident(Token[] tokens, int* pos)
{
    ASTNode* node = malloc(ASTNode.sizeof);
    String   name = current(tokens, *pos).value;

    consume(tokens, pos, TokenType.IDENT);
    consume(tokens, pos, TokenType.EQUALS);

    ASTNode* value = parse_string(tokens, pos);

    *node = { NodeType.VAR, { .var_node = { name, value } } };
    return node;
}

fn ASTNode* parse_string(Token[] tokens, int* pos)
{
    ASTNode* node = malloc(ASTNode.sizeof);

    *node = { NodeType.STRING, { .string_node = { current(tokens, *pos).value } } };
    consume(tokens, pos, TokenType.STRING);

    return node;
}

macro Token current(tokens, int pos) => tokens[pos];
macro Token peek(tokens, int pos)    => tokens[pos + 1];
macro consume(tokens, int* pos, TokenType type)
{
    Token token = tokens[*pos];

    if (token.type != type)
    {
        io::eprintfn("Unexpected token `%s`, expected `%s`[%d:%d]", token.type, type, token.range.line, token.range.col);
        os::exit(1);
    }
    
    *pos = *pos + 1;
}
