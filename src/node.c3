module node;

import std::collections::list;

enum NodeType
{
    STRING,
    VERSION,
    COMPILER,
    PROJECT,
    REQUIRE,
    FIND,
    IFDEF,
    OPTION,
    TASK,
    CMD,
    PROGRAM,
    CREATE,
    COPY,
    PRINT,
    REMOVE,
    ADD,
    VAR
}

enum VersionType
{
    EXACT,
    MIN,
    MAX,
    RANGE
}

struct ASTNode
{
    NodeType node_type;
    union node
    {
        StringNode   string_node;
        VersionNode  version_node;
        CompilerNode compiler_node;
        ProjectNode  project_node;
        RequireNode  require_node;
        FindNode     find_node;
        IfdefNode    ifdef_node;
        OptionNode   option_node;
        TaskNode     task_node;
        CmdNode      cmd_node;
        ProgramNode  program_node;
        CreateNode   create_node;
        CopyNode     copy_node;
        PrintNode    print_node;
        RemoveNode   remove_node;
        AddNode      add_node;
        VarNode      var_node;
    }
}

struct StringNode
{
    String value;
}

struct VersionNode
{
    VersionType type;
    union
    {
        String    exact_version;
        String    min_version;
        String    max_version;
        String[2] version_range;
    }
}

struct CompilerNode
{
    ASTNode* version;
}

struct ProjectNode
{
    String   name;
    ASTNode* version;
}

struct RequireNode
{
    String   type;
    ASTNode* name;
}

struct FindNode
{
    String   type;
    ASTNode* name;
}

struct IfdefNode
{
    String         cond;
    List{ASTNode*} body;
}

struct OptionNode
{
    ASTNode* option;
}

struct TaskNode
{
    ASTNode*       name;
    List{ASTNode*} body;
}

struct CmdNode
{
    ASTNode* cmd;
}

struct ProgramNode
{
    String       name;
    List{String} links;
}

struct CreateNode
{
    String   type;
    ASTNode* path;
}

struct CopyNode
{
    String   type;
    ASTNode* source;
    ASTNode* dest;
}

struct PrintNode
{
    ASTNode* string;
}

struct RemoveNode
{
    String   type;
    ASTNode* path;
}

struct AddNode
{
    List{ASTNode*} paths;
}

struct VarNode
{
    String   name;
    ASTNode* value;
}
