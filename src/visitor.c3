module visitor;

import std::io;
import std::collections::list;
import std::os::process;
import node;
import sema;
import util;
import regex;

fn void visit(ASTNode*[] nodes, ProjectInfo* info)
{
    foreach (node : nodes)
    {
        visit_node(node, info);
    }
}

fn void visit_node(ASTNode* node, ProjectInfo* info)
{
    switch (node.node_type)
    {
        case COMPILER: break;
        case PROJECT:  break;
        case REQUIRE:  break;
        case FIND:     break;
        case VAR:      break;
        case IFDEF:    visit_ifdef(node, info);
        case OPTION:   visit_option(node, info);
        case TASK:     visit_task(node, info);
        case REMOVE:   visit_remove(node, info);
        case CREATE:   visit_create(node, info);
        case PROGRAM:  visit_program(node, info);
        case COPY:     visit_copy(node, info);
        case PRINT:    visit_print(node, info);
        case ADD:      visit_add(node, info);
        case CMD:      visit_cmd(node, info);
        default:       io::printfn("missing visitor function >> %s", node.node_type);
    }
}

fn void visit_ifdef(ASTNode* node_in, ProjectInfo* info)
{
    IfdefNode node = node_in.node.ifdef_node;
    String    cond = node.cond;

    if (info.variables.get(cond)!!)
    {
        visit(node.body.to_array(mem), info);
    }
}

fn void visit_option(ASTNode* node_in, ProjectInfo* info)
{
    OptionNode node = node_in.node.option_node;
    String[]   args = node.option.node.string_node.value.split(mem, " ");

    info.options.push_all(args);
}

fn void visit_task(ASTNode* node_in, ProjectInfo* info)
{
    TaskNode node = node_in.node.task_node;
    String   name = node.name.node.string_node.value;

    info.tasks.set(name, node.body);
}

fn void visit_remove(ASTNode* node_in, ProjectInfo* info)
{
    RemoveNode node = node_in.node.remove_node;
    String     type = node.type;
    String     path = node.path.node.string_node.value;

    String f_path = util::format(path, info);
    
    switch (type)
    {
        case "DIR":
            if (catch result = path::rmtree(f_path.to_path(mem)))
            {
                io::printfn("[c3build] unable to delete directory `%s`: %s", f_path, result);
            } else
            {
                io::printfn("[c3build] deleted directory `%s`", f_path);
            }
        case "FILE":
            if (catch result = file::delete(path))
            {
                io::printfn("[c3build] unable to delete file `%s`: %s", f_path, result);
            } else
            {
                io::printfn("[c3build] deleted file `%s`", f_path);
            }
    }
}

fn void visit_create(ASTNode* node_in, ProjectInfo* info)
{
    CreateNode node = node_in.node.create_node;
    String     type = node.type;
    String     path = node.path.node.string_node.value;

    String f_path = util::format(path, info);
    
    switch (type)
    {
        case "DIR":
            if (catch result = path::mkdir(f_path, true))
            {
                io::printfn("[c3build] unable to create directory `%s`: %s", f_path, result);
            } else
            {
                io::printfn("[c3build] created directory `%s`", f_path);
            }
        case "FILE":
            if (catch result = file::save(f_path, ""))
            {
                io::printfn("[c3build] unable to create file `%s`: %s", f_path, result);
            } else
            {
                io::printfn("[c3build] created file `%s`", f_path);
            }
    }
}

