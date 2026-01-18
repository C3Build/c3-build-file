module sema;

import std::io;
import std::os;
import std::core::string::ansi;
import std::collections::map;
import std::collections::list;
import node;
import util;
import fs;
import regex;

struct ProjectInfo
{
    String                          name;
    String                          version;
    String                          author;
    HashMap{String, char*}          variables;
    HashMap{String, List{ASTNode*}} tasks;
    List{String}                    options;
    List{String}                    files;
    bool                            verbose;
}

fn void analyse(ASTNode*[] nodes, ProjectInfo* info)
{
    foreach (node : nodes)
    {
        analyse_node(node, info);
    }
}

fn void analyse_node(ASTNode* node, ProjectInfo* info)
{
    switch (node.node_type)
    {
        case COMPILER: analyse_compiler(node);
        case PROJECT:  analyse_project(node, info);
        case REQUIRE:  analyse_require(node, info);
        case FIND:     analyse_find(node, info);
        case IFDEF:    analyse_ifdef(node, info);
        case OPTION:   break;
        case TASK:     analyse_task(node, info);
        case REMOVE:   analyse_remove(node, info);
        case CREATE:   analyse_create(node, info);
        case COPY:     analyse_copy(node, info);
        case PROGRAM:  analyse_program(node, info);
        case STRING:   analyse_string(node, info);
        case ADD:      analyse_add(node, info);
        case PRINT:    analyse_print(node, info);
        case CMD:      analyse_cmd(node, info);
        case VAR:      analyse_var(node, info);
        default:       io::eprintfn("missing sema function >> %s", node.node_type);
    }
}

fn void analyse_compiler(ASTNode* node_in)
{
    CompilerNode node    = node_in.node.compiler_node;
    VersionNode  version = node.version.node.version_node;

    String version_string = $$VERSION;

    switch (version.type)
    {
        case VersionType.EXACT:
            if (version_string != version.exact_version)
            {
                io::eprint(Ansi.RED);
                io::eprint("[c3build] Compiler version does not match specified version.");
                io::eprintn(Ansi.RESET);
                os::exit(1);
            }
        case VersionType.MIN:
            if (util::is_version_below(version.min_version, version_string))
            {
                io::eprint(Ansi.RED);
                io::eprint("[c3build] Compiler version outside specified range.");
                io::eprintn(Ansi.RESET);
                os::exit(1);
            }
        case VersionType.MAX:
            if (util::is_version_above(version.max_version, version_string))
            {
                io::eprint(Ansi.RED);
                io::eprint("[c3build] Compiler version outside specified range");
                io::eprintn(Ansi.RESET);
                os::exit(1);
            }
        case VersionType.RANGE:
            if (!util::is_version_in_range(version.version_range[0], version.version_range[1], version_string))
            {
                io::eprint(Ansi.RED);
                io::eprint("[c3build] Compiler version outside specified range.");
                io::eprintn(Ansi.RESET);
                os::exit(1);
            }
    }
}

fn void analyse_project(ASTNode* node_in, ProjectInfo* info)
{
    ProjectNode node    = node_in.node.project_node;
    String      name    = node.name;

    if (info.name != "")
    {
        io::print(Ansi.YELLOW);
        io::print("[c3build] project already defined. >> skipping");
        io::printn(Ansi.RESET);
    } else
    {
        info.name    = name;
        info.version = node.version ? node.version.node.version_node.exact_version : "";
        info.author  = node.author ? node.author.node.string_node.value : "";
    }
}

fn void analyse_require(ASTNode* node_in, ProjectInfo* info)
{
    RequireNode node = node_in.node.require_node;
    String      type = node.type;
    String      name = node.name.node.string_node.value;

    Type filetype = enum_by_name(Type, type)!!;

    String  var_name  = string::format(mem, "%s_%s", type.to_lower_copy(mem), name.to_lower_copy(mem).replace(mem, "-", "_"));
    String? var_value = fs::find(name, filetype);

    if (catch var_value)
    {
        io::eprint(Ansi.RED);
        io::eprintf("[c3build] unable to locate %s `%s`. >> aborting", type, name);
        io::eprintn(Ansi.RESET);
        os::exit(1);
    }
    
    info.variables.set(var_name, var_value);
}

