module c3_build;

import std::io;
import std::os;
import util;
import lexer;
import node;
import parser;
import sema;
import visitor;
import token;
import version;

fn int main(String[] args)
{
    if (args.len == 2)
    {
        if (args[1] == "--help" ||
            args[1] == "-h")
        {
            print_help(args[0]);
            return 0;
        }

        if (args[1] == "--version" ||
            args[1] == "-v")
        {
            print_version();
            return 0;
        }
    }

    util::versions_init();

    String? content = (String)file::load(mem, "C3BuildFile");
    if (catch content)
    {
        io::eprintn("Unable to find C3BuildFile");
        return 1;
    }

    Token[]    tokens = lexer::lex(content);
    ASTNode*[] nodes  = parser::parse(tokens);

    ProjectInfo info;

    info.variables.set("HOME",    path::home_directory(mem)!!.str_view().zstr_copy(mem));
    info.variables.set("PROJECT", null);
    info.variables.set("VERSION", null);
    info.variables.set("OS_WINDOWS", null);
    info.variables.set("OS_DARWIN", null);
    info.variables.set("OS_LINUX", null);
    
    $if env::WIN32:
        info.variables.set("OS_WINDOWS", "");
    $else $if env::DARWIN:
        info.variables.set("OS_DARWIN", "");
    $else $if env::LINUX:
        info.variables.set("OS_LINUX", "");
    $endif $endif $endif
    
    sema::analyse(nodes, &info);

    info.variables.set("PROJECT", info.name);
    info.variables.set("VERSION", info.version);

    if (info.name    == "" ||
        info.version == "")
    {
        io::eprint(Ansi.RED);
        io::eprint("[c3build] project not defined. >> aborting");
        io::eprintn(Ansi.RESET);
        return 1;
    }

    if (args.len > 1)
    {
        if (args[1] == "--tasks" ||
            args[1] == "-t")
        {
            print_tasks(info);
        } else
        if (args[1] == "--verbose" ||
            args[1] == "-vv")
        {
            info.verbose = true;
        } else if (!info.tasks.has_key(args[1]))
        {
            print_short_help(args[0]);
        }
    }

    visitor::visit(nodes, &info);

    if (args.len > 1)
    {
        bool all_exists = true;
        for (int i = 1; i < args.len; i++)
        {
            if (args[i].starts_with("-")) continue;
            if (!info.tasks.has_key(args[i]))
            {
                all_exists = false;
            }
        }

        if (!all_exists) print_short_help(args[0]);

        for (int i = 1; i < args.len; i++)
        {
            if (info.tasks.has_key(args[i]))
            {
                io::printfn("[c3build] Running Task `%s`", args[i]);
                visitor::visit(info.tasks.get(args[i])!!.to_array(mem), &info);
            }
        }
    }

    return 0;
}

fn void print_short_help(String program)
{
    io::printfn("Usage: %s --help|-h", program);
    os::exit(1);
}

fn void print_help(String program)
{
    io::printfn("Usage: %s [command] <task>", program);
    io::printn("Commands:");
    io::printn("  --help    -h       Shows usage help.");
    io::printn("  --tasks   -t       Shows tasks.");
    io::printn("  --version -v       Shows version info.");
    io::printn("  --verbose -vv      Prints compile command.");
    io::printn("  <task>           Runs the specified task.");
    os::exit(1);
}

fn void print_tasks(ProjectInfo info)
{
    io::printn("Tasks:");
    foreach (task : info.tasks.keys(mem))
    {
        io::printfn("  %s", task);
    }
    os::exit(0);
}

fn void print_version()
{
    io::printfn("Version:        %s", version::VERSION);
    $if $feature(GIT_HASH):
    io::printfn("Git Hash:       %s", version::GIT_HASH);
    $endif
}