fn void visit_program(ASTNode* node_in, ProjectInfo* info)
{
    ProgramNode node = node_in.node.program_node;

    List{String} command;
    command.push(util::get_compiler());
    command.push("compile");
    command.push("--linker=builtin");
    command.push("-o");
    command.push(string::format(mem, "build/%s", info.name));
    command.add_all(&info.options);
    command.add_all(&info.files);

    foreach (link : node.links)
    {
        command.push("-l");
        command.push(((ZString)info.variables.get(link)).str_view())!!;
    }

    if (info.verbose)
    {
        io::printn(string::join(mem, command.to_array(mem), " "));
    }

    io::printfn("[c3build] Compiling program `%s`", info.name);

    SubProcess? process = process::create(command.to_array(mem));
    if (catch process)
    {
        io::eprint(Ansi.RED);
        io::eprintf("[c3build] failed to create compile process.");
        io::eprintn(Ansi.RESET);
        os::exit(1);
    }

    const BUF_SIZE = 4096;
    char[BUF_SIZE] stdout_buf;
    char[BUF_SIZE] stderr_buf;

    if (catch process.read_stdout(&stdout_buf, BUF_SIZE))
    {
        io::eprintn("[c3build] Failed to read stderr from compile command.");
        os::exit(1);
    }

    if (catch process.read_stderr(&stderr_buf, BUF_SIZE))
    {
        io::eprintn("[c3build] Failed to read stderr from compile command.");
        os::exit(1);
    }

    if (((ZString)&stdout_buf) != "")
    {
        io::printn((ZString)&stdout_buf);
    }

    if (((ZString)&stderr_buf) != "")
    {
        io::eprintn((ZString)&stderr_buf);
    }
}

fn void visit_print(ASTNode* node_in, ProjectInfo* info)
{
    PrintNode node      = node_in.node.print_node;
    String    string    = node.string.node.string_node.value;
    String    formatted = util::format(string, info);

    io::print(Ansi.GREEN);
    io::printf("[c3build] PRINT >> %s", formatted);
    io::printn(Ansi.RESET);
}

fn void visit_copy(ASTNode* node_in, ProjectInfo* info)
{
    CopyNode node   = node_in.node.copy_node;
    String   type   = node.type;
    String   source = node.source.node.string_node.value;
    String   dest   = node.dest.node.string_node.value;

    String f_source = util::format(source, info);
    String f_dest   = util::format(dest, info);
    
    switch (type)
    {
        case "DIR":
            if (catch result = util::cpdir(f_source, f_dest))
            {
                io::printfn("[c3build] unable to copy directory `%s` -> `%s`: %s", f_source, f_dest, result);
            }
        case "FILE":
            if (catch result = util::copy_file(f_source, f_dest))
            {
                io::printfn("[c3build] unable to copy file `%s` -> `%s`: %s", f_source, f_dest, result);
            }
    }
}

fn void visit_add(ASTNode* node_in, ProjectInfo* info)
{
    AddNode node = node_in.node.add_node;

    util::add_files(node.paths, info);
}

fn void visit_cmd(ASTNode* node_in, ProjectInfo* info)
{
    CmdNode  node  = node_in.node.cmd_node;
    String   s_cmd = node.cmd.node.string_node.value;
    String   f_cmd = util::format(s_cmd, info);
    String[] cmd   = f_cmd.split(mem, " ");

    SubProcess? process = process::create(cmd);
    if (catch process)
    {
        io::eprint(Ansi.RED);
        io::eprintf("[c3build] failed to create compile process.");
        io::eprintn(Ansi.RESET);
        os::exit(1);
    }

    const BUF_SIZE = 1024;
    char[BUF_SIZE] stdout_buf;
    char[BUF_SIZE] stderr_buf;

    if (catch process.read_stdout(&stdout_buf, BUF_SIZE))
    {
        io::eprintn("[c3build] Failed to read stdout from compile command.");
        os::exit(1);
    }

    if (catch process.read_stderr(&stderr_buf, BUF_SIZE))
    {
        io::eprintn("[c3build] Failed to read stderr from compile command.");
        os::exit(1);
    }

    if (((ZString)&stdout_buf) != "")
    {
        io::eprintn((ZString)&stdout_buf);
    }

    if (((ZString)&stderr_buf) != "")
    {
        io::eprintn((ZString)&stderr_buf);
    }
}
