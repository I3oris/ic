# 0.4.1 (Sun May 8 2022)

### New
* Update to the last crystal version (1.4.1)
* Add option -d to trigger the debugger at starting.
* New auto-completion UI
  * Allow 'tabulation' to roll over completions entries.
  * Enhance the display and avoid remaining boilerplate output.
  * Add 'escape' key to close the auto-completion and 'shift-tab' to unroll entries.
  * Permit auto-completion to work on block arguments and on `&.foo`.
  * Allow auto-completion to work inside a def (argument names are not taken in account yet)
    Take also into account the current scope, the auto-completion now proposes 'property'/'getter'.. macros as their belong to the scope of a class.
  * Add macros to auto-completion
  * Implements auto-completion on require node
  * Enable auto-completion in debugger mode

* Change the 'insert new line' shortcut: 'crtl-o' -> 'alt-enter'

### Bugs fix
* Fix bug causing pry to not exit
* Fix coloration bug with named tuple keys
* Fix bug with `+=` causing error instead of going multiline
* Fix semantics bug caused by auto-completion
* Fix remaining boilerplate output when displaying auto-completion on multiline input
* Fix auto-completion not to trigger on `if`/`while` conditions and on `def` default values
* Raise syntax error on `[1 \n ,2` rather than get stuck in multiline mode
* Allow 'ctrl-tab' to work on tty
* Remove `[]`, `[]?`, `[]=` from operators coloration, so `[] of String` is colored correctly
* Remove llvm_ext.o causing it to not build on git clone
* Fix bug with pasting expression starting by '#'

### Other
* Some little cleaning.
* Update `.ameba.yml`
* Remove color from prompt for a sober style.
* Remove '\`' from auto-completion entries
* Add `llvm_ext.o` to gitignore
* Give precision about release build
* Fix typo in README
* Add a gif to README
* Add release build mode into makefile
* Add this changelog from commits history

# 0.3.2 (Sat Jan 22 2022)

### Commits
* Update to the last crystal-i version (1.3.2)
* Use ameba 0.14
* Refactor main entry
* Remove out-dated spec
* Update README
* Add more context to the auto-completion to allow more powerful auto-completions in the future.
* Fix infinite loop triggered on 'tab' for expression starting with dot
* Fix bug with auto-indent of methods with a block and proc-literal.
* Add `-D`/`--define` option
* Use option parser and add following options:
    * `--version`
    * `--help`
    * `--no-color`
* Move auto_completion code to its own file
* Add shortcuts for `step`, `next`, `finish` and `whereami` in pry
* Integrate pry!

# 0.3.0 (Sat Jan 8 2022)

### Commits
* Update to the last crystal-i version (1.3.0)
* Update to the last crystal-i version
* Reduce aliasing when displaying very large expressions
* Update highlighter colors
* Enhance display of auto-completions entries
* Experimental: Implement auto-completion (work on basic receiver `(\w+.)*`, but ignore the context (def vars, class/module context, ...) )
* Add shortcuts move_cursor_to_begin/move_cursor_to_end
* Doing some optimizations to reduce aliasing on very long expression
* Fix bug inserting a character before an "end" wrongly triggering auto-unindent
* Remove unused ic_prelude.cr
* Trigger correct scrolling when moving history up/down
* Trigger scrolling when cursor moves on border
* Now use crystal-i as back-end to interpret crystal. The previous work done to carry out an interpreter is still available on the `custom-interpreter` branch.

### Note
The project change his goal, it not aims to reproduce an interpreter, it aims to provide a nice interface to wrap crystal interpreter

# 0.2.1 (Fri Nov 12 2022)

