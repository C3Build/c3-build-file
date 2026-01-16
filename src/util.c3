module util;

import std::io;
import std::os;
import std::collections::map;
import std::collections::list;
import regex;
import sema;
import node;

HashMap{String,int} versions;

fn void version_add(String version)
{
    versions.set(version, (int)versions.len());
}

fn void versions_init()
{
    version_add("0.7.0");
    version_add("0.7.1");
    version_add("0.7.2");
    version_add("0.7.3");
    version_add("0.7.4");
    version_add("0.7.5");
    version_add("0.7.6");
    version_add("0.7.7");
    version_add("0.7.8");
    version_add("0.7.9");
}

fn String get_compiler()
{
    $switch:
    $case env::WIN32:
        return "c3c.exe";
    $case env::DARWIN:
    $case env::LINUX:
        return "c3c";
    $endswitch
}

fn bool is_version_in_range(String min_version, String max_version, String version)
{
    int min_index     = versions.get(min_version)!!;
    int max_index     = versions.get(max_version)!!;
    int version_index = versions.get(version)!!;

    if (version_index < min_index) return false;
    if (version_index > max_index) return false;

    return true;
}

fn bool is_version_below(String max_version, String version)
{
    int max_index     = versions.get(max_version)!!;
    int version_index = versions.get(version)!!;

    if (version_index < max_index) return true;

    return false;
}

fn bool is_version_above(String min_version, String version)
{
    int min_index     = versions.get(min_version)!!;
    int version_index = versions.get(version)!!;

    if (version_index > min_index) return true;

    return false;
}

fn void? cpdir(String source, String dest)
{
    if (!source.len) return path::INVALID_PATH?;
    if (!dest.len)   return path::INVALID_PATH?;

    path::mkdir(dest)!;

    String* data = malloc(2 * String.sizeof);
    data[0] = source;
    data[1] = dest;

    path::traverse(source.to_path(mem), &traverse, data)!;

    free(data);
}

fn bool? traverse(Path path, bool is_dir, any data)
{
    String source = ((String*)data)[0];
    String dest   = ((String*)data)[1];

    if (is_dir)
    {
        path::mkdir(path.str_view().replace(mem, source, dest))!;
    } else
    {
        copy_file(path.str_view(), path.str_view().replace(mem, source, dest))!;
    }
    return false;
}

fn void? copy_file(String source, String dest)
{
    if (!source.len) return path::INVALID_PATH?;
    if (!dest.len)   return path::INVALID_PATH?;

    char[] data = file::load(mem, source)!;

    file::save(dest, data)!;

    io::printfn("[c3build] copied file `%s` -> `%s`", source, dest);
}

fn String format(String string, ProjectInfo* info)
{
    String result = string;
    Regex  regex  = &&regex::make_runtime_regex(`(?:\$\()([a-zA-Z0-9]+)(?:\))`, Options.NONE, mem)!!;
    MatchIterator iter = regex.iter_matches(string);

    while (try match = iter.next())
    {
        String var_name  = match[1].captured;
        if (!info.variables.has_key(var_name)) continue;
        String var_value = ((ZString)info.variables.get(var_name)).str_view()!!;
        String format    = string::format(mem, "$(%s)", var_name);
        
        result = result.replace(mem, format, var_value);
    }

    return result;
}

fn void add_files(List{ASTNode*} paths, ProjectInfo* info)
{
    foreach (node : paths)
    {
        String s_path = node.node.string_node.value;
        Path   path   = s_path.to_path(mem)!!;

        if (path::is_dir(path))
        {
            path::traverse(path, fn bool?(Path p, bool is_dir, data)
            {
                ProjectInfo* i = (ProjectInfo*)data;
                if (!is_dir)
                {
                    if (p.str_view().ends_with(".c3") ||
                        p.str_view().ends_with(".c3i"))
                    {
                        i.files.push(p.str_view().copy(mem));
                    }
                }

                return false;
            }, info)!!;
        } else
        {
            if (s_path.ends_with(".c3") ||
                s_path.ends_with(".c3i"))
            {
                info.files.push(path.absolute(mem).str_view())!!;
            }
        }
    }
}

fn String String.join(self, String other) => string::format(mem, "%s%s%s", self, path::PREFERRED_SEPARATOR, other);
