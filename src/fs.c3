module fs;

import std::thread;
import std::collections::list;
import std::os::env;
import std::io::path;
import std::io::file;
import std::io::os;
import libc;

const THREAD_COUNT = 4;

faultdef
    EMPTY_RESULT;

enum Type
{
    LIB,
    EXE
}

struct SearchThreadData
{
    String   filename;
    String*  result;
    String[] dirs;
    int      start;
    int      end;
    bool     found;
    Type     type;
    Mutex*   mutex;
    int      score;
    String   match;
}

Mutex g_mutex;

fn String? find(String filename, Type type)
{
    String result;

    g_mutex.init()!;
    String[] dirs = get_search_dirs(type)!;

    if (dirs.len == 0)
    {
        g_mutex.destroy()!;
        return EMPTY_RESULT?;
    }

    SearchThreadData[THREAD_COUNT] thread_data;
    Thread[THREAD_COUNT] threads;

    int dirs_per_thread = dirs.len / THREAD_COUNT;
    int remaining_dirs  = dirs.len % THREAD_COUNT;
    int current_start   = 0;

    for (int i = 0; i < THREAD_COUNT; i++)
    {
        int thread_dir_count = dirs_per_thread + (i < remaining_dirs ? 1 : 0);
        thread_data[i].filename = filename;
        thread_data[i].result   = &result;
        thread_data[i].dirs     = dirs;
        thread_data[i].start    = current_start;
        thread_data[i].end      = current_start + thread_dir_count;
        thread_data[i].found    = false;
        thread_data[i].type     = type;
        thread_data[i].mutex    = &g_mutex;
        thread_data[i].score    = -1;
        thread_data[i].match    = "";

        threads[i].create(&search_thread, &thread_data[i])!;
    }

    for (int i = 0; i < THREAD_COUNT; i++)
    {
        threads[i].join()!;
    }

    g_mutex.destroy();

    return result;
}

fn String[]? get_search_dirs(Type type)
{
    List{String} dirs;

    if(type == LIB)
    {
        $if env::WIN32:
            dirs.push("C:\\Windows\\System32");
            dirs.push("C:\\Windows");
            dirs.push("C:\\Program Files");
            dirs.push("C:\\Program Files (x86)");
        $else $if env::LINUX:
            dirs.push("/usr/local/lib");
            dirs.push("/usr/lib/x86_64-linux-gnu");
            dirs.push("/usr/lib");
            dirs.push("/lib");
            dirs.push("/lib64");
        $else $if env::DARWIN:
            dirs.push("/usr/local/lib");
            dirs.push("/usr/lib");
            dirs.push("/Library");
            dirs.push("/System/Library");
            dirs.push("/opt/homebrew/lib");
        $endif $endif $endif
    } else
    {
        $if env::WIN32:
            dirs.push("C:\\Windows\\System32");
            dirs.push("C:\\Windows");
            dirs.push("C:\\Program Files");
            dirs.push("C:\\Program Files (x86)");
            dirs.push("C:\\");
        $else $if env::LINUX:
            dirs.push("/usr/local/bin");
            dirs.push("/usr/bin");
            dirs.push("/bin");
            dirs.push("/sbin");
            dirs.push("/usr/sbin");
            dirs.push("/usr/local/sbin");
            dirs.push("/snap/bin");
            dirs.push("/usr");
            dirs.push("/opt");
            dirs.push("/");
        $else $if env::DARWIN:
            dirs.push("/usr/local/bin");
            dirs.push("/usr/bin");
            dirs.push("/bin");
            dirs.push("/sbin");
            dirs.push("/usr/sbin");
            dirs.push("/opt/homebrew/bin");
            dirs.push("/opt/local/bin");
            dirs.push("/Applications");
            dirs.push("/usr");
            dirs.push("/opt");
        $endif $endif $endif
    }

    String path_env = env::get_var(mem, "PATH")!;
    $if env::WIN32:
        String[] vars = path_env.split(mem, ";");
    $else
        String[] vars = path_env.split(mem, ":");
    $endif
    dirs.push_all(vars);

    return dirs.to_array(mem);
}

