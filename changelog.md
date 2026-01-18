# 0.3.2
- add bootstrap scripts
- update string lexing logic
- update buildscript for project
- fixed `fs::is_executable` for windows
- fixed getting git hash on windows
- fixed regex for injecting variables in `util::format`
- fixed file deletion using unformatted path

# 0.3.1
- add log for `cmd` statememnt

# 0.3.0
- add `AUTHOR` section to project definition
- add variable injection for `AUTHOR` and `VERSION`

# 0.2.1
- fixed crash due to panic on other thread than main thread
- add `--version` to display version and git hash
- fixed bug in file find logic where the seperator char was inserted as ASCII

# 0.2.0
- add support for custom variables
- updated error messages
- fixed possible faultdef in `util::format`