### Commits
* Fix multiline not trigger on `begin\rescue`
* Fix highlighting bug with `(a+b)/x`, previously colored as regex
* Support proper behaviour on pasting code
* Fix some intern documentation misspellings
* Reduce screen aliasing on large expressions
* Fix bug while displaying full expression
* Support displaying expressions higher than term height
* Clean up + improve comments
* Update the multiline behaviour, now always submit on enter unless cursor is on the last line and the expression is unterminated. Add 'ctrl+o' shortcut to insert a new line otherwise.
* Rename REPLInterface module => ReplInterface
* Merge MultilineInput + CrystalMultilineInput classes => ReplInterface
* Implements correctly move_cursor_to_end_of_first_line when move down the history
* Fix to be compatible with crystal-1.2
* Don't discard editing when history is turn up
* Simplify cursor code
* Remove unused callback
* Implements move cursor down
* Enhance intern documentation
* Implements move_cursor_up
* Cleaning using the ameba tool (cyclomatic complexity = 30)
* Remake the interface from scratch, now supports:
    * editing mulitline, 'delete', 'back' end 'enter' can remove/add lines
    * moving cursor left and right
    * lines greater than term width, and resizing the term
    * auto-indent on parenthesizes, bracket, and almost all that need to be indented

    Doesn't supports yet:
    * moving cursor up and down
    * expression higher than term height
    * pasting large expressions
* update gitignore
* Ensure that IC run on 1.1.0
* Remove 'pending' on some already solved spec + minor fix
* Display arrays and ranges
* Remake ICObject to hold compile-time type (instead of runtime type)
    * Implement in a better way boxing/unboxing of unions
    * Implement more correctly Casts
    * Work on dispatch
    * Make pointerof(var_union) works
    * Display '∅' on invalid/uninitialized vars
* format spec
* repair specs by executing the prelude
* clean and split out specs
* Start to implement dispatch defs
* fix bug in error display
* fix bug with assignments
* fix:
    ```cr
    x = 42
    typeof(x) # => Int32
    x = foo
    typeof(x) # => String|Int32
    ```
* remove mis-formating
* catch interminated call
* Add a nice feature that replace `.foo` by `__.foo`

# 0.2.0 (Sat Jun 5 2021)

### Commits
* Support most of LibC, LibCG methods (not those with callback)
* Fix display bug on 'printf' or 'macro puts'
* support the 'out' keyword
* start implementing LibC fun
* fix error lines on macro errors
* fix bug with vars not cleared correctly between specs
* improve error messages and lines number
* add coloration for `&+=`, `&-=`, and `&*=`
* fix coloration bug with `1/2` and add coloration for operators `&-`, `&+`, ...
* Handle closure on receivers
* Handle closure on receivers
* Support procedures with closure! (normal vars)
* start supporting `ARGV`
* Support ivars initializers!
* fix bug with constants and cleaning
* Support class vars
* add  vars
* fix bug: use fullname on Const and Enums
* clean the code by getting ride of ICType (use Crystal::Type instead), and do some other cleaning
* work-around for #1
* remove a remaining 'puts'
* Finish Enums
* fix bug with integer generic var
* fix bug with integer generic var
* implements yield and blocks
* start implementing Enums
* add reset command
* Implements CONST
* Support all primitives in primitives.cr (unless proc_call)
* rename the project ICR -> IC
* add scenario 3
* update README
* Clarify some intern comments
* support CONST, now only the last written expression is parsed
* Add more specs
* Cleaning, and fix bugs with char and symbol comparisons
* add Alias
* add spawn keyword
* Catch more unterminated expressions
* fix bug with GC and memory corruption when union type are used!
* Clean the code, and progress on union and virtual types
* provide an informative README
* Fix bug with lines number inside string
* Support classes, and crystal_type_id,start to works on unions
* make the pointers works!, then add Char, String, Tuple, Symbol, and NamedTuple
* clean the code, simplify the primitive process, and support all integer kind
* Implements ICRObject in a way to support pointers on structs and pointer on classes
* support overload & default arguments on functions, but break `_`. Try to implements pointers
* improve shell, fix bug with highlighter and supports more ASTNodes
* update gitignore
* improve the command interface!

# 0.1.0
* ICR is coming!