fn int search_thread(void* arg) => @pool_init(mem, 1024)
{
    SearchThreadData* data         = (SearchThreadData*)arg;
    int               local_score  = -1;
    String            local_match  = "";
    String            local_result = "";

    for (int i = data.start; i < data.end; i++)
    {
        if (data.dirs[i] == "") break;

        int    score  = -1;
        String match  = "";
        String result = "";

        if (search_dir(data.filename, data.dirs[i], &result, data.type, &score, &match))
        {
            if (local_score == -1 ||
                score < local_score)
            {
                local_score  = score;
                local_match  = match;
                local_result = result;
            }
        }
    }

    if (local_score != -1)
    {
        g_mutex.lock()!!;
        if (data.score == -1 ||
            local_score < data.score)
        {
            data.score  = local_score;
            data.match  = local_match;
            *data.result = local_result;
        }
        g_mutex.unlock()!!;
    }

    return 0;
}

fn bool search_dir(String filename, String dir, String* result, Type type, int* score, String* match)
{
    if (filename == "" || dir == "" || !result) return false;

    String full_path = dir.join(filename);

    if (file::exists(full_path) &&
        check_file_type(full_path, type))
    {
        *result = full_path;
        *score  = 0;
        *match  = filename;
        return true;
    }

    bool found = false;

    PathList children = path::ls(mem, dir.to_path(mem), true, true)!!;
    foreach (path : children)
    {
        String s_path = path.str_view();
        if (s_path.contains(filename))
        {
            String found_path = dir.join(filename);
            if (file::exists(found_path) && check_file_type(found_path, type))
            {
                int distance = levenshtein_distance(found_path.file_basename(mem), filename)!!;

                if (*score == -1 || distance < *score)
                {
                    *score  = distance;
                    *match  = found_path.file_basename(mem)!!;
                    *result = found_path;
                    found = true;
                }
            }
        }
    }

    return found;
}

fn bool check_file_type(String path, Type type)
{
    if (type == LIB)
    {
        return is_shared_library(path);
    } else
    {
        return is_executable(path);
    }
}

fn bool is_shared_library(String path)
{
    String extension = path.to_path(mem).extension()!!;
    
    $if env::WIN32:
        return extension == "dll" || extension == "lib";
    $else $if env::DARWIN:
        return extension == "dylib" || extnesion.contains("so");
    $else
        return extension == "so" || extension.contains("so.");
    $endif $endif
}

fn bool is_executable(String path)
{
    $if env::WIN32:
        String   extension = path.to_path(mem).extension()!!;
        String[] exts      = { "exe", "bat", "cmd", "com", "msi" };
        foreach (ext : exts)
        {
            if (ext == extension) return true;
        }
    $else
        Stat stat;
        os::native_stat(&stat, path)!!;
        return true && stat.st_mode & libc::S_IXUSR;
    $endif
}

fn int levenshtein_distance(String s1, String s2)
{
    int  len1 = s1.len;
    int  len2 = s2.len;
    int* v0   = malloc((long)(len2 + 1) * int.sizeof);
    int* v1   = malloc((long)(len2 + 1) * int.sizeof);

    if (!v0 || !v1)
    {
        free(v0);
        free(v1);
        return int.max;
    }

    for (int i = 0; i <= len2; i++)
    {
        v0[i] = i;
    }

    for (int i = 0; i < len1; i++)
    {
        v1[0] = i + 1;

        for (int j = 0; j < len2; j++)
        {
            int deletion_cost     = v0[j + 1] + 1;
            int insertion_cost    = v1[j] + 1;
            int substitution_cost = v0[j] + (s1[i] != s2[j] ? 0 : 1);

            v1[j + 1] = (deletion_cost < insertion_cost) ?
                        (deletion_cost < substitution_cost ? deletion_cost : substitution_cost) :
                        (insertion_cost < substitution_cost ? insertion_cost : substitution_cost);
        }

        int* temp = v0;
        v0 = v1;
        v1 = temp;
    }

    int result = v0[len2];
    free(v0);
    free(v1);
    return result;
}