fn void analyse_find(ASTNode* node_in, ProjectInfo* info)
{
    FindNode node = node_in.node.find_node;
    String   type = node.type;
    String   name = node.name.node.string_node.value;

    Type filetype = enum_by_name(Type, type)!!;

    String  var_name  = string::format(mem, "%s_%s", type.to_lower_copy(mem), name.to_lower_copy(mem).replace(mem, "-", "_"));

    if (try var_value = fs::find(name, filetype))
    {
        info.variables.set(var_name, var_value);
    }
}

fn void analyse_ifdef(ASTNode* node_in, ProjectInfo* info)
{
    IfdefNode node = node_in.node.ifdef_node;
    String    cond = node.cond;

    if (!info.variables.has_key(cond))
    {
        io::eprint(Ansi.RED);
        io::eprintf("[c3build] could not find variable `%s`. >> aborting", cond);
        io::eprintn(Ansi.RESET);
        os::exit(1);
    }

    foreach (child : node.body)
    {
        analyse_node(child, info);
    }
}

fn void analyse_task(ASTNode* node_in, ProjectInfo* info)
{
    TaskNode node = node_in.node.task_node;
    String   name = node.name.node.string_node.value;

    if (info.tasks.has_key(name))
    {
        io::eprint(Ansi.RED);
        io::eprintf("[c3build] task `%s` already defined >> aboring", name);
        io::eprintn(Ansi.RESET);
        os::exit(1);
    }

    analyse(node.body.to_array(mem), info);

    info.tasks.set(name, {});
}

fn void analyse_program(ASTNode* node_in, ProjectInfo* info)
{
    ProgramNode node = node_in.node.program_node;
    String      name = node.name;

    if (info.name != name)
    {
        io::eprint(Ansi.RED);
        io::eprintf("[c3build] could not find project `%s`. >> aborting", name);
        io::eprintn(Ansi.RESET);
        os::exit(1);
    }

    foreach (link : node.links)
    {
        if (!info.variables.has_key(link))
        {
            io::eprint(Ansi.RED);
            io::eprintf("[c3build] could not find variable `%s`. >> aborting", link);
            io::eprintn(Ansi.RESET);
            os::exit(1);
        }
    }
}

fn void analyse_add(ASTNode* node_in, ProjectInfo* info)
{
    AddNode node = node_in.node.add_node;

    analyse(node.paths.to_array(mem), info);
}

fn void analyse_string(ASTNode* node_in, ProjectInfo* info)
{
    StringNode    node  = node_in.node.string_node;
    Regex         regex = &&regex::make_runtime_regex(`(?:\$\()([a-zA-Z0-9]+)(?:\))`, Options.NONE, mem)!!;
    MatchIterator iter  = regex.iter_matches(node.value);

    while (try match = iter.next())
    {
        String var_name = match[1].captured;

        if (!info.variables.has_key(var_name))
        {
            io::eprint(Ansi.RED);
            io::eprintf("[c3build] could not find variable `%s`.", var_name);
            io::eprintn(Ansi.RESET);
        }
    }
}

fn void analyse_remove(ASTNode* node_in, ProjectInfo* info)
{
    RemoveNode node = node_in.node.remove_node;

    analyse_node(node.path, info);
}

fn void analyse_create(ASTNode* node_in, ProjectInfo* info)
{
    CreateNode node = node_in.node.create_node;

    analyse_node(node.path, info);
}

fn void analyse_copy(ASTNode* node_in, ProjectInfo* info)
{
    CopyNode node = node_in.node.copy_node;

    analyse_node(node.source, info);
    analyse_node(node.dest, info);
}

fn void analyse_print(ASTNode* node_in, ProjectInfo* info)
{
    PrintNode node = node_in.node.print_node;

    analyse_node(node.string, info);
}

fn void analyse_cmd(ASTNode* node_in, ProjectInfo* info)
{
    CmdNode node = node_in.node.cmd_node;

    analyse_node(node.cmd, info);
}

fn void analyse_var(ASTNode* node_in, ProjectInfo* info)
{
    VarNode node  = node_in.node.var_node;
    String  value = node.value.node.string_node.value;
    
    if (info.variables.has_key(node.name))
    {
        io::eprint(Ansi.RED);
        io::eprintf("[c3build] variable `%s` already defined >> aborting", node.name);
        io::eprintn(Ansi.RESET);
        os::exit(1);
    }

    analyse_node(node.value, info);
    
    info.variables.set(node.name, null);
}
